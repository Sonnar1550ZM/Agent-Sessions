import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode

    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code"
        }
    }

    public init(label: String) {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        if normalized.contains("claude") {
            self = .claudeCode
        } else {
            self = .codex
        }
    }
}

public enum AgentSessionVisibility {
    public static func isCodexMemoryWorkspace(agent: AgentKind, cwd: String) -> Bool {
        guard agent == .codex else {
            return false
        }

        let sessionPath = normalizedPath(cwd)
        guard !sessionPath.isEmpty else {
            return false
        }

        let memoriesPath = normalizedPath("~/.codex/memories")
        return sessionPath == memoriesPath || sessionPath.hasPrefix(memoriesPath + "/")
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let expandedPath: String
        if trimmed == "~" {
            expandedPath = homePath
        } else if trimmed.hasPrefix("~/") {
            expandedPath = homePath + String(trimmed.dropFirst())
        } else {
            expandedPath = trimmed
        }

        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }
}

public enum AgentTextSanitizer {
    public static func latestResponseText(_ value: String?, limit: Int = 1_000) -> String? {
        guard let value else {
            return nil
        }

        let normalizedText = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let text = displayTextByCollapsingMarkdownLinks(normalizedText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return nil
        }

        guard text.count > limit else {
            return text
        }

        return String(text.prefix(limit))
    }

    private static func displayTextByCollapsingMarkdownLinks(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = markdownLinkPattern.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        var result = ""
        var currentIndex = text.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let labelRange = Range(match.range(at: 1), in: text),
                  let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            result += text[currentIndex..<fullRange.lowerBound]
            result += markdownLinkDisplayText(
                label: String(text[labelRange]),
                target: String(text[targetRange])
            ) ?? String(text[fullRange])
            currentIndex = fullRange.upperBound
        }
        result += text[currentIndex...]

        return result
    }

    private static func markdownLinkDisplayText(label: String, target: String) -> String? {
        let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = markdownLinkTarget(target)
        guard isLocalFileLinkTarget(normalizedTarget),
              let lineNumber = markdownLinkLineNumber(normalizedTarget) else {
            return nil
        }

        return "\(displayLabel) (line \(lineNumber))"
    }

    private static func markdownLinkTarget(_ target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }

    private static func isLocalFileLinkTarget(_ target: String) -> Bool {
        target.hasPrefix("/")
            || target.hasPrefix("~/")
            || target.hasPrefix("file://")
    }

    private static func markdownLinkLineNumber(_ target: String) -> String? {
        let range = NSRange(target.startIndex..<target.endIndex, in: target)
        guard let match = lineNumberSuffixPattern.firstMatch(in: target, range: range),
              let lineRange = Range(match.range(at: 1), in: target) else {
            return nil
        }

        return String(target[lineRange])
    }

    private static let markdownLinkPattern = try! NSRegularExpression(
        pattern: #"(?<!!)\[([^\]\n]+)\]\((<[^>\n]+>|[^)\n]+)\)"#
    )
    private static let lineNumberSuffixPattern = try! NSRegularExpression(
        pattern: #"(?::|#L)(\d+)$"#
    )
}

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case working
    case waiting
    case idle
    case ended

    public var symbol: String {
        switch self {
        case .working:
            "●"
        case .waiting:
            "△"
        case .idle:
            "○"
        case .ended:
            "-"
        }
    }

    public var displayName: String {
        switch self {
        case .working:
            "Working"
        case .waiting:
            "Waiting"
        case .idle:
            "Idle"
        case .ended:
            "Ended"
        }
    }

    public var isActive: Bool {
        self == .working || self == .waiting
    }

    public init(label: String?) {
        let normalized = (label ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "working", "work", "busy", "auto", "posttooluse", "pretooluse", "userpromptsubmit":
            self = .working
        case "waiting", "wait", "notification", "permission":
            self = .waiting
        case "ended", "end", "sessionend":
            self = .ended
        case "idle", "stop", "sessionstart":
            self = .idle
        default:
            self = .idle
        }
    }
}

