import AgentSessionsCore
import AppKit
import Carbon
import Combine
import CoreText
import QuartzCore
import ServiceManagement
import SwiftUI

@main
struct AgentSessionsApp: App {
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
            "Dropdown Menu"
        }
    }

    var helperText: String {
        switch self {
        case .menuBar:
            "Choose providers that appear as menu bar icons."
        case .dropdownMenu:
            "Drag providers to reorder dropdown sections."
        }
    }

    var supportsReordering: Bool {
        switch self {
        case .menuBar:
            false
        case .dropdownMenu:
            true
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

private struct KeyboardShortcutModifierSymbol: Identifiable, Equatable {
    let id: String
    let systemName: String
    let accessibilityLabel: String
}

private struct PopupToggleKeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifierFlagsRawValue: UInt
    let keyDisplay: String

    init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard keyCode != UInt32(kVK_Escape) else {
            return nil
        }

        let modifierFlags = Self.supportedModifierFlags(from: event.modifierFlags)
        guard !modifierFlags.isEmpty else {
            return nil
        }

        let keyDisplay = Self.displayKey(for: event)
        guard !keyDisplay.isEmpty else {
            return nil
        }

        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.rawValue
        self.keyDisplay = keyDisplay
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        let modifierFlags = modifierFlags
        if modifierFlags.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }

    var displayText: String {
        var parts: [String] = []
        let modifierFlags = modifierFlags
        if modifierFlags.contains(.control) {
            parts.append("Ctrl")
        }
        if modifierFlags.contains(.option) {
            parts.append("Opt")
        }
        if modifierFlags.contains(.shift) {
            parts.append("Shift")
        }
        if modifierFlags.contains(.command) {
            parts.append("Cmd")
        }
        parts.append(keyDisplay)
        return parts.joined(separator: "+")
    }

    var modifierSymbols: [KeyboardShortcutModifierSymbol] {
        var symbols: [KeyboardShortcutModifierSymbol] = []
        let modifierFlags = modifierFlags
        if modifierFlags.contains(.control) {
            symbols.append(KeyboardShortcutModifierSymbol(
                id: "control",
                systemName: "control",
                accessibilityLabel: "Control"
            ))
        }
        if modifierFlags.contains(.option) {
            symbols.append(KeyboardShortcutModifierSymbol(
                id: "option",
                systemName: "option",
                accessibilityLabel: "Option"
            ))
        }
        if modifierFlags.contains(.shift) {
            symbols.append(KeyboardShortcutModifierSymbol(
                id: "shift",
                systemName: "shift",
                accessibilityLabel: "Shift"
            ))
        }
        if modifierFlags.contains(.command) {
            symbols.append(KeyboardShortcutModifierSymbol(
                id: "command",
                systemName: "command",
                accessibilityLabel: "Command"
            ))
        }
        return symbols
    }

    var menuKeyEquivalentModifierMask: NSEvent.ModifierFlags {
        modifierFlags
    }

    var menuKeyEquivalent: String? {
        if let keyEquivalent = Self.menuKeyEquivalents[UInt32(keyCode)] {
            return keyEquivalent
        }

        guard keyDisplay.count == 1 else {
            return nil
        }
        return keyDisplay.lowercased()
    }

    static func supportedModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        let supportedFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return flags.intersection(supportedFlags)
    }

    private static func displayKey(for event: NSEvent) -> String {
        if let key = specialKeyNames[UInt32(event.keyCode)] {
            return key
        }

        guard let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !characters.isEmpty else {
            return ""
        }

        return characters.uppercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "Left",
        UInt32(kVK_RightArrow): "Right",
        UInt32(kVK_DownArrow): "Down",
        UInt32(kVK_UpArrow): "Up",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12"
    ]

    private static let menuKeyEquivalents: [UInt32: String] = [
        UInt32(kVK_Return): "\r",
        UInt32(kVK_Tab): "\t",
        UInt32(kVK_Space): " ",
        UInt32(kVK_Delete): "\u{8}",
        UInt32(kVK_ForwardDelete): "\u{F728}",
        UInt32(kVK_Home): "\u{F729}",
        UInt32(kVK_End): "\u{F72B}",
        UInt32(kVK_PageUp): "\u{F72C}",
        UInt32(kVK_PageDown): "\u{F72D}",
        UInt32(kVK_LeftArrow): "\u{F702}",
        UInt32(kVK_RightArrow): "\u{F703}",
        UInt32(kVK_DownArrow): "\u{F701}",
        UInt32(kVK_UpArrow): "\u{F700}",
        UInt32(kVK_F1): "\u{F704}",
        UInt32(kVK_F2): "\u{F705}",
        UInt32(kVK_F3): "\u{F706}",
        UInt32(kVK_F4): "\u{F707}",
        UInt32(kVK_F5): "\u{F708}",
        UInt32(kVK_F6): "\u{F709}",
        UInt32(kVK_F7): "\u{F70A}",
        UInt32(kVK_F8): "\u{F70B}",
        UInt32(kVK_F9): "\u{F70C}",
        UInt32(kVK_F10): "\u{F70D}",
        UInt32(kVK_F11): "\u{F70E}",
        UInt32(kVK_F12): "\u{F70F}"
    ]
}

@MainActor
private final class KeyboardShortcutStore: ObservableObject {
    static let shared = KeyboardShortcutStore()

    @Published private(set) var popupToggleShortcut: PopupToggleKeyboardShortcut?
    @Published private(set) var popupToggleStatusText: String

    private let defaults: UserDefaults
    private let storageKey = "PopupToggleKeyboardShortcut"
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var popupToggleAction: (() -> Void)?

    private static let popupToggleHotKeySignature = fourCharCode("AgSS")
    private static let popupToggleHotKeyIDValue: UInt32 = 1

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedShortcut: PopupToggleKeyboardShortcut?
        if let data = defaults.data(forKey: storageKey),
           let shortcut = try? JSONDecoder().decode(PopupToggleKeyboardShortcut.self, from: data) {
            loadedShortcut = shortcut
        } else {
            loadedShortcut = nil
        }
        popupToggleShortcut = loadedShortcut
        popupToggleStatusText = loadedShortcut == nil
            ? "No shortcut registered."
            : "Registered for toggling Popup."
        installEventHandlerIfNeeded()
        registerPopupToggleHotKey()
    }

    func configurePopupToggleAction(_ action: @escaping () -> Void) {
        popupToggleAction = action
    }

    func setPopupToggleShortcut(_ shortcut: PopupToggleKeyboardShortcut?) {
        popupToggleShortcut = shortcut
        savePopupToggleShortcut()
        registerPopupToggleHotKey()
    }

    func clearPopupToggleShortcut() {
        setPopupToggleShortcut(nil)
    }

    private func savePopupToggleShortcut() {
        guard let popupToggleShortcut else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        guard let data = try? JSONEncoder().encode(popupToggleShortcut) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                DispatchQueue.main.async {
                    let store = Unmanaged<KeyboardShortcutStore>.fromOpaque(userData).takeUnretainedValue()
                    store.handleHotKeyPressed(hotKeyID)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            popupToggleStatusText = "Shortcut listener unavailable."
        }
    }

    private func registerPopupToggleHotKey() {
        unregisterPopupToggleHotKey()

        guard let popupToggleShortcut else {
            popupToggleStatusText = "No shortcut registered."
            return
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.popupToggleHotKeySignature
        hotKeyID.id = Self.popupToggleHotKeyIDValue

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            popupToggleShortcut.keyCode,
            popupToggleShortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            popupToggleStatusText = "Shortcut unavailable. Choose another."
            return
        }

        self.hotKeyRef = hotKeyRef
        popupToggleStatusText = "Registered for toggling Popup."
    }

    private func unregisterPopupToggleHotKey() {
        guard let hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func handleHotKeyPressed(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.popupToggleHotKeySignature,
              hotKeyID.id == Self.popupToggleHotKeyIDValue else {
            return
        }

        popupToggleAction?()
    }

    private static func fourCharCode(_ value: String) -> OSType {
        value.unicodeScalars.prefix(4).reduce(0) { result, scalar in
            (result << 8) + OSType(scalar.value)
        }
    }
}

enum PopupWindowPosition: String, Codable, CaseIterable, Identifiable {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case topCenter
    case bottomCenter

    static let allCases: [PopupWindowPosition] = [
        .topRight,
        .topLeft,
        .bottomRight,
        .bottomLeft,
        .topCenter
    ]

    var id: Self { self }

    var title: String {
        switch self {
        case .topRight:
            "Top Right"
        case .topLeft:
            "Top Left"
        case .bottomRight:
            "Bottom Right"
        case .bottomLeft:
            "Bottom Left"
        case .topCenter:
            "Top Center"
        case .bottomCenter:
            "Bottom Center"
        }
    }

    var isRightSide: Bool {
        switch self {
        case .topRight, .bottomRight:
            true
        case .topLeft, .bottomLeft, .topCenter, .bottomCenter:
            false
        }
    }

    var placesNewestPopupSessionAtBottom: Bool {
        switch self {
        case .bottomRight, .bottomLeft, .bottomCenter:
            true
        case .topRight, .topLeft, .topCenter:
            false
        }
    }
}

fileprivate enum PopupVisualStyle: String, CaseIterable, Identifiable {
    case liquidGlass
    case textDropShadow

    var id: Self { self }

    var title: String {
        switch self {
        case .liquidGlass:
            "Liquid Glass"
        case .textDropShadow:
            "Text Drop Shadow"
        }
    }

    var systemImageName: String {
        switch self {
        case .liquidGlass:
            "sparkles"
        case .textDropShadow:
            "textformat"
        }
    }
}

private enum ProviderPreferenceDefaults {
    static let usesIndicatorLampStyle = false
    static let sessionDisplayCount = 5
    static let latestResponseLineLimit = 3
    static let subagentLatestResponseLineLimit = 1
    static let latestResponseHideAfterInterval: TimeInterval = 24 * 60 * 60
    static let latestResponseCompactsBlankLines = true
    static let dropdownShowsUserPrompt = true
    static let showsSubagents = true
    static let subagentHideAfterInterval: TimeInterval = 3 * 60
    static let menuBarEnabled = true
    static let popupEnabled = true
    static let popupDisplayInterval: TimeInterval = 15
    static let popupGlassEnabled = false
    static let popupUsesClearGlass = false
    static let popupUsesColoredBorder = true
    static let popupGlassOpacity = 0.7027258211678832
    static let popupOpacity = 0.8093635948905109
    static let popupWindowPosition = PopupWindowPosition.bottomRight
    static let popupRightAlignsTextOnRightSide = false
    static let popupWindowWidth = 400.0
    static let popupOffsetX = 0.0
    static let popupOffsetY = 0.0
    static let popupScale = 1.0076277687666928
    static let popupBackdropOpacity = 0.85
    static let popupTextOpacity = 1.0
    static let popupMouseProximityOpacity = 0.10462150483130862
    static let popupTextShadowEnabled = true
    static let legacyPopupTextShadowStrength = 0.65
    static let popupTextShadowStrength = 2.0074120724332674
    static let popupTextShadowDistance = 0.0
    static let popupTextShadowRadius = 1.1633347657784874
    static let popupParentSessionCount = 5
    static let popupShowsUserPrompt = true
    static let popupShowsResponseBody = true
    static let popupResponseCharacterLimit = 1000
    static let popupResponseLineLimit = 10
    static let popupResponseCompactsBlankLines = true
    static let popupResponseElidesShortFinalLine = true
    static let latestResponseHideAfterOptions: [TimeInterval] = [
        60,
        3 * 60,
        5 * 60,
        10 * 60,
        30 * 60,
        60 * 60,
        3 * 60 * 60,
        24 * 60 * 60
    ]
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
    static let popupDisplayOptions: [TimeInterval] = (1...60).map(TimeInterval.init)

    static func sanitizedSessionDisplayCount(_ count: Int?) -> Int {
        min(max(count ?? sessionDisplayCount, 3), 10)
    }

    static func sanitizedLatestResponseLineLimit(_ count: Int?) -> Int {
        min(max(count ?? latestResponseLineLimit, 1), 5)
    }

    static func sanitizedSubagentLatestResponseLineLimit(_ count: Int?) -> Int {
        min(max(count ?? subagentLatestResponseLineLimit, 1), 5)
    }

    static func sanitizedLatestResponseHideAfterInterval(_ interval: TimeInterval?) -> TimeInterval {
        guard let interval,
              let nearest = latestResponseHideAfterOptions.min(by: { abs($0 - interval) < abs($1 - interval) }) else {
            return latestResponseHideAfterInterval
        }
        return nearest
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

    static func sanitizedPopupDisplayInterval(_ interval: TimeInterval?) -> TimeInterval {
        guard let interval,
              let nearest = popupDisplayOptions.min(by: { abs($0 - interval) < abs($1 - interval) }) else {
            return popupDisplayInterval
        }
        return nearest
    }

    static func sanitizedPopupOpacity(_ opacity: Double?) -> Double {
        min(max(opacity ?? popupOpacity, 0), 1.0)
    }

    static func sanitizedPopupGlassOpacity(_ opacity: Double?) -> Double {
        min(max(opacity ?? popupGlassOpacity, 0), 1.0)
    }

    static func sanitizedPopupStyle(
        glassEnabled: Bool,
        textShadowEnabled: Bool
    ) -> (glassEnabled: Bool, textShadowEnabled: Bool) {
        if glassEnabled {
            return (true, false)
        }
        if textShadowEnabled {
            return (false, true)
        }
        return (popupGlassEnabled, !popupGlassEnabled)
    }

    static func sanitizedPopupWindowWidth(_ width: Double?) -> Double {
        min(max(width ?? popupWindowWidth, 200), 800)
    }

    static func sanitizedPopupOffset(_ offset: Double?) -> Double {
        min(max(offset ?? 0, -500), 500)
    }

    static func sanitizedPopupScale(_ scale: Double?) -> Double {
        min(max(scale ?? popupScale, 0.5), 1.5)
    }

    static func sanitizedPopupWindowPosition(_ position: PopupWindowPosition?) -> PopupWindowPosition {
        guard let position, PopupWindowPosition.allCases.contains(position) else {
            return popupWindowPosition
        }

        return position
    }

    static func sanitizedPopupBackdropOpacity(_ opacity: Double?) -> Double {
        min(max(opacity ?? popupBackdropOpacity, 0.05), 0.85)
    }

    static func sanitizedPopupTextOpacity(_ opacity: Double?) -> Double {
        min(max(opacity ?? popupTextOpacity, 0.35), 1.0)
    }

    static func sanitizedPopupMouseProximityOpacity(_ opacity: Double?) -> Double {
        min(max(opacity ?? popupMouseProximityOpacity, 0), 1)
    }

    static func inferredPopupTextShadowEnabled(strength: Double?, radius: Double?) -> Bool {
        guard let strength else {
            return popupTextShadowEnabled
        }

        return sanitizedPopupTextShadowStrength(strength) > 0
            && sanitizedPopupTextShadowRadius(radius) > 0
    }

    static func sanitizedPopupTextShadowStrength(_ strength: Double?) -> Double {
        min(max(strength ?? popupTextShadowStrength, 0), 3.0)
    }

    static func sanitizedPopupTextShadowDistance(_ distance: Double?) -> Double {
        min(max(distance ?? popupTextShadowDistance, 0), 12)
    }

    static func migratedPopupTextShadowStrength(_ strength: Double?) -> Double? {
        guard let strength else {
            return nil
        }

        if abs(strength - legacyPopupTextShadowStrength) < 0.0001 {
            return popupTextShadowStrength
        }

        return strength
    }

    static func sanitizedPopupTextShadowRadius(_ radius: Double?) -> Double {
        min(max(radius ?? popupTextShadowRadius, 0), 16)
    }

    static func sanitizedPopupParentSessionCount(_ count: Int?) -> Int {
        min(max(count ?? popupParentSessionCount, 1), 10)
    }

    static func sanitizedPopupResponseCharacterLimit(_ count: Int?) -> Int {
        min(max(count ?? popupResponseCharacterLimit, 40), 1000)
    }

    static func sanitizedPopupResponseLineLimit(_ count: Int?) -> Int {
        min(max(count ?? popupResponseLineLimit, 1), 30)
    }

    static func popupResponseCharacterLimit(fromLegacyLineLimit count: Int?) -> Int? {
        guard let count else {
            return nil
        }

        return sanitizedPopupResponseCharacterLimit(count * 60)
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

    static func latestResponseHideAfterLabel(for interval: TimeInterval) -> String {
        switch sanitizedLatestResponseHideAfterInterval(interval) {
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
        case 24 * 60 * 60:
            "24 hours"
        default:
            "10 minutes"
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

    static func popupDisplayLabel(for interval: TimeInterval) -> String {
        switch sanitizedPopupDisplayInterval(interval) {
        case 1:
            "1 second"
        case 2:
            "2 seconds"
        case 3:
            "3 seconds"
        case 4:
            "4 seconds"
        case 5:
            "5 seconds"
        case 6:
            "6 seconds"
        case 7:
            "7 seconds"
        case 8:
            "8 seconds"
        case 9:
            "9 seconds"
        case 10:
            "10 seconds"
        default:
            "\(Int(sanitizedPopupDisplayInterval(interval))) seconds"
        }
    }
}

private struct ProviderPreferencesDocument: Codable, Equatable {
    var values: [String: ProviderVisibility]
    var menuBarOrder: [String]
    var dropdownMenuOrder: [String]
    var usesColorDropdownIcons: Bool
    var usesIndicatorLampStyle: Bool
    var sessionDisplayCount: Int
    var latestResponseLineLimit: Int
    var subagentLatestResponseLineLimit: Int
    var latestResponseHideAfterInterval: TimeInterval
    var latestResponseCompactsBlankLines: Bool
    var dropdownShowsUserPrompt: Bool
    var showsSubagents: Bool
    var subagentHideAfterInterval: TimeInterval
    var hideAfterInterval: TimeInterval
    var menuBarEnabled: Bool
    var popupEnabled: Bool
    var popupDisplayInterval: TimeInterval
    var popupProviderVisibility: [String: Bool]
    var popupGlassEnabled: Bool
    var popupUsesClearGlass: Bool
    var popupUsesColoredBorder: Bool
    var popupGlassOpacity: Double
    var popupOpacity: Double
    var popupWindowPosition: PopupWindowPosition
    var popupRightAlignsTextOnRightSide: Bool
    var popupWindowWidth: Double
    var popupOffsetX: Double
    var popupOffsetY: Double
    var popupScale: Double
    var popupBackdropOpacity: Double
    var popupTextOpacity: Double
    var popupMouseProximityOpacity: Double
    var popupTextShadowEnabled: Bool
    var popupTextShadowStrength: Double
    var popupTextShadowDistance: Double
    var popupTextShadowRadius: Double
    var popupParentSessionCount: Int
    var popupShowsUserPrompt: Bool
    var popupShowsResponseBody: Bool
    var popupResponseCharacterLimit: Int
    var popupResponseLineLimit: Int
    var popupResponseCompactsBlankLines: Bool
    var popupResponseElidesShortFinalLine: Bool

    init(
        values: [String: ProviderVisibility],
        menuBarOrder: [String],
        dropdownMenuOrder: [String],
        usesColorDropdownIcons: Bool = false,
        usesIndicatorLampStyle: Bool = ProviderPreferenceDefaults.usesIndicatorLampStyle,
        sessionDisplayCount: Int = ProviderPreferenceDefaults.sessionDisplayCount,
        latestResponseLineLimit: Int = ProviderPreferenceDefaults.latestResponseLineLimit,
        subagentLatestResponseLineLimit: Int = ProviderPreferenceDefaults.subagentLatestResponseLineLimit,
        latestResponseHideAfterInterval: TimeInterval = ProviderPreferenceDefaults.latestResponseHideAfterInterval,
        latestResponseCompactsBlankLines: Bool = ProviderPreferenceDefaults.latestResponseCompactsBlankLines,
        dropdownShowsUserPrompt: Bool = ProviderPreferenceDefaults.dropdownShowsUserPrompt,
        showsSubagents: Bool = ProviderPreferenceDefaults.showsSubagents,
        subagentHideAfterInterval: TimeInterval = ProviderPreferenceDefaults.subagentHideAfterInterval,
        hideAfterInterval: TimeInterval = ProviderPreferenceDefaults.hideAfterInterval,
        menuBarEnabled: Bool = ProviderPreferenceDefaults.menuBarEnabled,
        popupEnabled: Bool = ProviderPreferenceDefaults.popupEnabled,
        popupDisplayInterval: TimeInterval = ProviderPreferenceDefaults.popupDisplayInterval,
        popupProviderVisibility: [String: Bool] = ProviderPreferencesDocument.defaultPopupProviderVisibility,
        popupGlassEnabled: Bool = ProviderPreferenceDefaults.popupGlassEnabled,
        popupUsesClearGlass: Bool = ProviderPreferenceDefaults.popupUsesClearGlass,
        popupUsesColoredBorder: Bool = ProviderPreferenceDefaults.popupUsesColoredBorder,
        popupGlassOpacity: Double = ProviderPreferenceDefaults.popupGlassOpacity,
        popupOpacity: Double = ProviderPreferenceDefaults.popupOpacity,
        popupWindowPosition: PopupWindowPosition = ProviderPreferenceDefaults.popupWindowPosition,
        popupRightAlignsTextOnRightSide: Bool = ProviderPreferenceDefaults.popupRightAlignsTextOnRightSide,
        popupWindowWidth: Double = ProviderPreferenceDefaults.popupWindowWidth,
        popupOffsetX: Double = ProviderPreferenceDefaults.popupOffsetX,
        popupOffsetY: Double = ProviderPreferenceDefaults.popupOffsetY,
        popupScale: Double = ProviderPreferenceDefaults.popupScale,
        popupBackdropOpacity: Double = ProviderPreferenceDefaults.popupBackdropOpacity,
        popupTextOpacity: Double = ProviderPreferenceDefaults.popupTextOpacity,
        popupMouseProximityOpacity: Double = ProviderPreferenceDefaults.popupMouseProximityOpacity,
        popupTextShadowEnabled: Bool = ProviderPreferenceDefaults.popupTextShadowEnabled,
        popupTextShadowStrength: Double = ProviderPreferenceDefaults.popupTextShadowStrength,
        popupTextShadowDistance: Double = ProviderPreferenceDefaults.popupTextShadowDistance,
        popupTextShadowRadius: Double = ProviderPreferenceDefaults.popupTextShadowRadius,
        popupParentSessionCount: Int = ProviderPreferenceDefaults.popupParentSessionCount,
        popupShowsUserPrompt: Bool = ProviderPreferenceDefaults.popupShowsUserPrompt,
        popupShowsResponseBody: Bool = ProviderPreferenceDefaults.popupShowsResponseBody,
        popupResponseCharacterLimit: Int = ProviderPreferenceDefaults.popupResponseCharacterLimit,
        popupResponseLineLimit: Int = ProviderPreferenceDefaults.popupResponseLineLimit,
        popupResponseCompactsBlankLines: Bool = ProviderPreferenceDefaults.popupResponseCompactsBlankLines,
        popupResponseElidesShortFinalLine: Bool = ProviderPreferenceDefaults.popupResponseElidesShortFinalLine
    ) {
        self.values = values
        self.menuBarOrder = menuBarOrder
        self.dropdownMenuOrder = dropdownMenuOrder
        self.usesColorDropdownIcons = usesColorDropdownIcons
        self.usesIndicatorLampStyle = usesIndicatorLampStyle
        self.sessionDisplayCount = sessionDisplayCount
        self.latestResponseLineLimit = latestResponseLineLimit
        self.subagentLatestResponseLineLimit = subagentLatestResponseLineLimit
        self.latestResponseHideAfterInterval = latestResponseHideAfterInterval
        self.latestResponseCompactsBlankLines = latestResponseCompactsBlankLines
        self.dropdownShowsUserPrompt = dropdownShowsUserPrompt
        self.showsSubagents = showsSubagents
        self.subagentHideAfterInterval = subagentHideAfterInterval
        self.hideAfterInterval = hideAfterInterval
        self.menuBarEnabled = menuBarEnabled
        self.popupEnabled = popupEnabled
        self.popupDisplayInterval = popupDisplayInterval
        self.popupProviderVisibility = Self.sanitizedPopupProviderVisibility(popupProviderVisibility)
        let popupStyle = ProviderPreferenceDefaults.sanitizedPopupStyle(
            glassEnabled: popupGlassEnabled,
            textShadowEnabled: popupTextShadowEnabled
        )
        self.popupGlassEnabled = popupStyle.glassEnabled
        self.popupUsesClearGlass = popupUsesClearGlass
        self.popupUsesColoredBorder = popupUsesColoredBorder
        self.popupGlassOpacity = ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(popupGlassOpacity)
        self.popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(popupOpacity)
        self.popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(popupWindowPosition)
        self.popupRightAlignsTextOnRightSide = popupRightAlignsTextOnRightSide
        self.popupWindowWidth = ProviderPreferenceDefaults.sanitizedPopupWindowWidth(popupWindowWidth)
        self.popupOffsetX = ProviderPreferenceDefaults.sanitizedPopupOffset(popupOffsetX)
        self.popupOffsetY = ProviderPreferenceDefaults.sanitizedPopupOffset(popupOffsetY)
        self.popupScale = ProviderPreferenceDefaults.sanitizedPopupScale(popupScale)
        self.popupBackdropOpacity = ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(popupBackdropOpacity)
        self.popupTextOpacity = ProviderPreferenceDefaults.sanitizedPopupTextOpacity(popupTextOpacity)
        self.popupMouseProximityOpacity = ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(popupMouseProximityOpacity)
        self.popupTextShadowEnabled = popupStyle.textShadowEnabled
        self.popupTextShadowStrength = ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(popupTextShadowStrength)
        self.popupTextShadowDistance = ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(popupTextShadowDistance)
        self.popupTextShadowRadius = ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(popupTextShadowRadius)
        self.popupParentSessionCount = ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(popupParentSessionCount)
        self.popupShowsUserPrompt = popupShowsUserPrompt
        self.popupShowsResponseBody = popupShowsResponseBody
        self.popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(popupResponseCharacterLimit)
        self.popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(popupResponseLineLimit)
        self.popupResponseCompactsBlankLines = popupResponseCompactsBlankLines
        self.popupResponseElidesShortFinalLine = popupResponseElidesShortFinalLine
    }

    private enum CodingKeys: String, CodingKey {
        case values
        case menuBarOrder
        case dropdownMenuOrder
        case usesColorDropdownIcons
        case usesIndicatorLampStyle
        case sessionDisplayCount
        case latestResponseLineLimit
        case subagentLatestResponseLineLimit
        case latestResponseHideAfterInterval
        case latestResponseCompactsBlankLines
        case dropdownShowsUserPrompt
        case subagentDisplayCount
        case showsSubagents
        case subagentHideAfterInterval
        case hideAfterInterval
        case menuBarEnabled
        case popupEnabled
        case popupDisplayInterval
        case popupProviderVisibility
        case popupGlassEnabled
        case popupUsesClearGlass
        case popupUsesColoredBorder
        case popupUsesStatusTint
        case popupGlassOpacity
        case popupOpacity
        case popupWindowPosition
        case popupRightAlignsTextOnRightSide
        case popupWindowWidth
        case popupOffsetX
        case popupOffsetY
        case popupScale
        case popupBackdropOpacity
        case popupTextOpacity
        case popupMouseProximityOpacity
        case popupTextShadowEnabled
        case popupTextShadowStrength
        case popupTextShadowDistance
        case popupTextShadowRadius
        case popupBackdropBlurRadius
        case popupParentSessionCount
        case popupShowsUserPrompt
        case popupShowsResponseBody
        case popupResponseCharacterLimit
        case popupResponseLineLimit
        case popupResponseCompactsBlankLines
        case popupResponseElidesShortFinalLine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decodeIfPresent([String: ProviderVisibility].self, forKey: .values) ?? [:]
        menuBarOrder = try container.decodeIfPresent([String].self, forKey: .menuBarOrder) ?? []
        dropdownMenuOrder = try container.decodeIfPresent([String].self, forKey: .dropdownMenuOrder) ?? []
        usesColorDropdownIcons = try container.decodeIfPresent(Bool.self, forKey: .usesColorDropdownIcons)
            ?? values.values.contains { $0.usesColorDropdownIcon }
        usesIndicatorLampStyle = try container.decodeIfPresent(Bool.self, forKey: .usesIndicatorLampStyle)
            ?? ProviderPreferenceDefaults.usesIndicatorLampStyle
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(
            try container.decodeIfPresent(Int.self, forKey: .sessionDisplayCount)
        )
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(
            try container.decodeIfPresent(Int.self, forKey: .latestResponseLineLimit)
        )
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
            try container.decodeIfPresent(Int.self, forKey: .subagentLatestResponseLineLimit)
        )
        latestResponseHideAfterInterval = ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .latestResponseHideAfterInterval)
        )
        latestResponseCompactsBlankLines = try container.decodeIfPresent(
            Bool.self,
            forKey: .latestResponseCompactsBlankLines
        ) ?? ProviderPreferenceDefaults.latestResponseCompactsBlankLines
        dropdownShowsUserPrompt = try container.decodeIfPresent(Bool.self, forKey: .dropdownShowsUserPrompt)
            ?? ProviderPreferenceDefaults.dropdownShowsUserPrompt
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
        menuBarEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarEnabled)
            ?? ProviderPreferenceDefaults.menuBarEnabled
        popupEnabled = try container.decodeIfPresent(Bool.self, forKey: .popupEnabled)
            ?? ProviderPreferenceDefaults.popupEnabled
        popupDisplayInterval = ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .popupDisplayInterval)
        )
        popupProviderVisibility = Self.sanitizedPopupProviderVisibility(
            try container.decodeIfPresent([String: Bool].self, forKey: .popupProviderVisibility)
        )
        popupGlassEnabled = try container.decodeIfPresent(Bool.self, forKey: .popupGlassEnabled)
            ?? ProviderPreferenceDefaults.popupGlassEnabled
        popupUsesClearGlass = try container.decodeIfPresent(Bool.self, forKey: .popupUsesClearGlass)
            ?? ProviderPreferenceDefaults.popupUsesClearGlass
        popupUsesColoredBorder = try container.decodeIfPresent(Bool.self, forKey: .popupUsesColoredBorder)
            ?? container.decodeIfPresent(Bool.self, forKey: .popupUsesStatusTint)
            ?? ProviderPreferenceDefaults.popupUsesColoredBorder
        popupGlassOpacity = ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupGlassOpacity)
        )
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupOpacity)
        )
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(
            try container.decodeIfPresent(PopupWindowPosition.self, forKey: .popupWindowPosition)
        )
        popupRightAlignsTextOnRightSide = try container.decodeIfPresent(
            Bool.self,
            forKey: .popupRightAlignsTextOnRightSide
        ) ?? ProviderPreferenceDefaults.popupRightAlignsTextOnRightSide
        popupWindowWidth = ProviderPreferenceDefaults.sanitizedPopupWindowWidth(
            try container.decodeIfPresent(Double.self, forKey: .popupWindowWidth)
        )
        popupOffsetX = ProviderPreferenceDefaults.sanitizedPopupOffset(
            try container.decodeIfPresent(Double.self, forKey: .popupOffsetX)
        )
        popupOffsetY = ProviderPreferenceDefaults.sanitizedPopupOffset(
            try container.decodeIfPresent(Double.self, forKey: .popupOffsetY)
        )
        popupScale = ProviderPreferenceDefaults.sanitizedPopupScale(
            try container.decodeIfPresent(Double.self, forKey: .popupScale)
        )
        popupBackdropOpacity = ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupBackdropOpacity)
        )
        popupTextOpacity = ProviderPreferenceDefaults.sanitizedPopupTextOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupTextOpacity)
        )
        popupMouseProximityOpacity = ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupMouseProximityOpacity)
        )
        let decodedTextShadowStrength = try container.decodeIfPresent(Double.self, forKey: .popupTextShadowStrength)
        let migratedTextShadowStrength = ProviderPreferenceDefaults.migratedPopupTextShadowStrength(decodedTextShadowStrength)
        popupTextShadowStrength = ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(
            migratedTextShadowStrength
        )
        let decodedTextShadowDistance = try container.decodeIfPresent(Double.self, forKey: .popupTextShadowDistance)
        popupTextShadowDistance = ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(
            decodedTextShadowDistance
        )
        let decodedTextShadowRadius = try container.decodeIfPresent(Double.self, forKey: .popupTextShadowRadius)
        let legacyBackdropBlurRadius = try container.decodeIfPresent(Double.self, forKey: .popupBackdropBlurRadius)
        let migratedTextShadowRadius = decodedTextShadowRadius ?? legacyBackdropBlurRadius
        popupTextShadowRadius = ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(
            migratedTextShadowRadius
        )
        popupTextShadowEnabled = try container.decodeIfPresent(Bool.self, forKey: .popupTextShadowEnabled)
            ?? ProviderPreferenceDefaults.inferredPopupTextShadowEnabled(
                strength: migratedTextShadowStrength,
                radius: migratedTextShadowRadius
            )
        popupParentSessionCount = ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(
            try container.decodeIfPresent(Int.self, forKey: .popupParentSessionCount)
        )
        popupShowsUserPrompt = try container.decodeIfPresent(Bool.self, forKey: .popupShowsUserPrompt)
            ?? ProviderPreferenceDefaults.popupShowsUserPrompt
        popupShowsResponseBody = try container.decodeIfPresent(Bool.self, forKey: .popupShowsResponseBody)
            ?? ProviderPreferenceDefaults.popupShowsResponseBody
        let decodedResponseCharacterLimit = try container.decodeIfPresent(Int.self, forKey: .popupResponseCharacterLimit)
        let decodedResponseLineLimit = try container.decodeIfPresent(Int.self, forKey: .popupResponseLineLimit)
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
            decodedResponseCharacterLimit
                ?? ProviderPreferenceDefaults.popupResponseCharacterLimit(fromLegacyLineLimit: decodedResponseLineLimit)
        )
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(decodedResponseLineLimit)
        popupResponseCompactsBlankLines = try container.decodeIfPresent(
            Bool.self,
            forKey: .popupResponseCompactsBlankLines
        ) ?? ProviderPreferenceDefaults.popupResponseCompactsBlankLines
        popupResponseElidesShortFinalLine = try container.decodeIfPresent(
            Bool.self,
            forKey: .popupResponseElidesShortFinalLine
        ) ?? ProviderPreferenceDefaults.popupResponseElidesShortFinalLine
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
        try container.encode(menuBarOrder, forKey: .menuBarOrder)
        try container.encode(dropdownMenuOrder, forKey: .dropdownMenuOrder)
        try container.encode(usesColorDropdownIcons, forKey: .usesColorDropdownIcons)
        try container.encode(usesIndicatorLampStyle, forKey: .usesIndicatorLampStyle)
        try container.encode(sessionDisplayCount, forKey: .sessionDisplayCount)
        try container.encode(latestResponseLineLimit, forKey: .latestResponseLineLimit)
        try container.encode(subagentLatestResponseLineLimit, forKey: .subagentLatestResponseLineLimit)
        try container.encode(latestResponseHideAfterInterval, forKey: .latestResponseHideAfterInterval)
        try container.encode(latestResponseCompactsBlankLines, forKey: .latestResponseCompactsBlankLines)
        try container.encode(dropdownShowsUserPrompt, forKey: .dropdownShowsUserPrompt)
        try container.encode(showsSubagents, forKey: .showsSubagents)
        try container.encode(subagentHideAfterInterval, forKey: .subagentHideAfterInterval)
        try container.encode(hideAfterInterval, forKey: .hideAfterInterval)
        try container.encode(menuBarEnabled, forKey: .menuBarEnabled)
        try container.encode(popupEnabled, forKey: .popupEnabled)
        try container.encode(popupDisplayInterval, forKey: .popupDisplayInterval)
        try container.encode(popupProviderVisibility, forKey: .popupProviderVisibility)
        try container.encode(popupGlassEnabled, forKey: .popupGlassEnabled)
        try container.encode(popupUsesClearGlass, forKey: .popupUsesClearGlass)
        try container.encode(popupUsesColoredBorder, forKey: .popupUsesColoredBorder)
        try container.encode(popupGlassOpacity, forKey: .popupGlassOpacity)
        try container.encode(popupOpacity, forKey: .popupOpacity)
        try container.encode(popupWindowPosition, forKey: .popupWindowPosition)
        try container.encode(popupRightAlignsTextOnRightSide, forKey: .popupRightAlignsTextOnRightSide)
        try container.encode(popupWindowWidth, forKey: .popupWindowWidth)
        try container.encode(popupOffsetX, forKey: .popupOffsetX)
        try container.encode(popupOffsetY, forKey: .popupOffsetY)
        try container.encode(popupScale, forKey: .popupScale)
        try container.encode(popupBackdropOpacity, forKey: .popupBackdropOpacity)
        try container.encode(popupTextOpacity, forKey: .popupTextOpacity)
        try container.encode(popupMouseProximityOpacity, forKey: .popupMouseProximityOpacity)
        try container.encode(popupTextShadowEnabled, forKey: .popupTextShadowEnabled)
        try container.encode(popupTextShadowStrength, forKey: .popupTextShadowStrength)
        try container.encode(popupTextShadowDistance, forKey: .popupTextShadowDistance)
        try container.encode(popupTextShadowRadius, forKey: .popupTextShadowRadius)
        try container.encode(popupParentSessionCount, forKey: .popupParentSessionCount)
        try container.encode(popupShowsUserPrompt, forKey: .popupShowsUserPrompt)
        try container.encode(popupShowsResponseBody, forKey: .popupShowsResponseBody)
        try container.encode(popupResponseCharacterLimit, forKey: .popupResponseCharacterLimit)
        try container.encode(popupResponseLineLimit, forKey: .popupResponseLineLimit)
        try container.encode(popupResponseCompactsBlankLines, forKey: .popupResponseCompactsBlankLines)
        try container.encode(popupResponseElidesShortFinalLine, forKey: .popupResponseElidesShortFinalLine)
    }

    static var defaultPopupProviderVisibility: [String: Bool] {
        Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0.rawValue, true) })
    }

    static func sanitizedPopupProviderVisibility(_ rawVisibility: [String: Bool]?) -> [String: Bool] {
        var visibility = defaultPopupProviderVisibility
        let knownIDs = Set(AgentKind.allCases.map(\.rawValue))

        for (id, isVisible) in rawVisibility ?? [:] where knownIDs.contains(id) {
            visibility[id] = isVisible
        }

        return visibility
    }
}

