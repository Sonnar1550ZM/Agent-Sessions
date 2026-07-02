import XCTest
@testable import AgentSessionsCore

final class SessionFileTextReaderTests: XCTestCase {
    func testContextTextReadsSmallFileExactlyOnce() throws {
        let lines = (0..<20).map { #"{"type":"event","index":\#($0)}"# }
        let content = lines.joined(separator: "\n") + "\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = SessionFileTextReader.contextText(from: file, headLimit: 1_000, tailLimit: 1_000)

        XCTAssertEqual(text, content)
        for line in lines {
            XCTAssertEqual(occurrences(of: line, in: text ?? ""), 1)
        }
    }

    func testContextTextNeverDuplicatesLinesInLargeFile() throws {
        let lines = (0..<200).map { index in
            String(format: #"{"type":"event","index":%04d}"#, index)
        }
        let content = lines.joined(separator: "\n") + "\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        let headLimit = 100
        let tailLimit: UInt64 = 200
        XCTAssertGreaterThan(UInt64(content.utf8.count), UInt64(headLimit) + tailLimit)

        let text = try XCTUnwrap(
            SessionFileTextReader.contextText(from: file, headLimit: headLimit, tailLimit: tailLimit)
        )
        let outputLines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        let originalLines = Set(lines)
        for line in outputLines {
            XCTAssertTrue(originalLines.contains(line), "corrupted line: \(line)")
        }
        XCTAssertEqual(outputLines.count, Set(outputLines).count, "duplicate lines in output")
        XCTAssertEqual(outputLines.first, lines.first)
        XCTAssertEqual(outputLines.last, lines.last)
        XCTAssertLessThan(outputLines.count, lines.count)
    }

    func testContextTextWithoutNewlineInHeadFallsBackToTail() throws {
        let prefix = String(repeating: "a", count: 300)
        let content = prefix + "\nlast-line\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = try XCTUnwrap(
            SessionFileTextReader.contextText(from: file, headLimit: 100, tailLimit: 100)
        )
        let outputLines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(outputLines, ["last-line"])
    }

    func testTailTextSkipsPartialFirstLine() throws {
        let lines = (0..<50).map { index in
            String(format: "line-%03d", index)
        }
        let content = lines.joined(separator: "\n") + "\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = try XCTUnwrap(SessionFileTextReader.tailText(from: file, limit: 100))
        let outputLines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        let originalLines = Set(lines)
        for line in outputLines {
            XCTAssertTrue(originalLines.contains(line), "corrupted line: \(line)")
        }
        XCTAssertEqual(outputLines.last, lines.last)
    }

    func testTailTextReturnsWholeSmallFile() throws {
        let content = "alpha\nbeta\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(SessionFileTextReader.tailText(from: file, limit: 1_000), content)
    }

    func testContextTextPreservesMultibyteContent() throws {
        let lines = (0..<10).map { "行その\($0)・テスト" }
        let content = lines.joined(separator: "\n") + "\n"
        let file = try writeTemporaryFile(content)
        defer { try? FileManager.default.removeItem(at: file) }

        let text = SessionFileTextReader.contextText(from: file, headLimit: 10_000, tailLimit: 10_000)

        XCTAssertEqual(text, content)
    }

    private func writeTemporaryFile(_ content: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-file-text-reader-\(UUID().uuidString).jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
