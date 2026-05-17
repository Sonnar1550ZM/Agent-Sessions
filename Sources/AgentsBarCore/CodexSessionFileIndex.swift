import Foundation

public enum CodexSessionFileStatus: Equatable, Sendable {
    case active
    case archived
    case missing
}

public struct CodexSessionFileIndex: Sendable {
    public var activeRoot: URL
    public var archivedRoot: URL

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
        guard !normalizedSessionId.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  url.lastPathComponent.contains(normalizedSessionId),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  Self.sessionId(fromRolloutURL: url) == normalizedSessionId else {
                continue
            }

            return url
        }

        return nil
    }
}
