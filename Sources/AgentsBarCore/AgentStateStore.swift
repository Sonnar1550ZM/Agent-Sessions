import Combine
import Foundation

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
            updatedAt: now
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
        let agentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
        let active = agentSessions
            .filter(\.state.isActive)
            .sorted(by: sessionSort)

        let history = agentSessions
            .filter { !$0.state.isActive && now.timeIntervalSince($0.updatedAt) <= historyVisibilityInterval }
            .sorted(by: sessionSort)
            .prefix(maxHistoryPerAgent)

        return active + history
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
            let agentSessions = sessions.filter { $0.agent == agent }
            let active = agentSessions.filter(\.state.isActive)
            let history = agentSessions
                .filter { !$0.state.isActive && now.timeIntervalSince($0.updatedAt) <= historyVisibilityInterval }
                .sorted(by: sessionSort)
                .prefix(maxHistoryPerAgent)
            retained.append(contentsOf: active)
            retained.append(contentsOf: history)
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
