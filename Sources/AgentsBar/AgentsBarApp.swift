import AgentsBarCore
import AppKit
import Combine
import SwiftUI

@main
struct AgentsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct ProviderVisibility: Codable, Equatable {
    var showsMenuBarIcon: Bool
    var showsDropdownMenu: Bool
    var usesColorDropdownIcon: Bool

    static let visible = ProviderVisibility(
        showsMenuBarIcon: true,
        showsDropdownMenu: true,
        usesColorDropdownIcon: false
    )

    init(
        showsMenuBarIcon: Bool,
        showsDropdownMenu: Bool,
        usesColorDropdownIcon: Bool = false
    ) {
        self.showsMenuBarIcon = showsMenuBarIcon
        self.showsDropdownMenu = showsDropdownMenu
        self.usesColorDropdownIcon = usesColorDropdownIcon
    }

    private enum CodingKeys: String, CodingKey {
        case showsMenuBarIcon
        case showsDropdownMenu
        case usesColorDropdownIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
        showsDropdownMenu = try container.decodeIfPresent(Bool.self, forKey: .showsDropdownMenu) ?? true
        usesColorDropdownIcon = try container.decodeIfPresent(Bool.self, forKey: .usesColorDropdownIcon) ?? false
    }
}

enum ProviderPlacement: String, CaseIterable, Identifiable {
    case menuBar
    case dropdownMenu

    var id: Self { self }

    var title: String {
        switch self {
        case .menuBar:
            "Menu Bar"
        case .dropdownMenu:
            "Drop-down Menu"
        }
    }

    var helperText: String {
        switch self {
        case .menuBar:
            "Drag providers to reorder menu bar icons."
        case .dropdownMenu:
            "Drag providers to reorder drop-down sections."
        }
    }

    var symbolName: String {
        switch self {
        case .menuBar:
            "menubar.rectangle"
        case .dropdownMenu:
            "list.bullet.rectangle"
        }
    }
}

private enum ProviderPreferenceDefaults {
    static let sessionDisplayCount = 5
    static let latestResponseLineLimit = 2
    static let subagentLatestResponseLineLimit = 2
    static let showsSubagents = true
    static let subagentHideAfterInterval: TimeInterval = 3 * 60
    static let subagentHideAfterOptions: [TimeInterval] = [
        60,
        3 * 60,
        5 * 60,
        10 * 60,
        30 * 60,
        60 * 60,
        3 * 60 * 60
    ]
    static let hideAfterInterval: TimeInterval = 24 * 60 * 60
    static let hideAfterOptions: [TimeInterval] = [
        15 * 60,
        60 * 60,
        6 * 60 * 60,
        12 * 60 * 60,
        24 * 60 * 60,
        7 * 24 * 60 * 60
    ]

    static func sanitizedSessionDisplayCount(_ count: Int?) -> Int {
        min(max(count ?? sessionDisplayCount, 3), 10)
    }

    static func sanitizedLatestResponseLineLimit(_ count: Int?) -> Int {
        min(max(count ?? latestResponseLineLimit, 1), 5)
    }

    static func sanitizedSubagentLatestResponseLineLimit(_ count: Int?) -> Int {
        min(max(count ?? subagentLatestResponseLineLimit, 1), 5)
    }

    static func sanitizedHideAfterInterval(_ interval: TimeInterval?) -> TimeInterval {
        guard let interval,
              let nearest = hideAfterOptions.min(by: { abs($0 - interval) < abs($1 - interval) }) else {
            return hideAfterInterval
        }
        return nearest
    }

    static func sanitizedSubagentHideAfterInterval(_ interval: TimeInterval?) -> TimeInterval {
        guard let interval,
              let nearest = subagentHideAfterOptions.min(by: { abs($0 - interval) < abs($1 - interval) }) else {
            return subagentHideAfterInterval
        }
        return nearest
    }

    static func subagentHideAfterLabel(for interval: TimeInterval) -> String {
        switch sanitizedSubagentHideAfterInterval(interval) {
        case 60:
            "1 minute"
        case 3 * 60:
            "3 minutes"
        case 5 * 60:
            "5 minutes"
        case 10 * 60:
            "10 minutes"
        case 30 * 60:
            "30 minutes"
        case 60 * 60:
            "1 hour"
        case 3 * 60 * 60:
            "3 hours"
        default:
            "3 minutes"
        }
    }

    static func hideAfterLabel(for interval: TimeInterval) -> String {
        switch sanitizedHideAfterInterval(interval) {
        case 15 * 60:
            "15 minutes"
        case 60 * 60:
            "1 hour"
        case 6 * 60 * 60:
            "6 hours"
        case 12 * 60 * 60:
            "12 hours"
        case 24 * 60 * 60:
            "24 hours"
        case 7 * 24 * 60 * 60:
            "7 days"
        default:
            "24 hours"
        }
    }
}

private struct ProviderPreferencesDocument: Codable, Equatable {
    var values: [String: ProviderVisibility]
    var menuBarOrder: [String]
    var dropdownMenuOrder: [String]
    var usesColorDropdownIcons: Bool
    var sessionDisplayCount: Int
    var latestResponseLineLimit: Int
    var subagentLatestResponseLineLimit: Int
    var showsSubagents: Bool
    var subagentHideAfterInterval: TimeInterval
    var hideAfterInterval: TimeInterval

    init(
        values: [String: ProviderVisibility],
        menuBarOrder: [String],
        dropdownMenuOrder: [String],
        usesColorDropdownIcons: Bool = false,
        sessionDisplayCount: Int = ProviderPreferenceDefaults.sessionDisplayCount,
        latestResponseLineLimit: Int = ProviderPreferenceDefaults.latestResponseLineLimit,
        subagentLatestResponseLineLimit: Int = ProviderPreferenceDefaults.subagentLatestResponseLineLimit,
        showsSubagents: Bool = ProviderPreferenceDefaults.showsSubagents,
        subagentHideAfterInterval: TimeInterval = ProviderPreferenceDefaults.subagentHideAfterInterval,
        hideAfterInterval: TimeInterval = ProviderPreferenceDefaults.hideAfterInterval
    ) {
        self.values = values
        self.menuBarOrder = menuBarOrder
        self.dropdownMenuOrder = dropdownMenuOrder
        self.usesColorDropdownIcons = usesColorDropdownIcons
        self.sessionDisplayCount = sessionDisplayCount
        self.latestResponseLineLimit = latestResponseLineLimit
        self.subagentLatestResponseLineLimit = subagentLatestResponseLineLimit
        self.showsSubagents = showsSubagents
        self.subagentHideAfterInterval = subagentHideAfterInterval
        self.hideAfterInterval = hideAfterInterval
    }

