import Combine
import Foundation

public enum AgentSessionDisplayRow: Equatable, Identifiable, Sendable {
    case session(AgentSession, indentLevel: Int)

    public var id: String {
        switch self {
        case .session(let session, let indentLevel):
            "\(session.id):\(indentLevel)"
        }
    }
}

public struct AgentWorkingSessionCounts: Equatable, Sendable {
    public var main: Int
    public var subagent: Int

    public init(main: Int = 0, subagent: Int = 0) {
        self.main = main
        self.subagent = subagent
    }

    public var total: Int {
        main + subagent
    }
}

public final class AgentStateStore: ObservableObject {
    @Published public private(set) var sessions: [AgentSession]

    public var maxHistoryPerAgent: Int
    public var showsSubagents: Bool
    public var subagentHideAfterInterval: TimeInterval
    public var historyVisibilityInterval: TimeInterval
    public var historyRetentionInterval: TimeInterval
    public var historyRetentionLimitPerAgent: Int
    public var activeStaleInterval: TimeInterval

    private let persistence: StatePersistence?
    private let clock: () -> Date

    public init(
        persistence: StatePersistence? = StatePersistence(),
        maxHistoryPerAgent: Int = 5,
        showsSubagents: Bool = true,
        subagentHideAfterInterval: TimeInterval = 3 * 60,
        historyVisibilityInterval: TimeInterval = 24 * 60 * 60,
        historyRetentionInterval: TimeInterval = 7 * 24 * 60 * 60,
        historyRetentionLimitPerAgent: Int = 10,
        activeStaleInterval: TimeInterval = 10 * 60,
        clock: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.maxHistoryPerAgent = maxHistoryPerAgent
        self.showsSubagents = showsSubagents
        self.subagentHideAfterInterval = subagentHideAfterInterval
        self.historyVisibilityInterval = historyVisibilityInterval
        self.historyRetentionInterval = historyRetentionInterval
        self.historyRetentionLimitPerAgent = historyRetentionLimitPerAgent
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
        let receivedAt = clock()
        let now = event.updatedAt ?? receivedAt
        let key = Self.key(agent: event.agent, sessionId: event.sessionId)
        let existing = sessions.first { Self.key(agent: $0.agent, sessionId: $0.sessionId) == key }
        let clearsLatestResponse = Self.clearsLatestResponse(existing: existing, event: event)
        let latestResponseText = clearsLatestResponse
            ? nil
            : (event.latestResponseText ?? existing?.latestResponseText)
        let latestResponsePhase = clearsLatestResponse
            ? nil
            : (event.latestResponsePhase ?? existing?.latestResponsePhase)
        let latestResponseUpdatedAt = Self.latestResponseUpdatedAt(
            existing: existing,
            eventText: event.latestResponseText,
            resolvedText: latestResponseText,
            now: now
        )
        let stateChangedAt = Self.stateChangedAt(
            existing: existing,
            eventState: event.state,
            eventUpdatedAt: now,
            receivedAt: receivedAt
        )

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
            subagentDepth: event.subagentDepth ?? existing?.subagentDepth,
            transcriptPath: event.transcriptPath ?? existing?.transcriptPath,
            latestResponseText: latestResponseText,
            latestResponsePhase: latestResponsePhase,
            latestResponseUpdatedAt: latestResponseUpdatedAt,
            stateChangedAt: stateChangedAt
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
        let allAgentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
        let visible = displayEligibleSessions(from: allAgentSessions, now: now)
            .sorted(by: sessionSort)
            .prefix(maxHistoryPerAgent)

        return Array(visible)
    }

    public func displayRows(for agent: AgentKind, now: Date = Date()) -> [AgentSessionDisplayRow] {
        let allAgentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
        let eligibleSessions = displayEligibleSessions(from: allAgentSessions, now: now)
        let eligibleSessionIds = Set(eligibleSessions.map(\.sessionId))
        let visibleParents = Array(
            eligibleSessions
                .filter { !$0.isSubagent }
                .sorted(by: sessionSort)
                .prefix(maxHistoryPerAgent)
        )
        let visibleSubagents = displayEligibleSubagents(
            from: eligibleSessions.filter(\.isSubagent),
            now: now,
            visibleParentIds: Set(visibleParents.map(\.sessionId)),
            allSessionIds: eligibleSessionIds
        )
        let visible = (visibleParents + visibleSubagents).sorted(by: sessionSort)

        return Self.displayRows(visibleSessions: visible, allSessions: eligibleSessions)
    }

    public func latestPopupParentSession(
        now: Date = Date(),
        displayInterval: TimeInterval,
        includedAgents: Set<AgentKind> = Set(AgentKind.allCases)
    ) -> AgentSession? {
        popupParentSessions(
            now: now,
            displayInterval: displayInterval,
            includedAgents: includedAgents,
            limit: 1
        ).first
    }

