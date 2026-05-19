import XCTest
@testable import AgentSessionsCore

final class AgentTextSanitizerTests: XCTestCase {
    func testLatestResponseTextCollapsesLocalFileMarkdownLinkToLabelAndLine() {
        let text = """
        修正箇所: [AgentSessionsApp.swift](</Users/test/My Drive/Agent Sessions/Sources/AgentSessions/AgentSessionsApp.swift:4053>) を確認。
        """

        XCTAssertEqual(
            AgentTextSanitizer.latestResponseText(text),
            "修正箇所: AgentSessionsApp.swift (line 4053) を確認。"
        )
    }

    func testLatestResponseTextLeavesNonFileMarkdownLinkUnchanged() {
        let text = "詳細は [OpenAI docs](https://platform.openai.com/docs) を参照。"

        XCTAssertEqual(
            AgentTextSanitizer.latestResponseText(text),
            "詳細は [OpenAI docs](https://platform.openai.com/docs) を参照。"
        )
    }

    func testLatestResponseTextLeavesImageMarkdownUnchanged() {
        let text = "結果: ![preview](/tmp/preview.png)"

        XCTAssertEqual(
            AgentTextSanitizer.latestResponseText(text),
            "結果: ![preview](/tmp/preview.png)"
        )
    }
}
