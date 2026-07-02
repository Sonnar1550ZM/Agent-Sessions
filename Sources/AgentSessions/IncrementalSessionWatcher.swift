import AgentSessionsCore
import Foundation

/// Shared incremental-jsonl watcher for Claude subagent transcripts and Codex
/// rollouts. The state machine, file tracking, and delta-read logic are
/// identical between the two; differences (parser, file discovery, snapshot
/// builder) are supplied via `Adapter`.
final class IncrementalSessionWatcher<Parsed> {
    struct Snapshot {
        let event: AgentEvent
        let fingerprint: String
    }

    struct Adapter {
        let queueLabel: String
        let watchRoot: () -> URL
        let latestFiles: (_ limit: Int) -> [URL]
        let isRelevantPath: (String) -> Bool
        let fallbackPollInterval: TimeInterval
        let fallbackPollLeeway: DispatchTimeInterval
        let loadFull: (_ file: URL, _ modifiedAt: Date) -> (snapshot: Snapshot, parsed: Parsed)?
        let applyDelta: (_ file: URL, _ modifiedAt: Date, _ text: String, _ base: Parsed) -> (snapshot: Snapshot, parsed: Parsed)?
    }

    private struct FileTracker {
        var inode: UInt64
        var bytesRead: UInt64
        var modifiedAt: Date
        var partialTail: Data
        var baseSession: Parsed?
        var lastSnapshot: Snapshot?
    }

    private let adapter: Adapter
    private let queue: DispatchQueue
    private let handler: (AgentEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var activityMonitor: FileSystemActivityMonitor?
    private var isActivityMonitorRunning = false
    private var pendingChangePoll: DispatchWorkItem?
    private var pendingChangedPaths: Set<String> = []
    private var pendingFullPoll = false
    private var lastPollDate = Date.distantPast
    private var lastMonitorSignalAt = Date.distantPast
    private var isInFullPoll = false
    private var fullPollEmittedChange = false
    private var lastFingerprints: [String: (fingerprint: String, lastSeenAt: Date)] = [:]
    private var fileTrackers: [String: FileTracker] = [:]
    private static var changePollDelay: TimeInterval { 0.02 }
    private static var minimumChangePollInterval: TimeInterval { 0.05 }
    private static var activityMonitorUnavailablePollInterval: TimeInterval { 5 }
    private static var activityMonitorUnavailablePollLeeway: DispatchTimeInterval { .seconds(1) }
    private static var activityMonitorStaleGrace: TimeInterval { 5 }

    init(adapter: Adapter, handler: @escaping (AgentEvent) -> Void) {
        self.adapter = adapter
        self.queue = DispatchQueue(label: adapter.queueLabel, qos: .userInitiated)
        self.handler = handler
    }

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        createActivityMonitorIfNeeded()
        isActivityMonitorRunning = activityMonitor?.start() ?? false
        if isActivityMonitorRunning {
            lastMonitorSignalAt = Date()
        }
        scheduleFallbackTimer(deadline: .now())
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        activityMonitor?.stop()
        activityMonitor = nil
        isActivityMonitorRunning = false
        pendingChangePoll?.cancel()
        pendingChangePoll = nil
        pendingChangedPaths.removeAll()
        pendingFullPoll = false
    }

    private func poll() {
        retryActivityMonitorIfNeeded()
        lastPollDate = Date()
        isInFullPoll = true
        fullPollEmittedChange = false
        var activePaths: Set<String> = []
        for file in adapter.latestFiles(50) {
            activePaths.insert(file.path)
            ingest(file)
        }
        isInFullPoll = false
        fileTrackers = fileTrackers.filter { activePaths.contains($0.key) }
        // Fingerprints embed the latest prompt/response text, so stale
        // entries are too heavy to keep for the lifetime of the process.
        lastFingerprints = WatcherCachePruning.prunedByAge(
            lastFingerprints,
            lastSeenAt: { $0.lastSeenAt }
        )
        restartActivityMonitorIfStale()
    }

