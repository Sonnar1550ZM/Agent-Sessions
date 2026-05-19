import AgentSessionsCore
import Foundation

/// Detects when a user interrupts a top-level Claude Code session.
///
/// Claude Code does not fire its `Stop` hook for user-initiated interrupts, so
/// the menu bar can be stuck showing `working` indefinitely. The watcher reads
/// just the tail of each modified main-session transcript and emits an idle
/// event when the last user-authored entry is the synthetic
/// `[Request interrupted by user]` marker that Claude Code writes after Esc.
final class ClaudeMainSessionInterruptWatcher {
    private struct FileTracker {
        var size: UInt64
        var modifiedAt: Date
        var emittedInterrupt: Bool
    }

    private let queue = DispatchQueue(
        label: "app.agentsessions.claude-main-interrupt-watcher",
        qos: .utility
    )
    private let handler: (AgentEvent) -> Void
    private var activityMonitor: FileSystemActivityMonitor?
    private var fileTrackers: [String: FileTracker] = [:]
    private var pendingChangePoll: DispatchWorkItem?
    private var pendingChangedPaths: Set<String> = []
    private static let changePollDelay: TimeInterval = 0.05
    private static let tailReadLimit: UInt64 = 64_000

    init(handler: @escaping (AgentEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        activityMonitor = FileSystemActivityMonitor(
            paths: [Self.watchRoot()],
            latency: Self.changePollDelay,
            queue: queue
        ) { [weak self] paths in
            self?.scheduleChangedPathPoll(paths)
        }
        activityMonitor?.start()
    }

    func stop() {
        activityMonitor?.stop()
        activityMonitor = nil
        pendingChangePoll?.cancel()
        pendingChangePoll = nil
        pendingChangedPaths.removeAll()
        fileTrackers.removeAll()
    }

    private func scheduleChangedPathPoll(_ paths: [String]) {
        let relevant = paths.filter(Self.isMainSessionPath)
        guard !relevant.isEmpty else {
            return
        }

        pendingChangedPaths.formUnion(relevant)
        guard pendingChangePoll == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = self.pendingChangedPaths
            self.pendingChangedPaths.removeAll()
            self.pendingChangePoll = nil
            for path in paths {
                self.check(URL(fileURLWithPath: path))
            }
        }
        pendingChangePoll = workItem
        queue.asyncAfter(deadline: .now() + Self.changePollDelay, execute: workItem)
    }

    private func check(_ file: URL) {
        let path = file.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let modifiedAt = attrs?[.modificationDate] as? Date,
              let sizeNumber = attrs?[.size] as? NSNumber else {
            return
        }
        let size = sizeNumber.uint64Value

        var tracker = fileTrackers[path] ?? FileTracker(
            size: 0,
            modifiedAt: modifiedAt,
            emittedInterrupt: false
        )
        defer { fileTrackers[path] = tracker }

        guard size != tracker.size || modifiedAt != tracker.modifiedAt else {
            return
        }
        let shrank = size < tracker.size
        tracker.size = size
        tracker.modifiedAt = modifiedAt
        if shrank {
            tracker.emittedInterrupt = false
        }

        guard size > 0,
              let text = Self.tailText(from: file, size: size, limit: Self.tailReadLimit) else {
            return
        }

        guard let lastEvent = Self.lastUserMessageEvent(in: text) else {
            return
        }

        switch lastEvent {
        case .interrupted(let info):
            guard !tracker.emittedInterrupt else {
                return
            }
            tracker.emittedInterrupt = true

            let sessionId = Self.sessionId(from: file)
            let event = AgentEvent(
                agent: .claudeCode,
                sessionId: sessionId,
                state: .idle,
                title: "",
                cwd: info.cwd ?? "",
                event: "interrupt",
                terminal: "",
                pid: nil,
                updatedAt: modifiedAt,
                transcriptPath: file.path
            )
            handler(event)
        case .userPrompt:
            tracker.emittedInterrupt = false
        }
    }

    private enum LastUserMessage {
        case interrupted(info: UserMessageInfo)
        case userPrompt
    }

    private struct UserMessageInfo {
        var cwd: String?
    }

    private static func lastUserMessageEvent(in text: String) -> LastUserMessage? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "user" else {
                continue
            }

            if ClaudeSessionParser.isInterruptedUserMessage(object) {
                let cwd = (object["cwd"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .interrupted(info: UserMessageInfo(cwd: (cwd?.isEmpty == false) ? cwd : nil))
            }
            return .userPrompt
        }
        return nil
    }

    private static func sessionId(from file: URL) -> String {
        let stem = file.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? file.lastPathComponent : stem
    }

    static func watchRoot() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    static func isMainSessionPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "jsonl" else {
            return false
        }
        let components = url.pathComponents
        guard !components.contains("subagents") else {
            return false
        }
        // Main session files live directly under the project directory, e.g.
        // `~/.claude/projects/<project>/<uuid>.jsonl`. The parent directory of
        // the file should be the project directory, whose parent is `projects`.
        let parent = url.deletingLastPathComponent()
        return parent.deletingLastPathComponent().lastPathComponent == "projects"
    }

    private static func tailText(from url: URL, size: UInt64, limit: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

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
