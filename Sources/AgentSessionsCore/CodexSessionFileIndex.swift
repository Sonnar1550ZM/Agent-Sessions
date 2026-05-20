import Foundation

public enum CodexSessionFileStatus: Equatable, Sendable {
    case active
    case archived
    case missing
}

public struct CodexSessionFileIndex: Sendable {
    public var activeRoot: URL
    public var archivedRoot: URL
    private static let rolloutFileCache = RolloutFileCache(ttl: 30)

    public init(
        activeRoot: URL = Self.defaultActiveRoot(),
        archivedRoot: URL = Self.defaultArchivedRoot()
    ) {
        self.activeRoot = activeRoot
        self.archivedRoot = archivedRoot
    }

    public static func defaultActiveRoot() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public static func defaultArchivedRoot() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/archived_sessions", isDirectory: true)
    }

    public func status(for sessionId: String) -> CodexSessionFileStatus {
        if hasActiveSession(sessionId) {
            return .active
        }

        if hasArchivedSession(sessionId) {
            return .archived
        }

        return .missing
    }

    public func hasActiveSession(_ sessionId: String) -> Bool {
        activeRolloutFile(for: sessionId) != nil
    }

    public func hasArchivedSession(_ sessionId: String) -> Bool {
        archivedRolloutFile(for: sessionId) != nil
    }

    public func activeRolloutFile(for sessionId: String) -> URL? {
        rolloutFile(for: sessionId, under: activeRoot)
    }

    public func archivedRolloutFile(for sessionId: String) -> URL? {
        rolloutFile(for: sessionId, under: archivedRoot)
    }

    public static func sessionId(fromRolloutURL url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.split(separator: "-").suffix(5).joined(separator: "-")
    }

    private func rolloutFile(for sessionId: String, under root: URL) -> URL? {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else {
            return nil
        }

        return Self.rolloutFileCache.file(for: normalizedSessionId, under: root)
    }

    private final class RolloutFileCache: @unchecked Sendable {
        private struct Snapshot {
            var expiresAt: Date
            var filesBySessionId: [String: URL]
        }

        private let lock = NSLock()
        private let ttl: TimeInterval
        private var snapshots: [String: Snapshot] = [:]

        init(ttl: TimeInterval) {
            self.ttl = ttl
        }

        func file(for sessionId: String, under root: URL) -> URL? {
            let rootPath = root.standardizedFileURL.path
            let now = Date()

            lock.lock()
            if let snapshot = snapshots[rootPath],
               snapshot.expiresAt > now {
                let file = snapshot.filesBySessionId[sessionId]
                lock.unlock()
                return file
            }
            lock.unlock()

            let filesBySessionId = Self.buildIndex(under: root)
            let snapshot = Snapshot(
                expiresAt: now.addingTimeInterval(ttl),
                filesBySessionId: filesBySessionId
            )

            lock.lock()
            snapshots[rootPath] = snapshot
            lock.unlock()

            return filesBySessionId[sessionId]
        }

        private static func buildIndex(under root: URL) -> [String: URL] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [:]
            }

            var filesBySessionId: [String: (url: URL, modifiedAt: Date)] = [:]
            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix("rollout-"),
                      url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else {
                    continue
                }

                let sessionId = CodexSessionFileIndex.sessionId(fromRolloutURL: url)
                guard !sessionId.isEmpty else {
                    continue
                }

                let modifiedAt = values.contentModificationDate ?? .distantPast
                if filesBySessionId[sessionId] == nil || modifiedAt > filesBySessionId[sessionId]!.modifiedAt {
                    filesBySessionId[sessionId] = (url, modifiedAt)
                }
            }

            return filesBySessionId.mapValues(\.url)
        }
    }
}
