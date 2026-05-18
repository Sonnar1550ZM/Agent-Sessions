import AgentSessionsCore
import Foundation

final class CodexSessionWatcher {
    private struct Snapshot {
        let event: AgentEvent
        let fingerprint: String
    }

    private struct CachedSnapshot {
        let modifiedAt: Date
        let snapshot: Snapshot?
    }

    private let queue = DispatchQueue(label: "app.agentsessions.codex-session-watcher")
    private let handler: (AgentEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var activityMonitor: FileSystemActivityMonitor?
    private var pendingChangePoll: DispatchWorkItem?
    private var pendingChangedPaths: Set<String> = []
    private var lastPollDate = Date.distantPast
    private var lastFingerprints: [String: String] = [:]
    private var cachedSnapshotsByPath: [String: CachedSnapshot] = [:]
    private static let changePollDelay: TimeInterval = 0.18
    private static let minimumChangePollInterval: TimeInterval = 0.35
    private static let fallbackPollInterval: TimeInterval = 30

    init(handler: @escaping (AgentEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.fallbackPollInterval, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        activityMonitor = FileSystemActivityMonitor(
            paths: [Self.watchRoot()],
            latency: Self.changePollDelay,
            queue: queue
        ) { [weak self] paths in
            self?.scheduleChangedPathPoll(paths)
        }
        activityMonitor?.start()
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        activityMonitor?.stop()
        activityMonitor = nil
        pendingChangePoll?.cancel()
        pendingChangePoll = nil
        pendingChangedPaths.removeAll()
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

    static func fileStatus(for sessionId: String) -> CodexSessionFileStatus {
        CodexSessionFileIndex().status(for: sessionId)
    }

    private func poll() {
        lastPollDate = Date()
        var activePaths: Set<String> = []
        for file in Self.latestRolloutFiles(limit: 50) {
            let path = file.path
            activePaths.insert(path)
            ingest(file)
        }

        cachedSnapshotsByPath = cachedSnapshotsByPath.filter { activePaths.contains($0.key) }
    }

    private func scheduleChangedPathPoll(_ paths: [String]) {
        let relevantPaths = paths.filter(Self.isRelevantRolloutPath)
        guard !relevantPaths.isEmpty else {
            return
        }

        pendingChangedPaths.formUnion(relevantPaths)
        guard pendingChangePoll == nil else {
            return
        }

        let elapsed = Date().timeIntervalSince(lastPollDate)
        let delay = max(Self.changePollDelay, Self.minimumChangePollInterval - elapsed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            let paths = self.pendingChangedPaths
            self.pendingChangedPaths.removeAll()
            self.pendingChangePoll = nil
            self.pollChangedPaths(paths)
        }
        pendingChangePoll = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func pollChangedPaths(_ paths: Set<String>) {
        lastPollDate = Date()
        for path in paths {
            ingest(URL(fileURLWithPath: path))
        }
    }

    private func ingest(_ file: URL) {
        guard let modifiedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let snapshot = snapshot(for: file, modifiedAt: modifiedAt) else {
            return
        }

        let key = snapshot.event.sessionId
        guard snapshot.fingerprint != lastFingerprints[key] else {
            return
        }

        lastFingerprints[key] = snapshot.fingerprint
        handler(snapshot.event)
    }

    private func snapshot(for file: URL, modifiedAt: Date) -> Snapshot? {
        let key = file.path
        if let cached = cachedSnapshotsByPath[key],
           cached.modifiedAt == modifiedAt {
            return Self.refreshedSnapshot(cached.snapshot, modifiedAt: modifiedAt)
        }

        let snapshot = Self.makeSnapshot(file: file, modifiedAt: modifiedAt)
        cachedSnapshotsByPath[key] = CachedSnapshot(modifiedAt: modifiedAt, snapshot: snapshot)
        return snapshot
    }

    private static func makeSnapshot(file: URL, modifiedAt: Date) -> Snapshot? {
        guard let text = contextText(from: file) else {
            return nil
        }

        let parsed = CodexSessionParser.parse(text, fallbackSessionId: fallbackSessionId(from: file))
        guard !parsed.cwd.isEmpty, !parsed.isInternalSubagent else {
            return nil
        }

        return snapshot(file: file, modifiedAt: modifiedAt, parsed: parsed)
    }

    private static func refreshedSnapshot(_ snapshot: Snapshot?, modifiedAt: Date) -> Snapshot? {
        guard let snapshot else {
            return nil
        }

        let age = Date().timeIntervalSince(modifiedAt)
        guard age > 120, snapshot.event.state != .idle else {
            return snapshot
        }

        let event = AgentEvent(
            agent: snapshot.event.agent,
            sessionId: snapshot.event.sessionId,
            state: .idle,
            title: snapshot.event.title,
            cwd: snapshot.event.cwd,
            event: snapshot.event.event,
            terminal: snapshot.event.terminal,
            pid: snapshot.event.pid,
            updatedAt: snapshot.event.updatedAt,
            parentSessionId: snapshot.event.parentSessionId,
            subagentNickname: snapshot.event.subagentNickname,
            subagentRole: snapshot.event.subagentRole,
            subagentDepth: snapshot.event.subagentDepth,
            transcriptPath: snapshot.event.transcriptPath,
            latestResponseText: snapshot.event.latestResponseText,
            latestResponsePhase: snapshot.event.latestResponsePhase
        )
        return Snapshot(
            event: event,
            fingerprint: snapshot.fingerprint + "|aged-idle"
        )
    }

    private static func snapshot(
        file: URL,
        modifiedAt: Date,
        parsed: CodexParsedSession
    ) -> Snapshot {
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
                parsed.subagentDepth.map(String.init) ?? "",
                parsed.latestResponseText ?? "",
                parsed.latestResponsePhase ?? ""
            ].joined(separator: "|")
        )
    }

    private static func latestRolloutFiles(limit: Int) -> [URL] {
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
