import AgentsBarCore
import AppKit
import Combine
import SwiftUI

@main
struct AgentsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = AppController()
        self.controller = controller
        statusMenuController = StatusMenuController(controller: controller)
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

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(controller: AppController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        configureStatusButton()
        updateStatusIcon()

        controller.store.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "AgentsBar"
        button.setAccessibilityLabel("AgentsBar")
    }

    private func updateStatusIcon() {
        let image = AgentImages.menuBarStatus(
            codexState: controller.store.aggregateState(for: .codex),
            claudeState: controller.store.aggregateState(for: .claudeCode)
        )
        statusItem.button?.image = image
        statusItem.length = AgentImages.menuBarStatusSize.width + 8
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        appendAgentSection(.codex)
        menu.addItem(.separator())
        appendAgentSection(.claudeCode)
        menu.addItem(.separator())

        let statusItem = NSMenuItem(title: controller.serverMessage, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(actionItem(title: "Reload State", action: #selector(reloadState)))
        menu.addItem(actionItem(title: "Open State File", action: #selector(openStateFile)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit AgentsBar", action: #selector(quit), keyEquivalent: "q"))
    }

    private func appendAgentSection(_ agent: AgentKind) {
        menu.addItem(hostedItem(AgentHeaderView(agent: agent)))

        let sessions = controller.store.visibleSessions(for: agent)
        if sessions.isEmpty {
            menu.addItem(hostedItem(EmptyAgentRow()))
        } else {
            for session in sessions {
                menu.addItem(hostedItem(SessionMenuRow(session: session)))
            }
        }
    }

    private func hostedItem<Content: View>(_ view: Content) -> NSMenuItem {
        let item = NSMenuItem()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = hostingView.fittingSize
        item.view = hostingView
        return item
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func reloadState() {
        controller.reload()
        updateStatusIcon()
    }

    @objc private func openStateFile() {
        NSWorkspace.shared.activateFileViewerSelecting([StatePersistence.defaultStateURL()])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct AgentHeaderView: View {
    let agent: AgentKind

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AgentImages.menuHeaderIcon(for: agent))
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(agent.menuHeaderTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 3)
    }
}

private extension AgentKind {
    var menuHeaderTitle: String {
        switch self {
        case .codex:
            "ChatGPT Codex"
        case .claudeCode:
            displayName
        }
    }
}

private struct EmptyAgentRow: View {
    var body: some View {
        Text("○ No sessions")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 320, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
    }
}

private struct SessionMenuRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Text(session.state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 12, alignment: .leading)
                Text(session.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detailText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .help(helpText)
    }

    private var symbolColor: Color {
        switch session.state {
        case .working:
            switch session.agent {
            case .codex:
                return Color(nsColor: AgentColors.codexWorking)
            case .claudeCode:
                return Color(nsColor: AgentColors.claudeWorking)
            }
        case .waiting:
            return Color(nsColor: AgentColors.waiting)
        case .idle, .ended:
            return .secondary
        }
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

}

private enum AgentColors {
    static let codexWorking = NSColor(srgbRed: 0x00 / 255, green: 0x6E / 255, blue: 0xFE / 255, alpha: 1)
    static let claudeWorking = NSColor(srgbRed: 0xCF / 255, green: 0x83 / 255, blue: 0x66 / 255, alpha: 1)
    static let waiting = NSColor(srgbRed: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
}

enum AgentImages {
    private static let menuBarLogoDisplayScale: CGFloat = 0.7
    private static let menuBarLogoGap: CGFloat = 2
    private static let assetScale: CGFloat = 3
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

    static func menuHeaderIcon(for agent: AgentKind) -> NSImage {
        let source = switch agent {
        case .codex:
            codexIcons.mono
        case .claudeCode:
            claudeIcons.mono
        }
        guard let image = source.copy() as? NSImage else {
            return source
        }
        image.isTemplate = true
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
            drawTemplateLogo(icons.mono, in: logoRect, color: AgentColors.waiting)
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