    /// FSEventStreams have been observed to stop delivering after long
    /// uptimes (sleep/wake cycles). When the fallback poll discovers changes
    /// the monitor stayed silent about, recreate the stream so the fast path
    /// comes back instead of degrading to poll-cadence latency for good.
    private func restartActivityMonitorIfStale() {
        guard isActivityMonitorRunning,
              fullPollEmittedChange,
              Date().timeIntervalSince(lastMonitorSignalAt) > Self.activityMonitorStaleGrace else {
            return
        }

        activityMonitor?.stop()
        activityMonitor = nil
        createActivityMonitorIfNeeded()
        isActivityMonitorRunning = activityMonitor?.start() ?? false
        if isActivityMonitorRunning {
            lastMonitorSignalAt = Date()
        } else {
            scheduleFallbackTimer(deadline: .now() + adapter.fallbackPollInterval)
        }
    }

    private func createActivityMonitorIfNeeded() {
        guard activityMonitor == nil else { return }

        activityMonitor = FileSystemActivityMonitor(
            paths: [adapter.watchRoot()],
            latency: Self.changePollDelay,
            queue: queue
        ) { [weak self] paths in
            self?.lastMonitorSignalAt = Date()
            self?.scheduleChangedPathPoll(paths)
        }
    }

    private func retryActivityMonitorIfNeeded() {
        guard !isActivityMonitorRunning else { return }

        createActivityMonitorIfNeeded()
        guard activityMonitor?.start() == true else { return }

        isActivityMonitorRunning = true
        lastMonitorSignalAt = Date()
        scheduleFallbackTimer(deadline: .now() + adapter.fallbackPollInterval)
    }

    private func scheduleFallbackTimer(deadline: DispatchTime) {
        guard let timer else { return }

        if isActivityMonitorRunning {
            // The fallback poll stays at the adapter's cadence even while
            // FSEvents is healthy: streams have been observed to go silent
            // after long uptimes (sleep/wake), and a slow safety net turns
            // that silent failure into user-visible lag.
            timer.schedule(
                deadline: deadline,
                repeating: adapter.fallbackPollInterval,
                leeway: adapter.fallbackPollLeeway
            )
        } else {
            timer.schedule(
                deadline: deadline,
                repeating: min(adapter.fallbackPollInterval, Self.activityMonitorUnavailablePollInterval),
                leeway: Self.activityMonitorUnavailablePollLeeway
            )
        }
    }