@MainActor
final class ProviderVisibilityStore: ObservableObject {
    static let shared = ProviderVisibilityStore()

    @Published private(set) var values: [String: ProviderVisibility]
    @Published private(set) var menuBarOrder: [String]
    @Published private(set) var dropdownMenuOrder: [String]
    @Published private(set) var usesColorDropdownIcons: Bool
    @Published private(set) var usesIndicatorLampStyle: Bool
    @Published private(set) var sessionDisplayCount: Int
    @Published private(set) var latestResponseLineLimit: Int
    @Published private(set) var subagentLatestResponseLineLimit: Int
    @Published private(set) var latestResponseHideAfterInterval: TimeInterval
    @Published private(set) var latestResponseCompactsBlankLines: Bool
    @Published private(set) var dropdownShowsUserPrompt: Bool
    @Published private(set) var showsSubagents: Bool
    @Published private(set) var subagentHideAfterInterval: TimeInterval
    @Published private(set) var hideAfterInterval: TimeInterval
    @Published private(set) var menuBarEnabled: Bool
    @Published private(set) var popupEnabled: Bool
    @Published private(set) var popupDisplayInterval: TimeInterval
    @Published private(set) var popupProviderVisibility: [String: Bool]
    @Published private(set) var popupGlassEnabled: Bool
    @Published private(set) var popupUsesClearGlass: Bool
    @Published private(set) var popupUsesColoredBorder: Bool
    @Published private(set) var popupGlassOpacity: Double
    @Published private(set) var popupOpacity: Double
    @Published private(set) var popupWindowPosition: PopupWindowPosition
    @Published private(set) var popupRightAlignsTextOnRightSide: Bool
    @Published private(set) var popupWindowWidth: Double
    @Published private(set) var popupOffsetX: Double
    @Published private(set) var popupOffsetY: Double
    @Published private(set) var popupScale: Double
    @Published private(set) var popupBackdropOpacity: Double
    @Published private(set) var popupTextOpacity: Double
    @Published private(set) var popupMouseProximityOpacity: Double
    @Published private(set) var popupTextShadowEnabled: Bool
    @Published private(set) var popupTextShadowStrength: Double
    @Published private(set) var popupTextShadowDistance: Double
    @Published private(set) var popupTextShadowRadius: Double
    @Published private(set) var popupParentSessionCount: Int
    @Published private(set) var popupShowsResponseBody: Bool
    @Published private(set) var popupResponseCharacterLimit: Int
    @Published private(set) var popupResponseLineLimit: Int
    @Published private(set) var popupResponseCompactsBlankLines: Bool
    @Published private(set) var popupResponseElidesShortFinalLine: Bool
    @Published private(set) var popupShowsUserPrompt: Bool

