import XCTest
@testable import AgentsBarCore

final class CodexSessionParserTests: XCTestCase {
    func testParsesUserSessionAsTopLevelSession() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"function_call"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.sessionId, "parent")
        XCTAssertEqual(parsed.cwd, "/tmp/project")
        XCTAssertEqual(parsed.state, .working)
        XCTAssertFalse(parsed.isInternalSubagent)
        XCTAssertNil(parsed.parentSessionId)
        XCTAssertNil(parsed.subagentNickname)
        XCTAssertNil(parsed.subagentRole)
        XCTAssertNil(parsed.subagentDepth)
    }

    func testParsesThreadSpawnSubagentMetadata() {
        let text = """
        {"type":"session_meta","payload":{"id":"child","cwd":"/tmp/project","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","depth":1,"agent_nickname":"Nested","agent_role":"worker"}}},"agent_nickname":"Sagan","agent_role":"explorer"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.sessionId, "child")
        XCTAssertEqual(parsed.state, .idle)
        XCTAssertFalse(parsed.isInternalSubagent)
        XCTAssertEqual(parsed.parentSessionId, "parent")
        XCTAssertEqual(parsed.subagentNickname, "Sagan")
        XCTAssertEqual(parsed.subagentRole, "explorer")
        XCTAssertEqual(parsed.subagentDepth, 1)
    }

    func testTurnAbortedEndsWorkingSession() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.sessionId, "parent")
        XCTAssertEqual(parsed.state, .idle)
        XCTAssertEqual(parsed.event, "turn_aborted")
    }

    func testParsesGuardianAsInternalSubagent() {
        let text = """
        {"type":"session_meta","payload":{"id":"guardian","cwd":"/tmp/project","thread_source":"subagent","source":{"subagent":{"other":"guardian"}}}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.sessionId, "guardian")
        XCTAssertTrue(parsed.isInternalSubagent)
        XCTAssertNil(parsed.parentSessionId)
    }

    func testNormalizesThreadNameWhitespace() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode","thread_name":"Fix menu\\nbar   layout\\tspacing"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "Fix menu bar layout spacing")
    }

    func testParsesLatestAssistantResponseFromResponseItems() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"作業中の応答"}],"phase":"commentary"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"最終応答です"}],"phase":"final_answer"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.latestResponseText, "最終応答です")
        XCTAssertEqual(parsed.latestResponsePhase, "final_answer")
        XCTAssertEqual(parsed.state, .idle)
    }

    func testPreservesNewlinesInLatestAssistantResponse() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"1行目\\n\\n2行目\\r\\n3行目"}],"phase":"final_answer"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.latestResponseText, "1行目\n\n2行目\n3行目")
    }

    func testParsesLatestAgentMessageEvent() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"agent_message","message":"現在確認しています。","phase":"commentary"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.latestResponseText, "現在確認しています。")
        XCTAssertEqual(parsed.latestResponsePhase, "commentary")
    }

    func testClearsLatestResponseAfterNewUserMessage() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"前回の応答"}],"phase":"final_answer"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"次の依頼"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.state, .working)
        XCTAssertEqual(parsed.event, "user_message")
        XCTAssertNil(parsed.latestResponseText)
        XCTAssertNil(parsed.latestResponsePhase)
    }
}
