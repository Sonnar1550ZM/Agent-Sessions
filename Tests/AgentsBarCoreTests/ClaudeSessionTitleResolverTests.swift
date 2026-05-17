import XCTest
@testable import AgentsBarCore

final class ClaudeSessionTitleResolverTests: XCTestCase {
    func testPrefersCustomTitleOverGeneratedTitleAndPromptFallbacks() throws {
        let root = try makeProjectsRoot()
        let sessionId = "abc"
        try writeTranscript(
            root: root,
            sessionId: sessionId,
            lines: [
                #"{"type":"ai-title","aiTitle":"Generated title","sessionId":"abc"}"#,
                #"{"type":"last-prompt","lastPrompt":"Latest prompt","sessionId":"abc"}"#,
                #"{"type":"custom-title","customTitle":"Manual title","sessionId":"abc"}"#
            ]
        )

        XCTAssertEqual(
            ClaudeSessionTitleResolver.title(for: sessionId, projectsRoot: root),
            "Manual title"
        )
    }

    func testUsesLastPromptWhenClaudeHasNoGeneratedTitle() throws {
        let root = try makeProjectsRoot()
        let sessionId = "def"
        try writeTranscript(
            root: root,
            sessionId: sessionId,
            lines: [
                #"{"type":"user","message":{"role":"user","content":"Earlier prompt"},"sessionId":"def"}"#,
                #"{"type":"last-prompt","lastPrompt":"  Fix\nClaude session names  ","sessionId":"def"}"#
            ]
        )

        XCTAssertEqual(
            ClaudeSessionTitleResolver.title(for: sessionId, projectsRoot: root),
            "Fix Claude session names"
        )
    }

    func testUsesUserPromptWhenNoTitleRecordsExist() throws {
        let root = try makeProjectsRoot()
        let sessionId = "ghi"
        try writeTranscript(
            root: root,
            sessionId: sessionId,
            lines: [
                #"{"type":"queue-operation","operation":"enqueue","content":"Queued prompt","sessionId":"ghi"}"#,
                #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Name this session from user text"},{"type":"tool_result","content":"ignored"}]},"sessionId":"ghi"}"#
            ]
        )

        XCTAssertEqual(
            ClaudeSessionTitleResolver.title(for: sessionId, projectsRoot: root),
            "Name this session from user text"
        )
    }

    private func makeProjectsRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTranscript(root: URL, sessionId: String, lines: [String]) throws {
        let project = root.appendingPathComponent("-tmp-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("\(sessionId).jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
