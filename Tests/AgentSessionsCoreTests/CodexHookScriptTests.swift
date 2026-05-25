import Foundation
import XCTest

final class CodexHookScriptTests: XCTestCase {
    func testManualPermissionRequestWaits() throws {
        let output = try runCodexHook(
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"PermissionRequest"}
            """,
            configText: "approvals_reviewer = \"manual\"\n"
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Waiting")
        XCTAssertEqual(payload["event"] as? String, "PermissionRequest")
    }

    func testAutoReviewPermissionRequestKeepsWorking() throws {
        let output = try runCodexHook(
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"PermissionRequest","approvals_reviewer":"auto_review"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Working")
        XCTAssertEqual(payload["event"] as? String, "PermissionRequest")
    }

    func testConfiguredAutoReviewPermissionRequestKeepsWorking() throws {
        let output = try runCodexHook(
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"PermissionRequest"}
            """,
            configText: "approvals_reviewer = \"guardian_subagent\"\n"
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Working")
        XCTAssertEqual(payload["event"] as? String, "PermissionRequest")
    }

    func testAutoReviewAskUserQuestionStillWaits() throws {
        let output = try runCodexHook(
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"AskUserQuestion","approvals_reviewer":"auto_review"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Waiting")
        XCTAssertEqual(payload["event"] as? String, "AskUserQuestion")
    }

    func testAutoReviewPermissionNotificationKeepsWorking() throws {
        let output = try runCodexHook(
            input: """
            {"session_id":"session-1","transcript_path":"/tmp/session-1.jsonl","cwd":"/tmp/project","hook_event_name":"Notification","notification_type":"permission_prompt","approvals_reviewer":"guardian_subagent"}
            """
        )

        let payload = try decodePayload(output)
        XCTAssertEqual(payload["state"] as? String, "Working")
        XCTAssertEqual(payload["event"] as? String, "Notification")
    }

    private func runCodexHook(input: String, configText: String = "") throws -> String {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/agent-sessions-codex-hook.sh")
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try configText.write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        var environment = ProcessInfo.processInfo.environment
        environment["AGENT_SESSIONS_DRY_RUN"] = "1"
        environment["AGENT_SESSIONS_HOST"] = "127.0.0.1"
        environment["AGENT_SESSIONS_PORT"] = "9"
        environment["AGENT_SESSIONS_CODEX_CONFIG"] = configURL.path
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
