import AgentSessionsCore
import Foundation

final class ClaudeSubagentWatcher {
    private let inner: IncrementalSessionWatcher<ClaudeParsedSubagent>

    init(handler: @escaping (AgentEvent) -> Void) {
        let adapter = IncrementalSessionWatcher<ClaudeParsedSubagent>.Adapter(
            queueLabel: "app.agentsessions.claude-subagent-watcher",
            watchRoot: Self.watchRoot,
            latestFiles: Self.latestSubagentFiles,
            isRelevantPath: Self.isRelevantSubagentPath,
            fallbackPollInterval: 5,
            fallbackPollLeeway: .seconds(5),
            loadFull: Self.loadFull(file:modifiedAt:),
            applyDelta: Self.applyDelta(file:modifiedAt:text:base:)
        )
        self.inner = IncrementalSessionWatcher(adapter: adapter, handler: handler)
    }

    func start() { inner.start() }
    func stop() { inner.stop() }

    private static func loadFull(
        file: URL,
        modifiedAt: Date
    ) -> (snapshot: IncrementalSessionWatcher<ClaudeParsedSubagent>.Snapshot, parsed: ClaudeParsedSubagent)? {
        guard let text = tailText(from: file),
              let parsed = ClaudeSessionParser.parseSubagentTranscript(
                  transcriptPath: file.path,
                  text: text
              ) else {
            return nil
        }
        return (snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed), parsed)
    }

    private static func applyDelta(
        file: URL,
        modifiedAt: Date,
        text: String,
        base: ClaudeParsedSubagent
    ) -> (snapshot: IncrementalSessionWatcher<ClaudeParsedSubagent>.Snapshot, parsed: ClaudeParsedSubagent)? {
        guard let parsed = ClaudeSessionParser.parseSubagentTranscriptDelta(
            transcriptPath: file.path,
            text: text,
            base: base
        ) else {
            return nil
        }
        return (snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed), parsed)
    }

    private static func snapshot(
        file: URL,
        modifiedAt: Date,
        parsed: ClaudeParsedSubagent
    ) -> IncrementalSessionWatcher<ClaudeParsedSubagent>.Snapshot {
        let age = Date().timeIntervalSince(modifiedAt)
        let state: AgentState = age > 600 ? .idle : parsed.state
        let metadata = parsed.metadata

        let event = AgentEvent(
            agent: .claudeCode,
            sessionId: metadata.sessionId,
            state: state,
            title: parsed.title,
            cwd: parsed.cwd,
            event: "JSONLWatch",
            terminal: "",
            pid: nil,
            updatedAt: modifiedAt,
            parentSessionId: metadata.parentSessionId,
            subagentNickname: metadata.subagentNickname,
            subagentRole: metadata.subagentRole,
            subagentDepth: metadata.subagentDepth,
            transcriptPath: file.path,
            latestResponseText: parsed.latestResponseText,
            latestResponsePhase: parsed.latestResponseText == nil ? nil : "assistant"
        )

        return .init(
            event: event,
            fingerprint: [
                file.path,
                String(modifiedAt.timeIntervalSince1970),
                state.rawValue,
                parsed.title,
                parsed.cwd,
                metadata.parentSessionId,
                metadata.subagentNickname,
                metadata.subagentRole,
                metadata.subagentDepth.description,
                parsed.latestResponseText ?? ""
            ].joined(separator: "|")
        )
    }

    private static func latestSubagentFiles(limit: Int) -> [URL] {
        let root = watchRoot()

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.pathComponents.contains("subagents"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate else {
                continue
            }

            files.append((url, modifiedAt))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
    }

    private static func watchRoot() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private static func isRelevantSubagentPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return url.pathExtension == "jsonl" && url.pathComponents.contains("subagents")
    }

    private static func tailText(from url: URL, limit: UInt64 = 1_000_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > limit ? size - limit : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        guard var text = String(data: data, encoding: .utf8) else {
            return nil
        }

        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}
