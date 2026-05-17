import XCTest
@testable import AgentsBarCore

final class AgentStateStoreTests: XCTestCase {
    func testSameSessionUpdatesExistingRow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, clock: { now })

        store.apply(AgentEvent(agent: .codex, sessionId: "a", state: .working, title: "First"))
        store.apply(AgentEvent(agent: .codex, sessionId: "a", state: .waiting, title: "Second"))

        let sessions = store.visibleSessions(for: .codex, now: now)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "a")
        XCTAssertEqual(sessions[0].state, .waiting)
        XCTAssertEqual(sessions[0].title, "Second")
    }

    func testDifferentSessionsCreateSeparateRows() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, clock: { now })

        store.apply(AgentEvent(agent: .codex, sessionId: "a", state: .working, title: "A"))
        store.apply(AgentEvent(agent: .codex, sessionId: "b", state: .working, title: "B"))

        let sessionIds = store.visibleSessions(for: .codex, now: now).map(\.sessionId)
        XCTAssertEqual(Set(sessionIds), ["a", "b"])
    }

    func testActiveSessionsSortBeforeHistoryThenByRecency() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "old-idle", state: .idle, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "waiting", state: .waiting, updatedAt: base.addingTimeInterval(10)))
        store.apply(AgentEvent(agent: .codex, sessionId: "working", state: .working, updatedAt: base.addingTimeInterval(5)))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(20)).map(\.sessionId),
            ["waiting", "working", "old-idle"]
        )
    }

    func testAggregateStatePrioritizesWaitingBeforeWorking() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "working", state: .working, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "waiting", state: .waiting, updatedAt: base.addingTimeInterval(1)))

        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(2)), .waiting)
    }

    func testHistoryIsLimitedPerAgent() {
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 5)
        let base = Date(timeIntervalSince1970: 1_000)

        for index in 0..<7 {
            store.apply(AgentEvent(
                agent: .claudeCode,
                sessionId: "idle-\(index)",
                state: .idle,
                updatedAt: base.addingTimeInterval(TimeInterval(index))
            ))
        }

        let visible = store.visibleSessions(for: .claudeCode, now: base.addingTimeInterval(100))
        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.map(\.sessionId), ["idle-6", "idle-5", "idle-4", "idle-3", "idle-2"])
    }

    func testSessionLimitCountsActiveAndHistoryTogether() {
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 3)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .claudeCode, sessionId: "old-idle", state: .idle, updatedAt: base))
        store.apply(AgentEvent(agent: .claudeCode, sessionId: "recent-idle", state: .idle, updatedAt: base.addingTimeInterval(1)))
        store.apply(AgentEvent(agent: .claudeCode, sessionId: "working", state: .working, updatedAt: base.addingTimeInterval(2)))
        store.apply(AgentEvent(agent: .claudeCode, sessionId: "waiting", state: .waiting, updatedAt: base.addingTimeInterval(3)))
        store.apply(AgentEvent(agent: .claudeCode, sessionId: "latest-idle", state: .idle, updatedAt: base.addingTimeInterval(4)))

        let visible = store.visibleSessions(for: .claudeCode, now: base.addingTimeInterval(5))
        XCTAssertEqual(visible.map(\.sessionId), ["waiting", "working", "latest-idle"])
    }

    func testStoredSessionsAreTrimmedAcrossAllStates() {
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 2)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "idle", state: .idle, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "working", state: .working, updatedAt: base.addingTimeInterval(1)))
        store.apply(AgentEvent(agent: .codex, sessionId: "waiting", state: .waiting, updatedAt: base.addingTimeInterval(2)))

        XCTAssertEqual(store.sessions.map(\.sessionId), ["waiting", "working"])
    }

    func testOldHistoryIsHidden() {
        let store = AgentStateStore(
            persistence: nil,
            maxHistoryPerAgent: 5,
            historyVisibilityInterval: 60
        )
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "old", state: .ended, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "recent", state: .idle, updatedAt: base.addingTimeInterval(55)))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(100)).map(\.sessionId),
            ["recent"]
        )
    }

    func testStaleActiveSessionIsDisplayedAsIdle() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(
            persistence: nil,
            activeStaleInterval: 60
        )

        store.apply(AgentEvent(agent: .codex, sessionId: "stale", state: .working, updatedAt: base))

        let visible = store.visibleSessions(for: .codex, now: base.addingTimeInterval(61))
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].sessionId, "stale")
        XCTAssertEqual(visible[0].state, .idle)
    }

    func testExpireStaleActiveSessionsPersistsIdleStateInMemory() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(
            persistence: nil,
            activeStaleInterval: 60
        )

        store.apply(AgentEvent(agent: .codex, sessionId: "stale", state: .working, updatedAt: base))
        store.expireStaleActiveSessions(now: base.addingTimeInterval(61))

        XCTAssertEqual(store.sessions.first?.state, .idle)
    }

    func testApplyPreservesSubagentMetadataWhenLaterEventOmitsIt() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, clock: { now })

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            parentSessionId: "parent",
            subagentNickname: "Sagan",
            subagentRole: "explorer",
            subagentDepth: 1
        ))
        store.apply(AgentEvent(agent: .codex, sessionId: "child", state: .idle))

        let session = store.sessions.first
        XCTAssertEqual(session?.parentSessionId, "parent")
        XCTAssertEqual(session?.subagentNickname, "Sagan")
        XCTAssertEqual(session?.subagentRole, "explorer")
        XCTAssertEqual(session?.subagentDepth, 1)
    }

    func testDisplayRowsNestSubagentsUnderVisibleParent() {
        let base = Date(timeIntervalSince1970: 1_000)
        let parent = AgentSession(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base)
        let child = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent",
            subagentNickname: "Sagan",
            subagentRole: "explorer"
        )

        let rows = AgentStateStore.displayRows(visibleSessions: [parent, child], allSessions: [parent, child])

        XCTAssertEqual(rows, [
            .session(parent, indentLevel: 0),
            .session(child, indentLevel: 1)
        ])
    }

    func testDisplayRowsTemporarilyIncludesStoredParentForVisibleChild() {
        let base = Date(timeIntervalSince1970: 1_000)
        let parent = AgentSession(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base)
        let child = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        )

        let rows = AgentStateStore.displayRows(visibleSessions: [child], allSessions: [parent, child])

        XCTAssertEqual(rows, [
            .session(parent, indentLevel: 0),
            .session(child, indentLevel: 1)
        ])
    }

    func testDisplayRowsFallsBackToSubagentsHeaderWhenParentIsMissing() {
        let base = Date(timeIntervalSince1970: 1_000)
        let child = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "missing"
        )

        let rows = AgentStateStore.displayRows(visibleSessions: [child], allSessions: [child])

        XCTAssertEqual(rows, [
            .header("Sub-agents"),
            .session(child, indentLevel: 1)
        ])
    }

    func testAggregateStateIncludesSubagentState() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(2)), .working)
    }

    func testAgentSessionDecodesOldPersistedStateWithoutSubagentMetadata() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsbar-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let json = """
        {
          "sessions": [
            {
              "agent": "codex",
              "sessionId": "old",
              "state": "idle",
              "title": "Old",
              "cwd": "",
              "event": "",
              "terminal": "",
              "updatedAt": "2026-05-17T00:00:00.000Z"
            }
          ]
        }
        """
        try Data(json.utf8).write(to: stateURL)

        let document = try StatePersistence(stateURL: stateURL).load()

        XCTAssertEqual(document.sessions.count, 1)
        XCTAssertNil(document.sessions[0].parentSessionId)
        XCTAssertNil(document.sessions[0].subagentNickname)
        XCTAssertNil(document.sessions[0].subagentRole)
        XCTAssertNil(document.sessions[0].subagentDepth)
    }

    func testAgentEventDecodesAndEncodesSubagentMetadata() throws {
        let json = """
        {
          "agent": "Codex",
          "session_id": "child",
          "state": "Working",
          "parent_session_id": "parent",
          "subagent_nickname": "Sagan",
          "subagent_role": "explorer",
          "subagent_depth": 1
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AgentEvent.self, from: json)
        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: encoded)

        XCTAssertEqual(decoded.sessionId, "child")
        XCTAssertEqual(decoded.parentSessionId, "parent")
        XCTAssertEqual(decoded.subagentNickname, "Sagan")
        XCTAssertEqual(decoded.subagentRole, "explorer")
        XCTAssertEqual(decoded.subagentDepth, 1)
    }

    func testDecodesSnakeCaseSessionIdAndNormalizesClaude() throws {
        let json = """
        {
          "agent": "Claude",
          "session_id": "abc",
          "state": "Working",
          "title": "Implement",
          "cwd": "/tmp/project",
          "event": "UserPromptSubmit",
          "terminal": "Warp",
          "pid": 123
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AgentEvent.self, from: json)
        XCTAssertEqual(event.agent, .claudeCode)
        XCTAssertEqual(event.sessionId, "abc")
        XCTAssertEqual(event.state, .working)
        XCTAssertEqual(event.pid, 123)
    }

    func testCodexDisplayTitleDoesNotFallBackToProjectName() {
        let session = AgentSession(
            agent: .codex,
            sessionId: "abc",
            state: .working,
            cwd: "/tmp/project"
        )

        XCTAssertEqual(session.displayTitle, "Codex session")
    }

    func testClaudeDisplayTitleStillFallsBackToProjectName() {
        let session = AgentSession(
            agent: .claudeCode,
            sessionId: "abc",
            state: .working,
            cwd: "/tmp/project"
        )

        XCTAssertEqual(session.displayTitle, "project")
    }
}
