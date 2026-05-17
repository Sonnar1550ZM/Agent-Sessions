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
        subagentDepth: Int? = nil
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
        transcriptPath: String? = nil
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let agentLabel = try container.decodeIfPresent(String.self, forKey: .agent) ?? "Codex"
        let rawSessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .session_id)
            ?? "default"
        let rawState = try container.decodeIfPresent(String.self, forKey: .state)

        agent = AgentKind(label: agentLabel)
        sessionId = rawSessionId.trimmedOrDefault("default")
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
        transcriptPath = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .transcriptPath,
            fallbackKey: .transcript_path,
            limit: 1024
        )

        if let date = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updated_at) {
            updatedAt = date
        } else if let dateString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updated_at) {
            updatedAt = AgentsBarDates.date(from: dateString)
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
            try container.encode(AgentsBarDates.string(from: updatedAt), forKey: .updatedAt)
        }
        try container.encodeIfPresent(parentSessionId, forKey: .parentSessionId)
        try container.encodeIfPresent(subagentNickname, forKey: .subagentNickname)
        try container.encodeIfPresent(subagentRole, forKey: .subagentRole)
        try container.encodeIfPresent(subagentDepth, forKey: .subagentDepth)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
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
}

public enum AgentsBarDates {
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

    func trimmedOrDefault(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
