import Foundation

public enum ClaudeAppSessionStatus: Equatable, Sendable {
    case active
    case archived
    case missing
}

public enum ClaudeSessionTitleResolver {
    private struct AppSessionMetadata {
        var title: String?
        var isArchived: Bool
        var score: Double
    }

    private final class AppSessionMetadataCache: @unchecked Sendable {
        private struct Snapshot {
            var rootPath: String
            var expiresAt: Date
            var rootModifiedAt: Date?
            var metadataBySessionId: [String: AppSessionMetadata]
        }

        private struct FileCacheEntry {
            var modifiedAt: Date
            var size: Int
            var cliSessionId: String?
            var metadata: AppSessionMetadata?
        }

        private let lock = NSLock()
        private let ttl: TimeInterval
        private var snapshot: Snapshot?
        private var fileCache: [String: FileCacheEntry] = [:]

        init(ttl: TimeInterval) {
            self.ttl = ttl
        }

        func metadata(for sessionId: String, sessionsRoot: URL?) -> AppSessionMetadata? {
            guard let sessionsRoot else {
                return nil
            }

            let rootPath = sessionsRoot.standardizedFileURL.path
            let now = Date()
            // A single stat of the root catches top-level additions (new
            // window directories, root creation) ahead of the TTL; changes
            // deeper in the tree wait for the TTL, which is cheap to expire
            // now that unchanged files are served from `fileCache`. Read via
            // FileManager because URL.resourceValues caches per URL instance
            // and would keep returning the stale mtime for a reused URL.
            let rootModifiedAt = (try? FileManager.default.attributesOfItem(
                atPath: rootPath
            ))?[.modificationDate] as? Date

            lock.lock()
            defer { lock.unlock() }

            if let snapshot,
               snapshot.rootPath == rootPath,
               snapshot.expiresAt > now,
               snapshot.rootModifiedAt == rootModifiedAt {
                return snapshot.metadataBySessionId[sessionId]
            }

            if snapshot?.rootPath != rootPath {
                fileCache.removeAll()
            }
            let metadataBySessionId = buildMetadataIndex(sessionsRoot: sessionsRoot)
            snapshot = Snapshot(
                rootPath: rootPath,
                expiresAt: now.addingTimeInterval(ttl),
                rootModifiedAt: rootModifiedAt,
                metadataBySessionId: metadataBySessionId
            )
            return metadataBySessionId[sessionId]
        }

        func invalidate() {
            lock.lock()
            snapshot = nil
            lock.unlock()
        }

        private func buildMetadataIndex(sessionsRoot: URL) -> [String: AppSessionMetadata] {
            guard let enumerator = FileManager.default.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [:]
            }

            var metadataBySessionId: [String: AppSessionMetadata] = [:]
            var seenPaths: Set<String> = []

            for case let url as URL in enumerator {
                guard url.pathExtension == "json",
                      let values = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
                      ),
                      values.isRegularFile == true else {
                    continue
                }

                let path = url.path
                seenPaths.insert(path)
                let modifiedAt = values.contentModificationDate ?? .distantPast
                let size = values.fileSize ?? -1

                let entry: FileCacheEntry
                if let cached = fileCache[path],
                   cached.modifiedAt == modifiedAt,
                   cached.size == size {
                    entry = cached
                } else {
                    entry = Self.parseMetadataFile(
                        at: url,
                        modifiedAt: modifiedAt,
                        size: size,
                        fallbackScore: values.contentModificationDate?.timeIntervalSince1970
                    )
                    fileCache[path] = entry
                }

                guard let cliSessionId = entry.cliSessionId,
                      let metadata = entry.metadata else {
                    continue
                }

                if metadataBySessionId[cliSessionId] == nil || metadata.score >= metadataBySessionId[cliSessionId]!.score {
                    metadataBySessionId[cliSessionId] = metadata
                }
            }

