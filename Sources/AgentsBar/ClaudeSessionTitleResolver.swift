import Foundation

enum ClaudeSessionTitleResolver {
    static func title(for sessionId: String) -> String? {
        guard !sessionId.isEmpty,
              let file = transcriptFile(for: sessionId),
              let text = tailText(from: file, limit: 1_000_000) else {
            return nil
        }

        var generatedTitle: String?
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
                return sanitized
            }

            if type == "ai-title",
               let title = object["aiTitle"] as? String,
               let sanitized = sanitizedTitle(title) {
                generatedTitle = sanitized
            }
        }

        return generatedTitle
    }

    private static func transcriptFile(for sessionId: String) -> URL? {
        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: root,
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

    private static func tailText(from url: URL, limit: UInt64) -> String? {
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

    private static func sanitizedTitle(_ value: String) -> String? {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
    }
}
