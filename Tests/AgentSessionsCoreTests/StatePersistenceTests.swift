import XCTest
@testable import AgentSessionsCore

final class StatePersistenceTests: XCTestCase {
    func testDefaultStateURLUsesAgentSessionsSupportDirectory() {
        let path = StatePersistence.defaultStateURL().path

        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Agent Sessions/state.json"))
    }

    func testLoadMigratesLegacyAgentsBarStateWhenNewStateIsMissing() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-sessions-state-\(UUID().uuidString)", isDirectory: true)
        let newStateURL = baseURL
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
        let legacyStateURL = baseURL
            .appendingPathComponent("AgentsBar", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        try FileManager.default.createDirectory(
            at: legacyStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyJSON = """
        {
          "sessions": [
            {
              "agent": "codex",
              "sessionId": "legacy",
              "state": "idle",
              "title": "",
              "cwd": "",
              "event": "",
              "terminal": "",
              "updatedAt": "2026-05-17T00:00:00.000Z"
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: legacyStateURL)

        let persistence = StatePersistence(stateURL: newStateURL, legacyStateURL: legacyStateURL)
        let loadedDocument = try persistence.load()

        XCTAssertEqual(loadedDocument.sessions.map(\.sessionId), ["legacy"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: newStateURL.path))
    }
}
