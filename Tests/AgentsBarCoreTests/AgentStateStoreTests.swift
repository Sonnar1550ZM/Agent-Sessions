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

    func testLatestResponsePersistsAcrossMetadataOnlyUpdates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, clock: { now })

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .working,
            transcriptPath: "/tmp/a.jsonl",
            latestResponseText: "確認しています。",
            latestResponsePhase: "commentary"
        ))
        store.apply(AgentEvent(agent: .codex, sessionId: "a", state: .idle, title: "Updated title"))

        let session = store.visibleSessions(for: .codex, now: now).first
        XCTAssertEqual(session?.transcriptPath, "/tmp/a.jsonl")
        XCTAssertEqual(session?.latestResponseText, "確認しています。")
        XCTAssertEqual(session?.latestResponsePhase, "commentary")
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

    func testEndedSessionsAreNotVisible() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "ended", state: .ended, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "idle", state: .idle, updatedAt: base.addingTimeInterval(1)))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(2)).map(\.sessionId),
            ["idle"]
        )
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(2)).map(\.id), [
            "codex:idle:0"
        ])
        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(2)), .idle)
    }

    func testCodexMemoryWorkspaceSessionsAreNotVisible() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)
        let memoriesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/memories", isDirectory: true)
            .path

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "memory",
            state: .working,
            title: "memories",
            cwd: memoriesPath,
            updatedAt: base
        ))

        XCTAssertEqual(store.visibleSessions(for: .codex, now: base.addingTimeInterval(1)), [])
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(1)), [])
        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(1)), .idle)
    }

    func testOrdinaryMemoriesProjectSessionIsVisible() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "project",
            state: .idle,
            title: "memories",
            cwd: "/tmp/memories",
            updatedAt: base
        ))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(1)).map(\.sessionId),
            ["project"]
        )
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(1)).map(\.id), [
            "codex:project:0"
        ])
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

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle))
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

        let session = store.sessions.first { $0.sessionId == "child" }
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

    func testDisplayRowsHidesOrphanSubagentsWhenParentIsMissing() {
        let base = Date(timeIntervalSince1970: 1_000)
        let child = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "missing"
        )

        let rows = AgentStateStore.displayRows(visibleSessions: [child], allSessions: [child])

        XCTAssertEqual(rows, [])
    }

    func testDisplayRowsShowsWorkingSubagentsUnderVisibleParent() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 1)

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        let rows = store.displayRows(for: .codex, now: base.addingTimeInterval(2))
        XCTAssertEqual(rows.map(\.id), [
            "codex:parent:0",
            "codex:child:1"
        ])
    }

    func testSubagentToggleHidesSubagentsAndTheirState() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 1, showsSubagents: false)

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(2)).map(\.id), [
            "codex:parent:0",
        ])
        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(2)), .idle)
    }

    func testSubagentToggleDoesNotDeleteStoredSubagents() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 1, showsSubagents: false)

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        XCTAssertEqual(Set(store.sessions.map(\.sessionId)), ["parent", "child"])
        store.showsSubagents = true

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(2)).map(\.id), [
            "codex:parent:0",
            "codex:child:1"
        ])
    }

    func testSubagentRowsHideWhenTimestampIsThreeMinutesOld() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 1)

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .idle,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(180)).map(\.id), [
            "codex:parent:0",
            "codex:child:1"
        ])
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(181)).map(\.id), [
            "codex:parent:0",
        ])
    }

    func testSubagentRowsRespectConfiguredHideAfterInterval() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(
            persistence: nil,
            maxHistoryPerAgent: 1,
            subagentHideAfterInterval: 5 * 60
        )

        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .idle,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "parent"
        ))

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(300)).map(\.id), [
            "codex:parent:0",
            "codex:child:1"
        ])
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(301)).map(\.id), [
            "codex:parent:0",
        ])
    }

    func testDisplayRowsTemporarilyIncludesStoredParentForRecentInactiveSubagentOutsideParentLimit() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 1)

        store.apply(AgentEvent(agent: .codex, sessionId: "old-parent", state: .idle, updatedAt: base))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "recent-child",
            state: .idle,
            updatedAt: base.addingTimeInterval(1),
            parentSessionId: "old-parent"
        ))
        store.apply(AgentEvent(agent: .codex, sessionId: "recent-parent", state: .idle, updatedAt: base.addingTimeInterval(2)))

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(100)).map(\.id), [
            "codex:recent-parent:0",
            "codex:old-parent:0",
            "codex:recent-child:1"
        ])
        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(181)).map(\.id), [
            "codex:recent-parent:0"
        ])
    }

    func testAggregateStateIgnoresOrphanSubagentWhenParentIsMissing() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base,
            parentSessionId: "missing"
        ))

        XCTAssertEqual(store.displayRows(for: .codex, now: base.addingTimeInterval(1)), [])
        XCTAssertEqual(store.aggregateState(for: .codex, now: base.addingTimeInterval(1)), .idle)
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
          "subagent_depth": 1,
          "transcript_path": "/tmp/parent/subagents/agent-a.jsonl",
          "latest_response_text": "進めています。",
          "latest_response_phase": "commentary"
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
        XCTAssertEqual(decoded.transcriptPath, "/tmp/parent/subagents/agent-a.jsonl")
        XCTAssertEqual(decoded.latestResponseText, "進めています。")
        XCTAssertEqual(decoded.latestResponsePhase, "commentary")
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

    func testClaudeSubagentDisplayTitleUsesNickname() {
        let session = AgentSession(
            agent: .claudeCode,
            sessionId: "parent/subagents/agent-a8142726721de1817",
            state: .working,
            cwd: "/tmp/project",
            parentSessionId: "parent",
            subagentNickname: "agent-a8142726721de1817",
            subagentRole: "Claude",
            subagentDepth: 1
        )

        XCTAssertEqual(session.displayTitle, "agent-a8142726721de1817")
    }

    func testSubagentDisplayLabelUsesRoleInsteadOfNickname() {
        let session = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            title: "Session Count実装を確認",
            parentSessionId: "parent",
            subagentNickname: "Rawls",
            subagentRole: "explorer",
            subagentDepth: 1
        )

        XCTAssertEqual(session.subagentDisplayLabel, "Session Count実装を確認 · Explorer · Rawls")
    }

    func testSubagentSessionTitleUsesExplicitTitle() {
        let session = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            title: "Session Count実装を確認",
            parentSessionId: "parent",
            subagentNickname: "Rawls",
            subagentRole: "explorer",
            subagentDepth: 1
        )

        XCTAssertEqual(session.subagentSessionTitle, "Session Count実装を確認")
    }

    func testSubagentNameAndRoleLabelShowsNameBeforeRole() {
        let session = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            title: "Session Count実装を確認",
            parentSessionId: "parent",
            subagentNickname: "Rawls",
            subagentRole: "explorer",
            subagentDepth: 1
        )

        XCTAssertEqual(session.subagentNameAndRoleLabel, "Rawls · Explorer")
    }

    func testSubagentDisplayLabelDeduplicatesRoleTitle() {
        let session = AgentSession(
            agent: .claudeCode,
            sessionId: "parent/subagents/agent-a2d0709031a162f40",
            state: .working,
            title: "general-purpose",
            parentSessionId: "parent",
            subagentNickname: "a2d0709031a162f40",
            subagentRole: "general-purpose",
            subagentDepth: 1
        )

        XCTAssertEqual(session.subagentDisplayLabel, "General Purpose · a2d0709031a162f40")
    }

    func testSubagentDisplayLabelFallsBackToRoleWhenTitleIsMissing() {
        let session = AgentSession(
            agent: .codex,
            sessionId: "child",
            state: .working,
            parentSessionId: "parent",
            subagentNickname: "Rawls",
            subagentRole: "explorer",
            subagentDepth: 1
        )

        XCTAssertEqual(session.subagentDisplayLabel, "Explorer · Rawls")
    }
}
