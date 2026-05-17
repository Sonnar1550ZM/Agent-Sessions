import XCTest
@testable import AgentsBarCore

final class ClaudeSessionTitleResolverTests: XCTestCase {
    func testPrefersClaudeAppSessionTitleOverTranscriptPromptFallbacks() throws {
        let root = try makeProjectsRoot()
        let appRoot = try makeProjectsRoot()
        let sessionId = "app-title"
        try writeTranscript(
            root: root,
            sessionId: sessionId,
            lines: [
                #"{"type":"last-prompt","lastPrompt":"claudeの外部サービスでサブスク認証を使える新しい仕組みを解説","sessionId":"app-title"}"#
            ]
        )
        try writeAppSession(
            root: appRoot,
            cliSessionId: sessionId,
            title: "Add subscription authentication for external services",
            lastActivityAt: 2
        )

        XCTAssertEqual(
            ClaudeSessionTitleResolver.title(for: sessionId, projectsRoot: root, appSessionsRoot: appRoot),
            "Add subscription authentication for external services"
        )
    }

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

    private func writeAppSession(
        root: URL,
        cliSessionId: String,
        title: String,
        lastActivityAt: Int
    ) throws {
        let window = root
            .appendingPathComponent("window", isDirectory: true)
            .appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: window, withIntermediateDirectories: true)
        let file = window.appendingPathComponent("local-\(UUID().uuidString).json")
        let json = """
        {
          "sessionId": "local-\(UUID().uuidString)",
          "cliSessionId": "\(cliSessionId)",
          "title": "\(title)",
          "lastActivityAt": \(lastActivityAt)
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
    }
}
