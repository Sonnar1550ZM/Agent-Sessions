import XCTest
@testable import AgentSessionsCore

final class WatcherCachePruningTests: XCTestCase {
    func testDropsEntriesOlderThanMaxAge() {
        let now = Date()
        let entries: [String: Date] = [
            "fresh": now.addingTimeInterval(-10),
            "stale": now.addingTimeInterval(-7_200)
        ]

        let pruned = WatcherCachePruning.prunedByAge(
            entries,
            lastSeenAt: { $0 },
            now: now,
            maxAge: 3_600,
            maxCount: 500
        )

        XCTAssertEqual(Set(pruned.keys), ["fresh"])
    }

    func testKeepsOnlyMostRecentEntriesWhenOverCount() {
        let now = Date()
        var entries: [String: Date] = [:]
        for index in 0..<10 {
            entries["entry-\(index)"] = now.addingTimeInterval(TimeInterval(-index))
        }

        let pruned = WatcherCachePruning.prunedByAge(
            entries,
            lastSeenAt: { $0 },
            now: now,
            maxAge: 3_600,
            maxCount: 3
        )

        XCTAssertEqual(Set(pruned.keys), ["entry-0", "entry-1", "entry-2"])
    }

    func testTouchedEntrySurvivesPruning() {
        let now = Date()
        var entries: [String: Date] = [
            "touched": now.addingTimeInterval(-7_200)
        ]
        entries["touched"] = now

        let pruned = WatcherCachePruning.prunedByAge(
            entries,
            lastSeenAt: { $0 },
            now: now,
            maxAge: 3_600,
            maxCount: 500
        )

        XCTAssertEqual(Set(pruned.keys), ["touched"])
    }

    func testInfiniteMaxAgeOnlyEnforcesCount() {
        let now = Date()
        let entries: [String: Date] = [
            "ancient": now.addingTimeInterval(-1_000_000),
            "recent": now
        ]

        let pruned = WatcherCachePruning.prunedByAge(
            entries,
            lastSeenAt: { $0 },
            now: now,
            maxAge: .infinity,
            maxCount: 1
        )

        XCTAssertEqual(Set(pruned.keys), ["recent"])
    }
}
