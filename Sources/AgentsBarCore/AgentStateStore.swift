import Combine
import Foundation

public enum AgentSessionDisplayRow: Equatable, Identifiable, Sendable {
    case session(AgentSession, indentLevel: Int)
    case header(String)

    public var id: String {
        switch self {
        case .session(let session, let indentLevel):
            "\(session.id):\(indentLevel)"
        case .header(let title):
            "header:\(title)"
        }
    }
}

public final class AgentStateStore: ObservableObject {
    @Published public private(set) var sessions: [AgentSession]

    public var maxHistoryPerAgent: Int
    public var historyVisibilityInterval: TimeInterval
    public var activeStaleInterval: TimeInterval

    private let persistence: StatePersistence?
    private let clock: () -> Date

    public init(
        persistence: StatePersistence? = StatePersistence(),
        maxHistoryPerAgent: Int = 5,
        historyVisibilityInterval: TimeInterval = 24 * 60 * 60,
        activeStaleInterval: TimeInterval = 10 * 60,
        clock: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.maxHistoryPerAgent = maxHistoryPerAgent
        self.historyVisibilityInterval = historyVisibilityInterval
        self.activeStaleInterval = activeStaleInterval
        self.clock = clock

        if let document = try? persistence?.load() {
            sessions = document.sessions
        } else {
            sessions = []
        }
    }

    @discardableResult
    public func apply(_ event: AgentEvent) -> AgentSession {
        let now = event.updatedAt ?? clock()
        let key = Self.key(agent: event.agent, sessionId: event.sessionId)
        let existing = sessions.first { Self.key(agent: $0.agent, sessionId: $0.sessionId) == key }

        let next = AgentSession(
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            title: event.title.isEmpty ? (existing?.title ?? "") : event.title,
            cwd: event.cwd.isEmpty ? (existing?.cwd ?? "") : event.cwd,
            event: event.event.isEmpty ? (existing?.event ?? "") : event.event,
            terminal: event.terminal.isEmpty ? (existing?.terminal ?? "") : event.terminal,
            pid: event.pid ?? existing?.pid,
            updatedAt: now,
            parentSessionId: event.parentSessionId ?? existing?.parentSessionId,
            subagentNickname: event.subagentNickname ?? existing?.subagentNickname,
            subagentRole: event.subagentRole ?? existing?.subagentRole,
            subagentDepth: event.subagentDepth ?? existing?.subagentDepth
        )

        if let index = sessions.firstIndex(where: { Self.key(agent: $0.agent, sessionId: $0.sessionId) == key }) {
            sessions[index] = next
        } else {
            sessions.append(next)
        }

        trimStoredSessions(now: now)
        persist()
        return next
    }

    public func visibleSessions(for agent: AgentKind, now: Date = Date()) -> [AgentSession] {
        let visible = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
            .sorted(by: sessionSort)
            .filter { session in
                session.state.isActive || now.timeIntervalSince(session.updatedAt) <= historyVisibilityInterval
            }
            .prefix(maxHistoryPerAgent)

        return Array(visible)
    }

    public func displayRows(for agent: AgentKind, now: Date = Date()) -> [AgentSessionDisplayRow] {
        let visible = visibleSessions(for: agent, now: now)
        let allAgentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }

