import AgentsBarCore
import AppKit
import SwiftUI

@main
struct AgentsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            AgentsMenu(controller: controller)
        } label: {
            AgentsMenuLabel(store: controller.store)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class AppController: ObservableObject {
    @Published var serverMessage = "Listening on 127.0.0.1:7823"

    let store = AgentStateStore()
    private var server: EventServer?
    private var codexWatcher: CodexSessionWatcher?
    private var maintenanceTimer: Timer?

    init() {
        startServer()
        startCodexWatcher()
        startMaintenanceTimer()
    }

    func startServer() {
        guard server == nil else {
            return
        }

        do {
            let eventServer = try EventServer(host: "127.0.0.1", port: 7823) { [weak self] event in
                Task { @MainActor in
                    self?.applyEvent(event)
                }
            }
            try eventServer.start()
            server = eventServer
            serverMessage = "Listening on 127.0.0.1:7823"
        } catch {
            serverMessage = "Server failed: \(error.localizedDescription)"
        }
    }

    func reload() {
        store.reloadFromDisk()
        refreshSessionTitles()
    }

    private func startCodexWatcher() {
        let watcher = CodexSessionWatcher { [weak self] event in
            Task { @MainActor in
                self?.applyEvent(event)
            }
        }
        watcher.start()
        codexWatcher = watcher
        refreshSessionTitles()
    }

    private func applyEvent(_ event: AgentEvent) {
        store.apply(eventWithResolvedTitle(event))
    }

    private func refreshSessionTitles() {
        pruneHiddenSessions()
        store.expireStaleActiveSessions()

        for session in store.sessions {
            let title = resolvedTitle(for: session) ?? fallbackTitle(for: session)

            guard title != session.title else {
                continue
            }

            store.apply(AgentEvent(
                agent: session.agent,
                sessionId: session.sessionId,
                state: session.state,
                title: title,
                cwd: session.cwd,
                event: session.event,
                terminal: session.terminal,
                pid: session.pid,
                updatedAt: session.updatedAt
            ))
        }
    }

    private func eventWithResolvedTitle(_ event: AgentEvent) -> AgentEvent {
        guard event.title.isEmpty else {
            return event
        }

        let title = resolvedTitle(agent: event.agent, sessionId: event.sessionId)
            ?? fallbackTitle(cwd: event.cwd, sessionId: event.sessionId)

        return AgentEvent(
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            title: title,
            cwd: event.cwd,
            event: event.event,
            terminal: event.terminal,
            pid: event.pid,
            updatedAt: event.updatedAt
        )
    }

    private func resolvedTitle(for session: AgentSession) -> String? {
        resolvedTitle(agent: session.agent, sessionId: session.sessionId)
    }

    private func resolvedTitle(agent: AgentKind, sessionId: String) -> String? {
        switch agent {
        case .codex:
            CodexSessionWatcher.title(for: sessionId)
        case .claudeCode:
            ClaudeSessionTitleResolver.title(for: sessionId)
        }
    }

    private func fallbackTitle(for session: AgentSession) -> String {
        fallbackTitle(cwd: session.cwd, sessionId: session.sessionId)
    }

    private func fallbackTitle(cwd: String, sessionId: String) -> String {
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCWD.isEmpty else {
            return sessionId
        }

        let lastPathComponent = URL(fileURLWithPath: trimmedCWD).lastPathComponent
        return lastPathComponent.isEmpty ? sessionId : lastPathComponent
    }

    private func pruneHiddenSessions() {
        store.removeSessions { session in
            session.agent == .codex && CodexSessionWatcher.shouldHideSession(session.sessionId)
        }
    }

    private func startMaintenanceTimer() {
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionTitles()
            }
        }
    }
}

struct AgentsMenuLabel: View {
    @ObservedObject var store: AgentStateStore

    var body: some View {
        Image(nsImage: AgentImages.menuBarStatus(
            codexState: store.aggregateState(for: .codex),
            claudeState: store.aggregateState(for: .claudeCode)
        ))
        .resizable()
        .interpolation(.high)
        .frame(width: AgentImages.menuBarStatusSize.width, height: AgentImages.menuBarStatusSize.height)
    }
}

struct AgentLogoView: View {
    let image: NSImage
    let state: AgentState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)

            Text(state.symbol)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .monospaced()
                .offset(x: 1, y: 1)
                .accessibilityLabel(state.displayName)
        }
        .frame(width: 14, height: 14)
    }
}

struct AgentsMenu: View {
    @ObservedObject var controller: AppController

