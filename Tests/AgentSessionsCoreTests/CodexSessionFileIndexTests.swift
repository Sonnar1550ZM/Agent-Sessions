import XCTest
@testable import AgentSessionsCore

final class CodexSessionFileIndexTests: XCTestCase {
    func testDistinguishesActiveArchivedAndMissingSessions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-sessions-codex-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let activeRoot = root.appendingPathComponent("sessions", isDirectory: true)
        let archivedRoot = root.appendingPathComponent("archived_sessions", isDirectory: true)
        let activeSessionId = "019e36c4-f44c-7572-bfc0-7579a10fb363"
        let archivedSessionId = "019e36af-62eb-7e00-ac09-31d162febda6"

        try writeRollout(root: activeRoot, sessionId: activeSessionId, nested: true)
        try writeRollout(root: archivedRoot, sessionId: archivedSessionId, nested: false)

        let index = CodexSessionFileIndex(activeRoot: activeRoot, archivedRoot: archivedRoot)

        XCTAssertEqual(index.status(for: activeSessionId), .active)
        XCTAssertEqual(index.status(for: archivedSessionId), .archived)
        XCTAssertEqual(index.status(for: "019e36b7-2a8d-7603-93ff-7c34e9e1cdec"), .missing)
    }

    func testActiveSessionWinsWhenArchiveCopyAlsoExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-sessions-codex-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let activeRoot = root.appendingPathComponent("sessions", isDirectory: true)
        let archivedRoot = root.appendingPathComponent("archived_sessions", isDirectory: true)
        let sessionId = "019e36c4-f44c-7572-bfc0-7579a10fb363"

        try writeRollout(root: activeRoot, sessionId: sessionId, nested: true)
        try writeRollout(root: archivedRoot, sessionId: sessionId, nested: false)

        let index = CodexSessionFileIndex(activeRoot: activeRoot, archivedRoot: archivedRoot)

        XCTAssertEqual(index.status(for: sessionId), .active)
    }

    private func writeRollout(root: URL, sessionId: String, nested: Bool) throws {
        let directory = nested
            ? root
                .appendingPathComponent("2026", isDirectory: true)
                .appendingPathComponent("05", isDirectory: true)
                .appendingPathComponent("18", isDirectory: true)
            : root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("rollout-2026-05-18T01-28-57-\(sessionId).jsonl")
        try #"{"type":"session_meta","payload":{"id":"\#(sessionId)","cwd":"/tmp/project"}}"#
            .write(to: file, atomically: true, encoding: .utf8)
    }
}
