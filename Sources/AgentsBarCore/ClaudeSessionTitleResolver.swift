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
              let text = transcriptText(from: file) else {
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
        guard let sessionsRoot,
              let enumerator = FileManager.default.enumerator(
                  at: sessionsRoot,
                  includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        var bestMatch: AppSessionMetadata?

        for case let url as URL in enumerator {
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["cliSessionId"] as? String == sessionId else {
                continue
            }

            let title = (object["title"] as? String).flatMap(sanitizedTitle)
            let score = timestampScore(from: object)
                ?? values.contentModificationDate?.timeIntervalSince1970
                ?? 0
            let metadata = AppSessionMetadata(
                title: title,
                isArchived: object["isArchived"] as? Bool == true,
                score: score
            )

            if bestMatch == nil || score >= bestMatch!.score {
                bestMatch = metadata
            }
        }

        return bestMatch
    }

    private static func transcriptFile(for sessionId: String, projectsRoot: URL) -> URL? {
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
        let title = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
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

                if let date = AgentsBarDates.date(from: value) {
                    return date.timeIntervalSince1970
                }
            }
        }

        return nil
    }
}