    public func popupParentSessions(
        now: Date = Date(),
        displayInterval: TimeInterval,
        includedAgents: Set<AgentKind> = Set(AgentKind.allCases),
        limit: Int
    ) -> [AgentSession] {
        guard displayInterval > 0, !includedAgents.isEmpty, limit > 0 else {
            return []
        }

        return Array(sessions
            .map { sessionForDisplay($0, now: now) }
            .filter { session in
                guard includedAgents.contains(session.agent),
                      !session.isSubagent,
                      session.state != .ended,
                      !AgentSessionVisibility.isCodexMemoryWorkspace(agent: session.agent, cwd: session.cwd) else {
                    return false
                }

                let hasLatestResponseText = AgentTextSanitizer.latestResponseText(session.latestResponseText)?.isEmpty == false
                guard session.state.isActive || hasLatestResponseText else {
                    return false
                }

                return session.state.isActive || now.timeIntervalSince(popupDisplayReferenceDate(for: session)) <= displayInterval
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                let lhsResponseUpdatedAt = lhs.latestResponseUpdatedAt ?? lhs.updatedAt
                let rhsResponseUpdatedAt = rhs.latestResponseUpdatedAt ?? rhs.updatedAt
                if lhsResponseUpdatedAt != rhsResponseUpdatedAt {
                    return lhsResponseUpdatedAt > rhsResponseUpdatedAt
                }
                return lhs.sessionId < rhs.sessionId
            }
            .prefix(limit))
    }

    public static func displayRows(
        visibleSessions: [AgentSession],
        allSessions: [AgentSession]
    ) -> [AgentSessionDisplayRow] {
        var rows: [AgentSessionDisplayRow] = []
        var renderedSessionIds: Set<String> = []

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
                continue
            }

