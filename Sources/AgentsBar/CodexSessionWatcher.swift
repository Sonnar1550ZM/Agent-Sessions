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

        return parseSessionText(text, fallbackSessionId: sessionId).isInternalSubagent
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

            let parsed = parseSessionText(text, fallbackSessionId: fallbackSessionId(from: file))
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
        parsed: (sessionId: String, state: AgentState, title: String, cwd: String, isInternalSubagent: Bool)
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
            event: "JSONLWatch",
            terminal: "",
            pid: nil,
            updatedAt: modifiedAt
        )

        return Snapshot(
            event: event,
            fingerprint: "\(file.path)|\(modifiedAt.timeIntervalSince1970)|\(state.rawValue)|\(title)"
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

    private static func parseSessionText(_ text: String, fallbackSessionId: String) -> (sessionId: String, state: AgentState, title: String, cwd: String, isInternalSubagent: Bool) {
        var sessionId = fallbackSessionId
        var state = AgentState.idle
        var title = ""
        var cwd = ""
        var isInternalSubagent = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let lineText = String(line)
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                if lineText.contains("\"type\":\"session_meta\"") {
                    if let id = extractJSONStringValue(named: "id", from: lineText), !id.isEmpty {
                        sessionId = id
                    }
                    if let metadataCwd = extractJSONStringValue(named: "cwd", from: lineText), !metadataCwd.isEmpty {
                        cwd = metadataCwd
                    }
                    if let metadataTitle = extractTitle(fromRawJSONLine: lineText) {
                        title = metadataTitle
                    }
                    if lineText.contains("\"source\":{\"subagent\":{\"other\":\"guardian\"") {
                        isInternalSubagent = true
                    }
                } else if lineText.contains("\"type\":\"turn_context\""),
                          let contextCwd = extractJSONStringValue(named: "cwd", from: lineText),
                          !contextCwd.isEmpty {
                    cwd = contextCwd
                    if let contextTitle = extractTitle(fromRawJSONLine: lineText) {
                        title = contextTitle
                    }
                }
                continue
            }

            let payload = object["payload"] as? [String: Any] ?? [:]
            if let payloadTitle = extractTitle(fromPayloadFields: payload) {
                title = payloadTitle
            }

            if type == "session_meta", let id = payload["id"] as? String, !id.isEmpty {
                sessionId = id
            }
            if type == "session_meta",
               let source = payload["source"] as? [String: Any],
               let subagent = source["subagent"] as? [String: Any],
               subagent["other"] as? String == "guardian" {
                isInternalSubagent = true
            }

            if ["session_meta", "turn_context"].contains(type),
               let contextCwd = payload["cwd"] as? String,
               !contextCwd.isEmpty {
                cwd = contextCwd
            }

            if type == "response_item" {
                let itemType = payload["type"] as? String ?? ""
                if itemType == "function_call" || itemType == "function_call_output" || itemType == "custom_tool_call_output" {
                    state = .working
                }
                if itemType == "message", let role = payload["role"] as? String, role == "user" {
                    state = .working
                }
                if itemType == "message", payload["phase"] as? String == "final_answer" {
                    state = .idle
                }
            }

            if type == "event_msg" {
                let eventType = payload["type"] as? String ?? ""
                if ["exec_command_begin", "mcp_tool_call_begin", "patch_apply_begin", "web_search_begin", "agent_message"].contains(eventType) {
                    state = .working
                }
                if ["task_complete", "turn_complete", "shutdown_complete"].contains(eventType) {
                    state = .idle
                }
                if let eventCwd = payload["cwd"] as? String, !eventCwd.isEmpty {
                    cwd = eventCwd
                }
            }
        }

        return (sessionId, state, title, cwd, isInternalSubagent)
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

    private static func extractTitle(fromPayloadFields payload: [String: Any]) -> String? {
        for key in ["thread_name", "title", "name"] {
            if let title = payload[key] as? String,
               let sanitized = sanitizedTitle(title) {
                return sanitized
            }
        }
        return nil
    }

    private static func extractTitle(fromRawJSONLine line: String) -> String? {
        if let title = extractJSONStringValue(named: "thread_name", from: line),
           let sanitized = sanitizedTitle(title) {
            return sanitized
        }
        return nil
    }

    private static func sanitizedTitle(_ value: String) -> String? {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }
        return String(title.prefix(160))
    }

    private static func extractJSONStringValue(named name: String, from text: String) -> String? {
        let marker = "\"\(name)\":\""
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        var value = ""
        var isEscaped = false
        var index = markerRange.upperBound

        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                switch character {
                case "\"", "\\", "/":
                    value.append(character)
                case "n":
                    value.append("\n")
                case "r":
                    value.append("\r")
                case "t":
                    value.append("\t")
                default:
                    value.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func fallbackSessionId(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.split(separator: "-").suffix(5).joined(separator: "-")
    }

    private static func extractTitle(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }

        for item in content {
            if let text = item["text"] as? String {
                return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
            }
        }
        return nil
    }
}
