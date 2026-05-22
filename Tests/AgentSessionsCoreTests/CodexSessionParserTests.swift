import XCTest
@testable import AgentSessionsCore

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
        XCTAssertEqual(parsed.title, "")
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

    func testTurnAbortedReminderDoesNotResumeWorking() {
        // After a user interrupt Codex appends a synthetic <turn_aborted>
        // user message and may follow it with <subagent_notification>
        // entries. Neither should flip the session back to working.
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<turn_aborted>\\nThe user interrupted the previous turn on purpose."}]}}
        {"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<subagent_notification>\\n{\\"agent_path\\":\\"abc\\",\\"status\\":\\"completed\\"}"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.state, .idle)
    }

    func testSyntheticTurnAbortedMessageEndsWorkingSessionWithoutEventMsg() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<turn_aborted>\\nThe user interrupted the previous turn on purpose.\\n</turn_aborted>"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.state, .idle)
        XCTAssertEqual(parsed.event, "turn_aborted")
        XCTAssertTrue(parsed.turnInterrupted)
    }

    func testDelayedToolOutputAfterTurnAbortedDoesNotResumeWorking() {
        let baseText = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1","reason":"interrupted"}}
        """
        let base = CodexSessionParser.parse(baseText, fallbackSessionId: "fallback")

        let parsed = CodexSessionParser.parseDelta(
            """
            {"type":"response_item","payload":{"type":"function_call_output","call_id":"late","output":"late output from an interrupted tool"}}
            """,
            base: base
        )

        XCTAssertEqual(parsed.state, .idle)
        XCTAssertTrue(parsed.turnInterrupted)
    }

    func testNewUserMessageAfterTurnAbortedResumesWorking() {
        let baseText = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"mcp_tool_call_begin"}}
        {"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1","reason":"interrupted"}}
        """
        let base = CodexSessionParser.parse(baseText, fallbackSessionId: "fallback")

        let parsed = CodexSessionParser.parseDelta(
            """
            {"type":"event_msg","payload":{"type":"user_message","message":"次の作業をお願いします"}}
            """,
            base: base
        )

        XCTAssertEqual(parsed.state, .working)
        XCTAssertFalse(parsed.turnInterrupted)
        XCTAssertEqual(parsed.event, "user_message")
    }

    func testRealUserMessageStillFlipsToWorking() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"次の作業をお願いします"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.state, .working)
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

    func testUsesUserPromptAsTemporaryTitleWhenThreadNameIsMissing() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Codexで新しくセッション始めた時の表示を直して"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "Codexで新しくセッション始めた時の表示を直して")
    }

    func testThreadNameOverridesTemporaryUserPromptTitle() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode","thread_name":"Generated session title"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Initial prompt title"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "Generated session title")
    }

    func testParsesTemporaryTitleFromUserMessageEvent() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"メニュー行の暫定タイトルをプロンプトにして"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "メニュー行の暫定タイトルをプロンプトにして")
        XCTAssertEqual(parsed.state, .working)
        XCTAssertEqual(parsed.event, "user_message")
    }

    func testIgnoresSafetyComplianceAmbientSuggestionUserMessageEvent() {
        let text = """
        {"type":"session_meta","payload":{"id":"suggestions","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"You are an expert at upholding safety and compliance\\nstandards for Codex ambient suggestions. I will present\\n\\n\\nRun a local project suggestion review."}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "")
        XCTAssertTrue(parsed.isInternalSubagent)
    }

    func testIgnoresBootstrapContextWhenChoosingTemporaryPromptTitle() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /tmp/project\\n\\n<INSTRUCTIONS>test</INSTRUCTIONS>"},{"type":"input_text","text":"<environment_context>\\n  <cwd>/tmp/project</cwd>\\n</environment_context>"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "")
    }

    func testIgnoresAmbientSuggestionPromptWhenChoosingTemporaryPromptTitle() {
        let text = """
        {"type":"session_meta","payload":{"id":"suggestions","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# Overview\\nGenerate 0 to 3 hyperpersonalized suggestions\\nfor what this user can do with Codex in this local project: /tmp/project"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "")
        XCTAssertTrue(parsed.isInternalSubagent)
    }

    func testIgnoresSafetyComplianceAmbientSuggestionPromptWhenChoosingTemporaryPromptTitle() {
        let text = """
        {"type":"session_meta","payload":{"id":"suggestions","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"You are an expert at upholding safety and compliance\\nstandards for Codex ambient suggestions. I will present\\n\\n\\nRun a local project suggestion review."}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "")
        XCTAssertTrue(parsed.isInternalSubagent)
    }

    func testQuotedAmbientSuggestionPromptStillLooksLikeUserSession() {
        let text = """
        {"type":"session_meta","payload":{"id":"debug","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"このメッセージも表示された\\n\\n# Overview\\nGenerate 0 to 3 hyperpersonalized suggestions\\nfor what this user can do with Codex in this local project: /tmp/project"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(
            parsed.title,
            "このメッセージも表示された # Overview Generate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project: /tmp/project"
        )
        XCTAssertFalse(parsed.isInternalSubagent)
    }

    func testQuotedSafetyComplianceAmbientSuggestionPromptStillLooksLikeUserSession() {
        let text = """
        {"type":"session_meta","payload":{"id":"debug","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"この名前が表示された\\n\\nYou are an expert at upholding safety and compliance\\nstandards for Codex ambient suggestions. I will present"}]}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(
            parsed.title,
            "この名前が表示された You are an expert at upholding safety and compliance standards for Codex ambient suggestions. I will present"
        )
        XCTAssertFalse(parsed.isInternalSubagent)
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

    func testParsesPlaceholderSuggestionOverviewAsInternalSession() {
        let text = """
        {"type":"session_meta","payload":{"id":"suggestions","cwd":"/tmp/project","thread_source":"user","source":"vscode","thread_name":"thinking..."}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"# Overview\\nGenerate 0 to 3 hyperpersonalized suggestions\\nfor what this user can do with Codex in this local project: /tmp/project"}],"phase":"commentary"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(parsed.title, "thinking...")
        XCTAssertTrue(parsed.isInternalSubagent)
    }

    func testParsesInternalSuggestionOverviewAsLatestResponse() {
        let text = """
        {"type":"session_meta","payload":{"id":"parent","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"# Overview\\nGenerate 0 to 3 hyperpersonalized suggestions\\nfor what this user can do with Codex in this local project: /tmp/project"}],"phase":"commentary"}}
        """

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: "fallback")

        XCTAssertEqual(
            parsed.latestResponseText,
            "# Overview\nGenerate 0 to 3 hyperpersonalized suggestions\nfor what this user can do with Codex in this local project: /tmp/project"
        )
        XCTAssertEqual(parsed.latestResponsePhase, "commentary")
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