    var body: some View {
        AgentSection(agent: .codex, store: controller.store)
        Divider()
        AgentSection(agent: .claudeCode, store: controller.store)
        Divider()
        Text(controller.serverMessage)
        Button("Reload State") {
            controller.reload()
        }
        Button("Open State File") {
            NSWorkspace.shared.activateFileViewerSelecting([StatePersistence.defaultStateURL()])
        }
        Divider()
        Button("Quit AgentsBar") {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct AgentSection: View {
    let agent: AgentKind
    @ObservedObject var store: AgentStateStore

    var body: some View {
        let sessions = store.visibleSessions(for: agent)

        Section(agent.displayName) {
            if sessions.isEmpty {
                Text("○ No sessions")
            } else {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(session.state.symbol) \(truncatedTitle)")
                .lineLimit(1)
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(helpText)
    }

    private var truncatedTitle: String {
        Self.truncated(session.displayTitle, limit: 22)
    }

    private var detailText: String {
        var parts: [String] = [session.state.displayName]
        if !session.terminal.isEmpty {
            parts.append(session.terminal)
        }
        if !session.cwd.isEmpty {
            parts.append(URL(fileURLWithPath: session.cwd).lastPathComponent)
        }
        parts.append(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()))
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        [
            session.agent.displayName,
            "session: \(session.sessionId)",
            session.cwd.isEmpty ? nil : session.cwd,
            session.event.isEmpty ? nil : "event: \(session.event)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit)) + "..."
    }
}

enum AgentImages {
    private static let menuBarLogoDisplayScale: CGFloat = 0.7
    private static let menuBarLogoGap: CGFloat = 2
    private static let assetScale: CGFloat = 3
    private static let waitingTintColor = NSColor(srgbRed: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
    private static let codexIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "Codex Mono@3x"),
        color: loadMenuBarIcon(name: "Codex Color@3x")
    )
    private static let claudeIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "claude Mono@3x"),
        color: loadMenuBarIcon(name: "Claude Color@3x")
    )
    private static let codexDisplaySize = displaySize(for: codexIcons.mono)
    private static let claudeDisplaySize = displaySize(for: claudeIcons.mono)
    static let menuBarStatusSize = NSSize(
        width: codexDisplaySize.width + menuBarLogoGap + claudeDisplaySize.width,
        height: max(codexDisplaySize.height, claudeDisplaySize.height)
    )

    static func menuBarStatus(codexState: AgentState, claudeState: AgentState) -> NSImage {
        let image = NSImage(size: menuBarStatusSize, flipped: false) { _ in
            drawAgentLogo(codexIcons, state: codexState, size: codexDisplaySize, x: 0)
            drawAgentLogo(claudeIcons, state: claudeState, size: claudeDisplaySize, x: codexDisplaySize.width + menuBarLogoGap)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func loadMenuBarIcon(name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "icon")
            ?? Bundle.module.url(forResource: "icon/\(name)", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 13, height: 13))
        }

        let pixelWidth = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        if pixelWidth > 0, pixelHeight > 0 {
            image.size = NSSize(width: CGFloat(pixelWidth) / assetScale, height: CGFloat(pixelHeight) / assetScale)
        }
        image.isTemplate = false
        return image
    }

    private static func displaySize(for logo: NSImage) -> NSSize {
        NSSize(
            width: logo.size.width * menuBarLogoDisplayScale,
            height: logo.size.height * menuBarLogoDisplayScale
        )
    }

    private static func drawAgentLogo(_ icons: AgentIconSet, state: AgentState, size: NSSize, x: CGFloat) {
        let logoRect = NSRect(
            x: x,
            y: (menuBarStatusSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )

        switch state {
        case .working:
            icons.color.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        case .waiting:
            drawTemplateLogo(icons.mono, in: logoRect, color: waitingTintColor)
        case .idle, .ended:
            drawTemplateLogo(icons.mono, in: logoRect, color: .labelColor)
        }
    }

    private static func drawTemplateLogo(_ logo: NSImage, in rect: NSRect, color: NSColor) {
        var proposedRect = NSRect(origin: .zero, size: logo.size)
        guard let cgImage = logo.cgImage(forProposedRect: &proposedRect, context: NSGraphicsContext.current, hints: nil),
              let context = NSGraphicsContext.current?.cgContext else {
            logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }

        context.saveGState()
        context.clip(to: rect, mask: cgImage)
        color.setFill()
        rect.fill()
        context.restoreGState()
    }

    private struct AgentIconSet {
        let mono: NSImage
        let color: NSImage
    }
}
