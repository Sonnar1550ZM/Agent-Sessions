import XCTest
@testable import AgentSessionsCore

final class AgentHookInstallerTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var installDirectory: URL!
    private var codexScriptSource: URL!
    private var claudeScriptSource: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AgentHookInstallerTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        installDirectory = root.appendingPathComponent("Application Support/Agent Sessions/hooks", isDirectory: true)
        codexScriptSource = root.appendingPathComponent("bundled/codex-hook.sh", isDirectory: false)
        claudeScriptSource = root.appendingPathComponent("bundled/claude-hook.sh", isDirectory: false)

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: codexScriptSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash\necho codex\n".write(to: codexScriptSource, atomically: true, encoding: .utf8)
        try "#!/bin/bash\necho claude\n".write(to: claudeScriptSource, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeInstaller(clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }) -> AgentHookInstaller {
        AgentHookInstaller(
            homeDirectory: home,
            installDirectory: installDirectory,
            bundledCodexScriptURL: codexScriptSource,
            bundledClaudeScriptURL: claudeScriptSource,
            clock: clock
        )
    }

    private func loadJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func entries(_ root: [String: Any], _ event: String) throws -> [[String: Any]] {
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        return try XCTUnwrap(hooks[event] as? [[String: Any]])
    }

    private func commands(in entry: [String: Any]) throws -> [String] {
        let hooks = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
        return hooks.compactMap { $0["command"] as? String }
    }

    // MARK: - Codex install

    func testInstallCodexCreatesConfigurationFromScratch() throws {
        let installer = makeInstaller()
        try installer.install(for: .codex)

        let scriptURL = installer.installedScriptURL(for: .codex)
        XCTAssertEqual(
            try String(contentsOf: scriptURL, encoding: .utf8),
            "#!/bin/bash\necho codex\n"
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.uint16Value & 0o755, 0o755)

        let hooksRoot = try loadJSON(installer.codexHooksURL)
        let hooks = try XCTUnwrap(hooksRoot["hooks"] as? [String: Any])
        XCTAssertEqual(
            Set(hooks.keys),
            [
                "PostToolUse", "PostCompact", "PreToolUse", "PreCompact",
                "PermissionRequest", "SessionStart", "Stop", "UserPromptSubmit"
            ]
        )

        let expectedCommand = "'\(scriptURL.path)' # agent-sessions-codex-hook"
        for event in hooks.keys {
            let eventEntries = try entries(hooksRoot, event)
            XCTAssertEqual(eventEntries.count, 1, "unexpected entry count for \(event)")
            XCTAssertEqual(try commands(in: eventEntries[0]), [expectedCommand])
        }

        let sessionStart = try entries(hooksRoot, "SessionStart")[0]
        XCTAssertEqual(sessionStart["matcher"] as? String, "startup|resume")

        XCTAssertEqual(
            try String(contentsOf: installer.codexConfigURL, encoding: .utf8),
            "[features]\ncodex_hooks = true  # agent-sessions-managed-codex-hooks\n"
        )
    }

    func testInstallCodexPreservesUserHooksAndReplacesManagedOnes() throws {
        let installer = makeInstaller()
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/user-hook.sh"],
                            ["type": "command", "command": "'/old/path/agent-sessions-codex-hook.sh' # agent-sessions-codex-hook"]
                        ]
                    ]
                ],
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": []]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try FileManager.default.createDirectory(
            at: installer.codexHooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: installer.codexHooksURL)

        try installer.install(for: .codex)

        let hooksRoot = try loadJSON(installer.codexHooksURL)
        let expectedCommand = "'\(installer.installedScriptURL(for: .codex).path)' # agent-sessions-codex-hook"

        let stop = try entries(hooksRoot, "Stop")[0]
        XCTAssertEqual(
            try commands(in: stop),
            ["/usr/local/bin/user-hook.sh", expectedCommand]
        )

        let preToolUse = try entries(hooksRoot, "PreToolUse")[0]
        XCTAssertNil(preToolUse["matcher"], "Bash matcher should be removed from PreToolUse")
        XCTAssertEqual(try commands(in: preToolUse), [expectedCommand])
    }

    func testInstallCodexUpdatesExistingFeaturesSection() throws {
        let installer = makeInstaller()
        try FileManager.default.createDirectory(
            at: installer.codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        model = "gpt-5"

        [features]
        memories = true
        codex_hooks = false

        [projects."/tmp/example"]
        trust_level = "trusted"
        """.write(to: installer.codexConfigURL, atomically: true, encoding: .utf8)

        try installer.install(for: .codex)

        XCTAssertEqual(
            try String(contentsOf: installer.codexConfigURL, encoding: .utf8),
            """
            model = "gpt-5"

            [features]
            memories = true
            codex_hooks = true  # agent-sessions-managed-codex-hooks

            [projects."/tmp/example"]
            trust_level = "trusted"

            """
        )
    }

    func testInstallCodexAppendsFeaturesSectionWhenMissing() throws {
        let installer = makeInstaller()
        try FileManager.default.createDirectory(
            at: installer.codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "model = \"gpt-5\"\n".write(to: installer.codexConfigURL, atomically: true, encoding: .utf8)

        try installer.install(for: .codex)

        XCTAssertEqual(
            try String(contentsOf: installer.codexConfigURL, encoding: .utf8),
            "model = \"gpt-5\"\n\n[features]\ncodex_hooks = true  # agent-sessions-managed-codex-hooks\n"
        )
    }

    // MARK: - Claude install

    func testInstallClaudeRegistersAllEventStates() throws {
        let installer = makeInstaller()
        try installer.install(for: .claudeCode)

        let settings = try loadJSON(installer.claudeSettingsURL)
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(hooks.count, 11)

        let scriptPath = installer.installedScriptURL(for: .claudeCode).path
        let expectations: [String: String] = [
            "SessionEnd": "Ended",
            "Notification": "Waiting",
            "PermissionRequest": "Waiting",
            "PreCompact": "Working",
            "PostCompact": "Idle",
            "PostToolUseFailure": "ToolFail",
            "SessionStart": "Idle",
            "Stop": "Idle",
            "PreToolUse": "Working",
            "UserPromptSubmit": "Working",
            "PostToolUse": "Auto"
        ]
        for (event, state) in expectations {
            let eventEntries = try entries(settings, event)
            XCTAssertEqual(eventEntries.count, 1, "unexpected entry count for \(event)")
            XCTAssertEqual(
                try commands(in: eventEntries[0]),
                ["'\(scriptPath)' \(state) # agent-sessions-claude-hook"],
                "unexpected command for \(event)"
            )
        }
    }

    func testInstallClaudeRemovesRetiredElicitationHooks() throws {
        let installer = makeInstaller()
        let existing: [String: Any] = [
            "hooks": [
                "Elicitation": [
                    [
                        "hooks": [
                            ["type": "command", "command": "'/old/agent-sessions-claude-hook.sh' Waiting # agent-sessions-claude-hook"]
                        ]
                    ]
                ]
            ],
            "permissions": ["allow": ["Bash(ls:*)"]]
        ]
        try FileManager.default.createDirectory(
            at: installer.claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.claudeSettingsURL)

        try installer.install(for: .claudeCode)

        let settings = try loadJSON(installer.claudeSettingsURL)
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertNil(hooks["Elicitation"], "retired Elicitation event should be removed")

        let permissions = try XCTUnwrap(settings["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash(ls:*)"])
    }

    func testInstallTwiceIsIdempotent() throws {
        let installer = makeInstaller()
        try installer.install(for: .codex)
        try installer.install(for: .claudeCode)

        let codexFirst = try Data(contentsOf: installer.codexHooksURL)
        let configFirst = try Data(contentsOf: installer.codexConfigURL)
        let claudeFirst = try Data(contentsOf: installer.claudeSettingsURL)

        try installer.install(for: .codex)
        try installer.install(for: .claudeCode)

        XCTAssertEqual(try Data(contentsOf: installer.codexHooksURL), codexFirst)
        XCTAssertEqual(try Data(contentsOf: installer.codexConfigURL), configFirst)
        XCTAssertEqual(try Data(contentsOf: installer.claudeSettingsURL), claudeFirst)
    }

    func testInstallBacksUpExistingConfigurationFiles() throws {
        let installer = makeInstaller(clock: { Date(timeIntervalSince1970: 86_400) })
        try FileManager.default.createDirectory(
            at: installer.claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{}".write(to: installer.claudeSettingsURL, atomically: true, encoding: .utf8)

        try installer.install(for: .claudeCode)

        let backups = try FileManager.default
            .contentsOfDirectory(atPath: installer.claudeSettingsURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("settings.json.bak.") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(
            try String(
                contentsOf: installer.claudeSettingsURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(backups[0]),
                encoding: .utf8
            ),
            "{}"
        )
    }

    // MARK: - Status

    func testStateTransitionsAcrossInstallAndTamper() throws {
        let installer = makeInstaller()
        XCTAssertEqual(installer.state(for: .codex), .notInstalled)
        XCTAssertEqual(installer.state(for: .claudeCode), .notInstalled)

        try installer.install(for: .codex)
        try installer.install(for: .claudeCode)
        XCTAssertEqual(installer.state(for: .codex), .installed)
        XCTAssertEqual(installer.state(for: .claudeCode), .installed)

        // Bundled script changed (e.g. app update) -> installed copy is stale.
        try "#!/bin/bash\necho codex v2\n".write(to: codexScriptSource, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.state(for: .codex), .updateAvailable)

        // Claude settings tampered: managed command edited by hand.
        let text = try String(contentsOf: installer.claudeSettingsURL, encoding: .utf8)
            .replacingOccurrences(of: "' Ended #", with: "' Broken #")
        try text.write(to: installer.claudeSettingsURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.state(for: .claudeCode), .updateAvailable)
    }

    func testStateIsBrokenWhenConfigurationUnreadable() throws {
        let installer = makeInstaller()
        try FileManager.default.createDirectory(
            at: installer.codexHooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: installer.codexHooksURL, atomically: true, encoding: .utf8)

        guard case .broken = installer.state(for: .codex) else {
            return XCTFail("expected .broken, got \(installer.state(for: .codex))")
        }
    }

    // MARK: - Uninstall

    func testUninstallRemovesManagedEntriesAndKeepsUserHooks() throws {
        let installer = makeInstaller()
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/user-hook.sh"]
                        ]
                    ]
                ]
            ]
        ]
        try FileManager.default.createDirectory(
            at: installer.claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.claudeSettingsURL)

        try installer.install(for: .claudeCode)
        try installer.uninstall(for: .claudeCode)

        let settings = try loadJSON(installer.claudeSettingsURL)
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Stop"], "only the user's Stop entry should remain")
        XCTAssertEqual(
            try commands(in: entries(settings, "Stop")[0]),
            ["/usr/local/bin/user-hook.sh"]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installer.installedScriptURL(for: .claudeCode).path)
        )
        XCTAssertEqual(installer.state(for: .claudeCode), .notInstalled)
    }
}