            fileCache = fileCache.filter { seenPaths.contains($0.key) }
            return metadataBySessionId
        }

        private static func parseMetadataFile(
            at url: URL,
            modifiedAt: Date,
            size: Int,
            fallbackScore: Double?
        ) -> FileCacheEntry {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cliSessionId = object["cliSessionId"] as? String,
                  !cliSessionId.isEmpty else {
                return FileCacheEntry(modifiedAt: modifiedAt, size: size, cliSessionId: nil, metadata: nil)
            }

            let title = (object["title"] as? String).flatMap(ClaudeSessionTitleResolver.sanitizedTitle)
            let score = ClaudeSessionTitleResolver.timestampScore(from: object)
                ?? fallbackScore
                ?? 0
            let metadata = AppSessionMetadata(
                title: title,
                isArchived: object["isArchived"] as? Bool == true,
                score: score
            )
            return FileCacheEntry(modifiedAt: modifiedAt, size: size, cliSessionId: cliSessionId, metadata: metadata)
        }
    }

    private static let appSessionMetadataCache = AppSessionMetadataCache(ttl: 5)

    public static func title(for sessionId: String) -> String? {
        title(
            for: sessionId,
            projectsRoot: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true),
            appSessionsRoot: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)
        )
    }

    public static func title(for sessionId: String, transcriptPath: String?) -> String? {
        title(
            for: sessionId,
            transcriptPath: transcriptPath,
            projectsRoot: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true),
            appSessionsRoot: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)
        )
    }

    static func title(for sessionId: String, projectsRoot: URL) -> String? {
        title(for: sessionId, projectsRoot: projectsRoot, appSessionsRoot: nil)
    }

    static func title(for sessionId: String, projectsRoot: URL, appSessionsRoot: URL?) -> String? {
        guard !sessionId.isEmpty else {
            return nil
        }

        if let appTitle = appSessionTitle(for: sessionId, sessionsRoot: appSessionsRoot) {
            return appTitle
        }

        return transcriptTitle(for: sessionId, projectsRoot: projectsRoot)
    }

    static func title(
        for sessionId: String,
        transcriptPath: String?,
        projectsRoot: URL,
        appSessionsRoot: URL?
    ) -> String? {
        guard !sessionId.isEmpty else {
            return nil
        }

        if let appTitle = appSessionTitle(for: sessionId, sessionsRoot: appSessionsRoot) {
            return appTitle
        }

        if let transcriptPath = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptPath.isEmpty,
           let title = transcriptTitle(for: sessionId, file: URL(fileURLWithPath: transcriptPath)) {
            return title
        }

        return transcriptTitle(for: sessionId, projectsRoot: projectsRoot)
    }

    public static func transcriptPath(for sessionId: String) -> String? {
        transcriptPath(
            for: sessionId,
            projectsRoot: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        )
    }

    static func transcriptPath(for sessionId: String, projectsRoot: URL) -> String? {
        guard !sessionId.isEmpty else {
            return nil
        }
        return transcriptFile(for: sessionId, projectsRoot: projectsRoot)?.path
    }

    public static func isArchived(sessionId: String) -> Bool {
        appSessionStatus(
            sessionId: sessionId,
            appSessionsRoot: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)
        ) == .archived
    }

    static func isArchived(sessionId: String, appSessionsRoot: URL?) -> Bool {
        appSessionStatus(sessionId: sessionId, appSessionsRoot: appSessionsRoot) == .archived
    }

    public static func appSessionStatus(sessionId: String) -> ClaudeAppSessionStatus {
        appSessionStatus(
            sessionId: sessionId,
            appSessionsRoot: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)
        )
    }

    static func appSessionStatus(sessionId: String, appSessionsRoot: URL?) -> ClaudeAppSessionStatus {
        guard let metadata = appSessionMetadata(for: sessionId, sessionsRoot: appSessionsRoot) else {
            return .missing
        }

        return metadata.isArchived ? .archived : .active
    }

    private static func transcriptTitle(for sessionId: String, projectsRoot: URL) -> String? {
        guard !sessionId.isEmpty,
              let file = transcriptFile(for: sessionId, projectsRoot: projectsRoot),
              let title = transcriptTitle(for: sessionId, file: file) else {
            return nil
        }

        return title
    }

    private static func transcriptTitle(for sessionId: String, file: URL) -> String? {
        guard let text = transcriptText(from: file) else {
            return nil
        }

        var customTitle: String?
        var generatedTitle: String?
        var lastPrompt: String?
        var latestUserPrompt: String?
        var queuedPrompt: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["sessionId"] as? String == sessionId,
                  let type = object["type"] as? String else {
                continue
            }

            if type == "custom-title",
               let title = object["customTitle"] as? String,
               let sanitized = sanitizedTitle(title) {
                customTitle = sanitized
            }

            if type == "ai-title",
               let title = object["aiTitle"] as? String,
               let sanitized = sanitizedTitle(title) {
                generatedTitle = sanitized
            }

            if type == "last-prompt",
               let prompt = object["lastPrompt"] as? String,
               let sanitized = sanitizedTitle(prompt) {
                lastPrompt = sanitized
            }

            if type == "queue-operation",
               object["operation"] as? String == "enqueue",
               let prompt = object["content"] as? String,
               let sanitized = sanitizedTitle(prompt) {
                queuedPrompt = sanitized
            }

            if type == "user",
               let sanitized = userPromptTitle(from: object) {
                latestUserPrompt = sanitized
            }
        }

        return customTitle ?? generatedTitle ?? lastPrompt ?? latestUserPrompt ?? queuedPrompt
    }

    private static func appSessionTitle(for sessionId: String, sessionsRoot: URL?) -> String? {
        appSessionMetadata(for: sessionId, sessionsRoot: sessionsRoot)?.title
    }

    private static func appSessionMetadata(for sessionId: String, sessionsRoot: URL?) -> AppSessionMetadata? {
        appSessionMetadataCache.metadata(for: sessionId, sessionsRoot: sessionsRoot)
    }

    /// Caches successful sessionId → transcript URL lookups so repeat callers
    /// skip the full projects-tree enumeration. Misses are never cached: a
    /// transcript that appears moments later (the response-refresh retry
    /// ladder) must be found on the next attempt.
    private final class TranscriptFileCache: @unchecked Sendable {
        private struct Entry {
            var url: URL
            var cachedAt: Date
        }

        private let lock = NSLock()
        private let limit: Int
        private var entries: [String: Entry] = [:]

        init(limit: Int) {
            self.limit = limit
        }

        func url(forKey key: String) -> URL? {
            lock.lock()
            let entry = entries[key]
            lock.unlock()
            guard let entry else {
                return nil
            }

            guard FileManager.default.fileExists(atPath: entry.url.path) else {
                lock.lock()
                entries[key] = nil
                lock.unlock()
                return nil
            }
            return entry.url
        }

        func store(_ url: URL, forKey key: String) {
            lock.lock()
            if entries[key] == nil,
               entries.count >= limit,
               let oldestKey = entries.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key {
                entries.removeValue(forKey: oldestKey)
            }
            entries[key] = Entry(url: url, cachedAt: Date())
            lock.unlock()
        }
    }

    private static let transcriptFileCache = TranscriptFileCache(limit: 500)

    private static func transcriptFile(for sessionId: String, projectsRoot: URL) -> URL? {
        let cacheKey = "\(projectsRoot.standardizedFileURL.path)|\(sessionId)"
        if let cached = transcriptFileCache.url(forKey: cacheKey) {
            return cached
        }

        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "\(sessionId).jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            transcriptFileCache.store(url, forKey: cacheKey)
            return url
        }

        return nil
    }

    private static func transcriptText(from url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private static func userPromptTitle(from object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any],
              message["role"] as? String == "user",
              let content = message["content"] else {
            return nil
        }

        if let text = content as? String {
            return sanitizedTitle(text)
        }

        guard let parts = content as? [[String: Any]] else {
            return nil
        }

        let text = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else {
                return nil
            }
            return part["text"] as? String
        }
        .joined(separator: " ")

        return sanitizedTitle(text)
    }

    private static func sanitizedTitle(_ value: String) -> String? {
        AgentSessionTitleSanitizer.optional(value)
    }

    private static func timestampScore(from object: [String: Any]) -> Double? {
        for key in ["lastActivityAt", "updatedAt", "createdAt"] {
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }

            if let value = object[key] as? String {
                if let number = Double(value) {
                    return number
                }

                if let date = AgentSessionsDates.date(from: value) {
                    return date.timeIntervalSince1970
                }
            }
        }

        return nil
    }
}