    private let defaults: UserDefaults
    private let storageKey = "ProviderPreferences"
    private let legacyVisibilityStorageKey = "ProviderVisibility"
    private static let deferredSaveDelayNanoseconds: UInt64 = 300_000_000
    private var deferredSaveTask: Task<Void, Never>?

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
        usesIndicatorLampStyle = document.usesIndicatorLampStyle
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(document.sessionDisplayCount)
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(document.latestResponseLineLimit)
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
            document.subagentLatestResponseLineLimit
        )
        latestResponseHideAfterInterval = ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
            document.latestResponseHideAfterInterval
        )
        latestResponseCompactsBlankLines = document.latestResponseCompactsBlankLines
        dropdownShowsUserPrompt = document.dropdownShowsUserPrompt
        showsSubagents = document.showsSubagents
        subagentHideAfterInterval = ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval)
        hideAfterInterval = ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval)
        menuBarEnabled = document.menuBarEnabled
        popupEnabled = document.popupEnabled
        popupDisplayInterval = ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(document.popupDisplayInterval)
        popupProviderVisibility = ProviderPreferencesDocument.sanitizedPopupProviderVisibility(document.popupProviderVisibility)
        popupGlassEnabled = document.popupGlassEnabled
        popupUsesClearGlass = document.popupUsesClearGlass
        popupUsesColoredBorder = document.popupUsesColoredBorder
        popupGlassOpacity = ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(document.popupGlassOpacity)
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(document.popupOpacity)
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(document.popupWindowPosition)
        popupRightAlignsTextOnRightSide = document.popupRightAlignsTextOnRightSide
        popupWindowWidth = ProviderPreferenceDefaults.sanitizedPopupWindowWidth(document.popupWindowWidth)
        popupOffsetX = ProviderPreferenceDefaults.sanitizedPopupOffset(document.popupOffsetX)
        popupOffsetY = ProviderPreferenceDefaults.sanitizedPopupOffset(document.popupOffsetY)
        popupScale = ProviderPreferenceDefaults.sanitizedPopupScale(document.popupScale)
        popupBackdropOpacity = ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(document.popupBackdropOpacity)
        popupTextOpacity = ProviderPreferenceDefaults.sanitizedPopupTextOpacity(document.popupTextOpacity)
        popupMouseProximityOpacity = ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(
            document.popupMouseProximityOpacity
        )
        popupTextShadowEnabled = document.popupTextShadowEnabled
        popupTextShadowStrength = ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(document.popupTextShadowStrength)
        popupTextShadowDistance = ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(document.popupTextShadowDistance)
        popupTextShadowRadius = ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(document.popupTextShadowRadius)
        popupParentSessionCount = ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(document.popupParentSessionCount)
        popupShowsResponseBody = document.popupShowsResponseBody
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(document.popupResponseCharacterLimit)
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(document.popupResponseLineLimit)
        popupResponseCompactsBlankLines = document.popupResponseCompactsBlankLines
        popupResponseElidesShortFinalLine = document.popupResponseElidesShortFinalLine
        popupShowsUserPrompt = document.popupShowsUserPrompt
        saveImmediately()
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

    func setUsesIndicatorLampStyle(_ usesIndicatorLamp: Bool) {
        usesIndicatorLampStyle = usesIndicatorLamp
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

    func setLatestResponseHideAfterInterval(_ interval: TimeInterval) {
        latestResponseHideAfterInterval = ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(interval)
        save()
    }

    func setLatestResponseCompactsBlankLines(_ compacts: Bool) {
        latestResponseCompactsBlankLines = compacts
        save()
    }

    func setDropdownShowsUserPrompt(_ shows: Bool) {
        dropdownShowsUserPrompt = shows
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

    func setMenuBarEnabled(_ isEnabled: Bool) {
        menuBarEnabled = isEnabled
        save()
    }

    func isPopupVisible(for agent: AgentKind) -> Bool {
        popupProviderVisibility[agent.rawValue] ?? true
    }

    var effectivePopupTextShadowStrength: Double {
        popupTextShadowEnabled ? ProviderPreferenceDefaults.popupTextShadowStrength : 0
    }

    var effectivePopupTextShadowDistance: Double {
        popupTextShadowEnabled ? ProviderPreferenceDefaults.popupTextShadowDistance : 0
    }

    var effectivePopupTextShadowRadius: Double {
        popupTextShadowEnabled ? ProviderPreferenceDefaults.popupTextShadowRadius : 0
    }

    fileprivate var popupVisualStyle: PopupVisualStyle {
        popupGlassEnabled ? .liquidGlass : .textDropShadow
    }

    func setPopupEnabled(_ isEnabled: Bool) {
        popupEnabled = isEnabled
        save()
    }

    func setPopupDisplayInterval(_ interval: TimeInterval) {
        popupDisplayInterval = ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(interval)
        save()
    }

    func setPopupVisible(_ isVisible: Bool, for agent: AgentKind) {
        var nextVisibility = popupProviderVisibility
        nextVisibility[agent.rawValue] = isVisible
        popupProviderVisibility = ProviderPreferencesDocument.sanitizedPopupProviderVisibility(nextVisibility)
        save()
    }

    func setPopupGlassEnabled(_ isEnabled: Bool) {
        let style = ProviderPreferenceDefaults.sanitizedPopupStyle(
            glassEnabled: isEnabled,
            textShadowEnabled: isEnabled ? false : popupTextShadowEnabled
        )
        popupGlassEnabled = style.glassEnabled
        popupTextShadowEnabled = style.textShadowEnabled
        save()
    }

    fileprivate func setPopupVisualStyle(_ visualStyle: PopupVisualStyle) {
        switch visualStyle {
        case .liquidGlass:
            setPopupGlassEnabled(true)
        case .textDropShadow:
            setPopupTextShadowEnabled(true)
        }
    }

    func setPopupUsesClearGlass(_ usesClearGlass: Bool) {
        popupUsesClearGlass = usesClearGlass
        save()
    }

    func setPopupUsesColoredBorder(_ usesColoredBorder: Bool) {
        popupUsesColoredBorder = usesColoredBorder
        save()
    }

    func setPopupGlassOpacity(_ opacity: Double) {
        popupGlassOpacity = ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(opacity)
        save()
    }

    func setPopupOpacity(_ opacity: Double) {
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(opacity)
        save()
    }

    func setPopupWindowPosition(_ position: PopupWindowPosition) {
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(position)
        save()
    }

    func setPopupRightAlignsTextOnRightSide(_ alignsText: Bool) {
        popupRightAlignsTextOnRightSide = alignsText
        save()
    }

    func setPopupWindowWidth(_ width: Double) {
        popupWindowWidth = ProviderPreferenceDefaults.sanitizedPopupWindowWidth(width)
        save()
    }

    func setPopupOffsetX(_ offset: Double) {
        popupOffsetX = ProviderPreferenceDefaults.sanitizedPopupOffset(offset)
        save()
    }

    func setPopupOffsetY(_ offset: Double) {
        popupOffsetY = ProviderPreferenceDefaults.sanitizedPopupOffset(offset)
        save()
    }

    func setPopupScale(_ scale: Double) {
        popupScale = ProviderPreferenceDefaults.sanitizedPopupScale(scale)
        save()
    }

    func setPopupBackdropOpacity(_ opacity: Double) {
        popupBackdropOpacity = ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(opacity)
        save()
    }

    func setPopupTextOpacity(_ opacity: Double) {
        popupTextOpacity = ProviderPreferenceDefaults.sanitizedPopupTextOpacity(opacity)
        save()
    }

    func setPopupMouseProximityOpacity(_ opacity: Double) {
        popupMouseProximityOpacity = ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(opacity)
        save()
    }

    func setPopupTextShadowEnabled(_ isEnabled: Bool) {
        let style = ProviderPreferenceDefaults.sanitizedPopupStyle(
            glassEnabled: isEnabled ? false : popupGlassEnabled,
            textShadowEnabled: isEnabled
        )
        popupGlassEnabled = style.glassEnabled
        popupTextShadowEnabled = style.textShadowEnabled
        save()
    }

    func setPopupTextShadowStrength(_ strength: Double) {
        popupTextShadowStrength = ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(strength)
        save()
    }

    func setPopupTextShadowDistance(_ distance: Double) {
        popupTextShadowDistance = ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(distance)
        save()
    }

    func setPopupTextShadowRadius(_ radius: Double) {
        popupTextShadowRadius = ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(radius)
        save()
    }

    func setPopupParentSessionCount(_ count: Int) {
        popupParentSessionCount = ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(count)
        save()
    }

    func setPopupShowsResponseBody(_ shows: Bool) {
        popupShowsResponseBody = shows
        save()
    }

    func setPopupShowsUserPrompt(_ shows: Bool) {
        popupShowsUserPrompt = shows
        save()
    }

    func setPopupResponseCharacterLimit(_ count: Int) {
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(count)
        save()
    }

    func setPopupResponseLineLimit(_ count: Int) {
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(count)
        save()
    }

    func setPopupResponseCompactsBlankLines(_ compacts: Bool) {
        popupResponseCompactsBlankLines = compacts
        save()
    }

    func setPopupResponseElidesShortFinalLine(_ elides: Bool) {
        popupResponseElidesShortFinalLine = elides
        save()
    }

    func resetPopupPreferences() {
        popupEnabled = ProviderPreferenceDefaults.popupEnabled
        popupDisplayInterval = ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(
            ProviderPreferenceDefaults.popupDisplayInterval
        )
        popupProviderVisibility = ProviderPreferencesDocument.defaultPopupProviderVisibility
        let popupStyle = ProviderPreferenceDefaults.sanitizedPopupStyle(
            glassEnabled: ProviderPreferenceDefaults.popupGlassEnabled,
            textShadowEnabled: ProviderPreferenceDefaults.popupTextShadowEnabled
        )
        popupGlassEnabled = popupStyle.glassEnabled
        popupUsesClearGlass = ProviderPreferenceDefaults.popupUsesClearGlass
        popupUsesColoredBorder = ProviderPreferenceDefaults.popupUsesColoredBorder
        popupGlassOpacity = ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(
            ProviderPreferenceDefaults.popupGlassOpacity
        )
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(ProviderPreferenceDefaults.popupOpacity)
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(
            ProviderPreferenceDefaults.popupWindowPosition
        )
        popupRightAlignsTextOnRightSide = ProviderPreferenceDefaults.popupRightAlignsTextOnRightSide
        popupWindowWidth = ProviderPreferenceDefaults.sanitizedPopupWindowWidth(
            ProviderPreferenceDefaults.popupWindowWidth
        )
        popupOffsetX = ProviderPreferenceDefaults.sanitizedPopupOffset(ProviderPreferenceDefaults.popupOffsetX)
        popupOffsetY = ProviderPreferenceDefaults.sanitizedPopupOffset(ProviderPreferenceDefaults.popupOffsetY)
        popupScale = ProviderPreferenceDefaults.sanitizedPopupScale(ProviderPreferenceDefaults.popupScale)
        popupBackdropOpacity = ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(
            ProviderPreferenceDefaults.popupBackdropOpacity
        )
        popupTextOpacity = ProviderPreferenceDefaults.sanitizedPopupTextOpacity(
            ProviderPreferenceDefaults.popupTextOpacity
        )
        popupMouseProximityOpacity = ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(
            ProviderPreferenceDefaults.popupMouseProximityOpacity
        )
        popupTextShadowEnabled = popupStyle.textShadowEnabled
        popupTextShadowStrength = ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(
            ProviderPreferenceDefaults.popupTextShadowStrength
        )
        popupTextShadowDistance = ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(
            ProviderPreferenceDefaults.popupTextShadowDistance
        )
        popupTextShadowRadius = ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(
            ProviderPreferenceDefaults.popupTextShadowRadius
        )
        popupParentSessionCount = ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(
            ProviderPreferenceDefaults.popupParentSessionCount
        )
        popupShowsUserPrompt = ProviderPreferenceDefaults.popupShowsUserPrompt
        popupShowsResponseBody = ProviderPreferenceDefaults.popupShowsResponseBody
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
            ProviderPreferenceDefaults.popupResponseCharacterLimit
        )
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(
            ProviderPreferenceDefaults.popupResponseLineLimit
        )
        popupResponseCompactsBlankLines = ProviderPreferenceDefaults.popupResponseCompactsBlankLines
        popupResponseElidesShortFinalLine = ProviderPreferenceDefaults.popupResponseElidesShortFinalLine
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

    func move(_ agent: AgentKind, by offset: Int, in placement: ProviderPlacement) {
        guard offset != 0 else {
            return
        }

        var order = orderIDs(for: placement)
        guard let index = order.firstIndex(of: agent.rawValue) else {
            return
        }

        let destination = index + offset
        guard order.indices.contains(destination) else {
            return
        }

        order.swapAt(index, destination)
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

    func flushPendingSave() {
        guard deferredSaveTask != nil else {
            return
        }

        deferredSaveTask?.cancel()
        deferredSaveTask = nil
        saveImmediately()
    }

    private func save() {
        deferredSaveTask?.cancel()
        deferredSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.deferredSaveDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            self?.saveImmediately()
            self?.deferredSaveTask = nil
        }
    }

    private func saveImmediately() {
        let document = ProviderPreferencesDocument(
            values: values,
            menuBarOrder: menuBarOrder,
            dropdownMenuOrder: dropdownMenuOrder,
            usesColorDropdownIcons: usesColorDropdownIcons,
            usesIndicatorLampStyle: usesIndicatorLampStyle,
            sessionDisplayCount: sessionDisplayCount,
            latestResponseLineLimit: latestResponseLineLimit,
            subagentLatestResponseLineLimit: subagentLatestResponseLineLimit,
            latestResponseHideAfterInterval: latestResponseHideAfterInterval,
            latestResponseCompactsBlankLines: latestResponseCompactsBlankLines,
            dropdownShowsUserPrompt: dropdownShowsUserPrompt,
            showsSubagents: showsSubagents,
            subagentHideAfterInterval: subagentHideAfterInterval,
            hideAfterInterval: hideAfterInterval,
            menuBarEnabled: menuBarEnabled,
            popupEnabled: popupEnabled,
            popupDisplayInterval: popupDisplayInterval,
            popupProviderVisibility: popupProviderVisibility,
            popupGlassEnabled: popupGlassEnabled,
            popupUsesClearGlass: popupUsesClearGlass,
            popupUsesColoredBorder: popupUsesColoredBorder,
            popupGlassOpacity: popupGlassOpacity,
            popupOpacity: popupOpacity,
            popupWindowPosition: popupWindowPosition,
            popupRightAlignsTextOnRightSide: popupRightAlignsTextOnRightSide,
            popupWindowWidth: popupWindowWidth,
            popupOffsetX: popupOffsetX,
            popupOffsetY: popupOffsetY,
            popupScale: popupScale,
            popupBackdropOpacity: popupBackdropOpacity,
            popupTextOpacity: popupTextOpacity,
            popupMouseProximityOpacity: popupMouseProximityOpacity,
            popupTextShadowEnabled: popupTextShadowEnabled,
            popupTextShadowStrength: popupTextShadowStrength,
            popupTextShadowDistance: popupTextShadowDistance,
            popupTextShadowRadius: popupTextShadowRadius,
            popupParentSessionCount: popupParentSessionCount,
            popupShowsUserPrompt: popupShowsUserPrompt,
            popupShowsResponseBody: popupShowsResponseBody,
            popupResponseCharacterLimit: popupResponseCharacterLimit,
            popupResponseLineLimit: popupResponseLineLimit,
            popupResponseCompactsBlankLines: popupResponseCompactsBlankLines,
            popupResponseElidesShortFinalLine: popupResponseElidesShortFinalLine
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
                usesIndicatorLampStyle: ProviderPreferenceDefaults.usesIndicatorLampStyle,
                sessionDisplayCount: ProviderPreferenceDefaults.sessionDisplayCount,
                latestResponseLineLimit: ProviderPreferenceDefaults.latestResponseLineLimit,
                subagentLatestResponseLineLimit: ProviderPreferenceDefaults.subagentLatestResponseLineLimit,
                latestResponseHideAfterInterval: ProviderPreferenceDefaults.latestResponseHideAfterInterval,
                latestResponseCompactsBlankLines: ProviderPreferenceDefaults.latestResponseCompactsBlankLines,
                dropdownShowsUserPrompt: ProviderPreferenceDefaults.dropdownShowsUserPrompt,
                showsSubagents: ProviderPreferenceDefaults.showsSubagents,
                subagentHideAfterInterval: ProviderPreferenceDefaults.subagentHideAfterInterval,
                hideAfterInterval: ProviderPreferenceDefaults.hideAfterInterval,
                menuBarEnabled: ProviderPreferenceDefaults.menuBarEnabled,
                popupEnabled: ProviderPreferenceDefaults.popupEnabled,
                popupDisplayInterval: ProviderPreferenceDefaults.popupDisplayInterval,
                popupProviderVisibility: ProviderPreferencesDocument.defaultPopupProviderVisibility,
                popupGlassEnabled: ProviderPreferenceDefaults.popupGlassEnabled,
                popupUsesClearGlass: ProviderPreferenceDefaults.popupUsesClearGlass,
                popupUsesColoredBorder: ProviderPreferenceDefaults.popupUsesColoredBorder,
                popupGlassOpacity: ProviderPreferenceDefaults.popupGlassOpacity,
                popupOpacity: ProviderPreferenceDefaults.popupOpacity,
                popupWindowPosition: ProviderPreferenceDefaults.popupWindowPosition,
                popupRightAlignsTextOnRightSide: ProviderPreferenceDefaults.popupRightAlignsTextOnRightSide,
                popupWindowWidth: ProviderPreferenceDefaults.popupWindowWidth,
                popupOffsetX: ProviderPreferenceDefaults.popupOffsetX,
                popupOffsetY: ProviderPreferenceDefaults.popupOffsetY,
                popupScale: ProviderPreferenceDefaults.popupScale,
                popupBackdropOpacity: ProviderPreferenceDefaults.popupBackdropOpacity,
                popupTextOpacity: ProviderPreferenceDefaults.popupTextOpacity,
                popupMouseProximityOpacity: ProviderPreferenceDefaults.popupMouseProximityOpacity,
                popupTextShadowEnabled: ProviderPreferenceDefaults.popupTextShadowEnabled,
                popupTextShadowStrength: ProviderPreferenceDefaults.popupTextShadowStrength,
                popupTextShadowDistance: ProviderPreferenceDefaults.popupTextShadowDistance,
                popupTextShadowRadius: ProviderPreferenceDefaults.popupTextShadowRadius,
                popupParentSessionCount: ProviderPreferenceDefaults.popupParentSessionCount,
                popupShowsUserPrompt: ProviderPreferenceDefaults.popupShowsUserPrompt,
                popupShowsResponseBody: ProviderPreferenceDefaults.popupShowsResponseBody,
                popupResponseCharacterLimit: ProviderPreferenceDefaults.popupResponseCharacterLimit,
                popupResponseLineLimit: ProviderPreferenceDefaults.popupResponseLineLimit,
                popupResponseCompactsBlankLines: ProviderPreferenceDefaults.popupResponseCompactsBlankLines,
                popupResponseElidesShortFinalLine: ProviderPreferenceDefaults.popupResponseElidesShortFinalLine
            )
        }

        return ProviderPreferencesDocument(
            values: document.values,
            menuBarOrder: sanitizedOrder(document.menuBarOrder),
            dropdownMenuOrder: sanitizedOrder(document.dropdownMenuOrder),
            usesColorDropdownIcons: document.usesColorDropdownIcons,
            usesIndicatorLampStyle: document.usesIndicatorLampStyle,
            sessionDisplayCount: ProviderPreferenceDefaults.sanitizedSessionDisplayCount(document.sessionDisplayCount),
            latestResponseLineLimit: ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(document.latestResponseLineLimit),
            subagentLatestResponseLineLimit: ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
                document.subagentLatestResponseLineLimit
            ),
            latestResponseHideAfterInterval: ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
                document.latestResponseHideAfterInterval
            ),
            latestResponseCompactsBlankLines: document.latestResponseCompactsBlankLines,
            dropdownShowsUserPrompt: document.dropdownShowsUserPrompt,
            showsSubagents: document.showsSubagents,
            subagentHideAfterInterval: ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval),
            hideAfterInterval: ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval),
            menuBarEnabled: document.menuBarEnabled,
            popupEnabled: document.popupEnabled,
            popupDisplayInterval: ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(document.popupDisplayInterval),
            popupProviderVisibility: ProviderPreferencesDocument.sanitizedPopupProviderVisibility(document.popupProviderVisibility),
            popupGlassEnabled: document.popupGlassEnabled,
            popupUsesClearGlass: document.popupUsesClearGlass,
            popupUsesColoredBorder: document.popupUsesColoredBorder,
            popupGlassOpacity: ProviderPreferenceDefaults.sanitizedPopupGlassOpacity(document.popupGlassOpacity),
            popupOpacity: ProviderPreferenceDefaults.sanitizedPopupOpacity(document.popupOpacity),
            popupWindowPosition: ProviderPreferenceDefaults.sanitizedPopupWindowPosition(document.popupWindowPosition),
            popupRightAlignsTextOnRightSide: document.popupRightAlignsTextOnRightSide,
            popupWindowWidth: ProviderPreferenceDefaults.sanitizedPopupWindowWidth(document.popupWindowWidth),
            popupOffsetX: ProviderPreferenceDefaults.sanitizedPopupOffset(document.popupOffsetX),
            popupOffsetY: ProviderPreferenceDefaults.sanitizedPopupOffset(document.popupOffsetY),
            popupScale: ProviderPreferenceDefaults.sanitizedPopupScale(document.popupScale),
            popupBackdropOpacity: ProviderPreferenceDefaults.sanitizedPopupBackdropOpacity(document.popupBackdropOpacity),
            popupTextOpacity: ProviderPreferenceDefaults.sanitizedPopupTextOpacity(document.popupTextOpacity),
            popupMouseProximityOpacity: ProviderPreferenceDefaults.sanitizedPopupMouseProximityOpacity(
                document.popupMouseProximityOpacity
            ),
            popupTextShadowEnabled: document.popupTextShadowEnabled,
            popupTextShadowStrength: ProviderPreferenceDefaults.sanitizedPopupTextShadowStrength(document.popupTextShadowStrength),
            popupTextShadowDistance: ProviderPreferenceDefaults.sanitizedPopupTextShadowDistance(document.popupTextShadowDistance),
            popupTextShadowRadius: ProviderPreferenceDefaults.sanitizedPopupTextShadowRadius(document.popupTextShadowRadius),
            popupParentSessionCount: ProviderPreferenceDefaults.sanitizedPopupParentSessionCount(document.popupParentSessionCount),
            popupShowsUserPrompt: document.popupShowsUserPrompt,
            popupShowsResponseBody: document.popupShowsResponseBody,
            popupResponseCharacterLimit: ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
                document.popupResponseCharacterLimit
            ),
            popupResponseLineLimit: ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(
                document.popupResponseLineLimit
            ),
            popupResponseCompactsBlankLines: document.popupResponseCompactsBlankLines,
            popupResponseElidesShortFinalLine: document.popupResponseElidesShortFinalLine
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
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(section: section)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .contentMargins(.top, 6, for: .scrollContent)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            SettingsDetailView(section: selectedSection, providerVisibility: providerVisibility)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accentColor)
        .frame(
            minWidth: 760,
            idealWidth: 820,
            maxWidth: .infinity,
            minHeight: 440,
            idealHeight: 620,
            maxHeight: .infinity
        )
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case dropdownMenu
    case popup
    case menuBar

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .dropdownMenu:
            "Dropdown Menu"
        case .popup:
            "Popup"
        case .menuBar:
            "Menubar"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .dropdownMenu:
            "list.bullet.rectangle"
        case .popup:
            "macwindow.on.rectangle"
        case .menuBar:
            "menubar.rectangle"
        }
    }

    var accent: Color {
        switch self {
        case .general:
            Color(nsColor: .secondaryLabelColor)
        case .dropdownMenu:
            Theme.accentColor
        case .popup:
            Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255)
        case .menuBar:
            Color(red: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255)
        }
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        } icon: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(section.accent.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: section.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(section.accent)
                )
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsDetailView: View {
    let section: SettingsSection
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        switch section {
        case .general:
            GeneralSettingsView()
        case .dropdownMenu:
            DropdownMenuSettingsView(providerVisibility: providerVisibility)
        case .popup:
            PopupSettingsView(providerVisibility: providerVisibility)
        case .menuBar:
            MenuBarSettingsView(providerVisibility: providerVisibility)
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let title: String
    var showsTitle = true
    private let content: Content

    init(title: String, showsTitle: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsTitle = showsTitle
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(showsTitle ? title : "")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    static let shared = LaunchAtLoginStore()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Off."

    private init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        statusText = Self.statusText(for: status)
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        var errorText: String?

        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            errorText = error.localizedDescription
        }

        refresh()
        if let errorText {
            statusText = errorText
        }
    }

    private static func statusText(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            "Enabled."
        case .requiresApproval:
            "Waiting for approval in Login Items."
        case .notRegistered:
            "Off."
        case .notFound:
            "Open the bundled Agent Sessions.app to manage this setting."
        @unknown default:
            "Unavailable."
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var launchAtLogin = LaunchAtLoginStore.shared
    @ObservedObject private var keyboardShortcuts = KeyboardShortcutStore.shared
    @ObservedObject private var providerVisibility = ProviderVisibilityStore.shared

    var body: some View {
        SettingsForm(title: SettingsSection.general.title) {
            SettingsGroupBox(
                title: "Startup",
                subtitle: "Launch behavior for Agent Sessions."
            ) {
                SettingsToggleRow(
                    title: "Launch at Login",
                    subtitle: launchAtLogin.statusText,
                    isOn: Binding(
                        get: {
                            launchAtLogin.isEnabled
                        },
                        set: { isEnabled in
                            launchAtLogin.setEnabled(isEnabled)
                        }
                    )
                )
            }

            SettingsGroupBox(
                title: "Appearance",
                subtitle: "Provider branding in the menu bar, drop-down menu, and popup."
            ) {
                SettingsToggleRow(
                    title: "Indicator Lamp Style",
                    subtitle: "Replace provider logos with brand-colored indicator lamps and shorten names to Codex / Claude.",
                    isOn: Binding(
                        get: {
                            providerVisibility.usesIndicatorLampStyle
                        },
                        set: { usesIndicatorLamp in
                            providerVisibility.setUsesIndicatorLampStyle(usesIndicatorLamp)
                        }
                    )
                )
            }

            SettingsGroupBox(
                title: "Keyboard Shortcuts",
                subtitle: keyboardShortcuts.popupToggleStatusText
            ) {
                SettingsKeyboardShortcutRow(
                    title: "Toggle Popup",
                    subtitle: "Global shortcut for switching Popup on or off.",
                    shortcut: keyboardShortcuts.popupToggleShortcut,
                    setShortcut: { shortcut in
                        keyboardShortcuts.setPopupToggleShortcut(shortcut)
                    },
                    clearShortcut: {
                        keyboardShortcuts.clearPopupToggleShortcut()
                    }
                )
            }

            SettingsGroupBox(
                title: "Application",
                subtitle: "App-level actions for Agent Sessions."
            ) {
                HStack(alignment: .center, spacing: 16) {
                    SettingsRowLabel(
                        title: "Quit",
                        subtitle: "Close Agent Sessions."
                    )

                    Spacer()

                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit Agent Sessions", systemImage: "power")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Quit Agent Sessions")
                }
                .padding(.vertical, 5)
            }
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }
}

private struct DropdownMenuSettingsView: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        SettingsForm(title: SettingsSection.dropdownMenu.title) {
            ProviderPlacementCard(
                placement: .dropdownMenu,
                providerVisibility: providerVisibility,
                title: "Providers",
                subtitle: "Provider order and visibility in the drop-down menu."
            )

            SettingsGroupBox(
                title: "Sessions",
                subtitle: "Parent rows shown in the menu."
            ) {
                SettingsStepperRow(
                    title: "Count",
                    subtitle: "Maximum parent sessions shown per provider.",
                    value: providerVisibility.sessionDisplayCount,
                    range: 3...10
                ) { count in
                    providerVisibility.setSessionDisplayCount(count)
                }

                SettingsDivider()

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

            SettingsGroupBox(
                title: "Response Body",
                subtitle: "Preview text shown below each session title."
            ) {
                SettingsToggleRow(
                    title: "User Prompt",
                    subtitle: "Show the latest user prompt below each session title.",
                    isOn: Binding(
                        get: {
                            providerVisibility.dropdownShowsUserPrompt
                        },
                        set: { showsUserPrompt in
                            providerVisibility.setDropdownShowsUserPrompt(showsUserPrompt)
                        }
                    )
                )

                SettingsDivider()

                SettingsStepperRow(
                    title: "Lines",
                    subtitle: "Maximum lines shown below each session title.",
                    value: providerVisibility.latestResponseLineLimit,
                    range: 1...5
                ) { count in
                    providerVisibility.setLatestResponseLineLimit(count)
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "Compact Blank Lines",
                    subtitle: "Remove response body lines that contain only whitespace.",
                    isOn: Binding(
                        get: {
                            providerVisibility.latestResponseCompactsBlankLines
                        },
                        set: { compactsBlankLines in
                            providerVisibility.setLatestResponseCompactsBlankLines(compactsBlankLines)
                        }
                    )
                )

                SettingsDivider()

                SettingsPickerRow(
                    title: "Hide After",
                    subtitle: "Hide response text after this interval.",
                    selection: Binding(
                        get: {
                            providerVisibility.latestResponseHideAfterInterval
                        },
                        set: { interval in
                            providerVisibility.setLatestResponseHideAfterInterval(interval)
                        }
                    ),
                    options: ProviderPreferenceDefaults.latestResponseHideAfterOptions,
                    labelProvider: ProviderPreferenceDefaults.latestResponseHideAfterLabel
                )
            }

            SettingsGroupBox(
                title: "Sub-agents",
                subtitle: "Nested session rows in the menu."
            ) {
                SettingsToggleRow(
                    title: "Show",
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

                SettingsDivider()

                SettingsStepperRow(
                    title: "Lines",
                    subtitle: "Maximum response lines shown for sub-agent rows.",
                    value: providerVisibility.subagentLatestResponseLineLimit,
                    range: 1...5
                ) { count in
                    providerVisibility.setSubagentLatestResponseLineLimit(count)
                }

                SettingsDivider()

                SettingsPickerRow(
                    title: "Hide After",
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
            }
        }
    }
}

private struct PopupSettingsView: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        SettingsForm(title: SettingsSection.popup.title, showsTitle: false) {
            SettingsGroupBox(
                title: "Display",
                subtitle: "Turn the popup window on or off."
            ) {
                SettingsToggleRow(
                    title: "Enable",
                    subtitle: "Show the latest parent session above other windows.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupEnabled
                        },
                        set: { isEnabled in
                            providerVisibility.setPopupEnabled(isEnabled)
                        }
                    )
                )
            }

            PopupProviderSettingsGroup(providerVisibility: providerVisibility)

            PopupStyleSettingsGroup(providerVisibility: providerVisibility)

            SettingsGroupBox(
                title: "Appearance",
                subtitle: "Popup content, position, size, and opacity."
            ) {
                SettingsStepperRow(
                    title: "Hide After Idle",
                    subtitle: "Hide this many seconds after the parent session becomes idle.",
                    value: Int(providerVisibility.popupDisplayInterval),
                    range: 1...60,
                    labelSuffix: "s"
                ) { count in
                    providerVisibility.setPopupDisplayInterval(TimeInterval(count))
                }
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsStepperRow(
                    title: "Sessions",
                    subtitle: "Maximum recent parent sessions shown in the popup.",
                    value: providerVisibility.popupParentSessionCount,
                    range: 1...10
                ) { count in
                    providerVisibility.setPopupParentSessionCount(count)
                }
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "User Prompt",
                    subtitle: "Show the latest user prompt below each popup session title.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupShowsUserPrompt
                        },
                        set: { showsUserPrompt in
                            providerVisibility.setPopupShowsUserPrompt(showsUserPrompt)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Response Body",
                    subtitle: "Show response text below each popup session title.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupShowsResponseBody
                        },
                        set: { showsResponseBody in
                            providerVisibility.setPopupShowsResponseBody(showsResponseBody)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Compact Blank Lines",
                    subtitle: "Remove response body lines that contain only whitespace.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupResponseCompactsBlankLines
                        },
                        set: { compactsBlankLines in
                            providerVisibility.setPopupResponseCompactsBlankLines(compactsBlankLines)
                        }
                    )
                )
                .disabled(!responseBodyControlsEnabled)
                .opacity(responseBodyControlsEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Short Last Line",
                    subtitle: "If the final wrapped response line has 5 or fewer characters, omit it and end the previous line with ...",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupResponseElidesShortFinalLine
                        },
                        set: { elidesShortFinalLine in
                            providerVisibility.setPopupResponseElidesShortFinalLine(elidesShortFinalLine)
                        }
                    )
                )
                .disabled(!responseBodyControlsEnabled)
                .opacity(responseBodyControlsEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsStepperRow(
                    title: "Characters",
                    subtitle: "Maximum response body characters per popup session.",
                    value: providerVisibility.popupResponseCharacterLimit,
                    range: 40...1000,
                    step: 10,
                    labelSuffix: "ch",
                    labelWidth: 62
                ) { count in
                    providerVisibility.setPopupResponseCharacterLimit(count)
                }
                .disabled(!responseBodyControlsEnabled)
                .opacity(responseBodyControlsEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsStepperRow(
                    title: "Lines",
                    subtitle: "Maximum response body lines per popup session.",
                    value: providerVisibility.popupResponseLineLimit,
                    range: 1...30,
                    labelSuffix: "ln",
                    labelWidth: 40
                ) { count in
                    providerVisibility.setPopupResponseLineLimit(count)
                }
                .disabled(!responseBodyControlsEnabled)
                .opacity(responseBodyControlsEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsEnumPickerRow(
                    title: "Window",
                    subtitle: "Place the popup on the current main screen.",
                    selection: Binding(
                        get: {
                            providerVisibility.popupWindowPosition
                        },
                        set: { position in
                            providerVisibility.setPopupWindowPosition(position)
                        }
                    ),
                    options: PopupWindowPosition.allCases
                ) { position in
                    position.title
                }
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsStepperRow(
                    title: "Offset X",
                    subtitle: "Move the popup horizontally from its selected position.",
                    value: Int(providerVisibility.popupOffsetX),
                    range: -500...500,
                    step: 5,
                    labelSuffix: "px",
                    labelWidth: 58
                ) { offset in
                    providerVisibility.setPopupOffsetX(Double(offset))
                }
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsStepperRow(
                    title: "Offset Y",
                    subtitle: "Move the popup vertically from its selected position.",
                    value: Int(providerVisibility.popupOffsetY),
                    range: -500...500,
                    step: 5,
                    labelSuffix: "px",
                    labelWidth: 58
                ) { offset in
                    providerVisibility.setPopupOffsetY(Double(offset))
                }
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Right Align Text",
                    subtitle: "Only applies when Window is Top Right or Bottom Right.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupRightAlignsTextOnRightSide
                        },
                        set: { alignsText in
                            providerVisibility.setPopupRightAlignsTextOnRightSide(alignsText)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsSliderRow(
                    title: "Width",
                    subtitle: "Adjust popup window width.",
                    value: Binding(
                        get: {
                            providerVisibility.popupWindowWidth
                        },
                        set: { width in
                            providerVisibility.setPopupWindowWidth(width)
                        }
                    ),
                    range: 200...800,
                    label: "\(Int(providerVisibility.popupWindowWidth))px"
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsSliderRow(
                    title: "Size",
                    subtitle: "Scale the whole popup window.",
                    value: Binding(
                        get: {
                            providerVisibility.popupScale
                        },
                        set: { scale in
                            providerVisibility.setPopupScale(scale)
                        }
                    ),
                    range: 0.5...1.5,
                    label: "\(Int(providerVisibility.popupScale * 100))%"
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsSliderRow(
                    title: "Opacity",
                    subtitle: "Adjust the entire popup window opacity.",
                    value: Binding(
                        get: {
                            providerVisibility.popupOpacity
                        },
                        set: { opacity in
                            providerVisibility.setPopupOpacity(opacity)
                        }
                    ),
                    range: 0...1,
                    label: "\(Int(providerVisibility.popupOpacity * 100))%"
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsSliderRow(
                    title: "Cursor Near Opacity",
                    subtitle: "Set popup opacity while the cursor is near it.",
                    value: Binding(
                        get: {
                            providerVisibility.popupMouseProximityOpacity
                        },
                        set: { opacity in
                            providerVisibility.setPopupMouseProximityOpacity(opacity)
                        }
                    ),
                    range: 0...1,
                    label: "\(Int(providerVisibility.popupMouseProximityOpacity * 100))%"
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)
            }

            SettingsGroupBox(
                title: "Reset",
                subtitle: "Restore popup settings to their defaults."
            ) {
                Button {
                    providerVisibility.resetPopupPreferences()
                } label: {
                    Label("Reset to default", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Reset popup settings")
            }
        }
    }

    private var responseBodyControlsEnabled: Bool {
        providerVisibility.popupEnabled && providerVisibility.popupShowsResponseBody
    }

}

private struct PopupStyleSettingsGroup: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        SettingsGroupBox(
            title: "Style",
            subtitle: "Choose one popup visual treatment."
        ) {
            HStack(spacing: 10) {
                ForEach(PopupVisualStyle.allCases) { style in
                    SettingsStyleChoiceButton(
                        title: style.title,
                        systemImage: style.systemImageName,
                        isSelected: providerVisibility.popupVisualStyle == style
                    ) {
                        providerVisibility.setPopupVisualStyle(style)
                    }
                }
            }
            .disabled(!providerVisibility.popupEnabled)
            .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

            if providerVisibility.popupVisualStyle == .liquidGlass {
                SettingsDivider()

                SettingsToggleRow(
                    title: "Clear Glass",
                    subtitle: "Use the clear Liquid Glass material instead of regular.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupUsesClearGlass
                        },
                        set: { usesClearGlass in
                            providerVisibility.setPopupUsesClearGlass(usesClearGlass)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Colored Border",
                    subtitle: "Show provider color on every Liquid Glass popup border.",
                    isOn: Binding(
                        get: {
                            providerVisibility.popupUsesColoredBorder
                        },
                        set: { usesColoredBorder in
                            providerVisibility.setPopupUsesColoredBorder(usesColoredBorder)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)

                SettingsDivider()

                SettingsSliderRow(
                    title: "Liquid Glass Opacity",
                    subtitle: "Adjust the Liquid Glass background opacity.",
                    value: Binding(
                        get: {
                            providerVisibility.popupGlassOpacity
                        },
                        set: { opacity in
                            providerVisibility.setPopupGlassOpacity(opacity)
                        }
                    ),
                    range: 0...1,
                    label: "\(Int(providerVisibility.popupGlassOpacity * 100))%"
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)
            }
        }
    }
}

private struct SettingsStyleChoiceButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            }
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
    }
}

private struct ProviderSettingsRow: View {
    let agent: AgentKind
    let subtitle: String
    @Binding var isVisible: Bool
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    var canMoveUp = false
    var canMoveDown = false
    @ObservedObject private var providerVisibility = ProviderVisibilityStore.shared

    var body: some View {
        HStack(spacing: 12) {
            AgentIndicatorLampView(
                agent: agent,
                state: .working,
                iconSize: 12,
                animatesWorkingLamp: false
            )
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(providerVisibility.usesIndicatorLampStyle ? agent.shortDisplayName : agent.providerSettingsTitle)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer()

            Toggle("", isOn: $isVisible)
                .toggleStyle(.switch)
                .labelsHidden()

            if moveUp != nil || moveDown != nil {
                HStack(spacing: 2) {
                    Button {
                        moveUp?()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!canMoveUp)
                    .help("Move up")

                    Button {
                        moveDown?()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!canMoveDown)
                    .help("Move down")
                }
                .frame(width: 54, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MenuBarSettingsView: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        SettingsForm(title: SettingsSection.menuBar.title) {
            SettingsGroupBox(
                title: "Display",
                subtitle: "Control whether Agent Sessions appears in the menu bar."
            ) {
                SettingsToggleRow(
                    title: "Enable",
                    subtitle: "Show Agent Sessions in the menu bar.",
                    isOn: Binding(
                        get: {
                            providerVisibility.menuBarEnabled
                        },
                        set: { isEnabled in
                            providerVisibility.setMenuBarEnabled(isEnabled)
                        }
                    )
                )

                if !providerVisibility.menuBarEnabled {
                    SettingsDivider()

                    SettingsWarningRow(
                        text: "Menu bar access is hidden while this is off. Open Agent Sessions.app again while it is running to show Settings."
                    )
                }
            }

            ProviderPlacementCard(
                placement: .menuBar,
                providerVisibility: providerVisibility,
                title: "Providers",
                subtitle: "Choose providers that appear as menu bar icons."
            )
            .disabled(!providerVisibility.menuBarEnabled)
            .opacity(providerVisibility.menuBarEnabled ? 1 : 0.55)
        }
    }
}

private struct PopupProviderSettingsGroup: View {
    @ObservedObject var providerVisibility: ProviderVisibilityStore

    var body: some View {
        SettingsGroupBox(
            title: "Providers",
            subtitle: "Choose providers that can appear in the popup."
        ) {
            ForEach(AgentKind.allCases, id: \.rawValue) { agent in
                ProviderSettingsRow(
                    agent: agent,
                    subtitle: "Allow this provider in the popup.",
                    isVisible: Binding(
                        get: {
                            providerVisibility.isPopupVisible(for: agent)
                        },
                        set: { isVisible in
                            providerVisibility.setPopupVisible(isVisible, for: agent)
                        }
                    )
                )
                .disabled(!providerVisibility.popupEnabled)
                .opacity(providerVisibility.popupEnabled ? 1 : 0.55)
            }
        }
    }
}

private struct ProviderPlacementCard: View {
    let placement: ProviderPlacement
    @ObservedObject var providerVisibility: ProviderVisibilityStore
    let title: String
    let subtitle: String

    init(
        placement: ProviderPlacement,
        providerVisibility: ProviderVisibilityStore,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.placement = placement
        self.providerVisibility = providerVisibility
        self.title = title ?? placement.title
        self.subtitle = subtitle ?? placement.helperText
    }

    var body: some View {
        let agents = providerVisibility.orderedAgents(for: placement)

        SettingsGroupBox(
            title: title,
            subtitle: subtitle
        ) {
            ForEach(agents, id: \.rawValue) { agent in
                let index = agents.firstIndex(of: agent) ?? 0

                ProviderSettingsRow(
                    agent: agent,
                    subtitle: subtitle(for: placement),
                    isVisible: Binding(
                        get: {
                            providerVisibility.isVisible(agent, in: placement)
                        },
                        set: { isVisible in
                            providerVisibility.setVisible(isVisible, for: agent, in: placement)
                        }
                    ),
                    moveUp: placement.supportsReordering ? {
                        providerVisibility.move(agent, by: -1, in: placement)
                    } : nil,
                    moveDown: placement.supportsReordering ? {
                        providerVisibility.move(agent, by: 1, in: placement)
                    } : nil,
                    canMoveUp: placement.supportsReordering && index > 0,
                    canMoveDown: placement.supportsReordering && index < agents.count - 1
                )
            }
        }
    }

    private func subtitle(for placement: ProviderPlacement) -> String {
        switch placement {
        case .menuBar:
            "Show this provider in the menu bar."
        case .dropdownMenu:
            "Show this provider in the drop-down menu."
        }
    }
}

private struct SettingsGroupBox<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
                .font(.headline)
                .textCase(nil)
        } footer: {
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        EmptyView()
    }
}

private struct SettingsWarningRow: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsKeyboardShortcutRow: View {
    let title: String
    let subtitle: String
    let shortcut: PopupToggleKeyboardShortcut?
    let setShortcut: (PopupToggleKeyboardShortcut) -> Void
    let clearShortcut: () -> Void
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")

                        if isRecording {
                            Text("Press shortcut")
                        } else if let shortcut {
                            KeyboardShortcutDisplay(shortcut: shortcut)
                        } else {
                            Text("None")
                        }
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Record keyboard shortcut")

                Button {
                    clearShortcut()
                    stopRecording()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .help("Clear keyboard shortcut")
                .disabled(shortcut == nil && !isRecording)
            }
            .fixedSize()
        }
        .padding(.vertical, 5)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let modifierFlags = PopupToggleKeyboardShortcut.supportedModifierFlags(from: event.modifierFlags)

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        if event.keyCode == UInt16(kVK_Delete), modifierFlags.isEmpty {
            clearShortcut()
            stopRecording()
            return
        }

        guard let shortcut = PopupToggleKeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }

        setShortcut(shortcut)
        stopRecording()
    }
}