public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var terminal: String
    public var pid: Int?
    public var updatedAt: Date
    public var parentSessionId: String?
    public var subagentNickname: String?
    public var subagentRole: String?
    public var subagentDepth: Int?
    public var transcriptPath: String?
    public var latestResponseText: String?
    public var latestResponsePhase: String?
    public var latestResponseUpdatedAt: Date?
    public var stateChangedAt: Date?

    public var id: String {
        "\(agent.rawValue):\(sessionId)"
    }

    public var isSubagent: Bool {
        parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public init(
        agent: AgentKind,
        sessionId: String,
        state: AgentState,
        title: String = "",
        cwd: String = "",
        event: String = "",
        terminal: String = "",
        pid: Int? = nil,
        updatedAt: Date = Date(),
        parentSessionId: String? = nil,
        subagentNickname: String? = nil,
        subagentRole: String? = nil,
        subagentDepth: Int? = nil,
        transcriptPath: String? = nil,
        latestResponseText: String? = nil,
        latestResponsePhase: String? = nil,
        latestResponseUpdatedAt: Date? = nil,
        stateChangedAt: Date? = nil
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.state = state
        self.title = title
        self.cwd = cwd
        self.event = event
        self.terminal = terminal
        self.pid = pid
        self.updatedAt = updatedAt
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
        self.transcriptPath = transcriptPath
        self.latestResponseText = latestResponseText
        self.latestResponsePhase = latestResponsePhase
        self.latestResponseUpdatedAt = latestResponseUpdatedAt
        self.stateChangedAt = stateChangedAt ?? updatedAt
    }

    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        if isSubagent,
           let subagentNickname = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subagentNickname.isEmpty {
            return subagentNickname
        }

        if agent == .codex {
            return "Codex session"
        }

        if !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        return sessionId
    }

    public var subagentDisplayLabel: String {
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = Self.formattedSubagentRole(subagentRole)
        let name = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []

        if !explicitTitle.isEmpty {
            if !role.isEmpty,
               Self.normalizedSubagentLabel(explicitTitle) == Self.normalizedSubagentLabel(role) {
                parts.append(role)
            } else {
                parts.append(explicitTitle)
            }
        } else {
            let fallbackTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackTitle.isEmpty,
               Self.normalizedSubagentLabel(fallbackTitle) != Self.normalizedSubagentLabel(name),
               Self.normalizedSubagentLabel(fallbackTitle) != Self.normalizedSubagentLabel(role) {
                parts.append(fallbackTitle)
            }
        }

        if !role.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(role) }) {
            parts.append(role)
        }

        if !name.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(name) }) {
            parts.append(name)
        }

        return parts.isEmpty ? sessionId : parts.joined(separator: " · ")
    }

    public var subagentSessionTitle: String {
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitTitle.isEmpty {
            return explicitTitle
        }

        let fallbackTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTitle.isEmpty ? sessionId : fallbackTitle
    }

    public var subagentNameAndRoleLabel: String {
        let name = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let role = Self.formattedSubagentRole(subagentRole)
        var parts: [String] = []

        if !name.isEmpty {
            parts.append(name)
        }

        if !role.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(role) }) {
            parts.append(role)
        }

        return parts.isEmpty ? sessionId : parts.joined(separator: " · ")
    }

    private static func formattedSubagentRole(_ role: String?) -> String {
        let trimmedRole = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedRole.isEmpty else {
            return ""
        }

        let normalized = trimmedRole
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = normalized.split(separator: " ")
        guard !words.isEmpty else {
            return trimmedRole
        }

        return words
            .map { word -> String in
                let text = String(word)
                guard text == text.lowercased() else {
                    return text
                }
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func normalizedSubagentLabel(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var terminal: String
    public var pid: Int?
    public var updatedAt: Date?
    public var parentSessionId: String?
    public var subagentNickname: String?
    public var subagentRole: String?
    public var subagentDepth: Int?
    public var transcriptPath: String?
    public var latestResponseText: String?
    public var latestResponsePhase: String?

    public var isSubagent: Bool {
        parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private enum CodingKeys: String, CodingKey {
        case agent
        case sessionId
        case sessionID
        case session_id
        case state
        case title
        case cwd
        case event
        case terminal
        case pid
        case updatedAt
        case updated_at
        case parentSessionId
        case parent_session_id
        case subagentNickname
        case subagent_nickname
        case subagentRole
        case subagent_role
        case subagentDepth
        case subagent_depth
        case transcriptPath
        case transcript_path
        case latestResponseText
        case latest_response_text
        case latestResponsePhase
        case latest_response_phase
    }

    public init(
        agent: AgentKind,
        sessionId: String,
        state: AgentState,
        title: String = "",
        cwd: String = "",
        event: String = "",
        terminal: String = "",
        pid: Int? = nil,
        updatedAt: Date? = nil,
        parentSessionId: String? = nil,
        subagentNickname: String? = nil,
        subagentRole: String? = nil,
        subagentDepth: Int? = nil,
        transcriptPath: String? = nil,
        latestResponseText: String? = nil,
        latestResponsePhase: String? = nil
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.state = state
        self.title = title
        self.cwd = cwd
        self.event = event
        self.terminal = terminal
        self.pid = pid
        self.updatedAt = updatedAt
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
        self.transcriptPath = transcriptPath
        self.latestResponseText = latestResponseText
        self.latestResponsePhase = latestResponsePhase
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let agentLabel = try container.decodeIfPresent(String.self, forKey: .agent) ?? "Codex"
        let rawTranscriptPath = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .transcriptPath,
            fallbackKey: .transcript_path,
            limit: 1024
        )
        let rawSessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .session_id)
            ?? Self.sessionId(fromTranscriptPath: rawTranscriptPath)
        let rawState = try container.decodeIfPresent(String.self, forKey: .state)

        agent = AgentKind(label: agentLabel)
        let normalizedSessionId = rawSessionId?.trimmed(limit: 160) ?? ""
        guard !normalizedSessionId.isEmpty, normalizedSessionId != "default" else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionId,
                in: container,
                debugDescription: "Agent event requires a unique sessionId."
            )
        }
        sessionId = normalizedSessionId
        state = AgentState(label: rawState)
        title = (try container.decodeIfPresent(String.self, forKey: .title) ?? "").trimmed(limit: 160)
        cwd = (try container.decodeIfPresent(String.self, forKey: .cwd) ?? "").trimmed(limit: 512)
        event = (try container.decodeIfPresent(String.self, forKey: .event) ?? "").trimmed(limit: 80)
        terminal = (try container.decodeIfPresent(String.self, forKey: .terminal) ?? "").trimmed(limit: 80)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        parentSessionId = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .parentSessionId,
            fallbackKey: .parent_session_id,
            limit: 160
        )
        subagentNickname = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .subagentNickname,
            fallbackKey: .subagent_nickname,
            limit: 80
        )
        subagentRole = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .subagentRole,
            fallbackKey: .subagent_role,
            limit: 80
        )
        subagentDepth = try container.decodeIfPresent(Int.self, forKey: .subagentDepth)
            ?? container.decodeIfPresent(Int.self, forKey: .subagent_depth)
        transcriptPath = rawTranscriptPath
        latestResponseText = try Self.decodeLatestResponseText(
            from: container,
            primaryKey: .latestResponseText,
            fallbackKey: .latest_response_text,
            limit: 1000
        )
        latestResponsePhase = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .latestResponsePhase,
            fallbackKey: .latest_response_phase,
            limit: 80
        )

        if let date = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updated_at) {
            updatedAt = date
        } else if let dateString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updated_at) {
            updatedAt = AgentSessionsDates.date(from: dateString)
        } else {
            updatedAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agent.rawValue, forKey: .agent)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(title, forKey: .title)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(event, forKey: .event)
        try container.encode(terminal, forKey: .terminal)
        try container.encodeIfPresent(pid, forKey: .pid)
        if let updatedAt {
            try container.encode(AgentSessionsDates.string(from: updatedAt), forKey: .updatedAt)
        }
        try container.encodeIfPresent(parentSessionId, forKey: .parentSessionId)
        try container.encodeIfPresent(subagentNickname, forKey: .subagentNickname)
        try container.encodeIfPresent(subagentRole, forKey: .subagentRole)
        try container.encodeIfPresent(subagentDepth, forKey: .subagentDepth)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
        try container.encodeIfPresent(latestResponseText, forKey: .latestResponseText)
        try container.encodeIfPresent(latestResponsePhase, forKey: .latestResponsePhase)
    }

    private static func decodeTrimmedOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys,
        limit: Int
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: primaryKey)
            ?? container.decodeIfPresent(String.self, forKey: fallbackKey)
            ?? ""
        let trimmed = value.trimmed(limit: limit)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeLatestResponseText(
        from container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys,
        limit: Int
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: primaryKey)
            ?? container.decodeIfPresent(String.self, forKey: fallbackKey)
        return AgentTextSanitizer.latestResponseText(value, limit: limit)
    }

    private static func sessionId(fromTranscriptPath transcriptPath: String?) -> String? {
        guard let transcriptPath,
              !transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let fileName = URL(fileURLWithPath: transcriptPath).lastPathComponent
        guard fileName.hasSuffix(".jsonl") else {
            return nil
        }

        let sessionId = String(fileName.dropLast(".jsonl".count)).trimmed(limit: 160)
        return sessionId.isEmpty ? nil : sessionId
    }
}

public enum AgentSessionsDates {
    public static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    public static func date(from value: String) -> Date? {
        formatter().date(from: value)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension String {
    func trimmed(limit: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit {
            return trimmed
        }
        return String(trimmed.prefix(limit))
    }

}
