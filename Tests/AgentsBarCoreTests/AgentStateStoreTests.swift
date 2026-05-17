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