    private enum CodingKeys: String, CodingKey {
        case values
        case menuBarOrder
        case dropdownMenuOrder
        case usesColorDropdownIcons
        case sessionDisplayCount
        case latestResponseLineLimit
        case subagentLatestResponseLineLimit
        case subagentDisplayCount
        case showsSubagents
        case subagentHideAfterInterval
        case hideAfterInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decodeIfPresent([String: ProviderVisibility].self, forKey: .values) ?? [:]
        menuBarOrder = try container.decodeIfPresent([String].self, forKey: .menuBarOrder) ?? []
        dropdownMenuOrder = try container.decodeIfPresent([String].self, forKey: .dropdownMenuOrder) ?? []
        usesColorDropdownIcons = try container.decodeIfPresent(Bool.self, forKey: .usesColorDropdownIcons)
            ?? values.values.contains { $0.usesColorDropdownIcon }
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(
            try container.decodeIfPresent(Int.self, forKey: .sessionDisplayCount)
        )
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(
            try container.decodeIfPresent(Int.self, forKey: .latestResponseLineLimit)
        )
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
            try container.decodeIfPresent(Int.self, forKey: .subagentLatestResponseLineLimit)
        )
        if let showsSubagents = try container.decodeIfPresent(Bool.self, forKey: .showsSubagents) {
            self.showsSubagents = showsSubagents
        } else if let legacyCount = try container.decodeIfPresent(Int.self, forKey: .subagentDisplayCount) {
            showsSubagents = legacyCount > 0
        } else {
            showsSubagents = ProviderPreferenceDefaults.showsSubagents
        }
        subagentHideAfterInterval = ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .subagentHideAfterInterval)
        )
        hideAfterInterval = ProviderPreferenceDefaults.sanitizedHideAfterInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .hideAfterInterval)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
        try container.encode(menuBarOrder, forKey: .menuBarOrder)
        try container.encode(dropdownMenuOrder, forKey: .dropdownMenuOrder)
        try container.encode(usesColorDropdownIcons, forKey: .usesColorDropdownIcons)
        try container.encode(sessionDisplayCount, forKey: .sessionDisplayCount)
        try container.encode(latestResponseLineLimit, forKey: .latestResponseLineLimit)
        try container.encode(subagentLatestResponseLineLimit, forKey: .subagentLatestResponseLineLimit)
        try container.encode(showsSubagents, forKey: .showsSubagents)
        try container.encode(subagentHideAfterInterval, forKey: .subagentHideAfterInterval)
        try container.encode(hideAfterInterval, forKey: .hideAfterInterval)
    }
}

@MainActor
final class ProviderVisibilityStore: ObservableObject {
    static let shared = ProviderVisibilityStore()

    @Published private(set) var values: [String: ProviderVisibility]
    @Published private(set) var menuBarOrder: [String]
    @Published private(set) var dropdownMenuOrder: [String]
    @Published private(set) var usesColorDropdownIcons: Bool
    @Published private(set) var sessionDisplayCount: Int
    @Published private(set) var latestResponseLineLimit: Int
    @Published private(set) var subagentLatestResponseLineLimit: Int
    @Published private(set) var showsSubagents: Bool
    @Published private(set) var subagentHideAfterInterval: TimeInterval
    @Published private(set) var hideAfterInterval: TimeInterval

    private let defaults: UserDefaults
    private let storageKey = "ProviderPreferences"
    private let legacyVisibilityStorageKey = "ProviderVisibility"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let document = Self.loadDocument(
            defaults: defaults,
            key: storageKey,
            legacyVisibilityKey: legacyVisibilityStorageKey
        )
        values = document.values
        menuBarOrder = Self.sanitizedOrder(document.menuBarOrder)
        dropdownMenuOrder = Self.sanitizedOrder(document.dropdownMenuOrder)
        usesColorDropdownIcons = document.usesColorDropdownIcons
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(document.sessionDisplayCount)
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(document.latestResponseLineLimit)
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
            document.subagentLatestResponseLineLimit
        )
        showsSubagents = document.showsSubagents
        subagentHideAfterInterval = ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval)
        hideAfterInterval = ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval)
        save()
    }

    func visibility(for agent: AgentKind) -> ProviderVisibility {
        values[agent.rawValue] ?? .visible
    }

    func orderedAgents(for placement: ProviderPlacement) -> [AgentKind] {
        Self.agents(from: orderIDs(for: placement))
    }

    func isMenuBarIconVisible(for agent: AgentKind) -> Bool {
        visibility(for: agent).showsMenuBarIcon
    }

    func isDropdownMenuVisible(for agent: AgentKind) -> Bool {
        visibility(for: agent).showsDropdownMenu
    }

    func toggleMenuBarIcon(for agent: AgentKind) {
        setVisible(!isMenuBarIconVisible(for: agent), for: agent, in: .menuBar)
    }

    func toggleDropdownMenu(for agent: AgentKind) {
        setVisible(!isDropdownMenuVisible(for: agent), for: agent, in: .dropdownMenu)
    }

    func setUsesColorDropdownIcons(_ usesColor: Bool) {
        usesColorDropdownIcons = usesColor
        save()
    }

    func setSessionDisplayCount(_ count: Int) {
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(count)
        save()
    }

    func setLatestResponseLineLimit(_ count: Int) {
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(count)
        save()
    }

    func setSubagentLatestResponseLineLimit(_ count: Int) {
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(count)
        save()
    }

    func setShowsSubagents(_ shows: Bool) {
        showsSubagents = shows
        save()
    }

    func setSubagentHideAfterInterval(_ interval: TimeInterval) {
        subagentHideAfterInterval = ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(interval)
        save()
    }

    func setHideAfterInterval(_ interval: TimeInterval) {
        hideAfterInterval = ProviderPreferenceDefaults.sanitizedHideAfterInterval(interval)
        save()
    }

    func isVisible(_ agent: AgentKind, in placement: ProviderPlacement) -> Bool {
        switch placement {
        case .menuBar:
            isMenuBarIconVisible(for: agent)
        case .dropdownMenu:
            isDropdownMenuVisible(for: agent)
        }
    }

    func setVisible(_ isVisible: Bool, for agent: AgentKind, in placement: ProviderPlacement) {
        update(agent) { visibility in
            switch placement {
            case .menuBar:
                visibility.showsMenuBarIcon = isVisible
            case .dropdownMenu:
                visibility.showsDropdownMenu = isVisible
            }
        }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int, in placement: ProviderPlacement) {
        var order = orderIDs(for: placement)
        order.move(fromOffsets: offsets, toOffset: destination)
        setOrder(order, for: placement)
    }

    private func update(_ agent: AgentKind, _ transform: (inout ProviderVisibility) -> Void) {
        var nextValues = values
        var visibility = nextValues[agent.rawValue] ?? .visible
        transform(&visibility)
        nextValues[agent.rawValue] = visibility
        values = nextValues
        save()
    }

    private func orderIDs(for placement: ProviderPlacement) -> [String] {
        switch placement {
        case .menuBar:
            menuBarOrder
        case .dropdownMenu:
            dropdownMenuOrder
        }
    }

    private func setOrder(_ order: [String], for placement: ProviderPlacement) {
        let sanitized = Self.sanitizedOrder(order)
        switch placement {
        case .menuBar:
            menuBarOrder = sanitized
        case .dropdownMenu:
            dropdownMenuOrder = sanitized
        }
        save()
    }

    private func save() {
        let document = ProviderPreferencesDocument(
            values: values,
            menuBarOrder: menuBarOrder,
            dropdownMenuOrder: dropdownMenuOrder,
            usesColorDropdownIcons: usesColorDropdownIcons,
            sessionDisplayCount: sessionDisplayCount,
            latestResponseLineLimit: latestResponseLineLimit,
            subagentLatestResponseLineLimit: subagentLatestResponseLineLimit,
            showsSubagents: showsSubagents,
            subagentHideAfterInterval: subagentHideAfterInterval,
            hideAfterInterval: hideAfterInterval
        )

        guard let data = try? JSONEncoder().encode(document) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private static func loadDocument(
        defaults: UserDefaults,
        key: String,
        legacyVisibilityKey: String
    ) -> ProviderPreferencesDocument {
        guard let data = defaults.data(forKey: key),
              let document = try? JSONDecoder().decode(ProviderPreferencesDocument.self, from: data) else {
            let values = loadLegacyValues(defaults: defaults, key: legacyVisibilityKey)
            return ProviderPreferencesDocument(
                values: values,
                menuBarOrder: defaultOrder,
                dropdownMenuOrder: defaultOrder,
                usesColorDropdownIcons: values.values.contains { $0.usesColorDropdownIcon },
                sessionDisplayCount: ProviderPreferenceDefaults.sessionDisplayCount,
                latestResponseLineLimit: ProviderPreferenceDefaults.latestResponseLineLimit,
                subagentLatestResponseLineLimit: ProviderPreferenceDefaults.subagentLatestResponseLineLimit,
                showsSubagents: ProviderPreferenceDefaults.showsSubagents,
                subagentHideAfterInterval: ProviderPreferenceDefaults.subagentHideAfterInterval,
                hideAfterInterval: ProviderPreferenceDefaults.hideAfterInterval
            )
        }

        return ProviderPreferencesDocument(
            values: document.values,
            menuBarOrder: sanitizedOrder(document.menuBarOrder),
            dropdownMenuOrder: sanitizedOrder(document.dropdownMenuOrder),
            usesColorDropdownIcons: document.usesColorDropdownIcons,
            sessionDisplayCount: ProviderPreferenceDefaults.sanitizedSessionDisplayCount(document.sessionDisplayCount),
            latestResponseLineLimit: ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(document.latestResponseLineLimit),
            subagentLatestResponseLineLimit: ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
                document.subagentLatestResponseLineLimit
            ),
            showsSubagents: document.showsSubagents,
            subagentHideAfterInterval: ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval),
            hideAfterInterval: ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval)
        )
    }

    private static func loadLegacyValues(defaults: UserDefaults, key: String) -> [String: ProviderVisibility] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: ProviderVisibility].self, from: data) else {
            return [:]
        }
        return values
    }

    private static var defaultOrder: [String] {
        AgentKind.allCases.map(\.rawValue)
    }

    private static func sanitizedOrder(_ rawOrder: [String]) -> [String] {
        let knownIDs = Set(defaultOrder)
        var seenIDs: Set<String> = []
        var order: [String] = []

        for id in rawOrder where knownIDs.contains(id) && !seenIDs.contains(id) {
            order.append(id)
            seenIDs.insert(id)
        }

        for id in defaultOrder where !seenIDs.contains(id) {
            order.append(id)
        }

        return order
    }

    private static func agents(from order: [String]) -> [AgentKind] {
        sanitizedOrder(order).compactMap { id in
            AgentKind.allCases.first { $0.rawValue == id }
        }
    }

}

private struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general
    @ObservedObject private var providerVisibility = ProviderVisibilityStore.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedSection: $selectedSection)

            Divider()

            SettingsDetailView(section: selectedSection, providerVisibility: providerVisibility)
        }
        .frame(width: 720, height: 460)
        .background(.regularMaterial)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case providers

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .providers:
            "Providers"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape.fill"
        case .providers:
            "puzzlepiece.extension.fill"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer()
        }
        .padding(.top, 62)
        .padding(.horizontal, 14)
        .frame(width: 210, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.gray.gradient)
                    )

                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.28))
        }
    }
}

private struct SettingsDetailView: View {
    let section: SettingsSection
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        switch section {
        case .general:
            GeneralSettingsView(providerVisibility: providerVisibility)
        case .providers:
            ProvidersSettingsView(providerVisibility: providerVisibility)
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: SettingsSection.general.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.gray.gradient)
                    )

                Text("General")
                    .font(.system(size: 24, weight: .bold))
            }

            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Color Icons",
                    subtitle: "Use color provider icons in the drop-down menu.",
                    isOn: Binding(
                        get: {
                            providerVisibility.usesColorDropdownIcons
                        },
                        set: { usesColor in
                            providerVisibility.setUsesColorDropdownIcons(usesColor)
                        }
                    )
                )

                Divider()
                    .padding(.leading, 18)

                SettingsStepperRow(
                    title: "Session Count",
                    subtitle: "Maximum parent sessions shown per provider.",
                    value: providerVisibility.sessionDisplayCount,
                    range: 3...10
                ) { count in
                    providerVisibility.setSessionDisplayCount(count)
                }

                Divider()
                    .padding(.leading, 18)

                SettingsStepperRow(
                    title: "Latest Response Lines",
                    subtitle: "Maximum lines shown below each session title.",
                    value: providerVisibility.latestResponseLineLimit,
                    range: 1...5
                ) { count in
                    providerVisibility.setLatestResponseLineLimit(count)
                }

                Divider()
                    .padding(.leading, 18)

                SettingsStepperRow(
                    title: "Sub-agent Response Lines",
                    subtitle: "Maximum response lines shown for sub-agent rows.",
                    value: providerVisibility.subagentLatestResponseLineLimit,
                    range: 1...5
                ) { count in
                    providerVisibility.setSubagentLatestResponseLineLimit(count)
                }

                Divider()
                    .padding(.leading, 18)

                SettingsToggleRow(
                    title: "Sub-agents",
                    subtitle: "Show active sub-agent sessions in the drop-down menu.",
                    isOn: Binding(
                        get: {
                            providerVisibility.showsSubagents
                        },
                        set: { showsSubagents in
                            providerVisibility.setShowsSubagents(showsSubagents)
                        }
                    )
                )

                Divider()
                    .padding(.leading, 18)

                SettingsPickerRow(
                    title: "Sub-agent Hide After",
                    subtitle: "Hide inactive sub-agents by timestamp.",
                    selection: Binding(
                        get: {
                            providerVisibility.subagentHideAfterInterval
                        },
                        set: { interval in
                            providerVisibility.setSubagentHideAfterInterval(interval)
                        }
                    ),
                    options: ProviderPreferenceDefaults.subagentHideAfterOptions,
                    labelProvider: ProviderPreferenceDefaults.subagentHideAfterLabel
                )
                .disabled(!providerVisibility.showsSubagents)
                .opacity(providerVisibility.showsSubagents ? 1 : 0.55)

                Divider()
                    .padding(.leading, 18)

                SettingsPickerRow(
                    title: "Hide After",
                    subtitle: "Hide inactive history.",
                    selection: Binding(
                        get: {
                            providerVisibility.hideAfterInterval
                        },
                        set: { interval in
                            providerVisibility.setHideAfterInterval(interval)
                        }
                    ),
                    options: ProviderPreferenceDefaults.hideAfterOptions,
                    labelProvider: ProviderPreferenceDefaults.hideAfterLabel
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }
}

