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
            fallbackPollLeeway: .milliseconds(250),
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

    static func latestResponse(
        for sessionId: String,
        afterUserPrompt expectedUserPrompt: String? = nil
    ) -> (text: String, phase: String?)? {
        guard let parsed = parsedSession(for: sessionId),
              !parsed.isInternalSubagent,
              AgentTextSanitizer.userPromptTextMatches(parsed.latestUserPrompt, expected: expectedUserPrompt),
              let latestResponseText = parsed.latestResponseText else {
            return nil
        }
        return (latestResponseText, parsed.latestResponsePhase)
    }

    private static func parsedSession(for sessionId: String) -> CodexParsedSession? {
        guard let file = rolloutFile(for: sessionId) else {
            return nil
        }

        let stats = fileStats(for: file)
        if let stats,
           let cached = cachedParsedSession(
                sessionId: sessionId,
                file: file,
                stats: stats
           ) {
            return cached
        }

        return parsedSessionFromDisk(sessionId: sessionId, file: file, stats: stats)
    }

    private static func parsedSessionFromDisk(
        sessionId: String,
        file: URL,
        stats: (size: UInt64, mtime: Date)?
    ) -> CodexParsedSession? {
        guard let text = contextText(from: file) else {
            return nil
        }

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: sessionId)
        if let stats {
            storeCachedParsedSession(parsed, sessionId: sessionId, file: file, stats: stats)
        }
        return parsed
    }

    private static func fileStats(for file: URL) -> (size: UInt64, mtime: Date)? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize.map(UInt64.init),
              let mtime = values.contentModificationDate else {
            return nil
        }
        return (size, mtime)
    }

    private static func cachedParsedSession(
        sessionId: String,
        file: URL,
        stats: (size: UInt64, mtime: Date)
    ) -> CodexParsedSession? {
        parsedSessionCacheLock.lock()
        defer { parsedSessionCacheLock.unlock() }

        guard let entry = parsedSessionCache[sessionId],
              entry.path == file.path,
              entry.size == stats.size,
              entry.mtime == stats.mtime else {
            return nil
        }
        return entry.parsed
    }

    private static func storeCachedParsedSession(
        _ parsed: CodexParsedSession,
        sessionId: String,
        file: URL,
        stats: (size: UInt64, mtime: Date)
    ) {
        parsedSessionCacheLock.lock()
        if parsedSessionCache[sessionId] == nil,
           parsedSessionCache.count >= parsedSessionCacheLimit,
           let oldestKey = parsedSessionCache.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            parsedSessionCache.removeValue(forKey: oldestKey)
        }
        parsedSessionCache[sessionId] = ParsedSessionCacheEntry(
            path: file.path,
            size: stats.size,
            mtime: stats.mtime,
            storedAt: Date(),
            parsed: parsed
        )
        parsedSessionCacheLock.unlock()
    }

    private static let parsedSessionCacheLock = NSLock()
    private static let parsedSessionCacheLimit = 200
    nonisolated(unsafe) private static var parsedSessionCache: [String: ParsedSessionCacheEntry] = [:]

    private struct ParsedSessionCacheEntry {
        let path: String
        let size: UInt64
        let mtime: Date
        let storedAt: Date
        let parsed: CodexParsedSession
    }

    static func fileStatus(for sessionId: String) -> CodexSessionFileStatus {
        sessionLookup(for: sessionId).status
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
        let state: AgentState = age > 600 ? .idle : parsed.state
        let title: String
        if AgentCompactionStatus.hasMatchingDisplayTitle(event: parsed.event, title: parsed.title) {
            title = parsed.title
        } else {
            title = threadTitle(for: parsed.sessionId)
                ?? parsed.title
        }

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
            latestUserPrompt: parsed.latestUserPrompt,
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
                parsed.latestUserPrompt ?? "",
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
        sessionLookup(for: sessionId).activeFile
    }

    private static func sessionLookup(for sessionId: String) -> SessionLookup {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else {
            return SessionLookup(status: .missing, activeFile: nil)
        }

        let now = Date()
        sessionLookupCacheLock.lock()
        if let entry = sessionLookupCache[normalizedSessionId],
           now.timeIntervalSince(entry.checkedAt) <= sessionLookupCacheTTL(for: entry.lookup.status) {
            sessionLookupCacheLock.unlock()
            return entry.lookup
        }
        sessionLookupCacheLock.unlock()

        let index = CodexSessionFileIndex()
        let activeFile = index.activeRolloutFile(for: normalizedSessionId)
        let status: CodexSessionFileStatus
        if activeFile != nil {
            status = .active
        } else if index.hasArchivedSession(normalizedSessionId) {
            status = .archived
        } else {
            status = .missing
        }
        let lookup = SessionLookup(status: status, activeFile: activeFile)

        sessionLookupCacheLock.lock()
        if sessionLookupCache[normalizedSessionId] == nil,
           sessionLookupCache.count >= sessionLookupCacheLimit,
           let oldestKey = sessionLookupCache.min(by: { $0.value.checkedAt < $1.value.checkedAt })?.key {
            sessionLookupCache.removeValue(forKey: oldestKey)
        }
        sessionLookupCache[normalizedSessionId] = SessionLookupCacheEntry(
            checkedAt: now,
            lookup: lookup
        )
        sessionLookupCacheLock.unlock()

        return lookup
    }

    private struct SessionLookup {
        let status: CodexSessionFileStatus
        let activeFile: URL?
    }

    private struct SessionLookupCacheEntry {
        let checkedAt: Date
        let lookup: SessionLookup
    }

    private static func sessionLookupCacheTTL(for status: CodexSessionFileStatus) -> TimeInterval {
        switch status {
        case .active, .archived:
            return 30
        case .missing:
            return 2
        }
    }

    private static let sessionLookupCacheLock = NSLock()
    private static let sessionLookupCacheLimit = 500
    nonisolated(unsafe) private static var sessionLookupCache: [String: SessionLookupCacheEntry] = [:]

    private static func contextText(from url: URL) -> String? {
        SessionFileTextReader.contextText(from: url)
    }

    private static let threadTitleCacheLock = NSLock()
    private static let threadTitleCacheLimit = 1_000
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
            if threadTitleCache.count >= threadTitleCacheLimit {
                threadTitleCache.removeAll(keepingCapacity: true)
            }
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
        guard let text = SessionFileTextReader.tailText(from: url, limit: tailLimit) else {
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
        AgentSessionTitleSanitizer.optional(value)
    }

    private static func fallbackSessionId(from url: URL) -> String {
        CodexSessionFileIndex.sessionId(fromRolloutURL: url)
    }
}
