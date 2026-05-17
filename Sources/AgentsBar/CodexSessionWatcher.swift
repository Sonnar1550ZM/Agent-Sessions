import AgentsBarCore
import Foundation

final class CodexSessionWatcher {
    private struct Snapshot {
        let event: AgentEvent
        let fingerprint: String
    }

    private let queue = DispatchQueue(label: "app.agentsbar.codex-session-watcher")
    private let handler: (AgentEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var lastFingerprints: [String: String] = [:]

    init(handler: @escaping (AgentEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    static func title(for sessionId: String) -> String? {
        threadTitle(for: sessionId)
    }

    static func shouldHideSession(_ sessionId: String) -> Bool {
        guard let file = rolloutFile(for: sessionId),
              let text = contextText(from: file) else {
            return false
        }

        return CodexSessionParser.parse(text, fallbackSessionId: sessionId).isInternalSubagent
    }

    private func poll() {
        for snapshot in Self.makeSnapshots() {
            let key = snapshot.event.sessionId
            guard snapshot.fingerprint != lastFingerprints[key] else {
                continue
            }

            lastFingerprints[key] = snapshot.fingerprint
            handler(snapshot.event)
        }
    }

    private static func makeSnapshots() -> [Snapshot] {
        var snapshots: [Snapshot] = []

        for file in latestRolloutFiles(limit: 50) {
            guard let modifiedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  let text = contextText(from: file) else {
                continue
            }

            let parsed = CodexSessionParser.parse(text, fallbackSessionId: fallbackSessionId(from: file))
            guard !parsed.cwd.isEmpty, !parsed.isInternalSubagent else {
                continue
            }

            snapshots.append(snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed))
        }

        return snapshots
    }

    private static func snapshot(
        file: URL,
        modifiedAt: Date,
        parsed: CodexParsedSession
    ) -> Snapshot {
        let age = Date().timeIntervalSince(modifiedAt)
        let state: AgentState = age > 120 ? .idle : parsed.state
        let title = threadTitle(for: parsed.sessionId)
            ?? URL(fileURLWithPath: parsed.cwd).lastPathComponent

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
            subagentDepth: parsed.subagentDepth
        )

        return Snapshot(
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
                parsed.subagentDepth.map(String.init) ?? ""
            ].joined(separator: "|")
        )
    }

    private static func latestRolloutFiles(limit: Int) -> [URL] {
        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)

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

    private static func rolloutFile(for sessionId: String) -> URL? {
        latestRolloutFiles(limit: 200).first { file in
            fallbackSessionId(from: file) == sessionId
        }
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

    private static func threadTitle(for sessionId: String) -> String? {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")

        guard let text = tailText(from: url, limit: 2_000_000) else {
            return nil
        }

        var matchedTitle: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] as? String == sessionId,
                  let title = object["thread_name"] as? String else {
                continue
            }
            matchedTitle = sanitizedTitle(title)
        }

        return matchedTitle
    }

    private static func sanitizedTitle(_ value: String) -> String? {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
    }

    private static func fallbackSessionId(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.split(separator: "-").suffix(5).joined(separator: "-")
    }
}