    private func scheduleChangedPathPoll(_ paths: [String]) {
        let relevantPaths = paths.filter(adapter.isRelevantPath)
        let watchRoot = adapter.watchRoot()
        let needsFullPoll = paths.contains { path in
            Self.isDirectoryEventPath(path, under: watchRoot)
        }
        guard !relevantPaths.isEmpty || needsFullPoll else { return }

        if needsFullPoll {
            pendingChangedPaths.removeAll()
            pendingFullPoll = true
        } else if !pendingFullPoll {
            pendingChangedPaths.formUnion(relevantPaths)
        }
        guard pendingChangePoll == nil else { return }

        let elapsed = Date().timeIntervalSince(lastPollDate)
        let delay = max(Self.changePollDelay, Self.minimumChangePollInterval - elapsed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = self.pendingChangedPaths
            let shouldPollAll = self.pendingFullPoll
            self.pendingChangedPaths.removeAll()
            self.pendingFullPoll = false
            self.pendingChangePoll = nil
            if shouldPollAll {
                self.poll()
            } else {
                self.pollChangedPaths(paths)
            }
        }
        pendingChangePoll = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func isDirectoryEventPath(_ path: String, under root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            return false
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func pollChangedPaths(_ paths: Set<String>) {
        lastPollDate = Date()
        for path in paths {
            ingest(URL(fileURLWithPath: path))
        }
    }

    private func ingest(_ file: URL) {
        let path = file.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let modifiedAt = attrs?[.modificationDate] as? Date,
              let inode = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value,
              let sizeNumber = attrs?[.size] as? NSNumber else {
            return
        }
        let size = sizeNumber.uint64Value

        var tracker = fileTrackers[path]
        let needsFullLoad = tracker == nil
            || tracker!.inode != inode
            || size < tracker!.bytesRead
        // Aged-idle refreshes also emit, but only byte-level changes indicate
        // file activity the monitor should have reported.
        let sawContentChange = needsFullLoad || size != tracker!.bytesRead

        let snapshot: Snapshot?
        if needsFullLoad {
            let result = adapter.loadFull(file, modifiedAt)
            snapshot = result?.snapshot
            fileTrackers[path] = FileTracker(
                inode: inode,
                bytesRead: size,
                modifiedAt: modifiedAt,
                partialTail: Data(),
                baseSession: result?.parsed,
                lastSnapshot: snapshot
            )
        } else if size == tracker!.bytesRead {
            snapshot = tracker!.lastSnapshot.flatMap {
                Self.refreshedSnapshot($0, modifiedAt: modifiedAt)
            }
            tracker!.modifiedAt = modifiedAt
            fileTrackers[path] = tracker
        } else if let base = tracker!.baseSession {
            snapshot = makeDeltaSnapshot(
                file: file,
                modifiedAt: modifiedAt,
                tracker: &tracker!,
                base: base,
                totalSize: size
            )
            fileTrackers[path] = tracker
        } else {
            let result = adapter.loadFull(file, modifiedAt)
            snapshot = result?.snapshot
            tracker!.bytesRead = size
            tracker!.modifiedAt = modifiedAt
            tracker!.partialTail = Data()
            tracker!.baseSession = result?.parsed
            tracker!.lastSnapshot = snapshot
            fileTrackers[path] = tracker
        }

        guard let snapshot else { return }

        let key = "\(file.path):\(snapshot.event.sessionId)"
        guard snapshot.fingerprint != lastFingerprints[key]?.fingerprint else {
            // Touch the entry so active-but-unchanged sessions survive pruning.
            lastFingerprints[key]?.lastSeenAt = Date()
            return
        }

        lastFingerprints[key] = (snapshot.fingerprint, Date())
        if isInFullPoll, sawContentChange {
            fullPollEmittedChange = true
        }
        handler(snapshot.event)
    }

    private func makeDeltaSnapshot(
        file: URL,
        modifiedAt: Date,
        tracker: inout FileTracker,
        base: Parsed,
        totalSize: UInt64
    ) -> Snapshot? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return tracker.lastSnapshot.flatMap { Self.refreshedSnapshot($0, modifiedAt: modifiedAt) }
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: tracker.bytesRead)
        } catch {
            return tracker.lastSnapshot.flatMap { Self.refreshedSnapshot($0, modifiedAt: modifiedAt) }
        }
        let deltaData = (try? handle.readToEnd()) ?? Data()
        var combined = tracker.partialTail + deltaData

        let newline = UInt8(ascii: "\n")
        if let lastNewlineIndex = combined.lastIndex(of: newline) {
            let after = combined.index(after: lastNewlineIndex)
            let partial = combined.suffix(from: after)
            tracker.partialTail = Data(partial)
            combined = Data(combined.prefix(upTo: after))
        } else {
            tracker.partialTail = combined
            tracker.bytesRead = totalSize
            tracker.modifiedAt = modifiedAt
            return tracker.lastSnapshot.flatMap { Self.refreshedSnapshot($0, modifiedAt: modifiedAt) }
        }

        // `partialTail` is already kept in memory, so advance to the real EOF.
        // Re-reading those bytes on the next delta corrupts the first JSONL line.
        tracker.bytesRead = totalSize
        tracker.modifiedAt = modifiedAt

        guard let text = String(data: combined, encoding: .utf8) else {
            tracker.baseSession = nil
            tracker.partialTail = Data()
            return tracker.lastSnapshot.flatMap { Self.refreshedSnapshot($0, modifiedAt: modifiedAt) }
        }

        guard let result = adapter.applyDelta(file, modifiedAt, text, base) else {
            return nil
        }
        tracker.baseSession = result.parsed
        tracker.lastSnapshot = result.snapshot
        return result.snapshot
    }

    private static func refreshedSnapshot(_ snapshot: Snapshot?, modifiedAt: Date) -> Snapshot? {
        guard let snapshot else { return nil }

        let age = Date().timeIntervalSince(modifiedAt)
        guard age > 600, snapshot.event.state != .idle else {
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
            latestUserPrompt: snapshot.event.latestUserPrompt,
            latestResponseText: snapshot.event.latestResponseText,
            latestResponsePhase: snapshot.event.latestResponsePhase
        )
        return Snapshot(event: event, fingerprint: snapshot.fingerprint + "|aged-idle")
    }
}