private struct ProvidersSettingsView: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: SettingsSection.providers.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.blue.gradient)
                    )

                Text("Providers")
                    .font(.system(size: 24, weight: .bold))
            }

            VStack(spacing: 14) {
                ProviderPlacementCard(placement: .menuBar, providerVisibility: providerVisibility)
                ProviderPlacementCard(placement: .dropdownMenu, providerVisibility: providerVisibility)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }
}

private struct ProviderPlacementCard: View {
    let placement: ProviderPlacement
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: placement.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(placement.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(placement.helperText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            List {
                ForEach(providerVisibility.orderedAgents(for: placement), id: \.rawValue) { agent in
                    ProviderPlacementRow(
                        agent: agent,
                        placement: placement,
                        providerVisibility: providerVisibility
                    )
                    .listRowInsets(EdgeInsets())
                }
                .onMove { offsets, destination in
                    providerVisibility.move(fromOffsets: offsets, toOffset: destination, in: placement)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(providerVisibility.orderedAgents(for: placement).count) * 52)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ProviderPlacementRow: View {
    let agent: AgentKind
    let placement: ProviderPlacement
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AgentImages.menuHeaderIcon(
                for: agent,
                color: false
            ))
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(agent.providerSettingsTitle)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(providerVisibility.isVisible(agent, in: placement) ? "ON" : "OFF", isOn: Binding(
                get: {
                    providerVisibility.isVisible(agent, in: placement)
                },
                set: { isVisible in
                    providerVisibility.setVisible(isVisible, for: agent, in: placement)
                }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12))
            .frame(width: 90, alignment: .trailing)
            .help(providerVisibility.isVisible(agent, in: placement) ? "Hide" : "Show")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .help("Drag to reorder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(height: 52)
    }
}

private struct SettingsStepperRow: View {
    let title: String
    let subtitle: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Stepper(value: Binding(
                get: {
                    value
                },
                set: { nextValue in
                    onChange(nextValue)
                }
            ), in: range) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct SettingsPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: TimeInterval
    let options: [TimeInterval]
    let labelProvider: (TimeInterval) -> String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { interval in
                    Text(labelProvider(interval))
                        .tag(interval)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 380)
        window.setContentSize(NSSize(width: 720, height: 460))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func open() {
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    private let providerVisibility = ProviderVisibilityStore.shared
    private var server: EventServer?
    private var codexWatcher: CodexSessionWatcher?
    private var claudeSubagentWatcher: ClaudeSubagentWatcher?
    private var maintenanceTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        applyDisplayPreferences()
        observeDisplayPreferences()
        startServer()
        startCodexWatcher()
        startClaudeSubagentWatcher()
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
        refreshForDisplay()
    }

    func refreshForDisplay() {
        refreshSessionTitles()
    }

    func applyDisplayPreferences() {
        store.maxHistoryPerAgent = providerVisibility.sessionDisplayCount
        store.showsSubagents = providerVisibility.showsSubagents
        store.subagentHideAfterInterval = providerVisibility.subagentHideAfterInterval
        store.historyVisibilityInterval = providerVisibility.hideAfterInterval
    }

    private func observeDisplayPreferences() {
        providerVisibility.$sessionDisplayCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyDisplayPreferences()
            }
            .store(in: &cancellables)

        providerVisibility.$showsSubagents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyDisplayPreferences()
            }
            .store(in: &cancellables)

        providerVisibility.$subagentHideAfterInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyDisplayPreferences()
            }
            .store(in: &cancellables)

        providerVisibility.$hideAfterInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyDisplayPreferences()
            }
            .store(in: &cancellables)
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

    private func startClaudeSubagentWatcher() {
        let watcher = ClaudeSubagentWatcher { [weak self] event in
            Task { @MainActor in
                self?.applyEvent(event)
            }
        }
        watcher.start()
        claudeSubagentWatcher = watcher
        refreshSessionTitles()
    }

    private func applyEvent(_ event: AgentEvent) {
        let responseEvent = eventWithClaudeLatestResponse(event)
        let enrichedEvent = eventWithClaudeSubagentMetadata(responseEvent)
        let resolvedEvent = eventWithResolvedTitle(enrichedEvent)

        guard !shouldHideSession(resolvedEvent) else {
            pruneHiddenSessions()
            return
        }

        store.apply(resolvedEvent)
    }

    private func eventWithClaudeLatestResponse(_ event: AgentEvent) -> AgentEvent {
        guard event.agent == .claudeCode,
              event.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let transcriptPath = Self.claudeTranscriptPath(
                  sessionId: event.sessionId,
                  transcriptPath: event.transcriptPath
              ),
              let text = Self.tailText(from: URL(fileURLWithPath: transcriptPath)),
              let latestResponseText = ClaudeSessionParser.latestAssistantResponseText(fromTranscript: text) else {
            return event
        }

        return AgentEvent(
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            title: event.title,
            cwd: event.cwd,
            event: event.event,
            terminal: event.terminal,
            pid: event.pid,
            updatedAt: event.updatedAt,
            parentSessionId: event.parentSessionId,
            subagentNickname: event.subagentNickname,
            subagentRole: event.subagentRole,
            subagentDepth: event.subagentDepth,
            transcriptPath: transcriptPath,
            latestResponseText: latestResponseText,
            latestResponsePhase: "assistant"
        )
    }

    private static func claudeTranscriptPath(sessionId: String, transcriptPath: String?) -> String? {
        if let path = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        return ClaudeSessionTitleResolver.transcriptPath(for: sessionId)
    }

    private static func latestClaudeResponse(
        for sessionId: String,
        transcriptPath: String?
    ) -> (text: String, transcriptPath: String)? {
        guard let transcriptPath = claudeTranscriptPath(sessionId: sessionId, transcriptPath: transcriptPath),
              let text = tailText(from: URL(fileURLWithPath: transcriptPath)),
              let latestResponseText = ClaudeSessionParser.latestAssistantResponseText(fromTranscript: text) else {
            return nil
        }

        return (latestResponseText, transcriptPath)
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

    private func refreshSessionTitles() {
        pruneHiddenSessions()
        store.expireStaleActiveSessions()

        for session in store.sessions {
            let title = resolvedTitle(for: session) ?? fallbackTitle(for: session)
            let latestClaudeResponse = session.agent == .claudeCode
                ? Self.latestClaudeResponse(for: session.sessionId, transcriptPath: session.transcriptPath)
                : nil
            let latestResponseText = latestClaudeResponse?.text ?? session.latestResponseText
            let latestResponsePhase = latestClaudeResponse == nil ? session.latestResponsePhase : "assistant"
            let transcriptPath = latestClaudeResponse?.transcriptPath ?? session.transcriptPath

            guard title != session.title
                || latestResponseText != session.latestResponseText
                || latestResponsePhase != session.latestResponsePhase
                || transcriptPath != session.transcriptPath else {
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
                updatedAt: session.updatedAt,
                parentSessionId: session.parentSessionId,
                subagentNickname: session.subagentNickname,
                subagentRole: session.subagentRole,
                subagentDepth: session.subagentDepth,
                transcriptPath: transcriptPath,
                latestResponseText: latestResponseText,
                latestResponsePhase: latestResponsePhase
            ))
        }
    }

