import Foundation

public struct CodexParsedSession: Equatable, Sendable {
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var isInternalSubagent: Bool
    public var parentSessionId: String?
    public var subagentNickname: String?
    public var subagentRole: String?
    public var subagentDepth: Int?
    public var latestResponseText: String?
    public var latestResponsePhase: String?

    public init(
        sessionId: String,
        state: AgentState,
        title: String,
        cwd: String,
        event: String = "",
        isInternalSubagent: Bool,
        parentSessionId: String? = nil,
        subagentNickname: String? = nil,
        subagentRole: String? = nil,
        subagentDepth: Int? = nil,
        latestResponseText: String? = nil,
        latestResponsePhase: String? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.title = title
        self.cwd = cwd
        self.event = event
        self.isInternalSubagent = isInternalSubagent
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
        self.latestResponseText = latestResponseText
        self.latestResponsePhase = latestResponsePhase
    }
}

public enum CodexSessionParser {
    public static func parse(_ text: String, fallbackSessionId: String) -> CodexParsedSession {
        var state = ParserState(fallbackSessionId: fallbackSessionId)
        applyLines(text, to: &state)
        return state.toSession()
    }

    /// Apply additional JSONL lines on top of a previously parsed session.
    /// Use this when reading only the appended portion of a session file to
    /// avoid re-parsing the entire transcript.
    public static func parseDelta(_ text: String, base: CodexParsedSession) -> CodexParsedSession {
        var state = ParserState(base: base)
        applyLines(text, to: &state)
        return state.toSession()
    }

    private struct ParserState {
        var sessionId: String
        var state: AgentState = .idle
        var title = ""
        var promptTitle = ""
        var cwd = ""
        var event = ""
        var isInternalSubagent = false
        var parentSessionId: String?
        var subagentNickname: String?
        var subagentRole: String?
        var subagentDepth: Int?
        var latestResponseText: String?
        var latestResponsePhase: String?

        init(fallbackSessionId: String) {
            self.sessionId = fallbackSessionId
        }

        init(base: CodexParsedSession) {
            self.sessionId = base.sessionId
            self.state = base.state
            self.title = base.title
            self.cwd = base.cwd
            self.event = base.event
            self.isInternalSubagent = base.isInternalSubagent
            self.parentSessionId = base.parentSessionId
            self.subagentNickname = base.subagentNickname
            self.subagentRole = base.subagentRole
            self.subagentDepth = base.subagentDepth
            self.latestResponseText = base.latestResponseText
            self.latestResponsePhase = base.latestResponsePhase
        }

        func toSession() -> CodexParsedSession {
            CodexParsedSession(
                sessionId: sessionId,
                state: state,
                title: title.isEmpty ? promptTitle : title,
                cwd: cwd,
                event: event,
                isInternalSubagent: isInternalSubagent,
                parentSessionId: parentSessionId,
                subagentNickname: subagentNickname,
                subagentRole: subagentRole,
                subagentDepth: subagentDepth,
                latestResponseText: latestResponseText,
                latestResponsePhase: latestResponsePhase
            )
        }
    }

