import Foundation

public enum AgentHookState: Equatable, Sendable {
    case notInstalled
    case installed
    case updateAvailable
    case broken(String)
}

public enum AgentHookInstallerError: LocalizedError {
    case invalidConfiguration(fileName: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(fileName, reason):
            "\(fileName): \(reason)"
        }
    }
}

/// Installs the Codex / Claude Code hook scripts and registers them in the
/// per-user agent configuration files, mirroring `scripts/install-hooks.sh`.
///
/// Hook scripts are copied to `installDirectory` so registered command paths
/// stay valid even when the app bundle or checkout moves. Every configuration
/// file is backed up as `<name>.bak.<timestamp>` before it is rewritten.
public struct AgentHookInstaller: Sendable {
    public static let codexScriptName = "agent-sessions-codex-hook.sh"
    public static let claudeScriptName = "agent-sessions-claude-hook.sh"

    static let codexHookMarker = "agent-sessions-codex-hook"
    static let claudeHookMarker = "agent-sessions-claude-hook"
    static let codexFeatureMarker = "agent-sessions-managed-codex-hooks"

    private static let codexEventDefaults: [(event: String, defaults: [String: String])] = [
        ("PostToolUse", [:]),
        ("PostCompact", [:]),
        ("PreToolUse", [:]),
        ("PreCompact", [:]),
        ("PermissionRequest", [:]),
        ("SessionStart", ["matcher": "startup|resume"]),
        ("Stop", [:]),
        ("UserPromptSubmit", [:])
    ]

    private static let claudeEventStates: [(event: String, state: String)] = [
        ("SessionEnd", "Ended"),
        ("Notification", "Waiting"),
        ("PermissionRequest", "Waiting"),
        ("PreCompact", "Working"),
        ("PostCompact", "Idle"),
        ("PostToolUseFailure", "ToolFail"),
        ("SessionStart", "Idle"),
        ("Stop", "Idle"),
        ("PreToolUse", "Working"),
        ("UserPromptSubmit", "Working"),
        ("PostToolUse", "Auto")
    ]

    private static let claudeRetiredEvents = ["Elicitation"]