    private func eventWithClaudeSubagentMetadata(_ event: AgentEvent) -> AgentEvent {
        guard event.agent == .claudeCode,
              let metadata = ClaudeSessionParser.subagentMetadata(transcriptPath: event.transcriptPath) else {
            return event
        }

        return AgentEvent(
            agent: event.agent,
            sessionId: metadata.sessionId,
            state: event.state,
            title: event.title,
            cwd: event.cwd,
            event: event.event,
            terminal: event.terminal,
            pid: event.pid,
            updatedAt: event.updatedAt,
            parentSessionId: event.parentSessionId ?? metadata.parentSessionId,
            subagentNickname: event.subagentNickname ?? metadata.subagentNickname,
            subagentRole: event.subagentRole ?? metadata.subagentRole,
            subagentDepth: event.subagentDepth ?? metadata.subagentDepth,
            transcriptPath: event.transcriptPath,
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
        )
    }

    private func eventWithResolvedTitle(_ event: AgentEvent) -> AgentEvent {
        guard event.title.isEmpty || event.agent == .claudeCode else {
            return event
        }

        let title = resolvedTitle(agent: event.agent, sessionId: event.sessionId)
            ?? fallbackTitle(for: event)

        return AgentEvent(
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            title: title,
            cwd: event.cwd,
            event: event.event,
            terminal: event.terminal,
            pid: event.pid,
            updatedAt: event.updatedAt,
            parentSessionId: event.parentSessionId,
            subagentNickname: event.subagentNickname,
            subagentRole: event.subagentRole,
            subagentDepth: event.subagentDepth,
            transcriptPath: event.transcriptPath,
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
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
        guard session.agent != .codex else {
            return session.title
        }
        guard !session.isSubagent else {
            return session.title
        }

        return fallbackTitle(cwd: session.cwd, sessionId: session.sessionId)
    }

    private func fallbackTitle(for event: AgentEvent) -> String {
        if event.agent == .codex {
            if event.state.isActive || event.event == "SessionStart" {
                return fallbackTitle(cwd: event.cwd, sessionId: event.sessionId)
            }
            return event.title
        }
        guard !event.isSubagent else {
            return event.title
        }

        return fallbackTitle(cwd: event.cwd, sessionId: event.sessionId)
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
            shouldHideSession(session)
        }
    }

    private func shouldHideSession(_ session: AgentSession) -> Bool {
        switch session.agent {
        case .codex:
            shouldHideCodexSession(
                sessionId: session.sessionId,
                state: session.state,
                title: session.title,
                cwd: session.cwd,
                event: session.event,
                allowsUnresolvedLiveSession: false
            )
        case .claudeCode:
            shouldHideClaudeSession(
                sessionId: session.sessionId,
                state: session.state,
                cwd: session.cwd,
                event: session.event,
                title: session.title,
                isSubagent: session.isSubagent,
                allowsUnresolvedLiveSession: false
            )
        }
    }

    private func shouldHideSession(_ event: AgentEvent) -> Bool {
        switch event.agent {
        case .codex:
            shouldHideCodexSession(
                sessionId: event.sessionId,
                state: event.state,
                title: event.title,
                cwd: event.cwd,
                event: event.event,
                allowsUnresolvedLiveSession: true
            )
        case .claudeCode:
            shouldHideClaudeSession(
                sessionId: event.sessionId,
                state: event.state,
                cwd: event.cwd,
                event: event.event,
                title: event.title,
                isSubagent: event.isSubagent,
                allowsUnresolvedLiveSession: true
            )
        }
    }

    private func shouldHideCodexSession(
        sessionId: String,
        state: AgentState,
        title: String,
        cwd: String,
        event: String,
        allowsUnresolvedLiveSession: Bool
    ) -> Bool {
        switch CodexSessionWatcher.fileStatus(for: sessionId) {
        case .active:
            break
        case .archived, .missing:
            return !(allowsUnresolvedLiveSession && shouldKeepUnresolvedCodexSession(
                sessionId: sessionId,
                state: state,
                cwd: cwd,
                event: event
            ))
        }

        if CodexSessionWatcher.shouldHideSession(sessionId) {
            return true
        }

        if AgentSessionVisibility.isCodexMemoryWorkspace(agent: .codex, cwd: cwd) {
            return true
        }

        if shouldKeepUnresolvedCodexSession(sessionId: sessionId, state: state, cwd: cwd, event: event) {
            return false
        }

        if CodexSessionWatcher.title(for: sessionId) != nil {
            return false
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            return true
        }

        let fallback = fallbackTitle(cwd: cwd, sessionId: sessionId)
        return normalizedTitle == fallback
    }

    private func shouldKeepUnresolvedCodexSession(
        sessionId: String,
        state: AgentState,
        cwd: String,
        event: String
    ) -> Bool {
        guard hasUsableSessionIdentity(sessionId: sessionId, cwd: cwd) else {
            return false
        }

        return state.isActive || event == "SessionStart"
    }

    private func shouldHideClaudeSession(
        sessionId: String,
        state: AgentState,
        cwd: String,
        event: String,
        title: String,
        isSubagent: Bool,
        allowsUnresolvedLiveSession: Bool
    ) -> Bool {
        if isClaudeProbeSession(cwd: cwd, title: title) {
            return true
        }

        guard !isSubagent else {
            return false
        }

        switch ClaudeSessionTitleResolver.appSessionStatus(sessionId: sessionId) {
        case .active:
            return false
        case .archived:
            return true
        case .missing:
            return !(allowsUnresolvedLiveSession && shouldKeepUnresolvedClaudeSession(
                sessionId: sessionId,
                state: state,
                cwd: cwd,
                event: event
            ))
        }
    }

    private func shouldKeepUnresolvedClaudeSession(
        sessionId: String,
        state: AgentState,
        cwd: String,
        event: String
    ) -> Bool {
        guard hasUsableSessionIdentity(sessionId: sessionId, cwd: cwd) else {
            return false
        }

        return state.isActive || event == "SessionStart" || event == "Start"
    }

