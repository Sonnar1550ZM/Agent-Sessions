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

    public init(metadata: ClaudeSubagentMetadata, state: AgentState, title: String, cwd: String) {
        self.metadata = metadata
        self.state = state
        self.title = title
        self.cwd = cwd
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
        guard var metadata = subagentMetadata(transcriptPath: transcriptPath) else {
            return nil
        }

        var state = AgentState.working
        var title = ""
        var cwd = ""
        var role = ""

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let lineCWD = object["cwd"] as? String, !lineCWD.isEmpty {
                cwd = lineCWD
            }
            if let agentId = object["agentId"] as? String, !agentId.isEmpty {
                metadata.subagentNickname = agentId
            }
            if let attributionAgent = object["attributionAgent"] as? String, !attributionAgent.isEmpty {
                role = attributionAgent
            }
            if title.isEmpty,
               object["type"] as? String == "user",
               let promptTitle = promptTitle(from: object["message"]) {
                title = promptTitle
            }

            let type = object["type"] as? String ?? ""
            if type == "assistant",
               let message = object["message"] as? [String: Any] {
                if containsToolUse(message["content"]) {
                    state = .working
                } else if message["stop_reason"] as? String == "end_turn" {
                    state = .idle
                }
            } else if type == "user" || type == "attachment" {
                state = .working
            }
        }

        if role.isEmpty {
            role = metadata.subagentRole
        } else {
            metadata.subagentRole = role
        }

        return ClaudeParsedSubagent(
            metadata: metadata,
            state: state,
            title: title.isEmpty ? role : title,
            cwd: cwd
        )
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
}