    public let codexHooksURL: URL
    public let codexConfigURL: URL
    public let claudeSettingsURL: URL
    public let installDirectory: URL
    public let bundledCodexScriptURL: URL
    public let bundledClaudeScriptURL: URL
    private let clock: @Sendable () -> Date

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installDirectory: URL? = nil,
        bundledCodexScriptURL: URL,
        bundledClaudeScriptURL: URL,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        codexHooksURL = homeDirectory.appendingPathComponent(".codex/hooks.json", isDirectory: false)
        codexConfigURL = homeDirectory.appendingPathComponent(".codex/config.toml", isDirectory: false)
        claudeSettingsURL = homeDirectory.appendingPathComponent(".claude/settings.json", isDirectory: false)
        self.installDirectory = installDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
        self.bundledCodexScriptURL = bundledCodexScriptURL
        self.bundledClaudeScriptURL = bundledClaudeScriptURL
        self.clock = clock
    }

    public func installedScriptURL(for agent: AgentKind) -> URL {
        let name = agent == .codex ? Self.codexScriptName : Self.claudeScriptName
        return installDirectory.appendingPathComponent(name, isDirectory: false)
    }

    // MARK: - Install

    public func install(for agent: AgentKind) throws {
        switch agent {
        case .codex:
            try installCodexHooks()
        case .claudeCode:
            try installClaudeHooks()
        }
    }

    private func installCodexHooks() throws {
        let scriptURL = try installScript(from: bundledCodexScriptURL, named: Self.codexScriptName)
        let command = "'\(scriptURL.path)' # \(Self.codexHookMarker)"

        try backupIfExists(codexHooksURL)
        let hooksRoot = try loadJSONObject(at: codexHooksURL)
        try writeJSONObject(Self.updatedCodexHooks(hooksRoot, command: command), to: codexHooksURL)

        try backupIfExists(codexConfigURL)
        let configText = try readTextIfExists(at: codexConfigURL)
        try writeText(Self.updatedCodexConfig(configText), to: codexConfigURL)
    }

    private func installClaudeHooks() throws {
        let scriptURL = try installScript(from: bundledClaudeScriptURL, named: Self.claudeScriptName)

        try backupIfExists(claudeSettingsURL)
        let settingsRoot = try loadJSONObject(at: claudeSettingsURL)
        try writeJSONObject(Self.updatedClaudeSettings(settingsRoot, scriptPath: scriptURL.path), to: claudeSettingsURL)
    }

    // MARK: - Uninstall

    public func uninstall(for agent: AgentKind) throws {
        switch agent {
        case .codex:
            try removeManagedHooks(at: codexHooksURL, marker: Self.codexHookMarker)
        case .claudeCode:
            try removeManagedHooks(at: claudeSettingsURL, marker: Self.claudeHookMarker)
        }

        let scriptURL = installedScriptURL(for: agent)
        if FileManager.default.fileExists(atPath: scriptURL.path) {
            try FileManager.default.removeItem(at: scriptURL)
        }
    }

    private func removeManagedHooks(at url: URL, marker: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try backupIfExists(url)
        let root = try loadJSONObject(at: url)
        try writeJSONObject(Self.removingAllManagedHooks(root, marker: marker), to: url)
    }

    // MARK: - Status

    public func state(for agent: AgentKind) -> AgentHookState {
        do {
            switch agent {
            case .codex:
                return try codexState()
            case .claudeCode:
                return try claudeState()
            }
        } catch {
            return .broken(error.localizedDescription)
        }
    }

    private func codexState() throws -> AgentHookState {
        let scriptURL = installedScriptURL(for: .codex)
        let command = "'\(scriptURL.path)' # \(Self.codexHookMarker)"

        let hooksRoot = try loadJSONObject(at: codexHooksURL)
        let hooksCurrent = jsonObjectsEqual(hooksRoot, Self.updatedCodexHooks(hooksRoot, command: command))

        let configText = try readTextIfExists(at: codexConfigURL)
        let configCurrent = Self.updatedCodexConfig(configText) == configText

        let scriptCurrent = scriptUpToDate(at: scriptURL, source: bundledCodexScriptURL)
        if hooksCurrent && configCurrent && scriptCurrent {
            return .installed
        }

        let hasTraces = containsMarker(hooksRoot, marker: Self.codexHookMarker)
            || FileManager.default.fileExists(atPath: scriptURL.path)
        return hasTraces ? .updateAvailable : .notInstalled
    }

    private func claudeState() throws -> AgentHookState {
        let scriptURL = installedScriptURL(for: .claudeCode)

        let settingsRoot = try loadJSONObject(at: claudeSettingsURL)
        let settingsCurrent = jsonObjectsEqual(
            settingsRoot,
            Self.updatedClaudeSettings(settingsRoot, scriptPath: scriptURL.path)
        )

        let scriptCurrent = scriptUpToDate(at: scriptURL, source: bundledClaudeScriptURL)
        if settingsCurrent && scriptCurrent {
            return .installed
        }

        let hasTraces = containsMarker(settingsRoot, marker: Self.claudeHookMarker)
            || FileManager.default.fileExists(atPath: scriptURL.path)
        return hasTraces ? .updateAvailable : .notInstalled
    }

    // MARK: - Configuration transforms

    static func updatedCodexHooks(_ root: [String: Any], command: String) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, defaults) in codexEventDefaults {
            var entries = hooks[event] as? [Any] ?? []
            if entries.isEmpty {
                entries.append(defaults as [String: Any])
            }
            entries = entries.map { item -> Any in
                guard var entry = item as? [String: Any] else {
                    return item
                }
                if event == "PostToolUse" || event == "PreToolUse",
                   entry["matcher"] as? String == "Bash" {
                    entry.removeValue(forKey: "matcher")
                }
                for (key, value) in defaults where entry[key] == nil {
                    entry[key] = value
                }
                return replacingManagedHooks(in: entry, command: command, marker: codexHookMarker)
            }
            hooks[event] = entries
        }

        root["hooks"] = hooks
        return root
    }

    static func updatedClaudeSettings(_ root: [String: Any], scriptPath: String) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, state) in claudeEventStates {
            let command = "'\(scriptPath)' \(state) # \(claudeHookMarker)"
            var entries = hooks[event] as? [Any] ?? []
            if entries.isEmpty {
                entries.append([String: Any]())
            }
            entries = entries.map { item -> Any in
                guard let entry = item as? [String: Any] else {
                    return item
                }
                return replacingManagedHooks(in: entry, command: command, marker: claudeHookMarker)
            }
            hooks[event] = entries
        }

        for event in claudeRetiredEvents {
            hooks = removingManagedEventHooks(from: hooks, event: event, marker: claudeHookMarker)
        }

        root["hooks"] = hooks
        return root
    }

    static func updatedCodexConfig(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }

        let featureLine = "codex_hooks = true  # \(codexFeatureMarker)"
        let featuresIndex = lines.firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[features]"
        }

        if let featuresIndex {
            var nextSection = lines.count
            for index in (featuresIndex + 1)..<lines.count {
                let stripped = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if stripped.hasPrefix("["), stripped.hasSuffix("]") {
                    nextSection = index
                    break
                }
            }

            var codexHooksIndex: Int?
            for index in (featuresIndex + 1)..<nextSection {
                let beforeComment = lines[index]
                    .components(separatedBy: "#")[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if beforeComment.hasPrefix("codex_hooks") {
                    codexHooksIndex = index
                    break
                }
            }

            if let codexHooksIndex {
                lines[codexHooksIndex] = featureLine
            } else {
                lines.insert(featureLine, at: featuresIndex + 1)
            }
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
            }
            lines.append("[features]")
            lines.append(featureLine)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func removingAllManagedHooks(_ root: [String: Any], marker: String) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else {
            return root
        }
        for event in Array(hooks.keys) {
            hooks = removingManagedEventHooks(from: hooks, event: event, marker: marker)
        }
        root["hooks"] = hooks
        return root
    }

    private static func replacingManagedHooks(
        in entry: [String: Any],
        command: String,
        marker: String
    ) -> [String: Any] {
        var entry = entry
        var kept: [Any] = []
        if let hooks = entry["hooks"] as? [Any] {
            for hook in hooks {
                if let dictionary = hook as? [String: Any],
                   let existingCommand = dictionary["command"] as? String,
                   existingCommand.contains(marker) {
                    continue
                }
                kept.append(hook)
            }
        }
        kept.append(["type": "command", "command": command])
        entry["hooks"] = kept
        return entry
    }

    private static func removingManagedEventHooks(
        from hooks: [String: Any],
        event: String,
        marker: String
    ) -> [String: Any] {
        var hooks = hooks
        guard let entries = hooks[event] as? [Any] else {
            return hooks
        }

        var keptEntries: [Any] = []
        for item in entries {
            guard let entry = item as? [String: Any],
                  let eventHooks = entry["hooks"] as? [Any] else {
                keptEntries.append(item)
                continue
            }

            let keptHooks = eventHooks.filter { hook in
                guard let dictionary = hook as? [String: Any],
                      let command = dictionary["command"] as? String else {
                    return true
                }
                return !command.contains(marker)
            }

            if !keptHooks.isEmpty {
                var updated = entry
                updated["hooks"] = keptHooks
                keptEntries.append(updated)
            }
        }

        if keptEntries.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = keptEntries
        }
        return hooks
    }

    // MARK: - File helpers

    private func installScript(from source: URL, named name: String) throws -> URL {
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let destination = installDirectory.appendingPathComponent(name, isDirectory: false)
        try data.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private func scriptUpToDate(at destination: URL, source: URL) -> Bool {
        guard let installed = try? Data(contentsOf: destination),
              let bundled = try? Data(contentsOf: source),
              installed == bundled else {
            return false
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        return permissions & 0o111 != 0
    }

    private func backupIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).bak.\(formatter.string(from: clock()))")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: url, to: backupURL)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AgentHookInstallerError.invalidConfiguration(
                fileName: url.lastPathComponent,
                reason: "top-level value is not an object"
            )
        }
        return dictionary
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: url, options: [.atomic])
    }

    private func readTextIfExists(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func jsonObjectsEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }

    private func containsMarker(_ object: [String: Any], marker: String) -> Bool {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(marker)
    }
}
