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

    func testParsesGuardianAsInternalSubagent() {
        let text = """
        {"type":"session_meta","payload":{"id":"guardian","cwd":"/tmp/project","thread_source":"subagent","source":{"subagent":{"other":"guardian"}}}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.sessionId, "guardian")
        XCTAssertTrue(parsed.isInternalSubagent)
        XCTAssertNil(parsed.parentSessionId)
    }
}