    private func hasUsableSessionIdentity(sessionId: String, cwd: String) -> Bool {
        let trimmedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionId.isEmpty else {
            return false
        }

        if trimmedSessionId != "default" {
            return true
        }

        return !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isClaudeProbeSession(cwd: String, title: String) -> Bool {
        let normalizedCWD = cwd
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        if normalizedCWD.contains("/application support/codexbar/claudeprobe") {
            return true
        }

        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return normalizedTitle == "claudeprobe"
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
    private let providerVisibility = ProviderVisibilityStore.shared
    private let menu = NSMenu()
    private var statusItems: [AgentKind: NSStatusItem] = [:]
    private var fallbackStatusItem: NSStatusItem?
    private var statusIconRefreshTimer: Timer?
    private var statusIconRefreshInterval: TimeInterval?
    private var statusIconAnimationStartDate = Date()
    private var cancellables: Set<AnyCancellable> = []
    private var isMenuOpen = false
    private var needsMenuRebuild = true
    private var hostedViews: [NSView] = []
    private static let statusItemHorizontalPadding: CGFloat = 1
    private static let idleStatusIconRefreshInterval: TimeInterval = 1
    private static let animatedStatusIconRefreshInterval: TimeInterval = 1.0 / 24.0
    private static let statusIconHighlightDuration: TimeInterval = 1.15
    private static let recentStartupWorkingInterval: TimeInterval = 3
    private static let startupIdleEvents: Set<String> = ["SessionStart", "JSONLWatch"]

    init(controller: AppController) {
        self.controller = controller
        super.init()

        menu.delegate = self
        syncStatusItems()

        controller.store.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcons()
                self?.resizeMenuIfOpen()
            }
            .store(in: &cancellables)

        providerVisibility.$values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncStatusItems()
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$menuBarOrder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncStatusItems()
            }
            .store(in: &cancellables)

        providerVisibility.$dropdownMenuOrder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$usesColorDropdownIcons
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$sessionDisplayCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.controller.applyDisplayPreferences()
                self?.updateStatusIcons()
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$latestResponseLineLimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
                self?.resizeMenuIfOpen()
            }
            .store(in: &cancellables)