    private static func applyLines(_ text: String, to parserState: inout ParserState) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineText = String(line)
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                if lineText.contains("\"type\":\"session_meta\"") {
                    if let id = extractJSONStringValue(named: "id", from: lineText), !id.isEmpty {
                        parserState.sessionId = id
                    }
                    if let metadataCwd = extractJSONStringValue(named: "cwd", from: lineText), !metadataCwd.isEmpty {
                        parserState.cwd = metadataCwd
                    }
                    if let metadataTitle = extractTitle(fromRawJSONLine: lineText) {
                        parserState.title = metadataTitle
                    }
                    if lineText.contains("\"source\":{\"subagent\":{\"other\":\"guardian\"") {
                        parserState.isInternalSubagent = true
                    }
                    if extractJSONStringValue(named: "thread_source", from: lineText) == "subagent" {
                        parserState.parentSessionId = extractJSONStringValue(named: "parent_thread_id", from: lineText) ?? parserState.parentSessionId
                        parserState.subagentNickname = extractJSONStringValue(named: "agent_nickname", from: lineText) ?? parserState.subagentNickname
                        parserState.subagentRole = extractJSONStringValue(named: "agent_role", from: lineText) ?? parserState.subagentRole
                        parserState.subagentDepth = extractJSONIntValue(named: "depth", from: lineText) ?? parserState.subagentDepth
                    }
                } else if lineText.contains("\"type\":\"turn_context\""),
                          let contextCwd = extractJSONStringValue(named: "cwd", from: lineText),
                          !contextCwd.isEmpty {
                    parserState.cwd = contextCwd
                    if let contextTitle = extractTitle(fromRawJSONLine: lineText) {
                        parserState.title = contextTitle
                    }
                }
                continue
            }

            let payload = object["payload"] as? [String: Any] ?? [:]
            if let payloadTitle = extractTitle(fromPayloadFields: payload) {
                parserState.title = payloadTitle
            }

            if type == "session_meta" {
                if let id = payload["id"] as? String, !id.isEmpty {
                    parserState.sessionId = id
                }
                let metadata = subagentMetadata(from: payload)
                parserState.isInternalSubagent = parserState.isInternalSubagent || metadata.isInternalSubagent
                parserState.parentSessionId = metadata.parentSessionId ?? parserState.parentSessionId
                parserState.subagentNickname = metadata.subagentNickname ?? parserState.subagentNickname
                parserState.subagentRole = metadata.subagentRole ?? parserState.subagentRole
                parserState.subagentDepth = metadata.subagentDepth ?? parserState.subagentDepth
            }

            if ["session_meta", "turn_context"].contains(type),
               let contextCwd = payload["cwd"] as? String,
               !contextCwd.isEmpty {
                parserState.cwd = contextCwd
            }

            if type == "response_item" {
                let itemType = payload["type"] as? String ?? ""
                if !itemType.isEmpty {
                    parserState.event = itemType
                }
                if itemType == "function_call" || itemType == "function_call_output" || itemType == "custom_tool_call_output" {
                    parserState.state = .working
                }
                if itemType == "message", let role = payload["role"] as? String, role == "user" {
                    parserState.state = .working
                    parserState.event = "user_message"
                    if parserState.promptTitle.isEmpty,
                       let userTitle = extractPromptTitle(fromUserMessagePayload: payload) {
                        parserState.promptTitle = userTitle
                    }
                    parserState.latestResponseText = nil
                    parserState.latestResponsePhase = nil
                }
                if itemType == "message", let role = payload["role"] as? String, role == "assistant",
                   let responseText = responseText(from: payload) {
                    parserState.latestResponseText = responseText
                    parserState.latestResponsePhase = trimmedString(payload["phase"], limit: 80)
                }
                if itemType == "message", payload["phase"] as? String == "final_answer" {
                    parserState.state = .idle
                }
            }

            if type == "event_msg" {
                let eventType = payload["type"] as? String ?? ""
                if !eventType.isEmpty {
                    parserState.event = eventType
                }
                if ["exec_command_begin", "mcp_tool_call_begin", "patch_apply_begin", "web_search_begin", "agent_message"].contains(eventType) {
                    parserState.state = .working
                }
                if eventType == "agent_message",
                   let responseText = sanitizedResponseText(payload["message"] as? String) {
                    parserState.latestResponseText = responseText
                    parserState.latestResponsePhase = trimmedString(payload["phase"], limit: 80)
                }
                if ["task_complete", "turn_complete", "shutdown_complete", "turn_aborted"].contains(eventType) {
                    parserState.state = .idle
                }
                if let eventCwd = payload["cwd"] as? String, !eventCwd.isEmpty {
                    parserState.cwd = eventCwd
                }
                if eventType == "user_message" {
                    parserState.state = .working
                    if parserState.promptTitle.isEmpty,
                       let userTitle = sanitizedUserPromptTitle(payload["message"] as? String) {
                        parserState.promptTitle = userTitle
                    }
                    parserState.latestResponseText = nil
                    parserState.latestResponsePhase = nil
                }
            }
        }
    }

    private static func responseText(from payload: [String: Any]) -> String? {
        if let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "output_text" else {
                    return nil
                }
                return item["text"] as? String
            }
            .joined(separator: "\n")
            return sanitizedResponseText(text)
        }

        if let text = payload["content"] as? String {
            return sanitizedResponseText(text)
        }

        return sanitizedResponseText(payload["message"] as? String)
    }

    private static func sanitizedResponseText(_ value: String?) -> String? {
        AgentTextSanitizer.latestResponseText(value)
    }

    private static func subagentMetadata(from payload: [String: Any]) -> (
        isInternalSubagent: Bool,
        parentSessionId: String?,
        subagentNickname: String?,
        subagentRole: String?,
        subagentDepth: Int?
    ) {
        let threadSource = payload["thread_source"] as? String
        let source = payload["source"] as? [String: Any]
        let subagent = source?["subagent"] as? [String: Any]

        if subagent?["other"] as? String == "guardian" {
            return (true, nil, nil, nil, nil)
        }

        guard threadSource == "subagent" else {
            return (false, nil, nil, nil, nil)
        }

        let threadSpawn = subagent?["thread_spawn"] as? [String: Any]
        return (
            false,
            trimmedString(threadSpawn?["parent_thread_id"], limit: 160),
            trimmedString(payload["agent_nickname"], limit: 80) ?? trimmedString(threadSpawn?["agent_nickname"], limit: 80),
            trimmedString(payload["agent_role"], limit: 80) ?? trimmedString(threadSpawn?["agent_role"], limit: 80),
            intValue(threadSpawn?["depth"])
        )
    }

    private static func extractTitle(fromPayloadFields payload: [String: Any]) -> String? {
        for key in ["thread_name", "title", "name"] {
            if let title = payload[key] as? String,
               let sanitized = sanitizedTitle(title) {
                return sanitized
            }
        }
        return nil
    }

    private static func extractTitle(fromRawJSONLine line: String) -> String? {
        if let title = extractJSONStringValue(named: "thread_name", from: line),
           let sanitized = sanitizedTitle(title) {
            return sanitized
        }
        return nil
    }

    private static func extractPromptTitle(fromUserMessagePayload payload: [String: Any]) -> String? {
        if let text = payload["content"] as? String {
            return sanitizedUserPromptTitle(text)
        }

        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content.compactMap { item -> String? in
            let type = item["type"] as? String
            guard type == "input_text" || type == "text" else {
                return nil
            }
            return item["text"] as? String
        }
        .compactMap(sanitizedUserPromptTitle)
        .joined(separator: " ")

        return sanitizedTitle(text)
    }

    private static func sanitizedUserPromptTitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBootstrapContext(trimmed) else {
            return nil
        }

        return sanitizedTitle(trimmed)
    }

    private static func isBootstrapContext(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasPrefix("# agents.md instructions")
            || lowercased.hasPrefix("<environment_context>")
            || lowercased.hasPrefix("<permissions instructions>")
            || lowercased.hasPrefix("<apps_instructions>")
            || lowercased.hasPrefix("<skills_instructions>")
            || lowercased.hasPrefix("<plugins_instructions>")
            || lowercased.hasPrefix("<collaboration_mode>")
            || lowercased.hasPrefix("## memory")
    }

    private static func sanitizedTitle(_ value: String) -> String? {
        let title = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
    }

    private static func trimmedString(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(limit))
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func extractJSONStringValue(named name: String, from text: String) -> String? {
        let marker = "\"\(name)\":\""
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        var value = ""
        var isEscaped = false
        var index = markerRange.upperBound

        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                switch character {
                case "\"", "\\", "/":
                    value.append(character)
                case "n":
                    value.append("\n")
                case "r":
                    value.append("\r")
                case "t":
                    value.append("\t")
                default:
                    value.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func extractJSONIntValue(named name: String, from text: String) -> Int? {
        let marker = "\"\(name)\":"
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        var digits = ""
        var index = markerRange.upperBound
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber || (digits.isEmpty && character == "-") {
                digits.append(character)
                index = text.index(after: index)
                continue
            }
            break
        }
        return Int(digits)
    }
}
