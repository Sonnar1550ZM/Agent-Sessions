import AgentSessionsCore
import Foundation

final class CodexSessionWatcher {
    private let inner: IncrementalSessionWatcher<CodexParsedSession>

    init(handler: @escaping (AgentEvent) -> Void) {
        let adapter = IncrementalSessionWatcher<CodexParsedSession>.Adapter(
            queueLabel: "app.agentsessions.codex-session-watcher",
            watchRoot: Self.watchRoot,
            latestFiles: Self.latestRolloutFiles,
            isRelevantPath: Self.isRelevantRolloutPath,
            fallbackPollInterval: 1,
            fallbackPollLeeway: .milliseconds(200),
            loadFull: Self.loadFull(file:modifiedAt:),
            applyDelta: Self.applyDelta(file:modifiedAt:text:base:)
        )
        self.inner = IncrementalSessionWatcher(adapter: adapter, handler: handler)
    }

    func start() { inner.start() }
    func stop() { inner.stop() }

    static func title(for sessionId: String) -> String? {
        threadTitle(for: sessionId)
    }

    static func shouldHideSession(_ sessionId: String) -> Bool {
        parsedSession(for: sessionId)?.isInternalSubagent ?? false
    }

    static func latestResponse(for sessionId: String) -> (text: String, phase: String?)? {
        guard let parsed = parsedSession(for: sessionId),
              !parsed.isInternalSubagent,
              let latestResponseText = parsed.latestResponseText else {
            return nil
        }
        return (latestResponseText, parsed.latestResponsePhase)
    }

    private static func parsedSession(for sessionId: String) -> CodexParsedSession? {
        guard let file = rolloutFile(for: sessionId),
              let text = contextText(from: file) else {
            return nil
        }

        return CodexSessionParser.parse(text, fallbackSessionId: sessionId)
    }

    static func fileStatus(for sessionId: String) -> CodexSessionFileStatus {
        CodexSessionFileIndex().status(for: sessionId)
    }

