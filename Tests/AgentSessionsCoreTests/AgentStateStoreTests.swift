import XCTest
@testable import AgentSessionsCore

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
        let responseTime = Date(timeIntervalSince1970: 1_000)
        let metadataTime = responseTime.addingTimeInterval(60)
        let store = AgentStateStore(persistence: nil, clock: { metadataTime })

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .working,
            updatedAt: responseTime,
            transcriptPath: "/tmp/a.jsonl",
            latestResponseText: "確認しています。",
            latestResponsePhase: "commentary"
        ))
        store.apply(AgentEvent(agent: .codex, sessionId: "a", state: .idle, title: "Updated title"))

        let session = store.visibleSessions(for: .codex, now: metadataTime).first
        XCTAssertEqual(session?.transcriptPath, "/tmp/a.jsonl")
        XCTAssertEqual(session?.latestResponseText, "確認しています。")
        XCTAssertEqual(session?.latestResponsePhase, "commentary")
        XCTAssertEqual(session?.latestResponseUpdatedAt, responseTime)
        XCTAssertEqual(session?.updatedAt, metadataTime)
    }

    func testLatestResponseTimestampUpdatesWhenBodyChanges() {
        let firstTime = Date(timeIntervalSince1970: 1_000)
        let secondTime = firstTime.addingTimeInterval(30)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .working,
            updatedAt: firstTime,
            latestResponseText: "First"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .working,
            updatedAt: secondTime,
            latestResponseText: "Second"
        ))

        let session = store.visibleSessions(for: .codex, now: secondTime).first
        XCTAssertEqual(session?.latestResponseText, "Second")
        XCTAssertEqual(session?.latestResponseUpdatedAt, secondTime)
    }

    func testLatestResponseClearsWhenNewUserPromptStarts() {
        let responseTime = Date(timeIntervalSince1970: 1_000)
        let promptTime = responseTime.addingTimeInterval(30)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .idle,
            updatedAt: responseTime,
            latestResponseText: "Previous response",
            latestResponsePhase: "final_answer"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "a",
            state: .working,
            event: "UserPromptSubmit",
            updatedAt: promptTime
        ))

        let session = store.visibleSessions(for: .codex, now: promptTime).first
        XCTAssertNil(session?.latestResponseText)
        XCTAssertNil(session?.latestResponsePhase)
        XCTAssertNil(session?.latestResponseUpdatedAt)
    }

    func testLatestPopupParentSessionUsesNewestSessionTimestamp() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "older-session",
            state: .idle,
            updatedAt: base.addingTimeInterval(20),
            latestResponseText: "Newer response"
        ))
        store.apply(AgentEvent(
            agent: .claudeCode,
            sessionId: "newer-session",
            state: .idle,
            updatedAt: base.addingTimeInterval(30),
            latestResponseText: "Older response"
        ))
        store.apply(AgentEvent(
            agent: .claudeCode,
            sessionId: "newer-session",
            state: .idle,
            title: "Metadata only",
            updatedAt: base.addingTimeInterval(40)
        ))

        let session = store.latestPopupParentSession(
            now: base.addingTimeInterval(41),
            displayInterval: 10
        )

        XCTAssertEqual(session?.sessionId, "newer-session")
    }

    func testLatestPopupParentSessionExcludesSubagentsAndOldIdleSessions() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "parent",
            state: .idle,
            updatedAt: base,
            latestResponseText: "Parent"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "child",
            state: .working,
            updatedAt: base.addingTimeInterval(50),
            parentSessionId: "parent",
            latestResponseText: "Child"
        ))

        XCTAssertNil(store.latestPopupParentSession(
            now: base.addingTimeInterval(11),
            displayInterval: 10
        ))
    }

    func testLatestPopupParentSessionKeepsActiveSessionPastIdleDisplayInterval() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, activeStaleInterval: 60)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "active",
            state: .working,
            updatedAt: base,
            latestResponseText: "Still working"
        ))

        let session = store.latestPopupParentSession(
            now: base.addingTimeInterval(9),
            displayInterval: 1
        )

        XCTAssertEqual(session?.sessionId, "active")
    }

    func testLatestPopupParentSessionIncludesActiveSessionWithoutResponseText() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, activeStaleInterval: 60)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "thinking",
            state: .working,
            updatedAt: base
        ))

        let session = store.latestPopupParentSession(
            now: base.addingTimeInterval(9),
            displayInterval: 1
        )

        XCTAssertEqual(session?.sessionId, "thinking")
    }

    func testLatestPopupParentSessionExcludesIdleSessionWithoutResponseText() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "idle-without-response",
            state: .idle,
            updatedAt: base
        ))

        XCTAssertNil(store.latestPopupParentSession(
            now: base.addingTimeInterval(1),
            displayInterval: 10
        ))
    }

    func testLatestPopupParentSessionKeepsFreshlyIdleSessionWhenEventTimestampIsOld() {
        let base = Date(timeIntervalSince1970: 1_000)
        let idleTransitionTime = base.addingTimeInterval(121)
        let store = AgentStateStore(persistence: nil, clock: { idleTransitionTime })

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "parent",
            state: .working,
            updatedAt: base,
            latestResponseText: "Finished response"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "parent",
            state: .idle,
            updatedAt: base,
            latestResponseText: "Finished response"
        ))

        XCTAssertEqual(
            store.latestPopupParentSession(
                now: idleTransitionTime.addingTimeInterval(1),
                displayInterval: 5
            )?.sessionId,
            "parent"
        )
        XCTAssertNil(store.latestPopupParentSession(
            now: idleTransitionTime.addingTimeInterval(6),
            displayInterval: 5
        ))
    }

    func testLatestPopupParentSessionKeepsStaleActiveSessionAfterDisplayIdleTransition() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil, activeStaleInterval: 60)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "stale-active",
            state: .working,
            updatedAt: base,
            latestResponseText: "Finished response"
        ))

        let session = store.latestPopupParentSession(
            now: base.addingTimeInterval(62),
            displayInterval: 5
        )
        XCTAssertEqual(session?.sessionId, "stale-active")
        XCTAssertEqual(session?.state, .idle)
        XCTAssertNil(store.latestPopupParentSession(
            now: base.addingTimeInterval(66),
            displayInterval: 5
        ))
    }

    func testLatestPopupParentSessionRespectsIncludedProviders() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "codex",
            state: .idle,
            updatedAt: base.addingTimeInterval(1),
            latestResponseText: "Codex"
        ))
        store.apply(AgentEvent(
            agent: .claudeCode,
            sessionId: "claude",
            state: .idle,
            updatedAt: base.addingTimeInterval(2),
            latestResponseText: "Claude"
        ))

        let session = store.latestPopupParentSession(
            now: base.addingTimeInterval(3),
            displayInterval: 60,
            includedAgents: [.codex]
        )

        XCTAssertEqual(session?.sessionId, "codex")
    }

    func testPopupParentSessionsRespectLimit() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        for index in 0..<4 {
            store.apply(AgentEvent(
                agent: .codex,
                sessionId: "parent-\(index)",
                state: .idle,
                updatedAt: base.addingTimeInterval(TimeInterval(index)),
                latestResponseText: "Response \(index)"
            ))
        }

        let sessions = store.popupParentSessions(
            now: base.addingTimeInterval(5),
            displayInterval: 10,
            limit: 2
        )

        XCTAssertEqual(sessions.map(\.sessionId), ["parent-3", "parent-2"])
    }

    func testPopupParentSessionsOnlyShowsSessionsMatchingPopupConditions() {
        let base = Date(timeIntervalSince1970: 1_000)
        let store = AgentStateStore(persistence: nil)

        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "old-idle",
            state: .idle,
            updatedAt: base,
            latestResponseText: "Older response"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "working",
            state: .working,
            updatedAt: base.addingTimeInterval(80),
            latestResponseText: "Working response"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "recent-idle",
            state: .idle,
            updatedAt: base.addingTimeInterval(100),
            latestResponseText: "Recent response"
        ))

        let sessions = store.popupParentSessions(
            now: base.addingTimeInterval(104),
            displayInterval: 5,
            limit: 3
        )

        XCTAssertEqual(sessions.map(\.sessionId), ["recent-idle", "working"])
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

    func testWorkingSessionCountsSeparateMainAndSubagents() {
        let store = AgentStateStore(persistence: nil)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "main-working", state: .working, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "main-waiting", state: .waiting, updatedAt: base.addingTimeInterval(1)))
        store.apply(AgentEvent(agent: .codex, sessionId: "parent", state: .idle, updatedAt: base.addingTimeInterval(2)))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "subagent-working",
            state: .working,
            updatedAt: base.addingTimeInterval(3),
            parentSessionId: "parent"
        ))
        store.apply(AgentEvent(
            agent: .codex,
            sessionId: "orphan-subagent",
            state: .working,
            updatedAt: base.addingTimeInterval(4),
            parentSessionId: "missing"
        ))
        store.apply(AgentEvent(agent: .claudeCode, sessionId: "other-agent", state: .working, updatedAt: base.addingTimeInterval(5)))

        XCTAssertEqual(
            store.workingSessionCounts(for: .codex, now: base.addingTimeInterval(6)),
            AgentWorkingSessionCounts(main: 1, subagent: 1)
        )
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

    func testStoredSessionsKeepRetentionBufferBeyondVisibleLimit() {
        let store = AgentStateStore(persistence: nil, maxHistoryPerAgent: 2)
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "idle", state: .idle, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "working", state: .working, updatedAt: base.addingTimeInterval(1)))
        store.apply(AgentEvent(agent: .codex, sessionId: "waiting", state: .waiting, updatedAt: base.addingTimeInterval(2)))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(3)).map(\.sessionId),
            ["waiting", "working"]
        )
        XCTAssertEqual(store.sessions.map(\.sessionId), ["waiting", "working", "idle"])
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

    func testHiddenHistoryReappearsWhenHideAfterIsIncreased() {
        let store = AgentStateStore(
            persistence: nil,
            maxHistoryPerAgent: 5,
            historyVisibilityInterval: 60
        )
        let base = Date(timeIntervalSince1970: 1_000)

        store.apply(AgentEvent(agent: .codex, sessionId: "old", state: .idle, updatedAt: base))
        store.apply(AgentEvent(agent: .codex, sessionId: "recent", state: .idle, updatedAt: base.addingTimeInterval(100)))

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(100)).map(\.sessionId),
            ["recent"]
        )
        XCTAssertTrue(store.sessions.contains { $0.sessionId == "old" })

        store.historyVisibilityInterval = 120

        XCTAssertEqual(
            store.visibleSessions(for: .codex, now: base.addingTimeInterval(100)).map(\.sessionId),
            ["recent", "old"]
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
            .appendingPathComponent("agent-sessions-\(UUID().uuidString).json")
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

    func testAgentEventFallsBackToTranscriptFileNameForSessionId() throws {
        let json = """
        {
          "agent": "Claude",
          "state": "Working",
          "transcript_path": "/tmp/project/session-from-file.jsonl"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AgentEvent.self, from: json)

        XCTAssertEqual(event.sessionId, "session-from-file")
        XCTAssertEqual(event.transcriptPath, "/tmp/project/session-from-file.jsonl")
    }

    func testAgentEventRejectsMissingSessionId() {
        let json = """
        {
          "agent": "Codex",
          "state": "Working"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AgentEvent.self, from: json))
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
