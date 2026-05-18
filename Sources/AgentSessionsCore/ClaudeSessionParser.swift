import Foundation

public struct ClaudeSubagentMetadata: Equatable, Sendable {
    public var sessionId: String
    public var parentSessionId: String
    public var subagentNickname: String
    public var subagentRole: String
    public var subagentDepth: Int

    public init(
        sessionId: String,
        parentSessionId: String,
        subagentNickname: String,
        subagentRole: String = "Claude",
        subagentDepth: Int = 1
    ) {
        self.sessionId = sessionId
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
    }
}

public struct ClaudeParsedSubagent: Equatable, Sendable {
    public var metadata: ClaudeSubagentMetadata
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var latestResponseText: String?

    public init(
        metadata: ClaudeSubagentMetadata,
        state: AgentState,
        title: String,
        cwd: String,
        latestResponseText: String? = nil
    ) {
        self.metadata = metadata
        self.state = state
        self.title = title
        self.cwd = cwd
        self.latestResponseText = latestResponseText
    }
}

public enum ClaudeSessionParser {
    public static func subagentMetadata(transcriptPath: String?) -> ClaudeSubagentMetadata? {
        guard let transcriptPath else {
            return nil
        }

        let normalizedPath = transcriptPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return nil
        }

        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let subagentsIndex = components.lastIndex(of: "subagents"),
              subagentsIndex > 0,
              subagentsIndex < components.count - 1 else {
            return nil
        }

        let parentSessionId = components[subagentsIndex - 1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = components.last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subagentFileStem = fileStem(filename)

        guard !parentSessionId.isEmpty, !subagentFileStem.isEmpty else {
            return nil
        }

        return ClaudeSubagentMetadata(
            sessionId: "\(parentSessionId)/subagents/\(subagentFileStem)",
            parentSessionId: parentSessionId,
            subagentNickname: subagentFileStem
        )
    }

    public static func parseSubagentTranscript(transcriptPath: String, text: String) -> ClaudeParsedSubagent? {
        guard let metadata = subagentMetadata(transcriptPath: transcriptPath) else {
            return nil
        }

        var state = SubagentParserState(metadata: metadata)
        applySubagentLines(text, to: &state)
        return state.toParsed()
    }

    /// Apply additional JSONL lines on top of a previously parsed subagent transcript.
    public static func parseSubagentTranscriptDelta(
        transcriptPath: String,
        text: String,
        base: ClaudeParsedSubagent
    ) -> ClaudeParsedSubagent? {
        guard subagentMetadata(transcriptPath: transcriptPath) != nil else {
            return nil
        }

        var state = SubagentParserState(base: base)
        applySubagentLines(text, to: &state)
        return state.toParsed()
    }

    private struct SubagentParserState {
        var metadata: ClaudeSubagentMetadata
        var state: AgentState = .working
        var title: String = ""
        var cwd: String = ""
        var role: String = ""
        var latestResponseText: String?

        init(metadata: ClaudeSubagentMetadata) {
            self.metadata = metadata
        }

        init(base: ClaudeParsedSubagent) {
            self.metadata = base.metadata
            self.state = base.state
            self.title = base.title
            self.cwd = base.cwd
            self.role = base.metadata.subagentRole
            self.latestResponseText = base.latestResponseText
        }

        func toParsed() -> ClaudeParsedSubagent {
            var metadata = self.metadata
            let resolvedRole: String
            if role.isEmpty {
                resolvedRole = metadata.subagentRole
            } else {
                resolvedRole = role
                metadata.subagentRole = role
            }

            return ClaudeParsedSubagent(
                metadata: metadata,
                state: state,
                title: title.isEmpty ? resolvedRole : title,
                cwd: cwd,
                latestResponseText: latestResponseText
            )
        }
    }

    private static func applySubagentLines(_ text: String, to parserState: inout SubagentParserState) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let lineCWD = object["cwd"] as? String, !lineCWD.isEmpty {
                parserState.cwd = lineCWD
            }
            if let agentId = object["agentId"] as? String, !agentId.isEmpty {
                parserState.metadata.subagentNickname = agentId
            }
            if let attributionAgent = object["attributionAgent"] as? String, !attributionAgent.isEmpty {
                parserState.role = attributionAgent
            }
            if parserState.title.isEmpty,
               object["type"] as? String == "user",
               let title = promptTitle(from: object["message"]) {
                parserState.title = title
            }

            let type = object["type"] as? String ?? ""
            if type == "assistant",
               let message = object["message"] as? [String: Any] {
                if let responseText = assistantResponseText(from: message) {
                    parserState.latestResponseText = responseText
                }
                if containsToolUse(message["content"]) {
                    parserState.state = .working
                } else if message["stop_reason"] as? String == "end_turn" {
                    parserState.state = .idle
                }
            } else if type == "user" {
                parserState.state = .working
                if isHumanUserMessage(object) {
                    parserState.latestResponseText = nil
                }
            } else if type == "attachment" {
                parserState.state = .working
            }
        }
    }

    public static func latestAssistantResponseText(fromTranscript text: String) -> String? {
        var latestResponseText: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            switch object["type"] as? String {
            case "assistant":
                guard let message = object["message"] as? [String: Any],
                      let responseText = assistantResponseText(from: message) else {
                    continue
                }
                latestResponseText = responseText
            case "user":
                if isHumanUserMessage(object) {
                    latestResponseText = nil
                }
            default:
                continue
            }
        }

        return latestResponseText
    }

    private static func fileStem(_ filename: String) -> String {
        guard filename.lowercased().hasSuffix(".jsonl") else {
            return filename
        }

        return String(filename.dropLast(".jsonl".count))
    }

    private static func containsToolUse(_ content: Any?) -> Bool {
        guard let parts = content as? [[String: Any]] else {
            return false
        }

        return parts.contains { part in
            part["type"] as? String == "tool_use"
        }
    }

    private static func isHumanUserMessage(_ object: [String: Any]) -> Bool {
        guard object["type"] as? String == "user",
              let message = object["message"] as? [String: Any] else {
            return false
        }

        if let content = message["content"] as? String {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let parts = message["content"] as? [[String: Any]] else {
            return false
        }

        return parts.contains { part in
            guard let type = part["type"] as? String else {
                return false
            }

            return type == "text" || type == "input_text"
        }
    }

    private static func assistantResponseText(from message: [String: Any]) -> String? {
        guard message["role"] as? String == "assistant",
              let parts = message["content"] as? [[String: Any]] else {
            return nil
        }

        let text = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text",
                  let text = part["text"] as? String else {
                return nil
            }
            return text
        }
        .joined(separator: "\n")

        return sanitizedResponseText(text)
    }

    private static func promptTitle(from message: Any?) -> String? {
        guard let message = message as? [String: Any] else {
            return nil
        }

        if let content = message["content"] as? String {
            return sanitizedPromptTitle(content)
        }

        guard let parts = message["content"] as? [[String: Any]] else {
            return nil
        }

        for part in parts {
            guard part["type"] as? String == "text",
                  let text = part["text"] as? String,
                  let title = sanitizedPromptTitle(text) else {
                continue
            }
            return title
        }

        return nil
    }

    private static func sanitizedPromptTitle(_ value: String) -> String? {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else {
            return nil
        }

        let collapsed = firstLine
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return nil
        }

        let limit = 90
        guard collapsed.count > limit else {
            return collapsed
        }

        return String(collapsed.prefix(limit)) + "..."
    }

    private static func sanitizedResponseText(_ value: String) -> String? {
        AgentTextSanitizer.latestResponseText(value)
    }
}