    private static func loadFull(
        file: URL,
        modifiedAt: Date
    ) -> (snapshot: IncrementalSessionWatcher<CodexParsedSession>.Snapshot, parsed: CodexParsedSession)? {
        guard let text = contextText(from: file) else { return nil }
        let parsed = CodexSessionParser.parse(text, fallbackSessionId: fallbackSessionId(from: file))
        guard !parsed.isInternalSubagent,
              !parsed.cwd.isEmpty else {
            return nil
        }
        return (snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed), parsed)
    }

    private static func applyDelta(
        file: URL,
        modifiedAt: Date,
        text: String,
        base: CodexParsedSession
    ) -> (snapshot: IncrementalSessionWatcher<CodexParsedSession>.Snapshot, parsed: CodexParsedSession)? {
        let parsed = CodexSessionParser.parseDelta(text, base: base)
        guard !parsed.cwd.isEmpty, !parsed.isInternalSubagent else { return nil }
        return (snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed), parsed)
    }

    private static func snapshot(
        file: URL,
        modifiedAt: Date,
        parsed: CodexParsedSession
    ) -> IncrementalSessionWatcher<CodexParsedSession>.Snapshot {
        let age = Date().timeIntervalSince(modifiedAt)
        let state: AgentState = age > 120 ? .idle : parsed.state
        let title = threadTitle(for: parsed.sessionId)
            ?? parsed.title

        let event = AgentEvent(
            agent: .codex,
            sessionId: parsed.sessionId,
            state: state,
            title: title,
            cwd: parsed.cwd,
            event: parsed.event.isEmpty ? "JSONLWatch" : parsed.event,
            terminal: "",
            pid: nil,
            updatedAt: modifiedAt,
            parentSessionId: parsed.parentSessionId,
            subagentNickname: parsed.subagentNickname,
            subagentRole: parsed.subagentRole,
            subagentDepth: parsed.subagentDepth,
            latestResponseText: parsed.latestResponseText,
            latestResponsePhase: parsed.latestResponsePhase
        )

        return .init(
            event: event,
            fingerprint: [
                file.path,
                String(modifiedAt.timeIntervalSince1970),
                state.rawValue,
                title,
                parsed.event,
                parsed.parentSessionId ?? "",
                parsed.subagentNickname ?? "",
                parsed.subagentRole ?? "",
                parsed.subagentDepth.map(String.init) ?? "",
                parsed.latestResponseText ?? "",
                parsed.latestResponsePhase ?? ""
            ].joined(separator: "|")
        )
    }

    private static func latestRolloutFiles(limit: Int) -> [URL] {
        let root = watchRoot()
        let recent = recentRolloutFiles(under: root)
        if !recent.isEmpty {
            return recent
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.url)
        }
        return legacyEnumerateRolloutFiles(under: root, limit: limit)
    }

    private static func recentRolloutFiles(under root: URL) -> [(url: URL, modifiedAt: Date)] {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        var files: [(url: URL, modifiedAt: Date)] = []
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let y = cal.component(.year, from: day)
            let m = cal.component(.month, from: day)
            let d = cal.component(.day, from: day)
            let dir = root
                .appendingPathComponent(String(format: "%04d", y), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", m), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", d), isDirectory: true)
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls {
                guard url.lastPathComponent.hasPrefix("rollout-"),
                      url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate else {
                    continue
                }
                files.append((url, modifiedAt))
            }
        }
        return files
    }

    private static func legacyEnumerateRolloutFiles(under root: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
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
        CodexSessionFileIndex.defaultActiveRoot()
    }

    private static func isRelevantRolloutPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl"
    }

    private static func rolloutFile(for sessionId: String) -> URL? {
        CodexSessionFileIndex().activeRolloutFile(for: sessionId)
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

    private static func headText(from url: URL, limit: Int = 128_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: limit)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    private static func contextText(from url: URL) -> String? {
        guard let tail = tailText(from: url) else {
            return nil
        }

        guard let head = headText(from: url), !head.isEmpty else {
            return tail
        }

        return head + "\n" + tail
    }

    private static let threadTitleCacheLock = NSLock()
    nonisolated(unsafe) private static var threadTitleCache: [String: String?] = [:]
    nonisolated(unsafe) private static var threadTitleCacheKey: (size: UInt64, mtime: Date)?

    private static func threadTitle(for sessionId: String) -> String? {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")

        let stats: (size: UInt64, mtime: Date)? = {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize.map(UInt64.init),
                  let mtime = values.contentModificationDate else {
                return nil
            }
            return (size, mtime)
        }()

        threadTitleCacheLock.lock()
        let cacheValid: Bool
        if let stats, let key = threadTitleCacheKey {
            cacheValid = key.size == stats.size && key.mtime == stats.mtime
        } else {
            cacheValid = false
        }
        if cacheValid, let cached = threadTitleCache[sessionId] {
            threadTitleCacheLock.unlock()
            return cached
        }
        if !cacheValid {
            threadTitleCache.removeAll(keepingCapacity: true)
            threadTitleCacheKey = stats
        }
        threadTitleCacheLock.unlock()

        let title = scanThreadTitle(in: url, for: sessionId, tailLimit: 256_000)
            ?? scanThreadTitle(in: url, for: sessionId, tailLimit: 2_000_000)

        threadTitleCacheLock.lock()
        if threadTitleCacheKey?.size == stats?.size,
           threadTitleCacheKey?.mtime == stats?.mtime {
            threadTitleCache[sessionId] = title
        }
        threadTitleCacheLock.unlock()

        return title
    }

    private static func scanThreadTitle(
        in url: URL,
        for sessionId: String,
        tailLimit: UInt64
    ) -> String? {
        guard let text = tailText(from: url, limit: tailLimit) else {
            return nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.range(of: sessionId) != nil else {
                continue
            }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] as? String == sessionId,
                  let title = object["thread_name"] as? String else {
                continue
            }
            return sanitizedTitle(title)
        }
        return nil
    }

    private static func sanitizedTitle(_ value: String) -> String? {
        let title = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
    }

    private static func fallbackSessionId(from url: URL) -> String {
        CodexSessionFileIndex.sessionId(fromRolloutURL: url)
    }
}
