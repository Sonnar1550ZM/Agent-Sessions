import XCTest
@testable import AgentsBarCore

final class ClaudeSessionParserTests: XCTestCase {
    func testReturnsNilForTopLevelTranscriptPath() {
        let metadata = ClaudeSessionParser.subagentMetadata(
            transcriptPath: "/Users/me/.claude/projects/project/parent.jsonl"
        )

        XCTAssertNil(metadata)
    }

    func testParsesSubagentTranscriptPath() {
        let metadata = ClaudeSessionParser.subagentMetadata(
            transcriptPath: "/Users/me/.claude/projects/project/parent-session/subagents/agent-a8142726721de1817.jsonl"
        )

        XCTAssertEqual(metadata?.sessionId, "parent-session/subagents/agent-a8142726721de1817")
        XCTAssertEqual(metadata?.parentSessionId, "parent-session")
        XCTAssertEqual(metadata?.subagentNickname, "agent-a8142726721de1817")
        XCTAssertEqual(metadata?.subagentRole, "Claude")
        XCTAssertEqual(metadata?.subagentDepth, 1)
    }

    func testParsesSubagentTranscriptPathWithoutJsonlExtension() {
        let metadata = ClaudeSessionParser.subagentMetadata(
            transcriptPath: "/Users/me/.claude/projects/project/parent-session/subagents/agent-a8142726721de1817"
        )

        XCTAssertEqual(metadata?.sessionId, "parent-session/subagents/agent-a8142726721de1817")
        XCTAssertEqual(metadata?.parentSessionId, "parent-session")
        XCTAssertEqual(metadata?.subagentNickname, "agent-a8142726721de1817")
    }

    func testParsesSubagentTranscriptStateAndRole() {
        let text = """
        {"parentUuid":null,"isSidechain":true,"agentId":"a2d0709031a162f40","type":"user","message":{"role":"user","content":"Inspect"},"cwd":"/tmp/project","sessionId":"parent-session"}
        {"parentUuid":"one","isSidechain":true,"agentId":"a2d0709031a162f40","attributionAgent":"general-purpose","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"stop_reason":"end_turn"},"cwd":"/tmp/project","sessionId":"parent-session"}
        """

        let parsed = ClaudeSessionParser.parseSubagentTranscript(
            transcriptPath: "/Users/me/.claude/projects/project/parent-session/subagents/agent-a2d0709031a162f40.jsonl",
            text: text
        )

        XCTAssertEqual(parsed?.metadata.sessionId, "parent-session/subagents/agent-a2d0709031a162f40")
        XCTAssertEqual(parsed?.metadata.parentSessionId, "parent-session")
        XCTAssertEqual(parsed?.metadata.subagentNickname, "a2d0709031a162f40")
        XCTAssertEqual(parsed?.metadata.subagentRole, "general-purpose")
        XCTAssertEqual(parsed?.state, .idle)
        XCTAssertEqual(parsed?.title, "Inspect")
        XCTAssertEqual(parsed?.cwd, "/tmp/project")
        XCTAssertEqual(parsed?.latestResponseText, "Done")
    }

    func testParsesSubagentTitleFromFirstPromptLine() {
        let text = """
        {"parentUuid":null,"isSidechain":true,"agentId":"a3970cb458f30cc75","type":"user","message":{"role":"user","content":"作業ディレクトリ `/tmp/project` の中身を調査して、簡潔にレポートしてください。\\n\\n調査内容:\\n1. 一覧"},"cwd":"/tmp/project","sessionId":"parent-session"}
        {"parentUuid":"one","isSidechain":true,"agentId":"a3970cb458f30cc75","attributionAgent":"Explore","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"stop_reason":"end_turn"},"cwd":"/tmp/project","sessionId":"parent-session"}
        """

        let parsed = ClaudeSessionParser.parseSubagentTranscript(
            transcriptPath: "/Users/me/.claude/projects/project/parent-session/subagents/agent-a3970cb458f30cc75.jsonl",
            text: text
        )

        XCTAssertEqual(parsed?.title, "作業ディレクトリ `/tmp/project` の中身を調査して、簡潔にレポートしてください。")
        XCTAssertEqual(parsed?.metadata.subagentRole, "Explore")
    }

    func testParsesToolUseSubagentAsWorking() {
        let text = """
        {"agentId":"a2d0709031a162f40","attributionAgent":"general-purpose","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}],"stop_reason":"tool_use"},"cwd":"/tmp/project","sessionId":"parent-session"}
        """

        let parsed = ClaudeSessionParser.parseSubagentTranscript(
            transcriptPath: "/Users/me/.claude/projects/project/parent-session/subagents/agent-a2d0709031a162f40.jsonl",
            text: text
        )

        XCTAssertEqual(parsed?.state, .working)
        XCTAssertNil(parsed?.latestResponseText)
    }

    func testParsesLatestAssistantResponseTextFromTranscript() {
        let text = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"古い応答"}],"stop_reason":"end_turn"},"sessionId":"parent-session"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hidden"}],"stop_reason":"end_turn"},"sessionId":"parent-session"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"最新の応答です\\n2行目"}],"stop_reason":"end_turn"},"sessionId":"parent-session"}
        """

        let response = ClaudeSessionParser.latestAssistantResponseText(fromTranscript: text)

        XCTAssertEqual(response, "最新の応答です\n2行目")
    }
}
