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

    public var id: String {
        "\(agent.rawValue):\(sessionId)"
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
        updatedAt: Date = Date()
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
    }

    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        if !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        return sessionId
    }
}

public struct AgentEvent: Decodable, Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var terminal: String
    public var pid: Int?
    public var updatedAt: Date?

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
        updatedAt: Date? = nil
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