        return Self.displayRows(visibleSessions: visible, allSessions: allAgentSessions)
    }

    public static func displayRows(
        visibleSessions: [AgentSession],
        allSessions: [AgentSession]
    ) -> [AgentSessionDisplayRow] {
        var rows: [AgentSessionDisplayRow] = []
        var renderedSessionIds: Set<String> = []
        var orphanSubagents: [AgentSession] = []

        let allBySessionId = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.sessionId, $0) })
        let topLevelSessions = visibleSessions.filter { !$0.isSubagent }
        let subagents = visibleSessions.filter(\.isSubagent)
        let subagentsByParent = Dictionary(grouping: subagents) { $0.parentSessionId ?? "" }

        func append(_ session: AgentSession, indentLevel: Int) {
            rows.append(.session(session, indentLevel: indentLevel))
            renderedSessionIds.insert(session.sessionId)
        }

        func appendSubagents(parentSessionId: String) {
            for subagent in subagentsByParent[parentSessionId, default: []] {
                append(subagent, indentLevel: 1)
            }
        }

        for session in topLevelSessions {
            append(session, indentLevel: 0)
            appendSubagents(parentSessionId: session.sessionId)
        }

        for subagent in subagents where !renderedSessionIds.contains(subagent.sessionId) {
            guard let parentSessionId = subagent.parentSessionId, !parentSessionId.isEmpty else {
                orphanSubagents.append(subagent)
                continue
            }

            if let parent = allBySessionId[parentSessionId], !renderedSessionIds.contains(parent.sessionId) {
                append(parent, indentLevel: 0)
                appendSubagents(parentSessionId: parent.sessionId)
            } else if allBySessionId[parentSessionId] == nil {
                orphanSubagents.append(subagent)
            }
        }

        if !orphanSubagents.isEmpty {
            rows.append(.header("Sub-agents"))
            for subagent in orphanSubagents where !renderedSessionIds.contains(subagent.sessionId) {
                append(subagent, indentLevel: 1)
            }
        }

        return rows
    }

    public func aggregateState(for agent: AgentKind, now: Date = Date()) -> AgentState {
        let visible = visibleSessions(for: agent, now: now)
        if visible.contains(where: { $0.state == .waiting }) {
            return .waiting
        }
        if visible.contains(where: { $0.state == .working }) {
            return .working
        }
        if visible.contains(where: { $0.state == .idle }) {
            return .idle
        }
        if visible.contains(where: { $0.state == .ended }) {
            return .ended
        }
        return .idle
    }

    public func reloadFromDisk() {
        guard let document = try? persistence?.load() else {
            return
        }
        sessions = document.sessions
    }

    public func removeSessions(where shouldRemove: (AgentSession) -> Bool) {
        let originalCount = sessions.count
        sessions.removeAll(where: shouldRemove)

        guard sessions.count != originalCount else {
            return
        }

        persist()
    }

    public func expireStaleActiveSessions(now: Date = Date()) {
        var changed = false
        sessions = sessions.map { session in
            let next = sessionForDisplay(session, now: now)
            if next.state != session.state {
                changed = true
            }
            return next
        }

        guard changed else {
            return
        }

        trimStoredSessions(now: now)
        persist()
    }

    private func persist() {
        try? persistence?.save(AgentsBarDocument(sessions: sessions.sorted(by: sessionSort)))
    }

    private func trimStoredSessions(now: Date) {
        var retained: [AgentSession] = []

        for agent in AgentKind.allCases {
            let allAgentSessions = sessions.filter { $0.agent == agent }
                .map { sessionForDisplay($0, now: now) }
            var agentSessions = allAgentSessions
                .filter { session in
                    session.state.isActive || now.timeIntervalSince(session.updatedAt) <= historyVisibilityInterval
                }
                .sorted(by: sessionSort)
                .prefix(maxHistoryPerAgent)
                .map { $0 }
            var retainedIds = Set(agentSessions.map(\.sessionId))
            let parentIds = agentSessions.compactMap(\.parentSessionId)
            for parentId in parentIds where !retainedIds.contains(parentId) {
                if let parent = allAgentSessions.first(where: { $0.sessionId == parentId }) {
                    agentSessions.append(parent)
                    retainedIds.insert(parent.sessionId)
                }
            }
            retained.append(contentsOf: agentSessions)
        }

        sessions = retained.sorted(by: sessionSort)
    }

    private func sessionForDisplay(_ session: AgentSession, now: Date) -> AgentSession {
        guard session.state.isActive,
              now.timeIntervalSince(session.updatedAt) > activeStaleInterval else {
            return session
        }

        var next = session
        next.state = .idle
        return next
    }

    private func sessionSort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.state.isActive != rhs.state.isActive {
            return lhs.state.isActive
        }

        if priority(lhs.state) != priority(rhs.state) {
            return priority(lhs.state) < priority(rhs.state)
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.sessionId < rhs.sessionId
    }

    private func priority(_ state: AgentState) -> Int {
        switch state {
        case .waiting:
            0
        case .working:
            1
        case .idle:
            2
        case .ended:
            3
        }
    }

    private static func key(agent: AgentKind, sessionId: String) -> String {
        "\(agent.rawValue):\(sessionId)"
    }
}
