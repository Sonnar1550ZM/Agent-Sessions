import Foundation
import XCTest

final class ClaudeHookScriptTests: XCTestCase {
    func testIdlePromptNotificationIsIgnored() throws {
        let output = try runClaudeHook(
            state: "Waiting",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for input"}
            """
        )

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testPermissionPromptNotificationWaits() throws {
        let output = try runClaudeHook(
            state: "Waiting",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Waiting")
        XCTAssertEqual(payload["event"] as? String, "Notification")
    }

    func testElicitationDialogNotificationWaits() throws {
        let output = try runClaudeHook(
            state: "Waiting",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"Choose an option"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Waiting")
        XCTAssertEqual(payload["event"] as? String, "Notification")
    }

    func testResumeSessionStartIsIgnored() throws {
        let output = try runClaudeHook(
            state: "Idle",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"SessionStart","source":"resume"}
            """
        )

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testStartupSessionStartIsKept() throws {
        let output = try runClaudeHook(
            state: "Idle",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"SessionStart","source":"startup"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Idle")
        XCTAssertEqual(payload["event"] as? String, "SessionStart")
    }

    func testUserPromptSubmitEmitsLatestUserPrompt() throws {
        let output = try runClaudeHook(
            state: "Working",
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"UserPromptSubmit","prompt":"  ユーザーの依頼\\n詳しい条件  "}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["title"] as? String, "ユーザーの依頼 詳しい条件")
        XCTAssertEqual(payload["latestUserPrompt"] as? String, "ユーザーの依頼 詳しい条件")
    }

    private func runClaudeHook(state: String, input: String) throws -> String {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentSessions/Resources/hooks/agent-sessions-claude-hook.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, state]

        var environment = ProcessInfo.processInfo.environment
        environment["AGENT_SESSIONS_DRY_RUN"] = "1"
        environment["AGENT_SESSIONS_HOST"] = "127.0.0.1"
        environment["AGENT_SESSIONS_PORT"] = "9"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
        return output
    }

    private func decodePayload(_ output: String) throws -> [String: Any] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