private struct KeyboardShortcutDisplay: View {
    let shortcut: PopupToggleKeyboardShortcut

    var body: some View {
        HStack(spacing: 2) {
            ForEach(shortcut.modifierSymbols) { symbol in
                Image(systemName: symbol.systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel(symbol.accessibilityLabel)
            }

            Text(shortcut.keyDisplay)
                .font(.system(size: 13, weight: .medium))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.displayText)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct SettingsStepperRow: View {
    let title: String
    let subtitle: String
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var labelSuffix: String = ""
    var labelWidth: CGFloat = 28
    let onChange: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            HStack(spacing: 8) {
                Text("\(value)\(labelSuffix)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: labelWidth, alignment: .trailing)

                Stepper("", value: Binding(
                    get: {
                        value
                    },
                    set: { nextValue in
                        onChange(nextValue)
                    }
                ), in: range, step: max(step, 1))
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: TimeInterval
    let options: [TimeInterval]
    let labelProvider: (TimeInterval) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { interval in
                    Text(labelProvider(interval))
                        .tag(interval)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsEnumPickerRow<Value: Hashable>: View {
    let title: String
    let subtitle: String
    @Binding var selection: Value
    let options: [Value]
    let labelProvider: (Value) -> String

    init(
        title: String,
        subtitle: String,
        selection: Binding<Value>,
        options: [Value],
        labelProvider: @escaping (Value) -> String
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.options = options
        self.labelProvider = labelProvider
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(labelProvider(option))
                        .tag(option)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 170)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 5)
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowLabel(title: title, subtitle: subtitle)

            Spacer()

            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(width: 170)

                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
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
        window.toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("AgentSessionsSettingsToolbar"))
        window.toolbar = toolbar
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 440)
        window.setContentSize(NSSize(width: 820, height: 620))

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
    private var popupController: SessionPopupController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = AppController()
        self.controller = controller
        statusMenuController = StatusMenuController(controller: controller)
        popupController = SessionPopupController(controller: controller)
        KeyboardShortcutStore.shared.configurePopupToggleAction {
            Task { @MainActor in
                let providerVisibility = ProviderVisibilityStore.shared
                providerVisibility.setPopupEnabled(!providerVisibility.popupEnabled)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.open()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProviderVisibilityStore.shared.flushPendingSave()
        controller?.store.flushPersist()
    }
}

private extension AgentEvent {
    func settingUpdatedAtIfMissing(_ date: Date) -> AgentEvent {
        guard updatedAt == nil else {
            return self
        }

        var event = self
        event.updatedAt = date
        return event
    }

    func replacingLatestResponse(
        text: String,
        phase: String?,
        transcriptPath: String? = nil
    ) -> AgentEvent {
        var event = self
        event.transcriptPath = transcriptPath ?? self.transcriptPath
        event.latestResponseText = text
        event.latestResponsePhase = phase
        return event
    }
}

private enum ClaudeLatestResponseResolver {
    static func latestResponse(
        for sessionId: String,
        transcriptPath: String?,
        afterUserPrompt expectedUserPrompt: String? = nil
    ) -> (text: String, transcriptPath: String)? {
        guard let transcriptPath = resolvedTranscriptPath(sessionId: sessionId, transcriptPath: transcriptPath),
              let text = SessionFileTextReader.tailText(from: URL(fileURLWithPath: transcriptPath)),
              let latestResponseText = ClaudeSessionParser.latestAssistantResponseText(
                  fromTranscript: text,
                  afterUserPrompt: expectedUserPrompt
              ) else {
            return nil
        }

        return (latestResponseText, transcriptPath)
    }

    private static func resolvedTranscriptPath(sessionId: String, transcriptPath: String?) -> String? {
        if let path = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        return ClaudeSessionTitleResolver.transcriptPath(for: sessionId)
    }
}

private enum AgentEventEnricher {
    static func enrichedEvent(for event: AgentEvent) -> AgentEvent {
        let responseEvent = eventWithLatestResponse(event)
        let enrichedEvent = eventWithClaudeSubagentMetadata(responseEvent)
        return eventWithResolvedTitle(enrichedEvent)
    }

    static func shouldHideImmediately(_ event: AgentEvent) -> Bool {
        guard hasUsableSessionIdentity(sessionId: event.sessionId, cwd: event.cwd) else {
            return true
        }

        switch event.agent {
        case .codex:
            return AgentSessionVisibility.isCodexMemoryWorkspace(agent: .codex, cwd: event.cwd)
                || AgentSessionVisibility.isCodexInternalSuggestion(
                    agent: .codex,
                    title: event.title,
                    latestResponseText: event.latestResponseText
                )
        case .claudeCode:
            return !event.isSubagent && isClaudeProbeSession(cwd: event.cwd, title: event.title)
        }
    }

    static func shouldHide(_ event: AgentEvent) -> Bool {
        switch event.agent {
        case .codex:
            shouldHideCodexSession(
                sessionId: event.sessionId,
                state: event.state,
                title: event.title,
                cwd: event.cwd,
                event: event.event,
                latestResponseText: event.latestResponseText,
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

    private static func eventWithLatestResponse(_ event: AgentEvent) -> AgentEvent {
        switch event.agent {
        case .codex:
            return eventWithCodexLatestResponse(event)
        case .claudeCode:
            return eventWithClaudeLatestResponse(event)
        }
    }

    private static func eventWithCodexLatestResponse(_ event: AgentEvent) -> AgentEvent {
        guard shouldBackfillLatestResponse(for: event),
              let latestResponse = CodexSessionWatcher.latestResponse(
                  for: event.sessionId,
                  afterUserPrompt: event.latestUserPrompt
              ) else {
            return event
        }

        return event.replacingLatestResponse(text: latestResponse.text, phase: latestResponse.phase)
    }

    private static func eventWithClaudeLatestResponse(_ event: AgentEvent) -> AgentEvent {
        guard shouldBackfillLatestResponse(for: event),
              let latestResponse = ClaudeLatestResponseResolver.latestResponse(
                  for: event.sessionId,
                  transcriptPath: event.transcriptPath,
                  afterUserPrompt: event.latestUserPrompt
              ) else {
            return event
        }

        return event.replacingLatestResponse(
            text: latestResponse.text,
            phase: "assistant",
            transcriptPath: latestResponse.transcriptPath
        )
    }

    private static func shouldBackfillLatestResponse(for event: AgentEvent) -> Bool {
        event.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && !event.state.isActive
            && event.event != "UserPromptSubmit"
            && event.event != "user_message"
    }

    private static func eventWithClaudeSubagentMetadata(_ event: AgentEvent) -> AgentEvent {
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
            latestUserPrompt: event.latestUserPrompt,
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
        )
    }

    private static func eventWithResolvedTitle(_ event: AgentEvent) -> AgentEvent {
        guard !AgentCompactionStatus.hasMatchingDisplayTitle(event: event.event, title: event.title) else {
            return event
        }

        let title = resolvedTitle(for: event)
            ?? (event.agent == .claudeCode ? fallbackTitle(for: event) : event.title)

        guard title != event.title else {
            return event
        }

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
            latestUserPrompt: event.latestUserPrompt,
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
        )
    }

    private static func resolvedTitle(for event: AgentEvent) -> String? {
        switch event.agent {
        case .codex:
            return CodexSessionWatcher.title(for: event.sessionId)
        case .claudeCode:
            return ClaudeSessionTitleResolver.title(for: event.sessionId, transcriptPath: event.transcriptPath)
        }
    }

    static func shouldHideCodexSession(
        sessionId: String,
        state: AgentState,
        title: String,
        cwd: String,
        event: String,
        latestResponseText: String?,
        allowsUnresolvedLiveSession: Bool
    ) -> Bool {
        if AgentSessionVisibility.isCodexInternalSuggestion(
            agent: .codex,
            title: title,
            latestResponseText: latestResponseText
        ) {
            return true
        }

        if AgentSessionVisibility.isCodexUnresolvedToolEvent(
            agent: .codex,
            title: title,
            event: event,
            latestResponseText: latestResponseText
        ),
           CodexSessionWatcher.title(for: sessionId) == nil {
            return true
        }

        switch CodexSessionWatcher.fileStatus(for: sessionId) {
        case .active:
            break
        case .archived:
            return true
        case .missing:
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

    private static func shouldKeepUnresolvedCodexSession(
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

    static func shouldHideClaudeSession(
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

    private static func shouldKeepUnresolvedClaudeSession(
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

    private static func hasUsableSessionIdentity(sessionId: String, cwd: String) -> Bool {
        let trimmedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionId.isEmpty else {
            return false
        }

        if trimmedSessionId != "default" {
            return true
        }

        return !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isClaudeProbeSession(cwd: String, title: String) -> Bool {
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

    private static func fallbackTitle(for event: AgentEvent) -> String {
        if event.agent == .codex {
            return event.title
        }
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        guard !event.isSubagent else {
            return event.title
        }

        return fallbackTitle(cwd: event.cwd, sessionId: event.sessionId)
    }

    static func fallbackTitle(cwd: String, sessionId: String) -> String {
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCWD.isEmpty else {
            return sessionId
        }

        let lastPathComponent = URL(fileURLWithPath: trimmedCWD).lastPathComponent
        return lastPathComponent.isEmpty ? sessionId : lastPathComponent
    }
}

/// Resolves the slow parts of a session refresh — title lookup, latest
/// response extraction, hide checks — all of which read and parse session
/// files on disk. Everything here is static and isolation-free so
/// AppController can run it on `eventEnrichmentQueue` and apply the outcome
/// back on the main actor.
private enum SessionRefreshResolver {
    struct Outcome {
        var title: String
        var response: (text: String, phase: String?, transcriptPath: String?)?
    }

    static func resolve(for session: AgentSession, transcriptPathOverride: String?) -> Outcome {
        Outcome(
            title: resolvedTitle(for: session) ?? fallbackTitle(for: session),
            response: latestResponse(for: session, transcriptPathOverride: transcriptPathOverride)
        )
    }

    static func shouldHide(_ session: AgentSession) -> Bool {
        switch session.agent {
        case .codex:
            AgentEventEnricher.shouldHideCodexSession(
                sessionId: session.sessionId,
                state: session.state,
                title: session.title,
                cwd: session.cwd,
                event: session.event,
                latestResponseText: session.latestResponseText,
                allowsUnresolvedLiveSession: true
            )
        case .claudeCode:
            AgentEventEnricher.shouldHideClaudeSession(
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

    private static func resolvedTitle(for session: AgentSession) -> String? {
        if AgentCompactionStatus.hasMatchingDisplayTitle(event: session.event, title: session.title) {
            return session.title
        }

        switch session.agent {
        case .codex:
            return CodexSessionWatcher.title(for: session.sessionId)
        case .claudeCode:
            return ClaudeSessionTitleResolver.title(for: session.sessionId, transcriptPath: session.transcriptPath)
        }
    }

    private static func fallbackTitle(for session: AgentSession) -> String {
        guard session.agent != .codex else {
            return session.title
        }
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        guard !session.isSubagent else {
            return session.title
        }

        return AgentEventEnricher.fallbackTitle(cwd: session.cwd, sessionId: session.sessionId)
    }

    private static func latestResponse(
        for session: AgentSession,
        transcriptPathOverride: String?
    ) -> (text: String, phase: String?, transcriptPath: String?)? {
        switch session.agent {
        case .codex:
            guard let latestCodexResponse = CodexSessionWatcher.latestResponse(
                for: session.sessionId,
                afterUserPrompt: pendingResponseUserPrompt(for: session)
            ) else {
                return nil
            }
            return (
                text: latestCodexResponse.text,
                phase: latestCodexResponse.phase,
                transcriptPath: session.transcriptPath
            )
        case .claudeCode:
            guard let latestClaudeResponse = ClaudeLatestResponseResolver.latestResponse(
                for: session.sessionId,
                transcriptPath: transcriptPathOverride ?? session.transcriptPath,
                afterUserPrompt: pendingResponseUserPrompt(for: session)
            ) else {
                return nil
            }
            return (
                text: latestClaudeResponse.text,
                phase: "assistant",
                transcriptPath: latestClaudeResponse.transcriptPath
            )
        }
    }

    private static func pendingResponseUserPrompt(for session: AgentSession) -> String? {
        guard session.isAwaitingLatestResponseText else {
            return nil
        }

        return session.latestUserPrompt
    }
}

@MainActor
final class AppController: ObservableObject {
    let store = AgentStateStore()
    private let providerVisibility = ProviderVisibilityStore.shared
    private var server: EventServer?
    private var codexWatcher: CodexSessionWatcher?
    private var claudeSubagentWatcher: ClaudeSubagentWatcher?
    private var claudeMainInterruptWatcher: ClaudeMainSessionInterruptWatcher?
    private var maintenanceTimer: Timer?
    private var serverRetryWorkItem: DispatchWorkItem?
    private var serverGeneration = 0
    private let eventEnrichmentQueue = DispatchQueue(label: "app.agentsessions.event-enrichment", qos: .utility)
    private var codexResponseRefreshWorkItems: [String: [DispatchWorkItem]] = [:]
    private var claudeResponseRefreshWorkItems: [String: [DispatchWorkItem]] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private static let serverRetryDelay: TimeInterval = 5
    private static let responseRetryDelays: [TimeInterval] = [0.15, 0.5, 1.0, 2.0, 4.0]
    private static let responseRefreshFreshnessWindow: TimeInterval = 5 * 60

    init() {
        applyDisplayPreferences()
        observeDisplayPreferences()
        startServer()
        startCodexWatcher()
        startClaudeSubagentWatcher()
        startClaudeMainInterruptWatcher()
        startMaintenanceTimer()
    }

    func startServer() {
        guard server == nil else {
            return
        }

        serverGeneration += 1
        let generation = serverGeneration

        do {
            let eventServer = try EventServer(
                host: "127.0.0.1",
                port: 7823,
                failureHandler: { [weak self] error in
                    Task { @MainActor in
                        self?.handleServerFailure(error, generation: generation)
                    }
                },
                handler: { [weak self] event in
                    Task { @MainActor in
                        self?.applyEvent(event)
                    }
                }
            )
            try eventServer.start()
            serverRetryWorkItem?.cancel()
            serverRetryWorkItem = nil
            server = eventServer
        } catch {
            NSLog("Agent Sessions server failed: \(error.localizedDescription)")
            scheduleServerRetry()
        }
    }

    private func handleServerFailure(_ error: Error, generation: Int) {
        guard generation == serverGeneration else {
            return
        }

        NSLog("Agent Sessions server failed: \(error.localizedDescription)")
        server?.stop()
        server = nil
        scheduleServerRetry()
    }

    private func scheduleServerRetry() {
        guard serverRetryWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.serverRetryWorkItem = nil
                self?.startServer()
            }
        }
        serverRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.serverRetryDelay, execute: workItem)
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

    private func startClaudeMainInterruptWatcher() {
        let watcher = ClaudeMainSessionInterruptWatcher { [weak self] event in
            Task { @MainActor in
                self?.applyEvent(event)
            }
        }
        watcher.start()
        claudeMainInterruptWatcher = watcher
    }

    private func applyEvent(_ event: AgentEvent) {
        let immediateEvent = event.settingUpdatedAtIfMissing(Date())

        guard !AgentEventEnricher.shouldHideImmediately(immediateEvent) else {
            removeHiddenSession(immediateEvent)
            return
        }

        if AgentSessionVisibility.isCodexUnresolvedToolEvent(
            agent: immediateEvent.agent,
            title: immediateEvent.title,
            event: immediateEvent.event,
            latestResponseText: immediateEvent.latestResponseText
        ), !hasResolvedExistingCodexSession(for: immediateEvent) {
            resolveUnresolvedCodexToolEvent(immediateEvent)
            return
        }

        applyEventToStore(immediateEvent)
    }

    private func applyEventToStore(_ event: AgentEvent) {
        let session = store.apply(event)
        scheduleResponseRefreshes(for: session)
        enrichEventAfterInitialApply(event)
    }

    /// Pre/PostToolUse hook events arrive with empty titles for the whole
    /// session lifetime, but once the stored session has a title, a response,
    /// or a non-tool event, the drop decision is "keep" regardless of the
    /// thread title — so the event can apply synchronously, in arrival order,
    /// without touching the disk. Only brand-new or still-unresolved sessions
    /// take the asynchronous path below.
    private func hasResolvedExistingCodexSession(for event: AgentEvent) -> Bool {
        guard let existing = store.sessions.first(where: {
            $0.agent == event.agent && $0.sessionId == event.sessionId
        }) else {
            return false
        }

        let existingHasTitle = !existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let existingHasResponse = existing.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let existingIsUnresolvedToolEvent = AgentSessionVisibility.isCodexUnresolvedToolEvent(
            agent: existing.agent,
            title: existing.title,
            event: existing.event,
            latestResponseText: existing.latestResponseText
        )
        return existingHasTitle || existingHasResponse || !existingIsUnresolvedToolEvent
    }

    /// The drop decision needs the Codex thread title, which is read from
    /// `session_index.jsonl` on disk — resolve it off the main thread and
    /// finish the decision back on the main actor.
    private func resolveUnresolvedCodexToolEvent(_ event: AgentEvent) {
        let queue = eventEnrichmentQueue
        queue.async {
            let hasThreadTitle = CodexSessionWatcher.title(for: event.sessionId) != nil

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if self.shouldDropUnresolvedCodexToolEvent(event, hasThreadTitle: hasThreadTitle) {
                    self.removeHiddenSession(event)
                    return
                }

                guard self.shouldApplyEnrichedEvent(event) else {
                    return
                }
                self.applyEventToStore(event)
            }
        }
    }

    private func shouldDropUnresolvedCodexToolEvent(_ event: AgentEvent, hasThreadTitle: Bool) -> Bool {
        guard !hasThreadTitle else {
            return false
        }

        guard let existing = store.sessions.first(where: {
            $0.agent == event.agent && $0.sessionId == event.sessionId
        }) else {
            return true
        }

        let existingHasTitle = !existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let existingHasResponse = existing.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let existingIsUnresolvedToolEvent = AgentSessionVisibility.isCodexUnresolvedToolEvent(
            agent: existing.agent,
            title: existing.title,
            event: existing.event,
            latestResponseText: existing.latestResponseText
        )
        return !existingHasTitle && !existingHasResponse && existingIsUnresolvedToolEvent
    }

    private func enrichEventAfterInitialApply(_ event: AgentEvent) {
        let queue = eventEnrichmentQueue
        queue.async {
            let resolvedEvent = AgentEventEnricher.enrichedEvent(for: event)
            let shouldHide = AgentEventEnricher.shouldHide(resolvedEvent)

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                guard !shouldHide else {
                    self.removeHiddenSession(resolvedEvent)
                    return
                }

                guard resolvedEvent != event,
                      self.shouldApplyEnrichedEvent(resolvedEvent) else {
                    return
                }

                let session = self.store.apply(resolvedEvent)
                self.scheduleResponseRefreshes(for: session)
            }
        }
    }

    private func shouldApplyEnrichedEvent(_ event: AgentEvent) -> Bool {
        guard let updatedAt = event.updatedAt,
              let existing = store.sessions.first(where: {
                  $0.agent == event.agent && $0.sessionId == event.sessionId
              }) else {
            return true
        }

        let existingStateReferenceDate = existing.stateChangedAt ?? existing.updatedAt
        return updatedAt >= existingStateReferenceDate
    }

    private func scheduleResponseRefreshes(for session: AgentSession) {
        switch session.agent {
        case .codex:
            scheduleCodexResponseRefreshes(for: session)
        case .claudeCode:
            scheduleClaudeResponseRefreshes(for: session)
        }
    }

    private func scheduleCodexResponseRefreshes(for session: AgentSession) {
        guard session.agent == .codex else { return }

        let sessionId = session.sessionId
        codexResponseRefreshWorkItems[sessionId]?.forEach { $0.cancel() }

        var workItems: [DispatchWorkItem] = []
        for (index, delay) in Self.responseRetryDelays.enumerated() {
            let item = DispatchWorkItem { [weak self] in
                self?.refreshResponse(sessionId: sessionId, agent: .codex, transcriptPath: nil)
                if index == Self.responseRetryDelays.count - 1 {
                    self?.codexResponseRefreshWorkItems[sessionId] = nil
                }
            }
            workItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        codexResponseRefreshWorkItems[sessionId] = workItems
    }

    private func scheduleClaudeResponseRefreshes(for session: AgentSession) {
        guard session.agent == .claudeCode else { return }

        let sessionId = session.sessionId
        let transcriptPath = session.transcriptPath
        claudeResponseRefreshWorkItems[sessionId]?.forEach { $0.cancel() }

        var workItems: [DispatchWorkItem] = []
        for (index, delay) in Self.responseRetryDelays.enumerated() {
            let item = DispatchWorkItem { [weak self] in
                self?.refreshResponse(sessionId: sessionId, agent: .claudeCode, transcriptPath: transcriptPath)
                if index == Self.responseRetryDelays.count - 1 {
                    self?.claudeResponseRefreshWorkItems[sessionId] = nil
                }
            }
            workItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        claudeResponseRefreshWorkItems[sessionId] = workItems
    }

    private func refreshResponse(sessionId: String, agent: AgentKind, transcriptPath: String?) {
        guard let snapshot = store.sessions.first(where: {
            $0.agent == agent && $0.sessionId == sessionId
        }) else {
            return
        }

        let queue = eventEnrichmentQueue
        queue.async { [weak self] in
            let outcome = SessionRefreshResolver.resolve(for: snapshot, transcriptPathOverride: transcriptPath)
            guard outcome.response != nil else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyResponseRefresh(outcome, snapshot: snapshot, requiresResponse: true)
            }
        }
    }

    private func applyResponseRefresh(
        _ outcome: SessionRefreshResolver.Outcome,
        snapshot: AgentSession,
        requiresResponse: Bool
    ) {
        guard let current = store.sessions.first(where: {
            $0.agent == snapshot.agent && $0.sessionId == snapshot.sessionId
        }) else {
            return
        }

        // The response was resolved against the prompt captured in the
        // snapshot; a newer prompt makes it stale (the retry ladder and the
        // maintenance pass will re-resolve).
        guard current.latestUserPrompt == snapshot.latestUserPrompt else {
            return
        }

        if requiresResponse, outcome.response == nil {
            return
        }

        let response = outcome.response
        let title = outcome.title
        let latestResponseText = response.map(\.text) ?? current.latestResponseText
        let latestResponsePhase = response != nil ? response?.phase : current.latestResponsePhase
        let transcriptPath = response?.transcriptPath ?? current.transcriptPath
        let responseTextChanged = response != nil && latestResponseText != current.latestResponseText

        guard title != current.title
            || latestResponseText != current.latestResponseText
            || latestResponsePhase != current.latestResponsePhase
            || transcriptPath != current.transcriptPath else {
            return
        }

        let refreshedAt = Date()
        let applied = store.apply(AgentEvent(
            agent: current.agent,
            sessionId: current.sessionId,
            state: current.state,
            title: title,
            cwd: current.cwd,
            event: current.event,
            terminal: current.terminal,
            pid: current.pid,
            updatedAt: updatedAtForResponseRefresh(
                session: current,
                responseTextChanged: responseTextChanged,
                now: refreshedAt
            ),
            parentSessionId: current.parentSessionId,
            subagentNickname: current.subagentNickname,
            subagentRole: current.subagentRole,
            subagentDepth: current.subagentDepth,
            transcriptPath: transcriptPath,
            latestUserPrompt: current.latestUserPrompt,
            latestResponseText: latestResponseText,
            latestResponsePhase: latestResponsePhase
        ))

        if requiresResponse {
            scheduleHideCheck(for: applied)
        }
    }

    /// Hide checks hit the disk (rollout files, app-session metadata), so the
    /// predicate runs on the enrichment queue; removal happens back on the
    /// main actor only if the session saw no new activity in the meantime.
    private func scheduleHideCheck(for session: AgentSession) {
        let queue = eventEnrichmentQueue
        queue.async {
            guard SessionRefreshResolver.shouldHide(session) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                guard let current = self.store.sessions.first(where: {
                    $0.agent == session.agent && $0.sessionId == session.sessionId
                }), current.updatedAt == session.updatedAt else {
                    return
                }
                self.store.removeSession(agent: session.agent, sessionId: session.sessionId)
            }
        }
    }

    private func refreshSessionTitles() {
        store.expireStaleActiveSessions()

        let sessions = store.sessions
        guard !sessions.isEmpty else {
            return
        }

        let queue = eventEnrichmentQueue
        queue.async { [weak self] in
            var hidden: [AgentSession] = []
            var refreshes: [(snapshot: AgentSession, outcome: SessionRefreshResolver.Outcome)] = []
            for session in sessions {
                if SessionRefreshResolver.shouldHide(session) {
                    hidden.append(session)
                    continue
                }
                refreshes.append((session, SessionRefreshResolver.resolve(for: session, transcriptPathOverride: nil)))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                for session in hidden {
                    guard let current = self.store.sessions.first(where: {
                        $0.agent == session.agent && $0.sessionId == session.sessionId
                    }), current.updatedAt == session.updatedAt else {
                        continue
                    }
                    self.store.removeSession(agent: session.agent, sessionId: session.sessionId)
                }

                for (snapshot, outcome) in refreshes {
                    self.applyResponseRefresh(outcome, snapshot: snapshot, requiresResponse: false)
                }
            }
        }
    }

    private func updatedAtForResponseRefresh(
        session: AgentSession,
        responseTextChanged: Bool,
        now: Date
    ) -> Date {
        guard responseTextChanged else {
            return session.updatedAt
        }

        if session.state.isActive {
            return now
        }

        let elapsed = now.timeIntervalSince(session.updatedAt)
        guard elapsed >= 0,
              elapsed <= Self.responseRefreshFreshnessWindow else {
            return session.updatedAt
        }

        return now
    }

    private func removeHiddenSession(_ event: AgentEvent) {
        store.removeSession(agent: event.agent, sessionId: event.sessionId)
    }

    private func startMaintenanceTimer() {
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionTitles()
            }
        }
    }
}

@MainActor
final class SessionPopupController {
    private static let appearanceAnimationDuration: TimeInterval = 0.32
    private static let disappearanceAnimationDuration: TimeInterval = 0.24
    private static let frameUpdateAnimationDuration: TimeInterval = 0.18
    private static let emptySessionCloseDelay: TimeInterval = 0.35
    private static let appearanceAnimationOffset: CGFloat = 14
    private static let mouseProximityMargin: CGFloat = 60
    private static let mouseProximityAnimationDuration: TimeInterval = 0.08
    private static let mouseProximityEventMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged
    ]
    private static let minimumCompactPopupWidth: CGFloat = 200
    private static let pendingLatestResponseText = "Thinking..."
    private static let compactWidthRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private enum PopupVisibilityState {
        case hidden
        case appearing
        case visible
        case disappearing
    }

    private let controller: AppController
    private let providerVisibility = ProviderVisibilityStore.shared
    private var panel: NSPanel?
    private var hostingController: NSHostingController<LatestParentSessionsPopupView>?
    private var refreshTimer: Timer?
    private var emptyCloseTimer: Timer?
    private var mouseProximityLocalMonitor: Any?
    private var mouseProximityGlobalMonitor: Any?
    private var mouseProximityIsDimmed: Bool?
    private var renderedPopupSignature: String?
    private var popupAnimationGeneration = 0
    private var popupVisibilityState: PopupVisibilityState = .hidden
    private var cancellables: Set<AnyCancellable> = []

    init(controller: AppController) {
        self.controller = controller
        observeChanges()
        startRefreshTimer()
        updatePopup()
    }

    private func observeChanges() {
        controller.store.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupDisplayInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupProviderVisibility
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupGlassEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupUsesClearGlass
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupUsesColoredBorder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupGlassOpacity
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopupPanelAlpha(animated: true)
            }
            .store(in: &cancellables)

        providerVisibility.$popupWindowPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupRightAlignsTextOnRightSide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupWindowWidth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupOffsetX
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupOffsetY
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupBackdropOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupMouseProximityOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopupPanelAlpha(animated: true)
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextShadowEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextShadowStrength
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextShadowDistance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextShadowRadius
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupParentSessionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupShowsUserPrompt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupShowsResponseBody
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupResponseCharacterLimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupResponseLineLimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupResponseCompactsBlankLines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)

        providerVisibility.$popupResponseElidesShortFinalLine
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePopup()
            }
            .store(in: &cancellables)
    }

    private func startRefreshTimer() {
        scheduleNextPopupCheck(visibleSessions: nil)
    }

    private func scheduleNextPopupCheck(visibleSessions: [AgentSession]?) {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let displayInterval = providerVisibility.popupDisplayInterval
        let now = Date()

        let sessions = visibleSessions ?? currentPopupSessions(now: now)

        var earliestExpiration: Date?
        for session in sessions where !session.state.isActive {
            let referenceDate = max(session.stateChangedAt ?? session.updatedAt, session.updatedAt)
            let expirationDate = referenceDate.addingTimeInterval(displayInterval)
            if earliestExpiration == nil || expirationDate < earliestExpiration! {
                earliestExpiration = expirationDate
            }
        }

        guard let target = earliestExpiration else {
            return
        }

        let cappedTarget = min(target, now.addingTimeInterval(60))
        let delay = max(0.1, cappedTarget.timeIntervalSince(now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updatePopup()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func updatePopup() {
        guard providerVisibility.popupEnabled else {
            cancelDeferredPopupClose()
            closePopup()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        let now = Date()
        let sessions = currentPopupSessions(now: now)
        guard !sessions.isEmpty else {
            deferPopupCloseForTransientEmptyState()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        cancelDeferredPopupClose()
        showPopup(sessions: sessions)
        scheduleNextPopupCheck(visibleSessions: sessions)
    }

    private func currentPopupSessions(now: Date = Date()) -> [AgentSession] {
        let includedAgents = Set(AgentKind.allCases.filter { providerVisibility.isPopupVisible(for: $0) })
        return controller.store.popupParentSessions(
            now: now,
            displayInterval: providerVisibility.popupDisplayInterval,
            includedAgents: includedAgents,
            limit: providerVisibility.popupParentSessionCount
        )
    }

    private func deferPopupCloseForTransientEmptyState() {
        guard panel?.isVisible == true, popupVisibilityState != .hidden else {
            closePopup()
            return
        }

        guard emptyCloseTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: Self.emptySessionCloseDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.closePopupIfStillEmpty()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        emptyCloseTimer = timer
    }

    private func closePopupIfStillEmpty() {
        emptyCloseTimer?.invalidate()
        emptyCloseTimer = nil

        guard providerVisibility.popupEnabled else {
            closePopup()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        let sessions = currentPopupSessions()
        guard !sessions.isEmpty else {
            closePopup()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        showPopup(sessions: sessions)
        scheduleNextPopupCheck(visibleSessions: sessions)
    }

    private func cancelDeferredPopupClose() {
        emptyCloseTimer?.invalidate()
        emptyCloseTimer = nil
    }

    private func showPopup(sessions: [AgentSession]) {
        let renderSignature = popupRenderSignature(for: sessions)
        if panel?.isVisible == true,
           popupVisibilityState == .visible,
           renderedPopupSignature == renderSignature {
            updatePopupPanelAlpha(animated: false)
            return
        }

        let alignsTextTrailing = providerVisibility.popupRightAlignsTextOnRightSide
            && providerVisibility.popupWindowPosition.isRightSide
        let frameWidth = effectivePopupFrameWidth(
            for: sessions,
            alignsTextTrailing: alignsTextTrailing
        )
        let viewPopupWidth = frameWidth / CGFloat(providerVisibility.popupScale)
        let rootView = LatestParentSessionsPopupView(
            sessions: sessions,
            popupWidth: viewPopupWidth,
            popupScale: CGFloat(providerVisibility.popupScale),
            glassEnabled: providerVisibility.popupGlassEnabled,
            usesClearGlass: providerVisibility.popupUsesClearGlass,
            usesColoredBorder: providerVisibility.popupUsesColoredBorder,
            glassOpacity: providerVisibility.popupGlassOpacity,
            textOpacity: 1,
            textShadowStrength: providerVisibility.effectivePopupTextShadowStrength,
            textShadowDistance: CGFloat(providerVisibility.effectivePopupTextShadowDistance),
            textShadowRadius: CGFloat(providerVisibility.effectivePopupTextShadowRadius),
            alignsTextTrailing: alignsTextTrailing,
            placesNewestSessionAtBottom: providerVisibility.popupWindowPosition.placesNewestPopupSessionAtBottom,
            showsUserPrompt: providerVisibility.popupShowsUserPrompt,
            showsResponseBody: providerVisibility.popupShowsResponseBody,
            responseCharacterLimit: providerVisibility.popupResponseCharacterLimit,
            responseLineLimit: providerVisibility.popupResponseLineLimit,
            responseCompactsBlankLines: providerVisibility.popupResponseCompactsBlankLines,
            responseElidesShortFinalLine: providerVisibility.popupResponseElidesShortFinalLine,
            usesIndicatorLampStyle: providerVisibility.usesIndicatorLampStyle
        )
        let hostingController = ensureHostingController(rootView: rootView)
        hostingController.rootView = rootView
        hostingController.view.frame.size.width = frameWidth
        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.layoutSubtreeIfNeeded()

        let fittingSize = hostingController.view.fittingSize
        let panel = ensurePanel(hostingController: hostingController)
        let frame = positionedFrame(
            for: fittingSize,
            position: providerVisibility.popupWindowPosition,
            width: frameWidth
        )
        hostingController.view.frame.size = frame.size

        if popupVisibilityState == .disappearing {
            cancelPopupDisappearance(view: hostingController.view)
        }

        let shouldAnimateAppearance = !panel.isVisible || popupVisibilityState == .hidden
        let appearanceAnimationGeneration: Int?
        if shouldAnimateAppearance {
            popupAnimationGeneration += 1
            popupVisibilityState = .appearing
            appearanceAnimationGeneration = popupAnimationGeneration
        } else {
            appearanceAnimationGeneration = nil
        }

        updatePopupFrame(panel, to: frame, animated: !shouldAnimateAppearance && panel.isVisible)
        updatePopupPanelAlpha(animated: false)

        if let animationGeneration = appearanceAnimationGeneration {
            preparePopupContentForAppearance(hostingController.view)
            panel.orderFrontRegardless()
            startMouseProximityTracking()
            animatePopupContentIn(
                hostingController.view,
                position: providerVisibility.popupWindowPosition,
                animationGeneration: animationGeneration
            )
        } else {
            panel.orderFrontRegardless()
            startMouseProximityTracking()
            if popupVisibilityState == .visible {
                resetPopupContentAnimation(hostingController.view)
            }
        }
        renderedPopupSignature = renderSignature
    }

    private func cancelPopupDisappearance(view: NSView) {
        popupAnimationGeneration += 1
        popupVisibilityState = .visible
        resetPopupContentAnimation(view)
    }

    private func closePopup() {
        stopMouseProximityTracking()
        renderedPopupSignature = nil
        guard let panel, panel.isVisible else {
            if let view = hostingController?.view {
                stopPopupIconAnimations(in: view)
            }
            panel?.alphaValue = 1
            popupVisibilityState = .hidden
            return
        }
        guard popupVisibilityState != .disappearing else {
            return
        }

        popupAnimationGeneration += 1
        let animationGeneration = popupAnimationGeneration
        popupVisibilityState = .disappearing

        guard let view = hostingController?.view else {
            panel.orderOut(nil)
            popupVisibilityState = .hidden
            return
        }

        animatePopupContentOut(
            view,
            position: providerVisibility.popupWindowPosition,
            animationGeneration: animationGeneration
        ) { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, self.popupAnimationGeneration == animationGeneration else {
                    return
                }

                panel?.orderOut(nil)
                panel?.alphaValue = 1
                if let view = self.hostingController?.view {
                    self.resetPopupContentAnimation(view)
                    self.stopPopupIconAnimations(in: view)
                }
                self.renderedPopupSignature = nil
                self.popupVisibilityState = .hidden
            }
        }
    }

    private func popupRenderSignature(for sessions: [AgentSession]) -> String {
        var parts: [String] = [
            providerVisibility.popupWindowPosition.rawValue,
            "\(providerVisibility.popupWindowWidth)",
            "\(providerVisibility.popupOffsetX)",
            "\(providerVisibility.popupOffsetY)",
            "\(providerVisibility.popupScale)",
            "\(providerVisibility.popupGlassEnabled)",
            "\(providerVisibility.popupUsesClearGlass)",
            "\(providerVisibility.popupUsesColoredBorder)",
            "\(providerVisibility.popupGlassOpacity)",
            "\(providerVisibility.popupRightAlignsTextOnRightSide)",
            "\(providerVisibility.popupWindowPosition.isRightSide)",
            "\(providerVisibility.effectivePopupTextShadowStrength)",
            "\(providerVisibility.effectivePopupTextShadowDistance)",
            "\(providerVisibility.effectivePopupTextShadowRadius)",
            "\(providerVisibility.popupWindowPosition.placesNewestPopupSessionAtBottom)",
            "\(providerVisibility.popupShowsUserPrompt)",
            "\(providerVisibility.popupShowsResponseBody)",
            "\(providerVisibility.popupResponseCharacterLimit)",
            "\(providerVisibility.popupResponseLineLimit)",
            "\(providerVisibility.popupResponseCompactsBlankLines)",
            "\(providerVisibility.popupResponseElidesShortFinalLine)",
            "\(providerVisibility.usesIndicatorLampStyle)"
        ]

        for session in sessions {
            parts.append(session.id)
            parts.append(session.state.rawValue)
            parts.append(session.displayTitle)
            parts.append("\(session.updatedAt.timeIntervalSinceReferenceDate)")
            parts.append(session.latestUserPrompt ?? "")
            parts.append(session.latestResponseText ?? "")
            parts.append(session.latestResponsePhase ?? "")
        }

        return parts.joined(separator: "\u{1f}")
    }

    private func ensureHostingController(
        rootView: LatestParentSessionsPopupView
    ) -> NSHostingController<LatestParentSessionsPopupView> {
        if let hostingController {
            return hostingController
        }

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingController = hostingController
        return hostingController
    }

    private func ensurePanel(
        hostingController: NSHostingController<LatestParentSessionsPopupView>
    ) -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func startMouseProximityTracking() {
        updatePopupPanelAlpha(animated: false)

        guard mouseProximityLocalMonitor == nil, mouseProximityGlobalMonitor == nil else {
            return
        }

        mouseProximityLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mouseProximityEventMask) { [weak self] event in
            Task { @MainActor in
                self?.updatePopupPanelAlpha(animated: true)
            }
            return event
        }

        mouseProximityGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mouseProximityEventMask) { [weak self] _ in
            Task { @MainActor in
                self?.updatePopupPanelAlpha(animated: true)
            }
        }
    }

    private func stopMouseProximityTracking() {
        if let mouseProximityLocalMonitor {
            NSEvent.removeMonitor(mouseProximityLocalMonitor)
        }
        if let mouseProximityGlobalMonitor {
            NSEvent.removeMonitor(mouseProximityGlobalMonitor)
        }
        mouseProximityLocalMonitor = nil
        mouseProximityGlobalMonitor = nil
        mouseProximityIsDimmed = nil
    }

    private func updatePopupPanelAlpha(animated: Bool) {
        guard let panel, popupVisibilityState != .hidden else {
            return
        }

        let isDimmed = popupShouldDim(forMouseLocation: NSEvent.mouseLocation)
        let targetAlpha = CGFloat(isDimmed ? providerVisibility.popupMouseProximityOpacity : providerVisibility.popupOpacity)
        guard mouseProximityIsDimmed != isDimmed || abs(panel.alphaValue - targetAlpha) > 0.001 else {
            return
        }
        mouseProximityIsDimmed = isDimmed

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.mouseProximityAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = targetAlpha
            }
        } else {
            panel.alphaValue = targetAlpha
        }
    }

    private func popupShouldDim(forMouseLocation mouseLocation: NSPoint) -> Bool {
        guard let panel else {
            return false
        }

        let proximityFrame = panel.frame.insetBy(
            dx: -Self.mouseProximityMargin,
            dy: -Self.mouseProximityMargin
        )
        return proximityFrame.contains(mouseLocation)
    }

    private func updatePopupFrame(_ panel: NSPanel, to frame: NSRect, animated: Bool) {
        guard animated, !framesAreEquivalent(panel.frame, frame) else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.frameUpdateAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func framesAreEquivalent(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }

    private func positionedFrame(
        for fittingSize: NSSize,
        position: PopupWindowPosition,
        width: CGFloat
    ) -> NSRect {
        let scale = CGFloat(providerVisibility.popupScale)
        let height = max(fittingSize.height, 44 * scale)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 12
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .topRight:
            x = screenFrame.maxX - width - margin
            y = screenFrame.maxY - height - margin
        case .topLeft:
            x = screenFrame.minX + margin
            y = screenFrame.maxY - height - margin
        case .bottomRight:
            x = screenFrame.maxX - width - margin
            y = screenFrame.minY + margin
        case .bottomLeft:
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        case .topCenter:
            x = screenFrame.midX - width / 2
            y = screenFrame.maxY - height - margin
        case .bottomCenter:
            x = screenFrame.midX - width / 2
            y = screenFrame.minY + margin
        }

        return NSRect(
            x: x + CGFloat(providerVisibility.popupOffsetX),
            y: y + CGFloat(providerVisibility.popupOffsetY),
            width: width,
            height: height
        )
    }

    private func preparePopupContentForAppearance(_ view: NSView) {
        guard let layer = view.layer else {
            view.alphaValue = 0
            return
        }

        layer.removeAnimation(forKey: "popupAppearance")
        layer.removeAnimation(forKey: "popupDisappearance")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = popupContentStartTransform(for: providerVisibility.popupWindowPosition)
        CATransaction.commit()
    }

    private func resetPopupContentAnimation(_ view: NSView) {
        view.alphaValue = 1
        guard let layer = view.layer else {
            return
        }

        layer.removeAnimation(forKey: "popupAppearance")
        layer.removeAnimation(forKey: "popupDisappearance")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func stopPopupIconAnimations(in view: NSView) {
        if let iconView = view as? AnimatedAgentIconImageView {
            iconView.stopAnimating()
        }

        for subview in view.subviews {
            stopPopupIconAnimations(in: subview)
        }
    }

    private func animatePopupContentIn(
        _ view: NSView,
        position: PopupWindowPosition,
        animationGeneration: Int
    ) {
        guard let layer = view.layer else {
            view.alphaValue = 1
            popupVisibilityState = .visible
            return
        }

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0
        opacityAnimation.toValue = 1

        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = popupContentStartTransform(for: position)
        transformAnimation.toValue = CATransform3DIdentity

        let group = CAAnimationGroup()
        group.animations = [opacityAnimation, transformAnimation]
        group.duration = Self.appearanceAnimationDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.popupAnimationGeneration == animationGeneration else {
                    return
                }

                self.popupVisibilityState = .visible
            }
        }
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        layer.add(group, forKey: "popupAppearance")
        CATransaction.commit()
    }

    private func animatePopupContentOut(
        _ view: NSView,
        position: PopupWindowPosition,
        animationGeneration: Int,
        completion: @escaping @Sendable () -> Void
    ) {
        guard let layer = view.layer else {
            view.alphaValue = 0
            completion()
            return
        }

        let targetTransform = popupContentStartTransform(for: position)
        let presentationLayer = layer.presentation()

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = presentationLayer?.opacity ?? layer.opacity
        opacityAnimation.toValue = 0

        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = presentationLayer?.transform ?? layer.transform
        transformAnimation.toValue = targetTransform

        let group = CAAnimationGroup()
        group.animations = [opacityAnimation, transformAnimation]
        group.duration = Self.disappearanceAnimationDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            completion()
        }
        layer.opacity = 0
        layer.transform = targetTransform
        layer.add(group, forKey: "popupDisappearance")
        CATransaction.commit()
    }

    private func popupContentStartTransform(for position: PopupWindowPosition) -> CATransform3D {
        let offset = Self.appearanceAnimationOffset * CGFloat(providerVisibility.popupScale)
        let yOffset: CGFloat

        switch position {
        case .topRight, .topLeft, .topCenter:
            yOffset = offset
        case .bottomRight, .bottomLeft, .bottomCenter:
            yOffset = -offset
        }

        return CATransform3DTranslate(
            CATransform3DMakeScale(0.985, 0.985, 1),
            0,
            yOffset,
            0
        )
    }

    private var maximumPopupFrameWidth: CGFloat {
        CGFloat(providerVisibility.popupWindowWidth) * CGFloat(providerVisibility.popupScale)
    }

    private func effectivePopupFrameWidth(
        for sessions: [AgentSession],
        alignsTextTrailing: Bool
    ) -> CGFloat {
        let maximumWidth = maximumPopupFrameWidth
        guard providerVisibility.popupWindowPosition.isRightSide, !alignsTextTrailing else {
            return maximumWidth
        }

        let metrics = popupScaleMetrics()
        let outerHorizontalPadding = metrics.horizontalPadding + metrics.shadowBleedPadding
        let maxRowContentWidth = max(maximumWidth - (2 * outerHorizontalPadding), 1)
        let displayedSessions = sessions.filter { !$0.isSubagent }
        let measuredRowWidth = displayedSessions
            .map { compactRowContentWidth(for: $0, metrics: metrics, maxWidth: maxRowContentWidth) }
            .max() ?? maxRowContentWidth
        let minimumWidth = min(Self.minimumCompactPopupWidth * metrics.scale, maximumWidth)
        let compactWidth = measuredRowWidth + (2 * outerHorizontalPadding)
        return ceil(min(max(compactWidth, minimumWidth), maximumWidth))
    }

    private func compactRowContentWidth(
        for session: AgentSession,
        metrics: PopupScaleMetrics,
        maxWidth: CGFloat
    ) -> CGFloat {
        let responseTextWidthLimit = max(maxWidth - (2 * metrics.responseHorizontalPadding), 1)
        var measuredWidths: [CGFloat] = [
            compactTitleRowWidth(for: session, metrics: metrics, maxWidth: maxWidth),
            compactStateTimeRowWidth(for: session, metrics: metrics, maxWidth: maxWidth)
        ]

        if let userPromptText = compactUserPromptText(for: session) {
            measuredWidths.append(
                min(
                    measuredSingleLineWidth(
                        userPromptText,
                        font: .systemFont(ofSize: metrics.metadataFontSize, weight: .semibold),
                        maxWidth: responseTextWidthLimit
                    ) + (2 * metrics.responseHorizontalPadding),
                    maxWidth
                )
            )
        }

        if let responseText = compactResponseText(for: session) {
            measuredWidths.append(
                min(
                    measuredWrappedTextWidth(
                        responseText,
                        font: .systemFont(ofSize: metrics.responseFontSize),
                        maxWidth: responseTextWidthLimit
                    ) + (2 * metrics.responseHorizontalPadding),
                    maxWidth
                )
            )
        }

        return min(max(measuredWidths.max() ?? 1, 1), maxWidth)
    }

    private func compactTitleRowWidth(
        for session: AgentSession,
        metrics: PopupScaleMetrics,
        maxWidth: CGFloat
    ) -> CGFloat {
        let titleRowInnerWidth = max(maxWidth - (2 * metrics.responseHorizontalPadding), 1)
        let titleTextLimit = max(
            titleRowInnerWidth
                - metrics.iconSize
                - metrics.titleSpacing
                - (2 * metrics.titleHorizontalPadding),
            1
        )
        let titleWidth = measuredWrappedTextWidth(
            compactTitleText(for: session),
            font: .systemFont(ofSize: metrics.titleFontSize, weight: .semibold),
            maxWidth: titleTextLimit
        ) + (2 * metrics.titleHorizontalPadding)
        return min(
            metrics.iconSize
                + metrics.titleSpacing
                + titleWidth
                + (2 * metrics.responseHorizontalPadding),
            maxWidth
        )
    }

    private func compactStateTimeRowWidth(
        for session: AgentSession,
        metrics: PopupScaleMetrics,
        maxWidth: CGFloat
    ) -> CGFloat {
        min(
            measuredSingleLineWidth(
                compactStateTimeText(for: session),
                font: .systemFont(ofSize: metrics.metadataFontSize, weight: .semibold),
                maxWidth: max(maxWidth - (2 * metrics.responseHorizontalPadding), 1)
            ) + (2 * metrics.responseHorizontalPadding),
            maxWidth
        )
    }

    private func compactTitleText(for session: AgentSession) -> String {
        if session.state == .working,
           session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Thinking..."
        }

        return session.displayTitle
    }

    private func compactUserPromptText(for session: AgentSession) -> String? {
        guard providerVisibility.popupShowsUserPrompt,
              let prompt = AgentTextSanitizer.userPromptText(session.latestUserPrompt),
              !prompt.isEmpty,
              AgentSessionTitleSanitizer.normalized(prompt) != AgentSessionTitleSanitizer.normalized(compactTitleText(for: session)) else {
            return nil
        }

        return prompt
    }

    private func compactResponseText(for session: AgentSession) -> String? {
        guard providerVisibility.popupShowsResponseBody,
              providerVisibility.popupResponseLineLimit > 0 else {
            return nil
        }

        if let text = AgentTextSanitizer.latestResponseText(
            session.latestResponseText,
            compactsBlankLines: providerVisibility.popupResponseCompactsBlankLines
        ) {
            return Self.truncatedCompactText(text, to: providerVisibility.popupResponseCharacterLimit)
        }

        if session.isAwaitingLatestResponseText {
            return Self.pendingLatestResponseText
        }

        return nil
    }

    private func compactStateTimeText(for session: AgentSession) -> String {
        "\(session.state.displayName) · \(compactRelativeTimeText(for: session.updatedAt))"
    }

    private func compactRelativeTimeText(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 1 {
            return "0s ago"
        }

        return Self.compactWidthRelativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func measuredSingleLineWidth(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGFloat {
        let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(min(max(measuredWidth, 1), maxWidth))
    }

    private func measuredWrappedTextWidth(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGFloat {
        let measuredWidth = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).width
        return ceil(min(max(measuredWidth, 1), maxWidth))
    }

    private func popupScaleMetrics() -> PopupScaleMetrics {
        PopupScaleMetrics(
            scale: CGFloat(providerVisibility.popupScale),
            textOpacity: 1,
            textShadowStrength: providerVisibility.effectivePopupTextShadowStrength,
            textShadowDistance: CGFloat(providerVisibility.effectivePopupTextShadowDistance),
            textShadowRadius: CGFloat(providerVisibility.effectivePopupTextShadowRadius)
        )
    }

    private static func truncatedCompactText(_ text: String, to limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let truncatedLimit = max(limit - 3, 1)
        let truncatedText = String(text.prefix(truncatedLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncatedText + "..."
    }
}

private struct LatestParentSessionsPopupView: View {
    let sessions: [AgentSession]
    let popupWidth: CGFloat
    let popupScale: CGFloat
    let glassEnabled: Bool
    let usesClearGlass: Bool
    let usesColoredBorder: Bool
    let glassOpacity: Double
    let textOpacity: Double
    let textShadowStrength: Double
    let textShadowDistance: CGFloat
    let textShadowRadius: CGFloat
    let alignsTextTrailing: Bool
    let placesNewestSessionAtBottom: Bool
    let showsUserPrompt: Bool
    let showsResponseBody: Bool
    let responseCharacterLimit: Int
    let responseLineLimit: Int
    let responseCompactsBlankLines: Bool
    let responseElidesShortFinalLine: Bool
    let usesIndicatorLampStyle: Bool

    var body: some View {
        let metrics = PopupScaleMetrics(
            scale: popupScale,
            textOpacity: textOpacity,
            textShadowStrength: textShadowStrength,
            textShadowDistance: textShadowDistance,
            textShadowRadius: textShadowRadius
        )

        VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            ForEach(displayedSessions, id: \.id) { session in
                PopupSessionRow(
                    session: session,
                    metrics: metrics,
                    rowContentWidth: rowContentWidth,
                    alignsTextTrailing: alignsTextTrailing,
                    showsUserPrompt: showsUserPrompt,
                    showsResponseBody: showsResponseBody,
                    responseCharacterLimit: responseCharacterLimit,
                    responseLineLimit: responseLineLimit,
                    responseCompactsBlankLines: responseCompactsBlankLines,
                    responseElidesShortFinalLine: responseElidesShortFinalLine,
                    usesIndicatorLampStyle: usesIndicatorLampStyle
                )
                .padding(.horizontal, metrics.horizontalPadding + metrics.shadowBleedPadding)
                .padding(.vertical, metrics.verticalPadding + metrics.shadowBleedPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if glassEnabled {
                        PopupLiquidGlassBackground(
                            metrics: metrics,
                            usesClearGlass: usesClearGlass,
                            usesColoredBorder: usesColoredBorder,
                            opacity: glassOpacity,
                            agent: session.agent
                        )
                    }
                }
            }
        }
        .animation(Self.reorderAnimation, value: displayedSessionIDs)
        .frame(width: popupWidth * metrics.scale, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var rowContentWidth: CGFloat {
        max(popupWidth * metricsScale - (2 * rowOuterHorizontalPadding), 1)
    }

    private var metricsScale: CGFloat {
        min(max(popupScale, 0.5), 1.5)
    }

    private var rowOuterHorizontalPadding: CGFloat {
        let metrics = PopupScaleMetrics(
            scale: popupScale,
            textOpacity: textOpacity,
            textShadowStrength: textShadowStrength,
            textShadowDistance: textShadowDistance,
            textShadowRadius: textShadowRadius
        )
        return metrics.horizontalPadding + metrics.shadowBleedPadding
    }

    private var displayedSessions: [AgentSession] {
        let parentSessions = sessions.filter { !$0.isSubagent }

        if placesNewestSessionAtBottom {
            return Array(parentSessions.reversed())
        }

        return parentSessions
    }

    private var displayedSessionIDs: [String] {
        displayedSessions.map(\.id)
    }

    private static let reorderAnimation = Animation.interpolatingSpring(
        mass: 0.85,
        stiffness: 260,
        damping: 30,
        initialVelocity: 0.15
    )
}

private struct PopupLiquidGlassBackground: View {
    let metrics: PopupScaleMetrics
    let usesClearGlass: Bool
    let usesColoredBorder: Bool
    let opacity: Double
    let agent: AgentKind

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let opacity = min(max(opacity, 0), 1)
        let shape = RoundedRectangle(cornerRadius: metrics.glassCornerRadius, style: .continuous)

        Group {
            if reduceTransparency {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            } else {
                shape
                    .fill(.clear)
                    .glassEffect(nativeGlass(opacity: opacity, usesClearGlass: usesClearGlass), in: shape)
            }
        }
        .overlay(hairlineBorder(in: shape))
        .shadow(
            color: .black.opacity(0.025 * opacity),
            radius: metrics.glassShadowRadius,
            x: 0,
            y: metrics.glassShadowYOffset
        )
        .opacity(opacity)
    }

    private func nativeGlass(opacity: Double, usesClearGlass: Bool) -> Glass {
        guard opacity > 0.001 else {
            return .identity
        }

        let glass = usesClearGlass ? Glass.clear : Glass.regular
        return glass
            .interactive(false)
    }

    private func hairlineBorder(in shape: RoundedRectangle) -> some View {
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    colors: baseHairlineColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: metrics.glassBorderWidth
            )

            if usesColoredBorder {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.providerColor(agent).opacity(0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: metrics.glassBorderWidth
                )
            }
        }
    }

    private var baseHairlineColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.38), .white.opacity(0.06)]
            : [.black.opacity(0.12), .black.opacity(0.03)]
    }
}

private struct PopupSessionRow: View {
    let session: AgentSession
    let metrics: PopupScaleMetrics
    let rowContentWidth: CGFloat
    let alignsTextTrailing: Bool
    let showsUserPrompt: Bool
    let showsResponseBody: Bool
    let responseCharacterLimit: Int
    let responseLineLimit: Int
    let responseCompactsBlankLines: Bool
    let responseElidesShortFinalLine: Bool
    let usesIndicatorLampStyle: Bool

    private static let pendingLatestResponseText = "Thinking..."

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            titleRow
                .padding(.horizontal, metrics.responseHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)

            if let userPromptText {
                promptTextView(userPromptText)
            }

            if let responseText {
                PopupAlignedText(
                    text: responseText,
                    fontSize: metrics.responseFontSize,
                    textOpacity: metrics.textOpacity,
                    lineLimit: responseLineLimit,
                    alignsTrailing: alignsTextTrailing,
                    elidesShortFinalLine: responseElidesShortFinalLine
                )
                    .popupTextShadow(metrics)
                    .padding(.horizontal, metrics.responseHorizontalPadding)
                    .padding(.top, responseTopPadding)
                    .padding(.bottom, metrics.responseVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
            }

            stateTimeRow
                .padding(.horizontal, metrics.responseHorizontalPadding)
                .padding(.top, -metrics.rowSpacing)
                .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
    }

    private var titleRow: some View {
        titleCluster
    }

    private var stateTimeRow: some View {
        PopupSessionStateTimeText(
            session: session,
            metrics: metrics,
            alignsTrailing: alignsTextTrailing
        )
    }

    private var titleCluster: some View {
        HStack(alignment: .top, spacing: metrics.titleSpacing) {
            providerIcon
            titleTextStack
        }
        .frame(maxWidth: alignsTextTrailing ? nil : .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
    }

    private var titleTextStack: some View {
        VStack(alignment: alignsTextTrailing ? .trailing : .leading, spacing: metrics.promptSpacing) {
            titleTextView
        }
        .layoutPriority(1)
        .frame(width: titleColumnWidth, alignment: alignsTextTrailing ? .trailing : .leading)
        .frame(maxWidth: alignsTextTrailing ? nil : .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
    }

    private var titleTextView: some View {
        PopupAlignedText(
            text: titleText,
            fontSize: metrics.titleFontSize,
            fontWeight: .semibold,
            textOpacity: metrics.textOpacity,
            lineLimit: 2,
            alignsTrailing: alignsTextTrailing
        )
            .popupTextShadow(metrics)
            .padding(.leading, metrics.titleHorizontalPadding)
            .padding(.trailing, alignsTextTrailing ? 0 : metrics.titleHorizontalPadding)
            .padding(.top, metrics.titleVerticalPadding)
            .padding(.bottom, titleBottomPadding)
            .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
    }

    private func promptTextView(_ text: String) -> some View {
        Text("› " + text)
            .font(.system(size: metrics.metadataFontSize, weight: .semibold))
            .foregroundStyle(agentStateDetailTextColor(for: session.state).opacity(metrics.textOpacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(alignsTextTrailing ? .trailing : .leading)
            .padding(.horizontal, metrics.responseHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: alignsTextTrailing ? .trailing : .leading)
            .popupTextShadow(metrics)
    }

    @ViewBuilder
    private var providerIcon: some View {
        Group {
            if usesIndicatorLampStyle {
                AgentIndicatorLampView(
                    agent: session.agent,
                    state: session.state,
                    iconSize: metrics.iconSize
                )
            } else {
                AnimatedAgentIconView(
                    agent: session.agent,
                    state: session.state,
                    iconSize: metrics.iconSize,
                    animatesWorkingIcon: true,
                    usesMonochromeIdleIcon: false
                )
            }
        }
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .padding(.top, metrics.titleVerticalPadding)
        .accessibilityHidden(true)
    }

    private var titleText: String {
        if session.state == .working,
           session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Thinking..."
        }

        return session.displayTitle
    }

    private var userPromptText: String? {
        guard showsUserPrompt,
              let prompt = AgentTextSanitizer.userPromptText(session.latestUserPrompt),
              !prompt.isEmpty,
              AgentSessionTitleSanitizer.normalized(prompt) != AgentSessionTitleSanitizer.normalized(titleText) else {
            return nil
        }

        return prompt
    }

    private var titleBottomPadding: CGFloat {
        userPromptText == nil ? metrics.titleVerticalPadding : 0
    }

    private var responseTopPadding: CGFloat {
        userPromptText == nil ? metrics.responseVerticalPadding : 0
    }

    private var titleColumnWidth: CGFloat? {
        guard alignsTextTrailing else {
            return nil
        }

        return min(measuredTitleColumnWidth, titleColumnMaxWidth)
    }

    private var measuredTitleColumnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: metrics.titleFontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidthLimit = max(titleColumnMaxWidth - metrics.titleHorizontalPadding, 1)
        let measuredWidth = (titleText as NSString).boundingRect(
            with: NSSize(width: textWidthLimit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).width
        return max(ceil(min(measuredWidth, textWidthLimit)) + metrics.titleHorizontalPadding, 1)
    }

    private var titleColumnMaxWidth: CGFloat {
        let titleRowWidth = rowContentWidth - (2 * metrics.responseHorizontalPadding)
        let fixedWidth = metrics.iconSize
            + metrics.titleSpacing
        return max(titleRowWidth - fixedWidth, 1)
    }

    private var responseText: String? {
        guard showsResponseBody, responseLineLimit > 0 else {
            return nil
        }

        if let text = AgentTextSanitizer.latestResponseText(
            session.latestResponseText,
            compactsBlankLines: responseCompactsBlankLines
        ) {
            return Self.truncated(text, to: responseCharacterLimit)
        }

        if session.isAwaitingLatestResponseText {
            return Self.pendingLatestResponseText
        }

        return nil
    }

    private static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let truncatedLimit = max(limit - 3, 1)
        let truncatedText = String(text.prefix(truncatedLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncatedText + "..."
    }
}

private struct PopupSessionStateTimeText: View {
    let session: AgentSession
    let metrics: PopupScaleMetrics
    var alignsTrailing = true

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            Text(stateTimeText(relativeTo: timeline.date))
                .monospacedDigit()
                .lineLimit(1)
                .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                .foregroundStyle(metadataColor.opacity(metrics.textOpacity))
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.metadataTopPadding)
                .padding(.bottom, metrics.metadataBottomPadding)
                .popupTextShadow(metrics)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var textAlignment: TextAlignment {
        alignsTrailing ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        alignsTrailing ? .trailing : .leading
    }

    private var metadataColor: Color {
        switch session.state {
        case .working, .waiting:
            Theme.stateColor(session.state, agent: session.agent).opacity(0.95)
        case .idle, .ended:
            agentStateDetailTextColor(for: session.state)
        }
    }

    private var accessibilityText: String {
        "\(session.state.displayName) \(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()))"
    }

    private func stateTimeText(relativeTo now: Date) -> String {
        "\(session.state.displayName) · \(relativeTimeText(relativeTo: now))"
    }

    private func relativeTimeText(relativeTo now: Date) -> String {
        let elapsed = now.timeIntervalSince(session.updatedAt)
        if elapsed < 1 {
            return "0s ago"
        }
        return Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct AnimatedAgentIconView: NSViewRepresentable {
    let agent: AgentKind
    let state: AgentState
    let iconSize: CGFloat
    let animatesWorkingIcon: Bool
    let usesMonochromeIdleIcon: Bool

    func makeNSView(context: Context) -> AnimatedAgentIconImageView {
        let imageView = AnimatedAgentIconImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        imageView.configure(
            agent: agent,
            state: state,
            iconSize: iconSize,
            animatesWorkingIcon: animatesWorkingIcon,
            usesMonochromeIdleIcon: usesMonochromeIdleIcon
        )
        return imageView
    }

    func updateNSView(_ imageView: AnimatedAgentIconImageView, context: Context) {
        imageView.configure(
            agent: agent,
            state: state,
            iconSize: iconSize,
            animatesWorkingIcon: animatesWorkingIcon,
            usesMonochromeIdleIcon: usesMonochromeIdleIcon
        )
    }

    static func dismantleNSView(_ imageView: AnimatedAgentIconImageView, coordinator: ()) {
        imageView.stopAnimating()
    }
}

private final class AnimatedAgentIconImageView: NSImageView {
    private var renderedAgent: AgentKind?
    private var renderedState: AgentState?
    private var renderedIconSize: CGFloat = 0
    private var renderedAnimatesWorkingIcon = false
    private var renderedUsesMonochromeIdleIcon = false

    override var intrinsicContentSize: NSSize {
        guard renderedIconSize > 0 else {
            return super.intrinsicContentSize
        }
        return NSSize(width: renderedIconSize, height: renderedIconSize)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopAnimating()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        if let renderedAgent,
           renderedState == .working,
           renderedAnimatesWorkingIcon {
            startAnimating(agent: renderedAgent)
        }
    }

    func configure(
        agent: AgentKind,
        state: AgentState,
        iconSize: CGFloat,
        animatesWorkingIcon: Bool,
        usesMonochromeIdleIcon: Bool
    ) {
        let sizeChanged = abs(renderedIconSize - iconSize) > 0.001
        let identityChanged = renderedAgent != agent
            || renderedState != state
            || renderedAnimatesWorkingIcon != animatesWorkingIcon
            || renderedUsesMonochromeIdleIcon != usesMonochromeIdleIcon

        renderedAgent = agent
        renderedState = state
        renderedAnimatesWorkingIcon = animatesWorkingIcon
        renderedUsesMonochromeIdleIcon = usesMonochromeIdleIcon

        if sizeChanged {
            renderedIconSize = iconSize
            setFrameSize(NSSize(width: iconSize, height: iconSize))
            invalidateIntrinsicContentSize()
        }

        guard state == .working, animatesWorkingIcon else {
            stopAnimating()
            renderStaticIcon(
                agent: agent,
                state: state,
                usesMonochromeIdleIcon: usesMonochromeIdleIcon,
                force: identityChanged
            )
            return
        }

        renderStaticIcon(
            agent: agent,
            state: state,
            usesMonochromeIdleIcon: usesMonochromeIdleIcon,
            force: identityChanged || image == nil
        )
        startAnimating(agent: agent)
    }

    func stopAnimating() {
        AgentIconHighlightLayer.stop(in: self)
    }

    private func startAnimating(agent: AgentKind) {
        guard let maskImage = AgentImages.menuHeaderIconMaskImage(for: agent, color: true) else {
            return
        }

        let imageSize = image?.size ?? NSSize(width: renderedIconSize, height: renderedIconSize)
        let imageRect = AgentIconHighlightLayer.aspectFitRect(
            contentSize: imageSize,
            in: bounds
        )
        AgentIconHighlightLayer.start(
            in: self,
            imageRect: imageRect,
            maskImage: maskImage,
            duration: AgentIconAnimation.highlightDuration
        )
    }

    private func renderStaticIcon(
        agent: AgentKind,
        state: AgentState,
        usesMonochromeIdleIcon: Bool,
        force: Bool
    ) {
        guard force || image == nil else {
            return
        }
        image = AgentImages.menuHeaderIcon(
            for: agent,
            color: !(usesMonochromeIdleIcon && state == .idle),
            state: state
        )
    }
}

private enum AgentIndicatorLamp {
    static let menuBarViewSize = NSSize(width: 18, height: 18)
    static let pulseHalfPeriod: TimeInterval = Theme.Motion.lampPulsePeriod
    static let pulseHaloFloorOpacity: Float = 0.12
    static let pulseHaloFloorScale: CGFloat = 0.8
    static let pulseCoreFloorOpacity: Float = 0.55

    static func coreDiameter(forIconSize iconSize: CGFloat) -> CGFloat {
        max(iconSize * 0.3, 4)
    }

    static func haloDiameter(forIconSize iconSize: CGFloat) -> CGFloat {
        max(iconSize, coreDiameter(forIconSize: iconSize) + 2)
    }

    static func color(for agent: AgentKind, state: AgentState) -> NSColor {
        Theme.state(state, agent: agent)
    }

    static func coreHighlightColor(for color: NSColor) -> NSColor {
        color.blended(withFraction: 0.45, of: .white) ?? color
    }

    static func coreOpacity(for state: AgentState) -> Float {
        switch state {
        case .working, .waiting:
            1
        case .idle:
            0.45
        case .ended:
            0.35
        }
    }

    static func haloOpacity(for state: AgentState) -> Float {
        switch state {
        case .working:
            1
        case .waiting:
            0.8
        case .idle:
            0.15
        case .ended:
            0
        }
    }
}

private struct AgentIndicatorLampView: NSViewRepresentable {
    let agent: AgentKind
    let state: AgentState
    let iconSize: CGFloat
    var animatesWorkingLamp = true

    func makeNSView(context: Context) -> AgentIndicatorLampNSView {
        let view = AgentIndicatorLampNSView()
        view.configure(
            agent: agent,
            state: state,
            iconSize: iconSize,
            animatesWorkingLamp: animatesWorkingLamp && !Theme.Motion.reduceMotion
        )
        return view
    }

    func updateNSView(_ view: AgentIndicatorLampNSView, context: Context) {
        view.configure(
            agent: agent,
            state: state,
            iconSize: iconSize,
            animatesWorkingLamp: animatesWorkingLamp && !Theme.Motion.reduceMotion
        )
    }

    static func dismantleNSView(_ view: AgentIndicatorLampNSView, coordinator: ()) {
        view.stopAnimating()
    }
}

private final class AgentIndicatorLampNSView: NSView {
    private static let pulseAnimationKey = "agentSessionsIndicatorLampPulse"

    private let haloLayer = CAGradientLayer()
    private let coreLayer = CAGradientLayer()
    private var renderedAgent: AgentKind?
    private var renderedState: AgentState?
    private var renderedIconSize: CGFloat = 0
    private var renderedAnimatesWorkingLamp = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        haloLayer.type = .radial
        haloLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        haloLayer.endPoint = CGPoint(x: 1, y: 1)
        haloLayer.locations = [0, 0.35, 0.72, 1]

        coreLayer.type = .radial
        coreLayer.startPoint = CGPoint(x: 0.5, y: 0.58)
        coreLayer.endPoint = CGPoint(x: 1, y: 1)
        coreLayer.masksToBounds = true

        layer?.addSublayer(haloLayer)
        layer?.addSublayer(coreLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        layoutLampLayers()
        syncPulseAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLampAppearance()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopAnimating()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func configure(
        agent: AgentKind,
        state: AgentState,
        iconSize: CGFloat,
        animatesWorkingLamp: Bool
    ) {
        let changed = renderedAgent != agent
            || renderedState != state
            || abs(renderedIconSize - iconSize) > 0.001
            || renderedAnimatesWorkingLamp != animatesWorkingLamp

        renderedAgent = agent
        renderedState = state
        renderedIconSize = iconSize
        renderedAnimatesWorkingLamp = animatesWorkingLamp

        guard changed else {
            return
        }

        layoutLampLayers()
        applyLampAppearance()
        syncPulseAnimation()
    }

    func stopAnimating() {
        haloLayer.removeAnimation(forKey: Self.pulseAnimationKey)
        coreLayer.removeAnimation(forKey: Self.pulseAnimationKey)
    }

    private func layoutLampLayers() {
        guard renderedIconSize > 0 else {
            return
        }

        let coreDiameter = AgentIndicatorLamp.coreDiameter(forIconSize: renderedIconSize)
        let haloDiameter = AgentIndicatorLamp.haloDiameter(forIconSize: renderedIconSize)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloLayer.bounds = CGRect(x: 0, y: 0, width: haloDiameter, height: haloDiameter)
        haloLayer.position = center
        haloLayer.contentsScale = contentsScale
        coreLayer.bounds = CGRect(x: 0, y: 0, width: coreDiameter, height: coreDiameter)
        coreLayer.position = center
        coreLayer.cornerRadius = coreDiameter / 2
        coreLayer.contentsScale = contentsScale
        CATransaction.commit()
    }

    private func applyLampAppearance() {
        guard let renderedAgent, let renderedState else {
            return
        }

        let color = AgentIndicatorLamp.color(for: renderedAgent, state: renderedState)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            haloLayer.colors = [
                color.cgColor,
                color.withAlphaComponent(0.55).cgColor,
                color.withAlphaComponent(0.18).cgColor,
                color.withAlphaComponent(0).cgColor
            ]
            haloLayer.opacity = AgentIndicatorLamp.haloOpacity(for: renderedState)
            coreLayer.colors = [
                AgentIndicatorLamp.coreHighlightColor(for: color).cgColor,
                color.cgColor
            ]
            coreLayer.opacity = AgentIndicatorLamp.coreOpacity(for: renderedState)
            CATransaction.commit()
        }
    }

    private func syncPulseAnimation() {
        let shouldPulse = renderedState == .working
            && renderedAnimatesWorkingLamp
            && window != nil
            && !Theme.Motion.reduceMotion
        guard shouldPulse else {
            stopAnimating()
            return
        }

        if haloLayer.animation(forKey: Self.pulseAnimationKey) == nil {
            let opacityPulse = CABasicAnimation(keyPath: "opacity")
            opacityPulse.fromValue = AgentIndicatorLamp.haloOpacity(for: .working)
            opacityPulse.toValue = AgentIndicatorLamp.pulseHaloFloorOpacity

            let scalePulse = CABasicAnimation(keyPath: "transform.scale")
            scalePulse.fromValue = 1.0
            scalePulse.toValue = AgentIndicatorLamp.pulseHaloFloorScale

            let group = CAAnimationGroup()
            group.animations = [opacityPulse, scalePulse]
            Self.applyPulseTiming(to: group)
            haloLayer.add(group, forKey: Self.pulseAnimationKey)
        }

        if coreLayer.animation(forKey: Self.pulseAnimationKey) == nil {
            let corePulse = CABasicAnimation(keyPath: "opacity")
            corePulse.fromValue = AgentIndicatorLamp.coreOpacity(for: .working)
            corePulse.toValue = AgentIndicatorLamp.pulseCoreFloorOpacity
            Self.applyPulseTiming(to: corePulse)
            coreLayer.add(corePulse, forKey: Self.pulseAnimationKey)
        }
    }

    private static func applyPulseTiming(to animation: CAAnimation) {
        animation.duration = AgentIndicatorLamp.pulseHalfPeriod
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
    }
}

private struct MenuBarAgentIconView: View {
    let agent: AgentKind
    let state: AgentState
    let iconSize: NSSize
    let usesIndicatorLampStyle: Bool

    var body: some View {
        Group {
            if usesIndicatorLampStyle {
                AgentIndicatorLampView(
                    agent: agent,
                    state: state,
                    iconSize: min(iconSize.width, iconSize.height)
                )
            } else {
                AnimatedAgentIconView(
                    agent: agent,
                    state: state,
                    iconSize: max(iconSize.width, iconSize.height),
                    animatesWorkingIcon: true,
                    usesMonochromeIdleIcon: true
                )
            }
        }
        .frame(width: iconSize.width, height: iconSize.height)
        .accessibilityHidden(true)
    }
}

private final class MenuBarAgentIconHostingView: NSHostingView<MenuBarAgentIconView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct PopupAlignedText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    var fontWeight: NSFont.Weight = .regular
    let textOpacity: Double
    let lineLimit: Int
    var alignsTrailing = false
    var elidesShortFinalLine = false

    func makeNSView(context: Context) -> AlignedTextView {
        let textView = AlignedTextView()
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateNSView(_ textView: AlignedTextView, context: Context) {
        configure(textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AlignedTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }

        configure(nsView)
        return nsView.measuredSize(width: width)
    }

    private func configure(_ textView: AlignedTextView) {
        textView.configure(
            text: text,
            fontSize: fontSize,
            fontWeight: fontWeight,
            textOpacity: textOpacity,
            lineLimit: lineLimit,
            alignsTrailing: alignsTrailing,
            elidesShortFinalLine: elidesShortFinalLine
        )
    }

    final class AlignedTextView: NSView {
        private static let softBreak = "\u{200B}"
        private static let softBreakCharacters = Set<Character>(".:/_-()[]{}")
        private static let shortFinalLineThreshold = 5

        private var renderedText = ""
        private var renderedFontSize: CGFloat = 0
        private var renderedFontWeight: NSFont.Weight = .regular
        private var renderedTextOpacity: Double = 1
        private var renderedLineLimit = 1
        private var renderedAlignsTrailing = false
        private var renderedElidesShortFinalLine = false
        private var renderedFont = NSFont.systemFont(ofSize: 10)
        private var preferredMaxLayoutWidth: CGFloat = 0
        private var cachedLayoutWidth: CGFloat?
        private var cachedLayoutResult: LayoutResult?

        override var isOpaque: Bool {
            false
        }

        func configure(
            text: String,
            fontSize: CGFloat,
            fontWeight: NSFont.Weight,
            textOpacity: Double,
            lineLimit: Int,
            alignsTrailing: Bool,
            elidesShortFinalLine: Bool
        ) {
            let normalizedOpacity = min(max(textOpacity, 0), 1)
            let normalizedLineLimit = max(lineLimit, 1)

            let layoutChanged = renderedText != text
                || abs(renderedFontSize - fontSize) > 0.001
                || renderedFontWeight != fontWeight
                || renderedLineLimit != normalizedLineLimit
                || renderedElidesShortFinalLine != elidesShortFinalLine
            let displayChanged = layoutChanged
                || abs(renderedTextOpacity - normalizedOpacity) > 0.001
                || renderedAlignsTrailing != alignsTrailing

            guard displayChanged else {
                return
            }

            renderedText = text
            renderedFontSize = fontSize
            renderedFontWeight = fontWeight
            renderedTextOpacity = normalizedOpacity
            renderedLineLimit = normalizedLineLimit
            renderedAlignsTrailing = alignsTrailing
            renderedElidesShortFinalLine = elidesShortFinalLine
            renderedFont = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)

            if layoutChanged {
                invalidateLayoutCache()
                invalidateIntrinsicContentSize()
            }
            needsDisplay = true
        }

        func measuredSize(width: CGFloat) -> CGSize {
            preferredMaxLayoutWidth = width
            let result = layoutLines(width: width)
            let lineCount = max(result.lines.count, renderedText.isEmpty ? 0 : 1)
            return CGSize(width: width, height: lineHeight * CGFloat(lineCount))
        }

        override func layout() {
            super.layout()

            guard bounds.width.isFinite, bounds.width > 0 else {
                return
            }

            let roundedWidth = bounds.width.rounded(.down)
            guard abs(preferredMaxLayoutWidth - roundedWidth) > 0.5 else {
                return
            }

            preferredMaxLayoutWidth = roundedWidth
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }

        override var intrinsicContentSize: NSSize {
            guard preferredMaxLayoutWidth.isFinite, preferredMaxLayoutWidth > 0 else {
                return NSSize(width: NSView.noIntrinsicMetric, height: lineHeight)
            }

            return NSSize(width: NSView.noIntrinsicMetric, height: measuredSize(width: preferredMaxLayoutWidth).height)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            guard bounds.width.isFinite,
                  bounds.width > 0,
                  let context = NSGraphicsContext.current?.cgContext else {
                return
            }

            let result = layoutLines(width: bounds.width)
            var baselineY = bounds.height - renderedFont.ascender

            context.saveGState()
            context.textMatrix = .identity
            context.setAlpha(renderedTextOpacity)

            for layoutLine in result.lines {
                defer {
                    baselineY -= lineHeight
                }

                guard let line = layoutLine.line else {
                    continue
                }

                context.textPosition = CGPoint(x: originX(for: layoutLine, width: bounds.width), y: baselineY)
                CTLineDraw(line, context)
            }

            context.restoreGState()
        }

        private func originX(for layoutLine: LayoutLine, width: CGFloat) -> CGFloat {
            guard renderedAlignsTrailing, width > 0, layoutLine.naturalWidth > 0 else {
                return 0
            }

            return max(width - layoutLine.naturalWidth, 0)
        }

        private func layoutLines(width: CGFloat) -> LayoutResult {
            let normalizedWidth = normalizedLayoutWidth(width)
            if let cachedLayoutWidth,
               abs(cachedLayoutWidth - normalizedWidth) <= 0.5,
               let cachedLayoutResult {
                return cachedLayoutResult
            }

            let result = makeLayoutLines(width: width)
            cachedLayoutWidth = normalizedWidth
            cachedLayoutResult = result
            return result
        }

        private func makeLayoutLines(width: CGFloat) -> LayoutResult {
            let attributedText = attributedText()
            let rawString = attributedText.string as NSString
            let totalLength = rawString.length
            guard totalLength > 0, width > 0 else {
                return LayoutResult(lines: [], consumedLength: 0, totalLength: totalLength)
            }

            let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
            var lines: [LayoutLine] = []
            var index = 0

            while index < totalLength && lines.count < renderedLineLimit {
                let paragraph = paragraphRange(in: rawString, from: index)
                if paragraph.remainingLength == 0 {
                    lines.append(LayoutLine(
                        line: nil,
                        naturalWidth: 0,
                        visibleCharacterCount: 0,
                        endsParagraph: true
                    ))
                    index = paragraph.upperBound
                    continue
                }

                let suggestedLineLength = suggestedLineLength(
                    typesetter: typesetter,
                    startIndex: index,
                    width: width
                )
                let lineLength = min(max(suggestedLineLength, 1), paragraph.remainingLength)
                let range = CFRange(location: index, length: lineLength)
                let line = CTTypesetterCreateLine(typesetter, range)
                let endsParagraph = lineLength >= paragraph.remainingLength

                lines.append(LayoutLine(
                    line: line,
                    naturalWidth: naturalWidth(for: line),
                    visibleCharacterCount: visibleCharacterCount(in: rawString, range: range),
                    endsParagraph: endsParagraph
                ))
                index += lineLength

                if endsParagraph {
                    index = paragraph.upperBound
                } else {
                    index = skippingSoftWrapWhitespace(in: rawString, from: index, upperBound: paragraph.contentUpperBound)
                }
            }

            if renderedElidesShortFinalLine {
                lines = linesByElidingShortFinalLine(lines, width: width)
            }

            return LayoutResult(lines: lines, consumedLength: index, totalLength: totalLength)
        }

        private func normalizedLayoutWidth(_ width: CGFloat) -> CGFloat {
            max(width.rounded(.toNearestOrAwayFromZero), 0)
        }

        private func invalidateLayoutCache() {
            cachedLayoutWidth = nil
            cachedLayoutResult = nil
        }

        private func linesByElidingShortFinalLine(_ lines: [LayoutLine], width: CGFloat) -> [LayoutLine] {
            guard lines.count >= 2,
                  let lastLine = lines.last,
                  lastLine.line != nil,
                  lastLine.visibleCharacterCount > 0,
                  lastLine.visibleCharacterCount <= Self.shortFinalLineThreshold else {
                return lines
            }

            let previousIndex = lines.index(before: lines.endIndex - 1)
            guard lines[previousIndex].line != nil else {
                return lines
            }

            var adjustedLines = lines
            adjustedLines[previousIndex] = ellipsizedLine(adjustedLines[previousIndex], width: width)
            adjustedLines.removeLast()
            return adjustedLines
        }

        private func ellipsizedLine(_ layoutLine: LayoutLine, width: CGFloat) -> LayoutLine {
            guard let line = layoutLine.line else {
                return layoutLine
            }

            let token = CTLineCreateWithAttributedString(attributedEllipsis())
            let truncatedLine = CTLineCreateTruncatedLine(line, Double(width), .end, token) ?? token

            return LayoutLine(
                line: truncatedLine,
                naturalWidth: naturalWidth(for: truncatedLine),
                visibleCharacterCount: layoutLine.visibleCharacterCount,
                endsParagraph: false
            )
        }

        private func naturalWidth(for line: CTLine) -> CGFloat {
            max(
                0,
                CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            )
        }

        private func visibleCharacterCount(in string: NSString, range: CFRange) -> Int {
            guard range.location >= 0, range.length > 0 else {
                return 0
            }

            let substring = string.substring(with: NSRange(location: range.location, length: range.length))
                .replacingOccurrences(of: Self.softBreak, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return substring.count
        }

        private func suggestedLineLength(typesetter: CTTypesetter, startIndex: Int, width: CGFloat) -> Int {
            let lineBreak = CTTypesetterSuggestLineBreak(typesetter, startIndex, Double(width))
            if lineBreak > 0 {
                return lineBreak
            }

            return max(CTTypesetterSuggestClusterBreak(typesetter, startIndex, Double(width)), 1)
        }

        private func paragraphRange(in string: NSString, from index: Int) -> ParagraphRange {
            let searchRange = NSRange(location: index, length: string.length - index)
            let newlineRange = string.rangeOfCharacter(from: .newlines, options: [], range: searchRange)

            guard newlineRange.location != NSNotFound else {
                return ParagraphRange(
                    remainingLength: string.length - index,
                    contentUpperBound: string.length,
                    upperBound: string.length
                )
            }

            return ParagraphRange(
                remainingLength: newlineRange.location - index,
                contentUpperBound: newlineRange.location,
                upperBound: newlineRange.location + newlineRange.length
            )
        }

        private func skippingSoftWrapWhitespace(in string: NSString, from index: Int, upperBound: Int) -> Int {
            var currentIndex = index

            while currentIndex < upperBound {
                let character = string.character(at: currentIndex)
                guard character == 0x200B || isWrappingWhitespace(character) else {
                    break
                }
                currentIndex += 1
            }

            return currentIndex
        }

        private func isWrappingWhitespace(_ character: unichar) -> Bool {
            guard let scalar = UnicodeScalar(Int(character)) else {
                return false
            }
            return CharacterSet.whitespaces.contains(scalar)
        }

        private func attributedText() -> NSAttributedString {
            let font = CTFontCreateWithName(renderedFont.fontName as CFString, renderedFont.pointSize, nil)

            return NSAttributedString(
                string: Self.textWithSoftBreaks(renderedText),
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.white.cgColor
                ]
            )
        }

        private func attributedEllipsis() -> NSAttributedString {
            let font = CTFontCreateWithName(renderedFont.fontName as CFString, renderedFont.pointSize, nil)

            return NSAttributedString(
                string: "...",
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: NSColor.white.cgColor
                ]
            )
        }

        private static func textWithSoftBreaks(_ text: String) -> String {
            var result = ""
            var token = ""

            func flushToken() {
                guard !token.isEmpty else {
                    return
                }

                if token.count >= 24 {
                    for character in token {
                        result.append(character)
                        if softBreakCharacters.contains(character) {
                            result.append(softBreak)
                        }
                    }
                } else {
                    result.append(token)
                }

                token.removeAll(keepingCapacity: true)
            }

            for character in text {
                if character.isWhitespace {
                    flushToken()
                    result.append(character)
                } else {
                    token.append(character)
                }
            }

            flushToken()
            return result
        }

        private var lineHeight: CGFloat {
            max(ceil(renderedFont.ascender - renderedFont.descender + renderedFont.leading), 1)
        }

        private struct LayoutResult {
            let lines: [LayoutLine]
            let consumedLength: Int
            let totalLength: Int

            var isTruncated: Bool {
                consumedLength < totalLength
            }
        }

        private struct LayoutLine {
            let line: CTLine?
            let naturalWidth: CGFloat
            let visibleCharacterCount: Int
            let endsParagraph: Bool
        }

        private struct ParagraphRange {
            let remainingLength: Int
            let contentUpperBound: Int
            let upperBound: Int
        }
    }
}

private struct PopupScaleMetrics {
    let scale: CGFloat
    let textOpacity: Double
    let textShadowStrength: Double
    let textShadowDistance: CGFloat
    let textShadowRadius: CGFloat

    init(
        scale: CGFloat,
        textOpacity: Double,
        textShadowStrength: Double,
        textShadowDistance: CGFloat,
        textShadowRadius: CGFloat
    ) {
        self.scale = min(max(scale, 0.5), 1.5)
        self.textOpacity = min(max(textOpacity, 0.35), 1.0)
        self.textShadowStrength = min(max(textShadowStrength, 0), 3.0)
        self.textShadowDistance = min(max(textShadowDistance, 0), 12)
        self.textShadowRadius = min(max(textShadowRadius, 0), 16)
    }

    var stackSpacing: CGFloat { 10 * scale }
    var rowSpacing: CGFloat { 2 * scale }
    var titleSpacing: CGFloat { 1 * scale }
    var promptSpacing: CGFloat { 0.5 * scale }
    var horizontalPadding: CGFloat { 6 * scale }
    var verticalPadding: CGFloat { 5 * scale }
    var titleHorizontalPadding: CGFloat { 2 * scale }
    var titleVerticalPadding: CGFloat { 2 * scale }
    var metadataTopPadding: CGFloat { 0.5 * scale }
    var metadataBottomPadding: CGFloat { 1 * scale }
    var responseHorizontalPadding: CGFloat { 6 * scale }
    var responseVerticalPadding: CGFloat { 3 * scale }
    var shadowBleedPadding: CGFloat { textShadowRadius + textShadowDistance + 2 * scale }
    var glassCornerRadius: CGFloat { 18 * scale }
    var glassBorderWidth: CGFloat { max(0.75, 0.85 * scale) }
    var glassShadowRadius: CGFloat { 14 * scale }
    var glassShadowYOffset: CGFloat { 5 * scale }
    var iconSize: CGFloat { 16 * scale }
    var titleFontSize: CGFloat { 12 * scale }
    var metadataFontSize: CGFloat { 8.5 * scale }
    var responseFontSize: CGFloat { 10.5 * scale }

    func textShadowLayerOpacity(_ layer: Int) -> Double {
        min(max(textShadowStrength - Double(layer), 0), 1)
    }
}

private extension View {
    func popupTextShadow(_ metrics: PopupScaleMetrics) -> some View {
        self
            .shadow(
                color: .black.opacity(metrics.textShadowLayerOpacity(0)),
                radius: metrics.textShadowRadius,
                x: 0,
                y: metrics.textShadowDistance
            )
            .shadow(
                color: .black.opacity(metrics.textShadowLayerOpacity(1)),
                radius: metrics.textShadowRadius,
                x: 0,
                y: metrics.textShadowDistance
            )
            .shadow(
                color: .black.opacity(metrics.textShadowLayerOpacity(2)),
                radius: metrics.textShadowRadius,
                x: 0,
                y: metrics.textShadowDistance
            )
    }
}

@MainActor
private final class DropdownMenuRefreshClock: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var isRunning = false

    private let interval: TimeInterval
    private var timer: Timer?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func start() {
        now = Date()

        guard timer == nil else {
            return
        }

        isRunning = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let providerVisibility = ProviderVisibilityStore.shared
    private let keyboardShortcuts = KeyboardShortcutStore.shared
    private let menuRefreshClock = DropdownMenuRefreshClock(interval: 1)
    private let menu = NSMenu()
    private var statusItems: [AgentKind: NSStatusItem] = [:]
    private var statusIconHostingViews: [AgentKind: MenuBarAgentIconHostingView] = [:]
    private var fallbackStatusItem: NSStatusItem?
    private var statusIconRefreshTimer: Timer?
    private var statusIconRefreshInterval: TimeInterval?
    private var statusIconRefreshRepeats = false
    private var statusIconRefreshTargetDate: Date?
    private var statusIconDisplayStates: [AgentKind: AgentState] = [:]
    private var statusIconRenderKeys: [AgentKind: StatusIconRenderKey] = [:]
    private var fallbackStatusIconRendered = false
    private var lastStatusIconStateRefreshDate = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var isMenuOpen = false
    private var needsMenuRebuild = true
    private var isMenuResizeScheduled = false
    private var hostedViews: [NSView] = []
    private static let statusItemHorizontalPadding: CGFloat = 1
    private static let menuLayoutSizeEpsilon: CGFloat = 0.5
    private static let statusIconStateRefreshInterval: TimeInterval = 1
    private static let statusIconRefreshTargetEpsilon: TimeInterval = 0.05

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

        providerVisibility.$menuBarEnabled
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

        providerVisibility.$usesIndicatorLampStyle
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyIndicatorLampStyleChange()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyIndicatorLampStyleChange()
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

        providerVisibility.$latestResponseHideAfterInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
                self?.resizeMenuIfOpen()
            }
            .store(in: &cancellables)

        providerVisibility.$latestResponseCompactsBlankLines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
                self?.resizeMenuIfOpen()
            }
            .store(in: &cancellables)

        providerVisibility.$dropdownShowsUserPrompt
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

        providerVisibility.$popupEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$popupGlassEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$popupTextShadowEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        providerVisibility.$popupWindowPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        keyboardShortcuts.$popupToggleShortcut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setNeedsMenuRebuild()
            }
            .store(in: &cancellables)

        rebuildMenu()
        startStatusIconRefreshTimer()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        isMenuResizeScheduled = false
        menuRefreshClock.start()
        rebuildMenuIfNeeded()
        resizeMenuNow()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshClock.stop()
        isMenuOpen = false
        isMenuResizeScheduled = false
    }

    private func configureStatusButton(_ statusItem: NSStatusItem, agent: AgentKind?) {
        guard let button = statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let providerName = agent.map {
            providerVisibility.usesIndicatorLampStyle ? $0.shortDisplayName : $0.displayName
        }
        let label = providerName.map { "Agent Sessions - \($0)" } ?? "Agent Sessions"
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func applyIndicatorLampStyleChange() {
        for (agent, statusItem) in statusItems {
            configureStatusButton(statusItem, agent: agent)
        }
        statusIconHostingViews.values.forEach { $0.removeFromSuperview() }
        statusIconHostingViews.removeAll()
        statusIconRenderKeys.removeAll()
        updateStatusIcons(refreshDisplayStates: false)
        setNeedsMenuRebuild()
    }

    private func syncStatusItems() {
        guard providerVisibility.menuBarEnabled else {
            removeAllStatusItems()
            return
        }

        let visibleAgents = providerVisibility.orderedAgents(for: .menuBar)
            .filter { providerVisibility.isMenuBarIconVisible(for: $0) }
        let visibleSet = Set(visibleAgents)

        for agent in Array(statusItems.keys) where !visibleSet.contains(agent) {
            if let statusItem = statusItems.removeValue(forKey: agent) {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusIconHostingViews[agent]?.removeFromSuperview()
            statusIconHostingViews[agent] = nil
            statusIconDisplayStates[agent] = nil
            statusIconRenderKeys[agent] = nil
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

    private func removeAllStatusItems() {
        for statusItem in statusItems.values {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()
        statusIconHostingViews.values.forEach { $0.removeFromSuperview() }
        statusIconHostingViews.removeAll()
        removeFallbackStatusItem()
        statusIconDisplayStates.removeAll()
        statusIconRenderKeys.removeAll()
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
        fallbackStatusIconRendered = false
    }

    private func updateStatusIcons(refreshDisplayStates: Bool = true) {
        let now = Date()
        let shouldRefreshDisplayStates = refreshDisplayStates
            || now.timeIntervalSince(lastStatusIconStateRefreshDate) >= Self.statusIconStateRefreshInterval
        let hasAnimatedIcon = renderStatusIcons(now: now, refreshDisplayStates: shouldRefreshDisplayStates)
        if shouldRefreshDisplayStates {
            lastStatusIconStateRefreshDate = now
        }
        updateStatusIconRefreshTimer(animated: hasAnimatedIcon, now: now)
    }

    private func renderStatusIcons(now: Date, refreshDisplayStates: Bool) -> Bool {
        var hasAnimatedIcon = false

        for (agent, statusItem) in statusItems {
            let displayState = statusIconDisplayState(for: agent, now: now, refreshDisplayState: refreshDisplayStates)
            hasAnimatedIcon = hasAnimatedIcon || displayState == .working
            let renderKey = StatusIconRenderKey(
                state: displayState,
                usesIndicatorLampStyle: providerVisibility.usesIndicatorLampStyle
            )
            if statusIconRenderKeys[agent] != renderKey || statusIconHostingViews[agent] == nil {
                updateMenuBarIconView(
                    for: agent,
                    state: displayState,
                    statusItem: statusItem
                )
                statusIconRenderKeys[agent] = renderKey
            }
        }

        if let fallbackStatusItem {
            guard !fallbackStatusIconRendered else {
                return hasAnimatedIcon
            }
            let image = AgentImages.menuBarStatus([])
            fallbackStatusItem.button?.image = image
            fallbackStatusItem.length = image.size.width + Self.statusItemHorizontalPadding
            fallbackStatusIconRendered = true
        }

        return hasAnimatedIcon
    }

    private func startStatusIconRefreshTimer() {
        guard statusIconRefreshTimer == nil else {
            return
        }

        updateStatusIconRefreshTimer(animated: false, now: Date())
    }

    private func updateStatusIconRefreshTimer(animated: Bool, now: Date) {
        if animated {
            scheduleStatusIconRefreshTimer(
                interval: Self.statusIconStateRefreshInterval,
                repeats: true,
                targetDate: nil,
                refreshDisplayStatesOnFire: true
            )
            return
        }

        guard let delay = nextTransientStartupRefreshDelay(now: now) else {
            invalidateStatusIconRefreshTimer()
            return
        }

        let targetDate = now.addingTimeInterval(delay)
        scheduleStatusIconRefreshTimer(
            interval: delay,
            repeats: false,
            targetDate: targetDate,
            refreshDisplayStatesOnFire: true
        )
    }

    private func scheduleStatusIconRefreshTimer(
        interval: TimeInterval,
        repeats: Bool,
        targetDate: Date?,
        refreshDisplayStatesOnFire: Bool
    ) {
        if repeats,
           statusIconRefreshRepeats,
           statusIconRefreshInterval == interval {
            return
        }

        if !repeats,
           !statusIconRefreshRepeats,
           let statusIconRefreshTargetDate,
           let targetDate,
           abs(statusIconRefreshTargetDate.timeIntervalSince(targetDate)) <= Self.statusIconRefreshTargetEpsilon {
            return
        }

        statusIconRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !repeats {
                    self.clearStatusIconRefreshTimerState()
                }
                self.updateStatusIcons(refreshDisplayStates: refreshDisplayStatesOnFire)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusIconRefreshTimer = timer
        statusIconRefreshInterval = interval
        statusIconRefreshRepeats = repeats
        statusIconRefreshTargetDate = targetDate
    }

    private func invalidateStatusIconRefreshTimer() {
        statusIconRefreshTimer?.invalidate()
        clearStatusIconRefreshTimerState()
    }

    private func clearStatusIconRefreshTimerState() {
        statusIconRefreshTimer = nil
        statusIconRefreshInterval = nil
        statusIconRefreshRepeats = false
        statusIconRefreshTargetDate = nil
    }

    private func nextTransientStartupRefreshDelay(now: Date) -> TimeInterval? {
        let expirationDates = AgentKind.allCases.flatMap { agent in
            controller.store.visibleSessions(for: agent, now: now).compactMap { session in
                AgentDisplayState.transientStartupExpirationDate(for: session, now: now)
            }
        }

        guard let soonestExpiration = expirationDates.min() else {
            return nil
        }

        return max(0.05, soonestExpiration.timeIntervalSince(now))
    }

    private func statusIconDisplayState(for agent: AgentKind, now: Date, refreshDisplayState: Bool) -> AgentState {
        if !refreshDisplayState, let displayState = statusIconDisplayStates[agent] {
            return displayState
        }

        let aggregateState = controller.store.aggregateState(for: agent, now: now)
        let displayState = AgentDisplayState.displayState(
            for: agent,
            aggregateState: aggregateState,
            store: controller.store,
            now: now
        )
        statusIconDisplayStates[agent] = displayState
        return displayState
    }

    private struct StatusIconRenderKey: Equatable {
        let state: AgentState
        let usesIndicatorLampStyle: Bool
    }

    private func updateMenuBarIconView(for agent: AgentKind, state: AgentState, statusItem: NSStatusItem) {
        guard let button = statusItem.button else {
            return
        }

        let usesIndicatorLampStyle = providerVisibility.usesIndicatorLampStyle
        let iconSize = usesIndicatorLampStyle
            ? AgentIndicatorLamp.menuBarViewSize
            : AgentImages.menuBarIconSize(for: agent)
        statusItem.length = iconSize.width + Self.statusItemHorizontalPadding
        button.image = nil

        let iconView = MenuBarAgentIconView(
            agent: agent,
            state: state,
            iconSize: iconSize,
            usesIndicatorLampStyle: usesIndicatorLampStyle
        )
        if let hostingView = statusIconHostingViews[agent] {
            hostingView.rootView = iconView
            return
        }

        let hostingView = MenuBarAgentIconHostingView(rootView: iconView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        hostingView.setContentHuggingPriority(.required, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.widthAnchor.constraint(equalToConstant: iconSize.width),
            hostingView.heightAnchor.constraint(equalToConstant: iconSize.height)
        ])
        statusIconHostingViews[agent] = hostingView
    }

    private func setNeedsMenuRebuild() {
        needsMenuRebuild = true

        guard isMenuOpen else {
            return
        }

        resizeMenuIfOpen()
    }

    private func rebuildMenuIfNeeded() {
        guard needsMenuRebuild else {
            return
        }

        rebuildMenu()
    }

    private func resizeMenuIfOpen() {
        guard isMenuOpen, !isMenuResizeScheduled else {
            return
        }

        isMenuResizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isMenuResizeScheduled = false
            guard self.isMenuOpen else {
                return
            }
            self.resizeMenuNow()
        }
    }

    private func resizeMenuNow() {
        var didResize = false

        for view in hostedViews {
            view.layoutSubtreeIfNeeded()
            let fittingSize = view.fittingSize
            guard !Self.isMenuLayoutSize(view.frame.size, closeTo: fittingSize) else {
                continue
            }

            view.frame.size = fittingSize
            didResize = true
        }

        if didResize {
            menu.update()
        }
    }

    private static func isMenuLayoutSize(_ lhs: NSSize, closeTo rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) <= menuLayoutSizeEpsilon
            && abs(lhs.height - rhs.height) <= menuLayoutSizeEpsilon
    }

    private func rebuildMenu() {
        needsMenuRebuild = false
        isMenuResizeScheduled = false
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

        menu.addItem(popupToggleMenuItem())
        menu.addItem(popupStyleMenuItem())
        menu.addItem(popupPositionMenuItem())
        menu.addItem(actionItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit Agent Sessions", action: #selector(quit), keyEquivalent: "q"))
    }

    private func popupToggleMenuItem() -> NSMenuItem {
        let item = actionItem(title: "Popup", action: #selector(togglePopup))
        item.image = menuSymbol(named: "bubble.left", accessibilityDescription: "Popup")
        item.state = providerVisibility.popupEnabled ? .on : .off
        applyPopupToggleShortcut(to: item)
        return item
    }

    private func popupStyleMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Popup Style", action: nil, keyEquivalent: "")
        item.image = menuSymbol(named: "paintbrush", accessibilityDescription: "Popup Style")
        item.isEnabled = providerVisibility.popupEnabled
        let submenu = NSMenu()

        for style in PopupVisualStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.title,
                action: #selector(setPopupVisualStyle(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            styleItem.image = menuSymbol(named: style.systemImageName, accessibilityDescription: style.title)
            styleItem.state = providerVisibility.popupVisualStyle == style ? .on : .off
            submenu.addItem(styleItem)
        }

        item.submenu = submenu
        return item
    }

    private func applyPopupToggleShortcut(to item: NSMenuItem) {
        guard let shortcut = keyboardShortcuts.popupToggleShortcut,
              let keyEquivalent = shortcut.menuKeyEquivalent else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }

        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = shortcut.menuKeyEquivalentModifierMask
    }

    private func popupPositionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Popup Position", action: nil, keyEquivalent: "")
        item.image = menuSymbol(named: "mappin.and.ellipse", accessibilityDescription: "Popup Position")
        let submenu = NSMenu()

        for position in PopupWindowPosition.allCases {
            let positionItem = NSMenuItem(
                title: position.title,
                action: #selector(setPopupWindowPosition(_:)),
                keyEquivalent: ""
            )
            positionItem.target = self
            positionItem.representedObject = position.rawValue
            positionItem.state = providerVisibility.popupWindowPosition == position ? .on : .off
            submenu.addItem(positionItem)
        }

        item.submenu = submenu
        return item
    }

    private func appendAgentSection(_ agent: AgentKind) {
        menu.addItem(hostedItem(AgentSectionView(
            store: controller.store,
            refreshClock: menuRefreshClock,
            agent: agent,
            latestResponseLineLimit: providerVisibility.latestResponseLineLimit,
            subagentLatestResponseLineLimit: providerVisibility.subagentLatestResponseLineLimit,
            latestResponseHideAfterInterval: providerVisibility.latestResponseHideAfterInterval,
            latestResponseCompactsBlankLines: providerVisibility.latestResponseCompactsBlankLines,
            showsUserPrompt: providerVisibility.dropdownShowsUserPrompt,
            usesIndicatorLampStyle: providerVisibility.usesIndicatorLampStyle,
            onLayoutMayChange: { [weak self] in
                self?.resizeMenuIfOpen()
            }
        )))
    }

    private func hostedItem<Content: View>(_ view: Content) -> NSMenuItem {
        let item = NSMenuItem()
        let hostingView = NSHostingView(rootView: view)
        hostingView.layoutSubtreeIfNeeded()
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

    private func menuSymbol(named systemSymbolName: String, accessibilityDescription: String) -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        ) else {
            return nil
        }

        image.isTemplate = true
        return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) ?? image
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.open()
    }

    @objc private func togglePopup() {
        providerVisibility.setPopupEnabled(!providerVisibility.popupEnabled)
        setNeedsMenuRebuild()
    }

    @objc private func setPopupVisualStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let visualStyle = PopupVisualStyle(rawValue: rawValue) else {
            return
        }

        providerVisibility.setPopupVisualStyle(visualStyle)
        setNeedsMenuRebuild()
    }

    @objc private func setPopupWindowPosition(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let position = PopupWindowPosition(rawValue: rawValue) else {
            return
        }

        providerVisibility.setPopupWindowPosition(position)
        setNeedsMenuRebuild()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum AgentIconHighlightLayer {
    private static let layerName = "AgentSessionsWorkingHighlight"
    private static let gradientLayerName = "AgentSessionsWorkingHighlightGradient"
    private static let animationKey = "agentSessionsWorkingHighlightSweep"

    @MainActor
    static func start(in view: NSView, imageRect: CGRect, maskImage: CGImage, duration: TimeInterval) {
        guard !Theme.Motion.reduceMotion else {
            stop(in: view)
            return
        }

        view.wantsLayer = true
        guard let layer = view.layer else {
            return
        }

        if let existingLayer = layer.sublayers?.first(where: { $0.name == layerName }) {
            if abs(existingLayer.frame.width - imageRect.width) <= 0.5,
               abs(existingLayer.frame.height - imageRect.height) <= 0.5 {
                update(existingLayer, imageRect: imageRect)
                return
            }
            existingLayer.removeFromSuperlayer()
        }

        let contentsScale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let highlightLayer = CALayer()
        highlightLayer.name = layerName
        highlightLayer.frame = imageRect
        highlightLayer.masksToBounds = true
        highlightLayer.contentsScale = contentsScale
        highlightLayer.isGeometryFlipped = true

        let maskLayer = CALayer()
        maskLayer.frame = highlightLayer.bounds
        maskLayer.contents = maskImage
        maskLayer.contentsGravity = .resizeAspect
        maskLayer.contentsScale = contentsScale
        highlightLayer.mask = maskLayer

        let gradientLayer = CAGradientLayer()
        gradientLayer.name = gradientLayerName
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.white.withAlphaComponent(0.26).cgColor,
            NSColor.white.withAlphaComponent(0.65).cgColor,
            NSColor.white.withAlphaComponent(0.26).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        gradientLayer.locations = [0, 0.2, 0.39, 0.5, 0.61, 0.8, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: max(imageRect.width * 0.95, 8),
            height: max(imageRect.height * 2.7, 16)
        )
        gradientLayer.position = startPosition(in: highlightLayer.bounds, stripeSize: gradientLayer.bounds.size)
        gradientLayer.transform = CATransform3DMakeRotation(CGFloat.pi / 4, 0, 0, 1)

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = startPosition(in: highlightLayer.bounds, stripeSize: gradientLayer.bounds.size)
        animation.toValue = endPosition(in: highlightLayer.bounds, stripeSize: gradientLayer.bounds.size)
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        gradientLayer.add(animation, forKey: animationKey)

        highlightLayer.addSublayer(gradientLayer)
        layer.addSublayer(highlightLayer)
    }

    @MainActor
    static func stop(in view: NSView) {
        view.layer?.sublayers?
            .filter { $0.name == layerName }
            .forEach { $0.removeFromSuperlayer() }
    }

    static func aspectFitRect(contentSize: NSSize, in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, contentSize.width > 0, contentSize.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func update(_ layer: CALayer, imageRect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = imageRect
        layer.mask?.frame = layer.bounds
        CATransaction.commit()
    }

    private static func startPosition(in bounds: CGRect, stripeSize: CGSize) -> CGPoint {
        CGPoint(x: -stripeSize.width * 0.7, y: -stripeSize.height * 0.35)
    }

    private static func endPosition(in bounds: CGRect, stripeSize: CGSize) -> CGPoint {
        CGPoint(
            x: bounds.width + stripeSize.width * 0.7,
            y: bounds.height + stripeSize.height * 0.35
        )
    }
}

private struct AgentHeaderView: View {
    let agent: AgentKind
    let state: AgentState
    let workingSessionCounts: AgentWorkingSessionCounts
    let usesIndicatorLampStyle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                iconView

                Text(usesIndicatorLampStyle ? agent.shortDisplayName : agent.menuHeaderTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                workingCountBadge
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.providerColor(agent).opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .frame(width: 320, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 3)
    }

    private var workingCountBadge: some View {
        let isActive = workingSessionCounts.total > 0

        return Text(workingCountText)
            .font(Theme.Fonts.meta(10.5))
            .foregroundStyle(isActive ? Theme.providerColor(agent) : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Theme.providerColor(agent).opacity(isActive ? 0.14 : 0.06))
            )
            .neonGlow(
                Theme.providerGlowColor(agent),
                intensity: isActive ? 0.5 : 0,
                radius: 3
            )
    }

    @ViewBuilder
    private var iconView: some View {
        Group {
            if usesIndicatorLampStyle {
                AgentIndicatorLampView(
                    agent: agent,
                    state: state,
                    iconSize: 16
                )
            } else {
                AnimatedAgentIconView(
                    agent: agent,
                    state: state,
                    iconSize: 16,
                    animatesWorkingIcon: false,
                    usesMonochromeIdleIcon: false
                )
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var workingCountText: String {
        "Working \(workingSessionCounts.main) · Sub \(workingSessionCounts.subagent)"
    }
}

private struct AgentSectionView: View {
    @ObservedObject var store: AgentStateStore
    @ObservedObject var refreshClock: DropdownMenuRefreshClock
    let agent: AgentKind
    let latestResponseLineLimit: Int
    let subagentLatestResponseLineLimit: Int
    let latestResponseHideAfterInterval: TimeInterval
    let latestResponseCompactsBlankLines: Bool
    let showsUserPrompt: Bool
    let usesIndicatorLampStyle: Bool
    let onLayoutMayChange: () -> Void

    private static let pendingLatestResponseText = "Thinking..."

    var body: some View {
        let now = refreshClock.now
        let rows = store.displayRows(for: agent, now: now)
        let rowGroups = Self.rowGroups(for: rows)
        let rowGroupAnimationIDs = rowGroups.map(\.animationID)
        let layoutSignature = layoutSignature(for: rows, now: now)
        let state = AgentDisplayState.displayState(
            for: agent,
            aggregateState: store.aggregateState(for: agent, now: now),
            store: store,
            now: now
        )
        let workingSessionCounts = store.workingSessionCounts(for: agent, now: now)

        VStack(alignment: .leading, spacing: 0) {
            AgentHeaderView(
                agent: agent,
                state: state,
                workingSessionCounts: workingSessionCounts,
                usesIndicatorLampStyle: usesIndicatorLampStyle
            )

            if rows.isEmpty {
                EmptyAgentRow(agent: agent)
            } else {
                ForEach(rowGroups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.rows) { row in
                            switch row {
                            case .session(let session, let indentLevel):
                                SessionMenuRow(
                                    session: session,
                                    indentLevel: indentLevel,
                                    now: now,
                                    latestResponseLineLimit: latestResponseLineLimit,
                                    subagentLatestResponseLineLimit: subagentLatestResponseLineLimit,
                                    latestResponseHideAfterInterval: latestResponseHideAfterInterval,
                                    latestResponseCompactsBlankLines: latestResponseCompactsBlankLines,
                                    showsUserPrompt: showsUserPrompt
                                )
                            }
                        }
                    }
                }
            }
        }
        .animation(Self.reorderAnimation, value: rowGroupAnimationIDs)
        .onChange(of: layoutSignature) { _, _ in
            onLayoutMayChange()
        }
    }

    private func layoutSignature(for rows: [AgentSessionDisplayRow], now: Date) -> LayoutSignature {
        LayoutSignature(rows: rows.map { row in
            switch row {
            case .session(let session, let indentLevel):
                RowLayoutSignature(
                    id: session.id,
                    indentLevel: indentLevel,
                    latestResponseLineLimit: effectiveLatestResponseLineLimit(for: session),
                    userPromptText: visibleUserPromptText(for: session),
                    latestResponseText: visibleLatestResponseText(for: session, now: now)
                )
            }
        })
    }

    private func visibleLatestResponseText(for session: AgentSession, now: Date) -> String? {
        guard effectiveLatestResponseLineLimit(for: session) > 0 else {
            return nil
        }

        if let text = AgentTextSanitizer.latestResponseText(
            session.latestResponseText,
            compactsBlankLines: latestResponseCompactsBlankLines
        ), !text.isEmpty {
            guard shouldShowLatestResponseText(for: session, now: now) else {
                return nil
            }
            return text
        }

        if shouldShowPendingLatestResponseText(for: session, now: now) {
            return Self.pendingLatestResponseText
        }

        return nil
    }

    private func shouldShowPendingLatestResponseText(for session: AgentSession, now: Date) -> Bool {
        session.isAwaitingLatestResponseText
            || AgentDisplayState.transientStartupExpirationDate(for: session, now: now) != nil
    }

    private func visibleUserPromptText(for session: AgentSession) -> String? {
        guard showsUserPrompt,
              let prompt = AgentTextSanitizer.userPromptText(session.latestUserPrompt),
              !prompt.isEmpty else {
            return nil
        }

        let title = session.isSubagent ? session.subagentSessionTitle : session.displayTitle
        guard AgentSessionTitleSanitizer.normalized(prompt) != AgentSessionTitleSanitizer.normalized(title) else {
            return nil
        }

        return prompt
    }

    private func shouldShowLatestResponseText(for session: AgentSession, now: Date) -> Bool {
        let responseUpdatedAt = session.latestResponseUpdatedAt ?? session.updatedAt
        return now.timeIntervalSince(responseUpdatedAt) <= latestResponseHideAfterInterval
    }

    private func effectiveLatestResponseLineLimit(for session: AgentSession) -> Int {
        session.isSubagent ? subagentLatestResponseLineLimit : latestResponseLineLimit
    }

    private static func rowGroups(for rows: [AgentSessionDisplayRow]) -> [SessionMenuRowGroup] {
        var groups: [SessionMenuRowGroup] = []

        for row in rows {
            switch row {
            case .session(_, let indentLevel):
                let groupId = groupId(for: row)
                let shouldStartGroup = indentLevel == 0
                    || groups.last?.id != groupId

                if shouldStartGroup {
                    groups.append(SessionMenuRowGroup(id: groupId, rows: [row]))
                } else {
                    groups[groups.count - 1].rows.append(row)
                }
            }
        }

        return groups
    }

    private static func groupId(for row: AgentSessionDisplayRow) -> String {
        switch row {
        case .session(let session, let indentLevel):
            if indentLevel > 0,
               let parentSessionId = session.parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !parentSessionId.isEmpty {
                return "\(session.agent.rawValue):\(parentSessionId)"
            }

            return session.id
        }
    }

    private static let reorderAnimation = Animation.interpolatingSpring(
        mass: 0.85,
        stiffness: 260,
        damping: 30,
        initialVelocity: 0.15
    )

    private struct LayoutSignature: Equatable {
        var rows: [RowLayoutSignature]
    }

    private struct RowLayoutSignature: Equatable {
        var id: String
        var indentLevel: Int
        var latestResponseLineLimit: Int
        var userPromptText: String?
        var latestResponseText: String?
    }

    private struct SessionMenuRowGroup: Identifiable, Equatable {
        var id: String
        var rows: [AgentSessionDisplayRow]

        var animationID: String {
            "\(id)[\(rows.map(\.id).joined(separator: ","))]"
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

    var shortDisplayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude"
        }
    }
}

private enum AgentDisplayState {
    private static let recentStartupWorkingInterval: TimeInterval = 3
    private static let startupIdleEvents: Set<String> = ["SessionStart", "JSONLWatch"]

    static func displayState(
        for agent: AgentKind,
        aggregateState: AgentState,
        store: AgentStateStore,
        now: Date
    ) -> AgentState {
        guard aggregateState == .idle else {
            return aggregateState
        }

        let hasRecentStartupSession = store.visibleSessions(for: agent, now: now).contains {
            transientStartupExpirationDate(for: $0, now: now) != nil
        }

        return hasRecentStartupSession ? .working : aggregateState
    }

    static func transientStartupExpirationDate(for session: AgentSession, now: Date) -> Date? {
        guard session.state == .idle,
              startupIdleEvents.contains(session.event) else {
            return nil
        }

        let expirationDate = session.updatedAt.addingTimeInterval(recentStartupWorkingInterval)
        return expirationDate > now ? expirationDate : nil
    }
}

private struct EmptyAgentRow: View {
    let agent: AgentKind

    var body: some View {
        HStack(spacing: 4) {
            AgentIndicatorLampView(
                agent: agent,
                state: .ended,
                iconSize: 12,
                animatesWorkingLamp: false
            )
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)

            Text("No sessions")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
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
    let latestResponseHideAfterInterval: TimeInterval
    let latestResponseCompactsBlankLines: Bool
    let showsUserPrompt: Bool

    private static let pendingLatestResponseText = "Thinking..."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                SessionStateIcon(
                    agent: session.agent,
                    state: session.state,
                    symbolFontSize: symbolFontSize,
                    symbolWidth: symbolWidth
                )
                Text(titleText)
                    .font(.system(size: titleFontSize))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let userPromptText {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Color.clear
                        .frame(width: titleTextLeadingOffset, height: 0)

                    Text(userPromptText)
                        .font(.system(size: detailFontSize))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
            }
            if let latestResponseText {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: titleTextLeadingOffset, height: 0)

                    Text(latestResponseText)
                        .font(.system(size: latestResponseFontSize))
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
                            .foregroundStyle(stateTextColor)
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
        .overlay(alignment: .leading) {
            if indentLevel > 0 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.providerColor(session.agent).opacity(0.25))
                    .frame(width: 2)
                    .padding(.vertical, verticalPadding)
                    .padding(.leading, leadingPadding - 8)
            }
        }
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
        9
    }

    private var latestResponseFontSize: CGFloat {
        10
    }

    private var verticalPadding: CGFloat {
        3
    }

    private var titleColor: Color {
        session.state == .idle ? .primary.opacity(0.88) : .primary
    }

    private var detailColor: Color {
        agentStateDetailTextColor(for: session.state)
    }

    private var stateTextColor: Color {
        switch session.state {
        case .working, .waiting:
            Theme.stateColor(session.state, agent: session.agent)
        case .idle, .ended:
            detailColor
        }
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
        if shouldShowPendingTitle {
            return "Thinking..."
        }

        return session.isSubagent ? session.subagentSessionTitle : session.displayTitle
    }

    private var userPromptText: String? {
        guard showsUserPrompt,
              let prompt = AgentTextSanitizer.userPromptText(session.latestUserPrompt),
              !prompt.isEmpty,
              AgentSessionTitleSanitizer.normalized(prompt) != AgentSessionTitleSanitizer.normalized(titleText) else {
            return nil
        }

        return prompt
    }

    private var shouldShowPendingTitle: Bool {
        guard !session.isSubagent,
              session.agent == .codex,
              session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return session.event == "SessionStart" || session.event == "JSONLWatch"
    }

    private var latestResponseText: String? {
        guard effectiveLatestResponseLineLimit > 0 else {
            return nil
        }

        if let text = AgentTextSanitizer.latestResponseText(
            session.latestResponseText,
            compactsBlankLines: latestResponseCompactsBlankLines
        ), !text.isEmpty {
            guard shouldShowLatestResponseText else {
                return nil
            }
            return text
        }

        if shouldShowPendingLatestResponseText {
            return Self.pendingLatestResponseText
        }

        return nil
    }

    private var shouldShowLatestResponseText: Bool {
        let responseUpdatedAt = session.latestResponseUpdatedAt ?? session.updatedAt
        return now.timeIntervalSince(responseUpdatedAt) <= latestResponseHideAfterInterval
    }

    private var effectiveLatestResponseLineLimit: Int {
        session.isSubagent ? subagentLatestResponseLineLimit : latestResponseLineLimit
    }

    private var shouldShowPendingLatestResponseText: Bool {
        session.isAwaitingLatestResponseText
            || AgentDisplayState.transientStartupExpirationDate(for: session, now: now) != nil
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
            session.latestUserPrompt.map { "prompt: \($0)" },
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
    let agent: AgentKind
    let state: AgentState
    let symbolFontSize: CGFloat
    let symbolWidth: CGFloat

    var body: some View {
        AgentIndicatorLampView(
            agent: agent,
            state: state,
            iconSize: symbolWidth
        )
        .frame(width: symbolWidth, height: symbolWidth)
        .padding(.top, 2)
        .frame(width: symbolWidth, height: symbolFontSize + 3, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private func agentStateDetailTextColor(for state: AgentState) -> Color {
    state == .idle ? .primary.opacity(0.56) : .secondary
}

private enum AgentColors {
    static var waiting: NSColor { Theme.waiting }

    static func working(for agent: AgentKind) -> NSColor {
        Theme.provider(agent)
    }
}

private enum AgentIconAnimation {
    static let highlightDuration: TimeInterval = Theme.Motion.sweepDuration
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
    private static let renderedImageCache = RenderedImageCache()
    private static let codexIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "Codex Mono@3x"),
        color: loadMenuBarIcon(name: "Codex Color@3x")
    )
    private static let claudeIcons = AgentIconSet(
        mono: loadMenuBarIcon(name: "claude Mono@3x"),
        color: loadMenuBarIcon(name: "Claude Color@3x")
    )

    static func menuBarStatus(_ statuses: [AgentMenuBarStatus]) -> NSImage {
        guard !statuses.isEmpty else {
            return fallbackMenuBarStatus()
        }

        let size = menuBarStatusSize(for: statuses)
        let cacheKey = menuBarStatusCacheKey(statuses: statuses)

        return renderedImageCache.image(for: cacheKey) {
            renderImage(size: size, isTemplate: false) {
            var x: CGFloat = 0

            for status in statuses {
                let icons = iconSet(for: status.agent)
                let displaySize = displaySize(for: icons.mono)
                drawAgentLogo(
                    icons,
                    state: status.state,
                    size: displaySize,
                    x: x,
                    canvasHeight: size.height
                )
                x += displaySize.width + menuBarLogoGap
            }
            }
        }
    }

    static func menuHeaderIconMaskImage(for agent: AgentKind, color: Bool = true) -> CGImage? {
        let image = menuHeaderIcon(for: agent, color: color, state: .working)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func menuBarIconSize(for agent: AgentKind) -> NSSize {
        displaySize(for: iconSet(for: agent).mono)
    }

    static func menuHeaderIcon(for agent: AgentKind, color: Bool = false) -> NSImage {
        renderedImageCache.image(for: "menuHeader|\(agent.rawValue)|color:\(color)|state:base") {
            let icons = iconSet(for: agent)
            if color {
                return renderedColorIcon(icons.color)
            }

            guard let image = icons.mono.copy() as? NSImage else {
                return icons.mono
            }
            image.isTemplate = true
            return image
        }
    }

    static func menuHeaderIcon(
        for agent: AgentKind,
        color: Bool = false,
        state: AgentState
    ) -> NSImage {
        if color, state != .waiting {
            return menuHeaderIcon(for: agent, color: true)
        }

        guard state == .working || state == .waiting else {
            return menuHeaderIcon(for: agent, color: color)
        }

        let icons = iconSet(for: agent)
        let size = icons.mono.size
        let cacheKey = "menuHeader|\(agent.rawValue)|color:\(color)|state:\(state.rawValue)"

        return renderedImageCache.image(for: cacheKey) {
            renderImage(size: size, isTemplate: false) {
                drawAgentLogo(
                    icons,
                    state: state,
                    size: size,
                    x: 0,
                    canvasHeight: size.height
                )
            }
        }
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
        renderedImageCache.image(for: "menuBarStatus|fallback") {
            renderImage(size: fallbackMenuBarStatusSize, isTemplate: true) {
                let rect = NSRect(origin: .zero, size: fallbackMenuBarStatusSize)
            guard let symbol = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Agent Sessions") else {
                NSColor.labelColor.setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
                    return
            }

            var proposedRect = NSRect(origin: .zero, size: symbol.size)
            guard let cgImage = symbol.cgImage(forProposedRect: &proposedRect, context: NSGraphicsContext.current, hints: nil),
                  let context = NSGraphicsContext.current?.cgContext else {
                symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    return
            }

            context.saveGState()
            context.clip(to: rect, mask: cgImage)
            NSColor.labelColor.setFill()
            rect.fill()
            context.restoreGState()
            }
        }
    }

    private static func menuBarStatusCacheKey(statuses: [AgentMenuBarStatus]) -> String {
        let statusKey = statuses
            .map { "\($0.agent.rawValue):\($0.state.rawValue)" }
            .joined(separator: ",")
        return "menuBarStatus|\(statusKey)"
    }

    private static func renderImage(size: NSSize, isTemplate: Bool, draw: () -> Void) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw()
        image.unlockFocus()
        image.isTemplate = isTemplate
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

    private static func renderedColorIcon(_ logo: NSImage) -> NSImage {
        let size = logo.size
        return renderImage(size: size, isTemplate: false) {
            logo.draw(
                in: NSRect(origin: .zero, size: size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
    }

    private static func drawAgentLogo(
        _ icons: AgentIconSet,
        state: AgentState,
        size: NSSize,
        x: CGFloat,
        canvasHeight: CGFloat
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

    private final class RenderedImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private let capacity: Int
        private var images: [String: NSImage] = [:]
        private var insertionOrder: [String] = []

        init(capacity: Int = 256) {
            self.capacity = max(1, capacity)
            self.insertionOrder.reserveCapacity(capacity)
        }

        func image(for key: String, make: () -> NSImage) -> NSImage {
            lock.lock()
            if let image = images[key] {
                touchLocked(key)
                lock.unlock()
                return image
            }
            lock.unlock()

            let image = make()

            lock.lock()
            if images[key] == nil {
                images[key] = image
                insertionOrder.append(key)
                evictLocked()
            } else {
                touchLocked(key)
            }
            lock.unlock()

            return image
        }

        private func touchLocked(_ key: String) {
            guard let idx = insertionOrder.firstIndex(of: key) else {
                insertionOrder.append(key)
                return
            }
            insertionOrder.remove(at: idx)
            insertionOrder.append(key)
        }

        private func evictLocked() {
            while insertionOrder.count > capacity {
                let oldest = insertionOrder.removeFirst()
                images.removeValue(forKey: oldest)
            }
        }
    }
}