            if let parent = allBySessionId[parentSessionId], !renderedSessionIds.contains(parent.sessionId) {
                append(parent, indentLevel: 0)
                appendSubagents(parentSessionId: parent.sessionId)
            }
        }

        return rows
    }

    public func aggregateState(for agent: AgentKind, now: Date = Date()) -> AgentState {
        let allAgentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
        let eligibleSessions = displayEligibleSessions(from: allAgentSessions, now: now)
        let eligibleSessionIds = Set(eligibleSessions.map(\.sessionId))
        let visibleParents = eligibleSessions
            .filter { !$0.isSubagent }
        let visibleSubagents = displayEligibleSubagents(
            from: eligibleSessions.filter(\.isSubagent),
            now: now,
            visibleParentIds: Set(visibleParents.map(\.sessionId)),
            allSessionIds: eligibleSessionIds
        )
        let visible = visibleParents + visibleSubagents

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

    public func workingSessionCounts(for agent: AgentKind, now: Date = Date()) -> AgentWorkingSessionCounts {
        let allAgentSessions = sessions
            .filter { $0.agent == agent }
            .map { sessionForDisplay($0, now: now) }
        let eligibleSessions = displayEligibleSessions(from: allAgentSessions, now: now)
        let eligibleSessionIds = Set(eligibleSessions.map(\.sessionId))
        let mainSessions = eligibleSessions.filter { !$0.isSubagent }
        let subagentSessions = displayEligibleSubagents(
            from: eligibleSessions.filter(\.isSubagent),
            now: now,
            visibleParentIds: Set(mainSessions.map(\.sessionId)),
            allSessionIds: eligibleSessionIds
        )

        return AgentWorkingSessionCounts(
            main: mainSessions.filter { $0.state == .working }.count,
            subagent: subagentSessions.filter { $0.state == .working }.count
        )
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
        try? persistence?.save(AgentSessionsDocument(sessions: sessions.sorted(by: sessionSort)))
    }

    private func trimStoredSessions(now: Date) {
        var retained: [AgentSession] = []

        for agent in AgentKind.allCases {
            let allAgentSessions = sessions.filter { $0.agent == agent }
                .map { sessionForDisplay($0, now: now) }
            let retentionEligibleSessions = retentionEligibleSessions(from: allAgentSessions, now: now)
            let retentionLimit = max(maxHistoryPerAgent, historyRetentionLimitPerAgent)
            let retainedParents = Array(
                retentionEligibleSessions
                    .filter { !$0.isSubagent }
                    .sorted(by: sessionSort)
                    .prefix(retentionLimit)
            )
            let retainedSubagents = subagentsForRetention(
                from: retentionEligibleSessions.filter(\.isSubagent),
                now: now,
                retainedParentIds: Set(retainedParents.map(\.sessionId)),
                allSessionIds: Set(allAgentSessions.map(\.sessionId))
            )
            var agentSessions = retainedParents + retainedSubagents
            var retainedIds = Set(agentSessions.map(\.sessionId))

            for activeSession in allAgentSessions where activeSession.state.isActive && !retainedIds.contains(activeSession.sessionId) {
                agentSessions.append(activeSession)
                retainedIds.insert(activeSession.sessionId)
            }

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

    private func retentionEligibleSessions(from sessions: [AgentSession], now: Date) -> [AgentSession] {
        sessions.filter { session in
            session.state != .ended
                && !AgentSessionVisibility.isCodexMemoryWorkspace(agent: session.agent, cwd: session.cwd)
                && (session.state.isActive || now.timeIntervalSince(session.updatedAt) <= historyRetentionInterval)
        }
    }

    private func displayEligibleSessions(from sessions: [AgentSession], now: Date) -> [AgentSession] {
        sessions.filter { session in
            session.state != .ended
                && !AgentSessionVisibility.isCodexMemoryWorkspace(agent: session.agent, cwd: session.cwd)
                && (session.state.isActive || now.timeIntervalSince(session.updatedAt) <= historyVisibilityInterval)
        }
    }

    private func displayEligibleSubagents(
        from subagents: [AgentSession],
        now: Date,
        visibleParentIds: Set<String>,
        allSessionIds: Set<String>
    ) -> [AgentSession] {
        guard showsSubagents else {
            return []
        }

        let groupedSubagents = Dictionary(grouping: subagents.sorted(by: sessionSort)) { subagent in
            subagent.parentSessionId ?? ""
        }

        return groupedSubagents.values
            .flatMap { group -> [AgentSession] in
                let parentSessionId = group.first?.parentSessionId ?? ""
                let shouldDisplayGroup = visibleParentIds.contains(parentSessionId)
                    || group.contains { shouldDisplaySubagent($0, now: now) }
                guard hasKnownParent(group[0], allSessionIds: allSessionIds),
                      shouldDisplayGroup else {
                    return []
                }
                return group.filter { subagent in
                    shouldDisplaySubagent(subagent, now: now)
                }
            }
            .sorted(by: sessionSort)
    }

    private func shouldDisplaySubagent(_ session: AgentSession, now: Date) -> Bool {
        guard showsSubagents else {
            return false
        }

        if session.state == .working {
            return true
        }

        return isRecentSubagentTimestamp(session, now: now)
    }

    private func subagentsForRetention(
        from subagents: [AgentSession],
        now: Date,
        retainedParentIds: Set<String>,
        allSessionIds: Set<String>
    ) -> [AgentSession] {
        subagents
            .filter { subagent in
                guard hasKnownParent(subagent, allSessionIds: allSessionIds) else {
                    return false
                }

                let parentSessionId = subagent.parentSessionId ?? ""
                return retainedParentIds.contains(parentSessionId)
                    || subagent.state.isActive
                    || isRecentSubagentTimestamp(subagent, now: now)
            }
            .sorted(by: sessionSort)
    }

    private func isRecentSubagentTimestamp(_ session: AgentSession, now: Date) -> Bool {
        now.timeIntervalSince(session.updatedAt) < subagentHideAfterInterval
    }

    private func hasKnownParent(_ session: AgentSession, allSessionIds: Set<String>) -> Bool {
        guard let parentSessionId = session.parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parentSessionId.isEmpty else {
            return false
        }

        return allSessionIds.contains(parentSessionId)
    }

    private func sessionForDisplay(_ session: AgentSession, now: Date) -> AgentSession {
        guard session.state.isActive,
              now.timeIntervalSince(session.updatedAt) > activeStaleInterval else {
            return session
        }

        var next = session
        next.state = .idle
        next.stateChangedAt = session.updatedAt.addingTimeInterval(activeStaleInterval)
        return next
    }

    private func popupDisplayReferenceDate(for session: AgentSession) -> Date {
        max(session.stateChangedAt ?? session.updatedAt, session.updatedAt)
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

    private static func clearsLatestResponse(existing: AgentSession?, event: AgentEvent) -> Bool {
        guard event.latestResponseText == nil,
              existing?.latestResponseText != nil else {
            return false
        }

        if event.event == "UserPromptSubmit" || event.event == "user_message" {
            return true
        }

        return event.state == .working && existing?.state != .working
    }

    private static func latestResponseUpdatedAt(
        existing: AgentSession?,
        eventText: String?,
        resolvedText: String?,
        now: Date
    ) -> Date? {
        guard resolvedText != nil else {
            return nil
        }

        guard let eventText else {
            return existing?.latestResponseUpdatedAt ?? existing?.updatedAt
        }

        guard eventText == existing?.latestResponseText else {
            return now
        }

        return existing?.latestResponseUpdatedAt ?? existing?.updatedAt ?? now
    }

    private static func stateChangedAt(
        existing: AgentSession?,
        eventState: AgentState,
        eventUpdatedAt: Date,
        receivedAt: Date
    ) -> Date {
        guard let existing else {
            return eventUpdatedAt
        }

        guard existing.state != eventState else {
            return existing.stateChangedAt ?? existing.updatedAt
        }

        if existing.state.isActive,
           eventState == .idle,
           eventUpdatedAt <= existing.updatedAt {
            return receivedAt
        }

        return eventUpdatedAt
    }
}