        providerVisibility.$subagentLatestResponseLineLimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
                self?.resizeMenuIfOpen()
            }
            .store(in: &cancellables)

        providerVisibility.$showsSubagents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.controller.applyDisplayPreferences()
                self?.updateStatusIcons()
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$subagentHideAfterInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.controller.applyDisplayPreferences()
                self?.updateStatusIcons()
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$hideAfterInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.controller.applyDisplayPreferences()
                self?.updateStatusIcons()
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        rebuildMenu()
        startStatusIconRefreshTimer()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        rebuildMenuIfNeeded()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func configureStatusButton(_ statusItem: NSStatusItem, agent: AgentKind?) {
        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let label = agent.map { "AgentsBar - \($0.displayName)" } ?? "AgentsBar"
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func syncStatusItems() {
        let visibleAgents = providerVisibility.orderedAgents(for: .menuBar)
            .filter { providerVisibility.isMenuBarIconVisible(for: $0) }
        let visibleSet = Set(visibleAgents)

        for agent in Array(statusItems.keys) where !visibleSet.contains(agent) {
            if let statusItem = statusItems.removeValue(forKey: agent) {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
        }

        guard !visibleAgents.isEmpty else {
            showFallbackStatusItem()
            updateStatusIcons()
            return
        }

        removeFallbackStatusItem()

        for agent in visibleAgents where statusItems[agent] == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.menu = menu
            statusItems[agent] = statusItem
            configureStatusButton(statusItem, agent: agent)
        }

        updateStatusIcons()
    }

    private func showFallbackStatusItem() {
        guard fallbackStatusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        fallbackStatusItem = statusItem
        configureStatusButton(statusItem, agent: nil)
    }

    private func removeFallbackStatusItem() {
        guard let fallbackStatusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(fallbackStatusItem)
        self.fallbackStatusItem = nil
    }

    private func updateStatusIcons() {
        let hasAnimatedIcon = renderStatusIcons()
        updateStatusIconRefreshTimer(animated: hasAnimatedIcon)
    }

    private func renderStatusIcons() -> Bool {
        let now = Date()
        let highlightPhase = statusIconHighlightPhase(at: now)
        var hasAnimatedIcon = false

        for (agent, statusItem) in statusItems {
            let aggregateState = controller.store.aggregateState(for: agent, now: now)
            let displayState = menuBarDisplayState(for: agent, aggregateState: aggregateState, now: now)
            hasAnimatedIcon = hasAnimatedIcon || displayState == .working
            let status = AgentMenuBarStatus(
                agent: agent,
                state: displayState
            )
            let image = AgentImages.menuBarStatus(
                [status],
                highlightPhase: displayState == .working ? highlightPhase : nil
            )
            statusItem.button?.image = image
            statusItem.length = image.size.width + Self.statusItemHorizontalPadding
        }

        if let fallbackStatusItem {
            let image = AgentImages.menuBarStatus([])
            fallbackStatusItem.button?.image = image
            fallbackStatusItem.length = image.size.width + Self.statusItemHorizontalPadding
        }

        return hasAnimatedIcon
    }

    private func menuBarDisplayState(for agent: AgentKind, aggregateState: AgentState, now: Date) -> AgentState {
        guard aggregateState == .idle else {
            return aggregateState
        }

        let hasRecentStartupSession = controller.store.visibleSessions(for: agent, now: now).contains { session in
            session.state == .idle
                && Self.startupIdleEvents.contains(session.event)
                && now.timeIntervalSince(session.updatedAt) <= Self.recentStartupWorkingInterval
        }

        return hasRecentStartupSession ? .working : aggregateState
    }

    private func startStatusIconRefreshTimer() {
        guard statusIconRefreshTimer == nil else {
            return
        }

        updateStatusIconRefreshTimer(animated: false)
    }

    private func updateStatusIconRefreshTimer(animated: Bool) {
        let interval = animated
            ? Self.animatedStatusIconRefreshInterval
            : Self.idleStatusIconRefreshInterval

        if animated && statusIconRefreshInterval != Self.animatedStatusIconRefreshInterval {
            statusIconAnimationStartDate = Date()
        }

        guard statusIconRefreshInterval != interval else {
            return
        }

        statusIconRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusIcons()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusIconRefreshTimer = timer
        statusIconRefreshInterval = interval
    }

    private func statusIconHighlightPhase(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(statusIconAnimationStartDate)
        let rawPhase = elapsed.truncatingRemainder(dividingBy: Self.statusIconHighlightDuration)
            / Self.statusIconHighlightDuration
        return CGFloat(rawPhase)
    }

    private func setNeedsMenuRebuild() {
        needsMenuRebuild = true

        guard isMenuOpen else {
            return
        }

        rebuildMenu()
    }

    private func rebuildMenuIfNeeded() {
        guard needsMenuRebuild else {
            return
        }

        rebuildMenu()
    }

    private func resizeMenuIfOpen() {
        guard isMenuOpen else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isMenuOpen else {
                return
            }

            for view in self.hostedViews {
                view.frame.size = view.fittingSize
            }
            self.menu.update()
        }
    }

    private func rebuildMenu() {
        needsMenuRebuild = false
        hostedViews.removeAll()
        menu.removeAllItems()
        let visibleAgents = providerVisibility.orderedAgents(for: .dropdownMenu)
            .filter { providerVisibility.isDropdownMenuVisible(for: $0) }

        for (index, agent) in visibleAgents.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            appendAgentSection(agent)
        }

        if !visibleAgents.isEmpty {
            menu.addItem(.separator())
        }

        menu.addItem(actionItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit AgentsBar", action: #selector(quit), keyEquivalent: "q"))
    }

    private func appendAgentSection(_ agent: AgentKind) {
        menu.addItem(hostedItem(AgentSectionView(
            store: controller.store,
            agent: agent,
            usesColorIcon: providerVisibility.usesColorDropdownIcons,
            latestResponseLineLimit: providerVisibility.latestResponseLineLimit,
            subagentLatestResponseLineLimit: providerVisibility.subagentLatestResponseLineLimit,
            onLayoutMayChange: { [weak self] in
                self?.resizeMenuIfOpen()
            }
        )))
    }

    private func hostedItem<Content: View>(_ view: Content) -> NSMenuItem {
        let item = NSMenuItem()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = hostingView.fittingSize
        item.view = hostingView
        hostedViews.append(hostingView)
        return item
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func reloadState() {
        controller.reload()
        updateStatusIcons()
        resizeMenuIfOpen()
    }

    @objc private func openStateFile() {
        NSWorkspace.shared.activateFileViewerSelecting([StatePersistence.defaultStateURL()])
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.open()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct AgentHeaderView: View {
    let agent: AgentKind
    let usesColorIcon: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AgentImages.menuHeaderIcon(for: agent, color: usesColorIcon))
                .resizable()
                .renderingMode(usesColorIcon ? .original : .template)
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

private struct AgentSectionView: View {
    @ObservedObject var store: AgentStateStore
    let agent: AgentKind
    let usesColorIcon: Bool
    let latestResponseLineLimit: Int
    let subagentLatestResponseLineLimit: Int
    let onLayoutMayChange: () -> Void
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let rows = store.displayRows(for: agent, now: now)

        VStack(alignment: .leading, spacing: 0) {
            AgentHeaderView(agent: agent, usesColorIcon: usesColorIcon)

            if rows.isEmpty {
                EmptyAgentRow()
            } else {
                ForEach(rows) { row in
                    switch row {
                    case .session(let session, let indentLevel):
                        SessionMenuRow(
                            session: session,
                            indentLevel: indentLevel,
                            now: now,
                            latestResponseLineLimit: latestResponseLineLimit,
                            subagentLatestResponseLineLimit: subagentLatestResponseLineLimit
                        )
                    }
                }
            }
        }
        .onReceive(timer) { date in
            now = date
            onLayoutMayChange()
        }
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

    var providerSettingsTitle: String {
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
    let indentLevel: Int
    let now: Date
    let latestResponseLineLimit: Int
    let subagentLatestResponseLineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                SessionStateIcon(
                    state: session.state,
                    color: symbolColor,
                    symbol: session.state.symbol,
                    symbolFontSize: symbolFontSize,
                    symbolWidth: symbolWidth
                )
                Text(titleText)
                    .font(.system(size: titleFontSize))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let latestResponseText {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: titleTextLeadingOffset, height: 0)

                    Text(latestResponseText)
                        .font(.system(size: detailFontSize))
                        .foregroundStyle(titleColor)
                        .lineLimit(effectiveLatestResponseLineLimit)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Color.clear
                    .frame(width: titleTextLeadingOffset, height: 0)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    ZStack(alignment: .leading) {
                        Text(Self.stateWidthReferenceText)
                            .hidden()
                        Text(stateText)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                    ZStack(alignment: .leading) {
                        Text(Self.relativeTimeWidthReferenceText)
                            .hidden()
                        Text(relativeTimeText)
                    }
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(projectInfoText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .truncationMode(.head)

                        Text(" ")
                            .fixedSize(horizontal: true, vertical: false)

                        Text(absoluteTimeText)
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.system(size: detailFontSize))
            .foregroundStyle(detailColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: rowWidth, alignment: .leading)
        .help(helpText)
    }

    private var rowWidth: CGFloat {
        344
    }

    private var contentWidth: CGFloat {
        rowWidth - leadingPadding - trailingPadding
    }

    private var leadingPadding: CGFloat {
        12 + CGFloat(indentLevel) * 18
    }

    private var trailingPadding: CGFloat {
        12
    }

    private var horizontalSpacing: CGFloat {
        4
    }

    private var titleTextLeadingOffset: CGFloat {
        symbolWidth + horizontalSpacing
    }

    private var symbolFontSize: CGFloat {
        13
    }

    private var symbolWidth: CGFloat {
        12
    }

    private var titleFontSize: CGFloat {
        13
    }

    private var detailFontSize: CGFloat {
        11
    }

    private var verticalPadding: CGFloat {
        3
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

    private var titleColor: Color {
        session.state == .idle ? .primary.opacity(0.88) : .primary
    }

    private var detailColor: Color {
        session.state == .idle ? .primary.opacity(0.56) : .secondary
    }

    private var stateText: String {
        session.state.displayName
    }

    private var projectInfoText: String {
        if session.isSubagent {
            return session.subagentNameAndRoleLabel
        }

        if !session.cwd.isEmpty {
            return URL(fileURLWithPath: session.cwd).lastPathComponent
        }

        if !session.terminal.isEmpty {
            return session.terminal
        }

        return session.agent.displayName
    }

    private var relativeTimeText: String {
        let elapsed = now.timeIntervalSince(session.updatedAt)
        if elapsed < 1 {
            return "0s ago"
        }
        return Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: now)
    }

    private var absoluteTimeText: String {
        Self.absoluteTimeFormatter.string(from: session.updatedAt)
    }

    private var titleText: String {
        session.isSubagent ? session.subagentSessionTitle : session.displayTitle
    }

    private var latestResponseText: String? {
        guard effectiveLatestResponseLineLimit > 0,
              let text = session.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private var effectiveLatestResponseLineLimit: Int {
        session.isSubagent ? subagentLatestResponseLineLimit : latestResponseLineLimit
    }

    private var helpText: String {
        [
            session.agent.displayName,
            "session: \(session.sessionId)",
            session.parentSessionId.map { "parent: \($0)" },
            session.subagentRole.map { "role: \($0)" },
            session.subagentNickname.map { "nickname: \($0)" },
            session.cwd.isEmpty ? nil : session.cwd,
            session.event.isEmpty ? nil : "event: \(session.event)",
            session.latestResponsePhase.map { "response: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private static let stateWidthReferenceText = "Working"
    private static let relativeTimeWidthReferenceText = "000m ago"

}

private struct SessionStateIcon: View {
    let state: AgentState
    let color: Color
    let symbol: String
    let symbolFontSize: CGFloat
    let symbolWidth: CGFloat

    var body: some View {
        Group {
            if state == .working {
                IOSActivitySpinner(color: color)
                    .frame(width: symbolWidth, height: symbolWidth)
                    .padding(.top, 2)
            } else {
                Text(symbol)
                    .font(.system(size: symbolFontSize, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: symbolWidth, alignment: .leading)
            }
        }
        .frame(width: symbolWidth, height: symbolFontSize + 3, alignment: .topLeading)
    }
}

private struct IOSActivitySpinner: View {
    let color: Color

    private let size: CGFloat = 11
    private let lineWidth: CGFloat = 1.7
    private let cycleDuration: TimeInterval = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            Circle()
                .trim(from: 0.12, to: 0.78)
                .stroke(
                    color.opacity(0.78),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotationDegrees(at: timeline.date)))
        }
        .frame(width: size, height: size)
    }

    private func rotationDegrees(at date: Date) -> Double {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return progress * 360 - 90
    }
}

private enum AgentColors {
    static let codexWorking = NSColor(srgbRed: 0x00 / 255, green: 0x6E / 255, blue: 0xFE / 255, alpha: 1)
    static let claudeWorking = NSColor(srgbRed: 0xCF / 255, green: 0x83 / 255, blue: 0x66 / 255, alpha: 1)
    static let waiting = NSColor(srgbRed: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)

    static func working(for agent: AgentKind) -> NSColor {
        switch agent {
        case .codex:
            codexWorking
        case .claudeCode:
            claudeWorking
        }
    }
}

struct AgentMenuBarStatus {
    let agent: AgentKind
    let state: AgentState
}

enum AgentImages {
    private static let menuBarLogoDisplayScale: CGFloat = 0.7
    private static let menuBarLogoGap: CGFloat = 2
    private static let fallbackMenuBarStatusSize = NSSize(width: 15, height: 15)
    private static let assetScale: CGFloat = 3
    private static let codexIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "Codex Mono@3x"),
        color: loadMenuBarIcon(name: "Codex Color@3x")
    )
    private static let claudeIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "claude Mono@3x"),
        color: loadMenuBarIcon(name: "Claude Color@3x")
    )

    static func menuBarStatus(_ statuses: [AgentMenuBarStatus], highlightPhase: CGFloat? = nil) -> NSImage {
        guard !statuses.isEmpty else {
            return fallbackMenuBarStatus()
        }

        let size = menuBarStatusSize(for: statuses)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0

            for status in statuses {
                let icons = iconSet(for: status.agent)
                let displaySize = displaySize(for: icons.mono)
                drawAgentLogo(
                    icons,
                    state: status.state,
                    size: displaySize,
                    x: x,
                    canvasHeight: size.height,
                    highlightPhase: status.state == .working ? highlightPhase : nil
                )
                x += displaySize.width + menuBarLogoGap
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    static func menuHeaderIcon(for agent: AgentKind, color: Bool = false) -> NSImage {
        let icons = iconSet(for: agent)
        let source = color ? icons.color : icons.mono
        guard let image = source.copy() as? NSImage else {
            return source
        }
        image.isTemplate = !color
        return image
    }

    private static func menuBarStatusSize(for statuses: [AgentMenuBarStatus]) -> NSSize {
        let displaySizes = statuses.map { displaySize(for: iconSet(for: $0.agent).mono) }
        let totalLogoWidth = displaySizes.reduce(CGFloat(0)) { $0 + $1.width }
        let totalGapWidth = CGFloat(max(statuses.count - 1, 0)) * menuBarLogoGap
        return NSSize(
            width: totalLogoWidth + totalGapWidth,
            height: displaySizes.map(\.height).max() ?? fallbackMenuBarStatusSize.height
        )
    }

    private static func fallbackMenuBarStatus() -> NSImage {
        let image = NSImage(size: fallbackMenuBarStatusSize, flipped: false) { rect in
            guard let symbol = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "AgentsBar") else {
                NSColor.labelColor.setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
                return true
            }

            var proposedRect = NSRect(origin: .zero, size: symbol.size)
            guard let cgImage = symbol.cgImage(forProposedRect: &proposedRect, context: NSGraphicsContext.current, hints: nil),
                  let context = NSGraphicsContext.current?.cgContext else {
                symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                return true
            }

            context.saveGState()
            context.clip(to: rect, mask: cgImage)
            NSColor.labelColor.setFill()
            rect.fill()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func iconSet(for agent: AgentKind) -> AgentIconSet {
        switch agent {
        case .codex:
            codexIcons
        case .claudeCode:
            claudeIcons
        }
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

    private static func drawAgentLogo(
        _ icons: AgentIconSet,
        state: AgentState,
        size: NSSize,
        x: CGFloat,
        canvasHeight: CGFloat,
        highlightPhase: CGFloat?
    ) {
        let logoRect = NSRect(
            x: x,
            y: (canvasHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )

        switch state {
        case .working:
            icons.color.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            if let highlightPhase {
                drawWorkingHighlight(icons.color, in: logoRect, phase: highlightPhase)
            }
        case .waiting:
            drawTemplateLogo(icons.mono, in: logoRect, color: AgentColors.waiting)
        case .idle, .ended:
            drawTemplateLogo(icons.mono, in: logoRect, color: .labelColor)
        }
    }

    private static func drawWorkingHighlight(_ logo: NSImage, in rect: NSRect, phase: CGFloat) {
        var proposedRect = NSRect(origin: .zero, size: logo.size)
        guard let cgImage = logo.cgImage(forProposedRect: &proposedRect, context: NSGraphicsContext.current, hints: nil),
              let context = NSGraphicsContext.current?.cgContext,
              let gradient = NSGradient(colors: [
                .clear,
                NSColor.white.withAlphaComponent(0.18),
                NSColor.white.withAlphaComponent(0.58),
                NSColor.white.withAlphaComponent(0.18),
                .clear
              ]) else {
            return
        }

        let clampedPhase = min(max(phase, 0), 1)
        let stripeWidth = max(rect.width * 0.84, 7)
        let slant = rect.height * 0.5
        let travelWidth = rect.width + stripeWidth + (slant * 2)
        let leadingX = rect.minX - stripeWidth - slant + (travelWidth * clampedPhase)
        let stripePath = NSBezierPath()
        stripePath.move(to: NSPoint(x: leadingX - slant, y: rect.minY))
        stripePath.line(to: NSPoint(x: leadingX + stripeWidth - slant, y: rect.minY))
        stripePath.line(to: NSPoint(x: leadingX + stripeWidth + slant, y: rect.maxY))
        stripePath.line(to: NSPoint(x: leadingX + slant, y: rect.maxY))
        stripePath.close()

        context.saveGState()
        context.clip(to: rect, mask: cgImage)
        context.setBlendMode(.screen)
        stripePath.addClip()
        gradient.draw(
            from: NSPoint(x: leadingX - slant, y: rect.midY),
            to: NSPoint(x: leadingX + stripeWidth + slant, y: rect.midY),
            options: []
        )
        context.restoreGState()
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
