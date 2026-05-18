import AgentSessionsCore
import Foundation

final class ClaudeSubagentWatcher {
    private struct Snapshot {
        let event: AgentEvent
        let fingerprint: String
    }

    private struct CachedSnapshot {
        let modifiedAt: Date
        let snapshot: Snapshot?
    }

    private let queue = DispatchQueue(label: "app.agentsessions.claude-subagent-watcher")
    private let handler: (AgentEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var lastFingerprints: [String: String] = [:]
    private var cachedSnapshotsByPath: [String: CachedSnapshot] = [:]

    init(handler: @escaping (AgentEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5.0)
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

    private func poll() {
        var activePaths: Set<String> = []
        for file in Self.latestSubagentFiles(limit: 50) {
            let path = file.path
            activePaths.insert(path)
            guard let modifiedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  let snapshot = snapshot(for: file, modifiedAt: modifiedAt) else {
                continue
            }

            let key = snapshot.event.sessionId
            guard snapshot.fingerprint != lastFingerprints[key] else {
                continue
            }

            lastFingerprints[key] = snapshot.fingerprint
            handler(snapshot.event)
        }

        cachedSnapshotsByPath = cachedSnapshotsByPath.filter { activePaths.contains($0.key) }
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
        guard let text = tailText(from: file),
              let parsed = ClaudeSessionParser.parseSubagentTranscript(transcriptPath: file.path, text: text) else {
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
        parsed: ClaudeParsedSubagent
    ) -> Snapshot {
        let age = Date().timeIntervalSince(modifiedAt)
        let state: AgentState = age > 120 ? .idle : parsed.state
        let metadata = parsed.metadata

        let event = AgentEvent(
            agent: .claudeCode,
            sessionId: metadata.sessionId,
            state: state,
            title: parsed.title,
            cwd: parsed.cwd,
            event: "JSONLWatch",
            terminal: "",
            pid: nil,
            updatedAt: modifiedAt,
            parentSessionId: metadata.parentSessionId,
            subagentNickname: metadata.subagentNickname,
            subagentRole: metadata.subagentRole,
            subagentDepth: metadata.subagentDepth,
            transcriptPath: file.path,
            latestResponseText: parsed.latestResponseText,
            latestResponsePhase: parsed.latestResponseText == nil ? nil : "assistant"
        )

        return Snapshot(
            event: event,
            fingerprint: [
                file.path,
                String(modifiedAt.timeIntervalSince1970),
                state.rawValue,
                parsed.title,
                parsed.cwd,
                metadata.parentSessionId,
                metadata.subagentNickname,
                metadata.subagentRole,
                metadata.subagentDepth.description,
                parsed.latestResponseText ?? ""
            ].joined(separator: "|")
        )
    }

    private static func latestSubagentFiles(limit: Int) -> [URL] {
        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.pathComponents.contains("subagents"),
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
}
