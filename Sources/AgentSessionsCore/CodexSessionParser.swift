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
    public var turnInterrupted: Bool
    public var interruptedTurnId: String?

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
        latestResponsePhase: String? = nil,
        turnInterrupted: Bool = false,
        interruptedTurnId: String? = nil
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
        self.turnInterrupted = turnInterrupted
        self.interruptedTurnId = interruptedTurnId
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
        var statusTitle: String?
        var cwd = ""
        var event = ""
        var isInternalSubagent = false
        var parentSessionId: String?
        var subagentNickname: String?
        var subagentRole: String?
        var subagentDepth: Int?
        var latestResponseText: String?
        var latestResponsePhase: String?
        var turnInterrupted = false
        var interruptedTurnId: String?

        init(fallbackSessionId: String) {
            self.sessionId = fallbackSessionId
        }

        init(base: CodexParsedSession) {
            self.sessionId = base.sessionId
            self.state = base.state
            if AgentCompactionStatus.hasMatchingDisplayTitle(event: base.event, title: base.title) {
                self.statusTitle = base.title
            } else {
                self.title = base.title
            }
            self.cwd = base.cwd
            self.event = base.event
            self.isInternalSubagent = base.isInternalSubagent
            self.parentSessionId = base.parentSessionId
            self.subagentNickname = base.subagentNickname
            self.subagentRole = base.subagentRole
            self.subagentDepth = base.subagentDepth
            self.latestResponseText = base.latestResponseText
            self.latestResponsePhase = base.latestResponsePhase
            self.turnInterrupted = base.turnInterrupted
            self.interruptedTurnId = base.interruptedTurnId
        }

        func toSession() -> CodexParsedSession {
            let sessionTitle = statusTitle ?? (title.isEmpty ? promptTitle : title)
            let isInternalSuggestion = AgentSessionVisibility.isCodexInternalSuggestion(
                agent: .codex,
                title: sessionTitle,
                latestResponseText: latestResponseText
            )
            return CodexParsedSession(
                sessionId: sessionId,
                state: state,
                title: sessionTitle,
                cwd: cwd,
                event: event,
                isInternalSubagent: isInternalSubagent || isInternalSuggestion,
                parentSessionId: parentSessionId,
                subagentNickname: subagentNickname,
                subagentRole: subagentRole,
                subagentDepth: subagentDepth,
                latestResponseText: latestResponseText,
                latestResponsePhase: latestResponsePhase,
                turnInterrupted: turnInterrupted,
                interruptedTurnId: interruptedTurnId
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

            if type == "compacted" {
                parserState.event = "compacted"
                parserState.state = .idle
                parserState.statusTitle = AgentCompactionStatus.compactedTitle
            }

            if type == "response_item" {
                let itemType = payload["type"] as? String ?? ""
                if itemType == "message", let role = payload["role"] as? String, role == "user" {
                    switch syntheticUserNotification(payload) {
                    case .turnAborted:
                        parserState.state = .idle
                        parserState.event = "turn_aborted"
                        parserState.turnInterrupted = true
                        parserState.interruptedTurnId = nil
                        continue
                    case .subagentNotification:
                        continue
                    case nil:
                        parserState.turnInterrupted = false
                        parserState.interruptedTurnId = nil
                        parserState.statusTitle = nil
                        parserState.state = .working
                        parserState.event = "user_message"
                        if containsInternalSuggestionUserPrompt(payload) {
                            parserState.isInternalSubagent = true
                        }
                        if parserState.promptTitle.isEmpty,
                           let userTitle = extractPromptTitle(fromUserMessagePayload: payload) {
                            parserState.promptTitle = userTitle
                        }
                        parserState.latestResponseText = nil
                        parserState.latestResponsePhase = nil
                        continue
                    }
                }
                if parserState.turnInterrupted && isWorkingResponseItem(itemType) {
                    continue
                }
                if let waitingEvent = waitingEventForResponseItem(itemType: itemType, payload: payload) {
                    parserState.statusTitle = nil
                    parserState.event = waitingEvent
                    parserState.state = .waiting
                    continue
                }
                if !itemType.isEmpty {
                    parserState.event = itemType
                }
                if isWorkingResponseItem(itemType) {
                    parserState.statusTitle = nil
                    parserState.state = .working
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
                if eventType == "task_started" {
                    let turnId = payload["turn_id"] as? String
                    if parserState.interruptedTurnId == nil || turnId != parserState.interruptedTurnId {
                        parserState.turnInterrupted = false
                        parserState.interruptedTurnId = nil
                    }
                }
                if !eventType.isEmpty {
                    parserState.event = eventType
                }
                if let compactionEvent = compactionEvent(for: eventType, payload: payload) {
                    parserState.event = compactionEvent.event
                    parserState.state = compactionEvent.state
                    parserState.statusTitle = compactionEvent.title
                } else if !parserState.turnInterrupted && isWorkingEvent(eventType) {
                    parserState.statusTitle = nil
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
                if eventType == "turn_aborted" {
                    parserState.turnInterrupted = true
                    parserState.interruptedTurnId = payload["turn_id"] as? String
                }
                if let eventCwd = payload["cwd"] as? String, !eventCwd.isEmpty {
                    parserState.cwd = eventCwd
                }
                if eventType == "user_message" {
                    parserState.turnInterrupted = false
                    parserState.interruptedTurnId = nil
                    parserState.statusTitle = nil
                    parserState.state = .working
                    if isInternalSuggestionPrompt(payload["message"] as? String) {
                        parserState.isInternalSubagent = true
                    }
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

    private enum SyntheticUserNotification {
        case turnAborted
        case subagentNotification
    }

    private static func isWorkingResponseItem(_ itemType: String) -> Bool {
        itemType == "function_call"
            || itemType == "function_call_output"
            || itemType == "custom_tool_call_output"
    }

    private static func waitingEventForResponseItem(itemType: String, payload: [String: Any]) -> String? {
        guard itemType == "function_call" else {
            return nil
        }

        let name = functionCallName(payload)
        if requiresEscalatedSandboxPermission(payload) {
            return "permission_request"
        }
        if requiresUserInputFunction(name) {
            return "request_user_input"
        }
        return nil
    }

    private static func functionCallName(_ payload: [String: Any]) -> String {
        var candidates: [Any?] = [
            payload["name"],
            payload["function_name"],
            payload["tool_name"],
            payload["toolName"],
        ]
        for key in ["function", "tool", "tool_use", "toolUse"] {
            if let nested = payload[key] as? [String: Any] {
                candidates.append(nested["name"])
                candidates.append(nested["tool_name"])
                candidates.append(nested["toolName"])
            }
        }
        return candidates.compactMap { trimmedString($0, limit: 160) }.first ?? ""
    }

    private static func requiresUserInputFunction(_ name: String) -> Bool {
        let compact = name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return compact.contains("requestuserinput")
            || compact.contains("askuserquestion")
    }

    private static func requiresEscalatedSandboxPermission(_ payload: [String: Any]) -> Bool {
        for key in ["arguments", "args", "input", "tool_input", "toolInput"] {
            guard let value = payload[key] else {
                continue
            }
            if containsEscalatedSandboxPermission(value) {
                return true
            }
        }
        return false
    }

    private static func containsEscalatedSandboxPermission(_ value: Any) -> Bool {
        if let string = value as? String {
            if string.contains("\"sandbox_permissions\":\"require_escalated\"")
                || string.contains("\"sandbox_permissions\": \"require_escalated\"")
                || string.contains("\"sandboxPermissions\":\"require_escalated\"")
                || string.contains("\"sandboxPermissions\": \"require_escalated\"") {
                return true
            }
            guard let data = string.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return false
            }
            return containsEscalatedSandboxPermission(object)
        }

        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if ["sandbox_permissions", "sandboxPermissions"].contains(key),
                   trimmedString(nestedValue, limit: 80) == "require_escalated" {
                    return true
                }
                if containsEscalatedSandboxPermission(nestedValue) {
                    return true
                }
            }
        }

        if let array = value as? [Any] {
            return array.contains(where: containsEscalatedSandboxPermission)
        }

        return false
    }

    private static func compactionEvent(
        for eventType: String,
        payload: [String: Any]
    ) -> (event: String, state: AgentState, title: String)? {
        if eventType == "context_compacted" {
            return ("context_compacted", .idle, AgentCompactionStatus.compactedTitle)
        }

        guard eventType == "hook_started" || eventType == "hook_completed",
              let hookName = compactHookEventName(from: payload) else {
            return nil
        }

        if hookName == "PreCompact" {
            return ("PreCompact", .working, AgentCompactionStatus.compactingTitle)
        }
        if hookName == "PostCompact" {
            return ("PostCompact", .idle, AgentCompactionStatus.compactedTitle)
        }
        return nil
    }

    private static func compactHookEventName(from payload: [String: Any]) -> String? {
        var candidates: [Any?] = [
            payload["hook_event_name"],
            payload["hookEventName"],
            payload["event_name"],
            payload["eventName"],
        ]

        for key in ["run", "hook", "hook_run", "hookRun"] {
            if let nested = payload[key] as? [String: Any] {
                candidates.append(nested["hook_event_name"])
                candidates.append(nested["hookEventName"])
                candidates.append(nested["event_name"])
                candidates.append(nested["eventName"])
            }
        }

        for candidate in candidates.compactMap({ trimmedString($0, limit: 80) }) {
            let compact = candidate
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            if compact == "precompact" {
                return "PreCompact"
            }
            if compact == "postcompact" {
                return "PostCompact"
            }
        }
        return nil
    }

    private static func isWorkingEvent(_ eventType: String) -> Bool {
        ["exec_command_begin", "mcp_tool_call_begin", "patch_apply_begin", "web_search_begin", "agent_message"].contains(eventType)
    }

    private static func syntheticUserNotification(_ payload: [String: Any]) -> SyntheticUserNotification? {
        let texts: [String]
        if let stringContent = payload["content"] as? String {
            texts = [stringContent]
        } else if let parts = payload["content"] as? [[String: Any]] {
            texts = parts.compactMap { $0["text"] as? String }
        } else {
            return nil
        }

        guard let first = texts.first(where: { !$0.isEmpty }) else {
            return nil
        }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<turn_aborted>") {
            return .turnAborted
        }
        if trimmed.hasPrefix("<subagent_notification>") {
            return .subagentNotification
        }
        return nil
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

    private static func containsInternalSuggestionUserPrompt(_ payload: [String: Any]) -> Bool {
        if let text = payload["content"] as? String {
            return isInternalSuggestionPrompt(text)
        }

        guard let content = payload["content"] as? [[String: Any]] else {
            return false
        }

        return content.contains { item in
            let type = item["type"] as? String
            guard type == "input_text" || type == "text" else {
                return false
            }
            return isInternalSuggestionPrompt(item["text"] as? String)
        }
    }

    private static func isInternalSuggestionPrompt(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return AgentSessionVisibility.isCodexInternalSuggestion(
            agent: .codex,
            title: value.trimmingCharacters(in: .whitespacesAndNewlines),
            latestResponseText: nil
        )
    }

    private static func sanitizedUserPromptTitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isBootstrapContext(trimmed),
              !AgentSessionVisibility.isCodexInternalSuggestion(
                  agent: .codex,
                  title: trimmed,
                  latestResponseText: nil
              ) else {
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
        AgentSessionTitleSanitizer.optional(value)
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
