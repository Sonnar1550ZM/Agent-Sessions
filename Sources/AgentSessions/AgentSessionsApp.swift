import AgentSessionsCore
import AppKit
import Combine
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

    var alignsPopupHeaderTrailing: Bool {
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

private enum ProviderPreferenceDefaults {
    static let sessionDisplayCount = 5
    static let latestResponseLineLimit = 2
    static let subagentLatestResponseLineLimit = 2
    static let latestResponseHideAfterInterval: TimeInterval = 10 * 60
    static let showsSubagents = true
    static let subagentHideAfterInterval: TimeInterval = 3 * 60
    static let menuBarEnabled = true
    static let popupEnabled = true
    static let popupDisplayInterval: TimeInterval = 10
    static let popupGlassEnabled = true
    static let popupOpacity = 0.7957142857142857
    static let popupWindowPosition = PopupWindowPosition.bottomRight
    static let popupWindowWidth = 400.4190051020408
    static let popupOffsetX = 0.0
    static let popupOffsetY = 0.0
    static let popupScale = 1.0075659049513415
    static let popupBackdropOpacity = 0.05
    static let popupTextOpacity = 1.0
    static let popupMouseProximityOpacity = 0.2
    static let popupTextShadowEnabled = true
    static let legacyPopupTextShadowStrength = 0.65
    static let popupTextShadowStrength = 2.0074120724332674
    static let popupTextShadowDistance = 0.0
    static let popupTextShadowRadius = 1.1633347657784874
    static let popupParentSessionCount = 5
    static let popupShowsResponseBody = true
    static let popupResponseCharacterLimit = 500
    static let popupResponseLineLimit = 5
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
        min(max(width ?? popupWindowWidth, 260), 1000)
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
    var sessionDisplayCount: Int
    var latestResponseLineLimit: Int
    var subagentLatestResponseLineLimit: Int
    var latestResponseHideAfterInterval: TimeInterval
    var showsSubagents: Bool
    var subagentHideAfterInterval: TimeInterval
    var hideAfterInterval: TimeInterval
    var menuBarEnabled: Bool
    var popupEnabled: Bool
    var popupDisplayInterval: TimeInterval
    var popupProviderVisibility: [String: Bool]
    var popupGlassEnabled: Bool
    var popupOpacity: Double
    var popupWindowPosition: PopupWindowPosition
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
    var popupShowsResponseBody: Bool
    var popupResponseCharacterLimit: Int
    var popupResponseLineLimit: Int

    init(
        values: [String: ProviderVisibility],
        menuBarOrder: [String],
        dropdownMenuOrder: [String],
        usesColorDropdownIcons: Bool = false,
        sessionDisplayCount: Int = ProviderPreferenceDefaults.sessionDisplayCount,
        latestResponseLineLimit: Int = ProviderPreferenceDefaults.latestResponseLineLimit,
        subagentLatestResponseLineLimit: Int = ProviderPreferenceDefaults.subagentLatestResponseLineLimit,
        latestResponseHideAfterInterval: TimeInterval = ProviderPreferenceDefaults.latestResponseHideAfterInterval,
        showsSubagents: Bool = ProviderPreferenceDefaults.showsSubagents,
        subagentHideAfterInterval: TimeInterval = ProviderPreferenceDefaults.subagentHideAfterInterval,
        hideAfterInterval: TimeInterval = ProviderPreferenceDefaults.hideAfterInterval,
        menuBarEnabled: Bool = ProviderPreferenceDefaults.menuBarEnabled,
        popupEnabled: Bool = ProviderPreferenceDefaults.popupEnabled,
        popupDisplayInterval: TimeInterval = ProviderPreferenceDefaults.popupDisplayInterval,
        popupProviderVisibility: [String: Bool] = ProviderPreferencesDocument.defaultPopupProviderVisibility,
        popupGlassEnabled: Bool = ProviderPreferenceDefaults.popupGlassEnabled,
        popupOpacity: Double = ProviderPreferenceDefaults.popupOpacity,
        popupWindowPosition: PopupWindowPosition = ProviderPreferenceDefaults.popupWindowPosition,
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
        popupShowsResponseBody: Bool = ProviderPreferenceDefaults.popupShowsResponseBody,
        popupResponseCharacterLimit: Int = ProviderPreferenceDefaults.popupResponseCharacterLimit,
        popupResponseLineLimit: Int = ProviderPreferenceDefaults.popupResponseLineLimit
    ) {
        self.values = values
        self.menuBarOrder = menuBarOrder
        self.dropdownMenuOrder = dropdownMenuOrder
        self.usesColorDropdownIcons = usesColorDropdownIcons
        self.sessionDisplayCount = sessionDisplayCount
        self.latestResponseLineLimit = latestResponseLineLimit
        self.subagentLatestResponseLineLimit = subagentLatestResponseLineLimit
        self.latestResponseHideAfterInterval = latestResponseHideAfterInterval
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
        self.popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(popupOpacity)
        self.popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(popupWindowPosition)
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
        self.popupShowsResponseBody = popupShowsResponseBody
        self.popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(popupResponseCharacterLimit)
        self.popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(popupResponseLineLimit)
    }

    private enum CodingKeys: String, CodingKey {
        case values
        case menuBarOrder
        case dropdownMenuOrder
        case usesColorDropdownIcons
        case sessionDisplayCount
        case latestResponseLineLimit
        case subagentLatestResponseLineLimit
        case latestResponseHideAfterInterval
        case subagentDisplayCount
        case showsSubagents
        case subagentHideAfterInterval
        case hideAfterInterval
        case menuBarEnabled
        case popupEnabled
        case popupDisplayInterval
        case popupProviderVisibility
        case popupGlassEnabled
        case popupOpacity
        case popupWindowPosition
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
        case popupShowsResponseBody
        case popupResponseCharacterLimit
        case popupResponseLineLimit
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
        latestResponseHideAfterInterval = ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .latestResponseHideAfterInterval)
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
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(
            try container.decodeIfPresent(Double.self, forKey: .popupOpacity)
        )
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(
            try container.decodeIfPresent(PopupWindowPosition.self, forKey: .popupWindowPosition)
        )
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
        popupShowsResponseBody = try container.decodeIfPresent(Bool.self, forKey: .popupShowsResponseBody)
            ?? ProviderPreferenceDefaults.popupShowsResponseBody
        let decodedResponseCharacterLimit = try container.decodeIfPresent(Int.self, forKey: .popupResponseCharacterLimit)
        let decodedResponseLineLimit = try container.decodeIfPresent(Int.self, forKey: .popupResponseLineLimit)
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
            decodedResponseCharacterLimit
                ?? ProviderPreferenceDefaults.popupResponseCharacterLimit(fromLegacyLineLimit: decodedResponseLineLimit)
        )
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(decodedResponseLineLimit)
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
        try container.encode(latestResponseHideAfterInterval, forKey: .latestResponseHideAfterInterval)
        try container.encode(showsSubagents, forKey: .showsSubagents)
        try container.encode(subagentHideAfterInterval, forKey: .subagentHideAfterInterval)
        try container.encode(hideAfterInterval, forKey: .hideAfterInterval)
        try container.encode(menuBarEnabled, forKey: .menuBarEnabled)
        try container.encode(popupEnabled, forKey: .popupEnabled)
        try container.encode(popupDisplayInterval, forKey: .popupDisplayInterval)
        try container.encode(popupProviderVisibility, forKey: .popupProviderVisibility)
        try container.encode(popupGlassEnabled, forKey: .popupGlassEnabled)
        try container.encode(popupOpacity, forKey: .popupOpacity)
        try container.encode(popupWindowPosition, forKey: .popupWindowPosition)
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
        try container.encode(popupShowsResponseBody, forKey: .popupShowsResponseBody)
        try container.encode(popupResponseCharacterLimit, forKey: .popupResponseCharacterLimit)
        try container.encode(popupResponseLineLimit, forKey: .popupResponseLineLimit)
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
    @Published private(set) var sessionDisplayCount: Int
    @Published private(set) var latestResponseLineLimit: Int
    @Published private(set) var subagentLatestResponseLineLimit: Int
    @Published private(set) var latestResponseHideAfterInterval: TimeInterval
    @Published private(set) var showsSubagents: Bool
    @Published private(set) var subagentHideAfterInterval: TimeInterval
    @Published private(set) var hideAfterInterval: TimeInterval
    @Published private(set) var menuBarEnabled: Bool
    @Published private(set) var popupEnabled: Bool
    @Published private(set) var popupDisplayInterval: TimeInterval
    @Published private(set) var popupProviderVisibility: [String: Bool]
    @Published private(set) var popupGlassEnabled: Bool
    @Published private(set) var popupOpacity: Double
    @Published private(set) var popupWindowPosition: PopupWindowPosition
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
        sessionDisplayCount = ProviderPreferenceDefaults.sanitizedSessionDisplayCount(document.sessionDisplayCount)
        latestResponseLineLimit = ProviderPreferenceDefaults.sanitizedLatestResponseLineLimit(document.latestResponseLineLimit)
        subagentLatestResponseLineLimit = ProviderPreferenceDefaults.sanitizedSubagentLatestResponseLineLimit(
            document.subagentLatestResponseLineLimit
        )
        latestResponseHideAfterInterval = ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
            document.latestResponseHideAfterInterval
        )
        showsSubagents = document.showsSubagents
        subagentHideAfterInterval = ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval)
        hideAfterInterval = ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval)
        menuBarEnabled = document.menuBarEnabled
        popupEnabled = document.popupEnabled
        popupDisplayInterval = ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(document.popupDisplayInterval)
        popupProviderVisibility = ProviderPreferencesDocument.sanitizedPopupProviderVisibility(document.popupProviderVisibility)
        popupGlassEnabled = document.popupGlassEnabled
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(document.popupOpacity)
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(document.popupWindowPosition)
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

    func setPopupOpacity(_ opacity: Double) {
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(opacity)
        save()
    }

    func setPopupWindowPosition(_ position: PopupWindowPosition) {
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(position)
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

    func setPopupResponseCharacterLimit(_ count: Int) {
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(count)
        save()
    }

    func setPopupResponseLineLimit(_ count: Int) {
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(count)
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
        popupOpacity = ProviderPreferenceDefaults.sanitizedPopupOpacity(ProviderPreferenceDefaults.popupOpacity)
        popupWindowPosition = ProviderPreferenceDefaults.sanitizedPopupWindowPosition(
            ProviderPreferenceDefaults.popupWindowPosition
        )
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
        popupShowsResponseBody = ProviderPreferenceDefaults.popupShowsResponseBody
        popupResponseCharacterLimit = ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
            ProviderPreferenceDefaults.popupResponseCharacterLimit
        )
        popupResponseLineLimit = ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(
            ProviderPreferenceDefaults.popupResponseLineLimit
        )
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
            sessionDisplayCount: sessionDisplayCount,
            latestResponseLineLimit: latestResponseLineLimit,
            subagentLatestResponseLineLimit: subagentLatestResponseLineLimit,
            latestResponseHideAfterInterval: latestResponseHideAfterInterval,
            showsSubagents: showsSubagents,
            subagentHideAfterInterval: subagentHideAfterInterval,
            hideAfterInterval: hideAfterInterval,
            menuBarEnabled: menuBarEnabled,
            popupEnabled: popupEnabled,
            popupDisplayInterval: popupDisplayInterval,
            popupProviderVisibility: popupProviderVisibility,
            popupGlassEnabled: popupGlassEnabled,
            popupOpacity: popupOpacity,
            popupWindowPosition: popupWindowPosition,
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
            popupShowsResponseBody: popupShowsResponseBody,
            popupResponseCharacterLimit: popupResponseCharacterLimit,
            popupResponseLineLimit: popupResponseLineLimit
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
                latestResponseHideAfterInterval: ProviderPreferenceDefaults.latestResponseHideAfterInterval,
                showsSubagents: ProviderPreferenceDefaults.showsSubagents,
                subagentHideAfterInterval: ProviderPreferenceDefaults.subagentHideAfterInterval,
                hideAfterInterval: ProviderPreferenceDefaults.hideAfterInterval,
                menuBarEnabled: ProviderPreferenceDefaults.menuBarEnabled,
                popupEnabled: ProviderPreferenceDefaults.popupEnabled,
                popupDisplayInterval: ProviderPreferenceDefaults.popupDisplayInterval,
                popupProviderVisibility: ProviderPreferencesDocument.defaultPopupProviderVisibility,
                popupGlassEnabled: ProviderPreferenceDefaults.popupGlassEnabled,
                popupOpacity: ProviderPreferenceDefaults.popupOpacity,
                popupWindowPosition: ProviderPreferenceDefaults.popupWindowPosition,
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
                popupShowsResponseBody: ProviderPreferenceDefaults.popupShowsResponseBody,
                popupResponseCharacterLimit: ProviderPreferenceDefaults.popupResponseCharacterLimit,
                popupResponseLineLimit: ProviderPreferenceDefaults.popupResponseLineLimit
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
            latestResponseHideAfterInterval: ProviderPreferenceDefaults.sanitizedLatestResponseHideAfterInterval(
                document.latestResponseHideAfterInterval
            ),
            showsSubagents: document.showsSubagents,
            subagentHideAfterInterval: ProviderPreferenceDefaults.sanitizedSubagentHideAfterInterval(document.subagentHideAfterInterval),
            hideAfterInterval: ProviderPreferenceDefaults.sanitizedHideAfterInterval(document.hideAfterInterval),
            menuBarEnabled: document.menuBarEnabled,
            popupEnabled: document.popupEnabled,
            popupDisplayInterval: ProviderPreferenceDefaults.sanitizedPopupDisplayInterval(document.popupDisplayInterval),
            popupProviderVisibility: ProviderPreferencesDocument.sanitizedPopupProviderVisibility(document.popupProviderVisibility),
            popupGlassEnabled: document.popupGlassEnabled,
            popupOpacity: ProviderPreferenceDefaults.sanitizedPopupOpacity(document.popupOpacity),
            popupWindowPosition: ProviderPreferenceDefaults.sanitizedPopupWindowPosition(document.popupWindowPosition),
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
            popupShowsResponseBody: document.popupShowsResponseBody,
            popupResponseCharacterLimit: ProviderPreferenceDefaults.sanitizedPopupResponseCharacterLimit(
                document.popupResponseCharacterLimit
            ),
            popupResponseLineLimit: ProviderPreferenceDefaults.sanitizedPopupResponseLineLimit(
                document.popupResponseLineLimit
            )
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
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            SettingsDetailView(section: selectedSection, providerVisibility: providerVisibility)
        }
        .navigationSplitViewStyle(.balanced)
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
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        } icon: {
            Image(systemName: section.symbolName)
                .font(.system(size: 14, weight: .medium))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)
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
                SettingsStepperRow(
                    title: "Lines",
                    subtitle: "Maximum lines shown below each session title.",
                    value: providerVisibility.latestResponseLineLimit,
                    range: 1...5
                ) { count in
                    providerVisibility.setLatestResponseLineLimit(count)
                }

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
                    range: 260...1000,
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
                    Label("Reset Popup Settings", systemImage: "arrow.counterclockwise")
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
                SettingsStyleChoiceButton(
                    title: "Liquid Glass",
                    systemImage: "sparkles",
                    isSelected: providerVisibility.popupGlassEnabled
                ) {
                    providerVisibility.setPopupGlassEnabled(true)
                }

                SettingsStyleChoiceButton(
                    title: "Text Drop Shadow",
                    systemImage: "textformat",
                    isSelected: providerVisibility.popupTextShadowEnabled
                ) {
                    providerVisibility.setPopupTextShadowEnabled(true)
                }
            }
            .disabled(!providerVisibility.popupEnabled)
            .opacity(providerVisibility.popupEnabled ? 1 : 0.55)
        }
    }
}

private struct SettingsStyleChoiceButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(isSelected ? .accentColor : .secondary)
        .foregroundStyle(isSelected ? .primary : .secondary)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AgentImages.menuHeaderIcon(
                for: agent,
                color: true
            ))
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.providerSettingsTitle)
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
        toolbar.showsBaselineSeparator = false
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
        transcriptPath: String?
    ) -> (text: String, transcriptPath: String)? {
        guard let transcriptPath = resolvedTranscriptPath(sessionId: sessionId, transcriptPath: transcriptPath),
              let text = tailText(from: URL(fileURLWithPath: transcriptPath)),
              let latestResponseText = ClaudeSessionParser.latestAssistantResponseText(fromTranscript: text) else {
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
        guard event.event != "UserPromptSubmit",
              event.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let latestResponse = CodexSessionWatcher.latestResponse(for: event.sessionId) else {
            return event
        }

        return event.replacingLatestResponse(text: latestResponse.text, phase: latestResponse.phase)
    }

    private static func eventWithClaudeLatestResponse(_ event: AgentEvent) -> AgentEvent {
        guard event.latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let latestResponse = ClaudeLatestResponseResolver.latestResponse(
                  for: event.sessionId,
                  transcriptPath: event.transcriptPath
              ) else {
            return event
        }

        return event.replacingLatestResponse(
            text: latestResponse.text,
            phase: "assistant",
            transcriptPath: latestResponse.transcriptPath
        )
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
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
        )
    }

    private static func eventWithResolvedTitle(_ event: AgentEvent) -> AgentEvent {
        let title: String
        switch event.agent {
        case .codex:
            title = resolvedTitle(agent: event.agent, sessionId: event.sessionId)
                ?? event.title
        case .claudeCode:
            title = resolvedTitle(agent: event.agent, sessionId: event.sessionId)
                ?? fallbackTitle(for: event)
        }

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
            latestResponseText: event.latestResponseText,
            latestResponsePhase: event.latestResponsePhase
        )
    }

    private static func resolvedTitle(agent: AgentKind, sessionId: String) -> String? {
        switch agent {
        case .codex:
            CodexSessionWatcher.title(for: sessionId)
        case .claudeCode:
            ClaudeSessionTitleResolver.title(for: sessionId)
        }
    }

    private static func shouldHideCodexSession(
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

    private static func shouldHideClaudeSession(
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

    private static func fallbackTitle(cwd: String, sessionId: String) -> String {
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCWD.isEmpty else {
            return sessionId
        }

        let lastPathComponent = URL(fileURLWithPath: trimmedCWD).lastPathComponent
        return lastPathComponent.isEmpty ? sessionId : lastPathComponent
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
    private var claudeMainInterruptWatcher: ClaudeMainSessionInterruptWatcher?
    private var maintenanceTimer: Timer?
    private let eventEnrichmentQueue = DispatchQueue(label: "app.agentsessions.event-enrichment", qos: .utility)
    private var claudeResponseRefreshWorkItems: [String: [DispatchWorkItem]] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private static let claudeResponseRetryDelays: [TimeInterval] = [0.5, 2.0]
    private static let claudeResponseRefreshFreshnessWindow: TimeInterval = 5 * 60

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

        let session = store.apply(immediateEvent)
        scheduleClaudeResponseRefreshes(for: session)
        enrichEventAfterInitialApply(immediateEvent)
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
                self.scheduleClaudeResponseRefreshes(for: session)
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

    private func scheduleClaudeResponseRefreshes(for session: AgentSession) {
        guard session.agent == .claudeCode else {
            return
        }

        let sessionId = session.sessionId
        let transcriptPath = session.transcriptPath
        claudeResponseRefreshWorkItems[sessionId]?.forEach { $0.cancel() }

        var workItems: [DispatchWorkItem] = []
        for (index, delay) in Self.claudeResponseRetryDelays.enumerated() {
            let item = DispatchWorkItem { [weak self] in
                self?.refreshClaudeResponse(sessionId: sessionId, transcriptPath: transcriptPath)
                if index == Self.claudeResponseRetryDelays.count - 1 {
                    self?.claudeResponseRefreshWorkItems[sessionId] = nil
                }
            }
            workItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        claudeResponseRefreshWorkItems[sessionId] = workItems
    }

    private func refreshClaudeResponse(sessionId: String, transcriptPath: String?) {
        guard let session = store.sessions.first(where: {
            $0.agent == .claudeCode && $0.sessionId == sessionId
        }) else {
            return
        }

        let title = resolvedTitle(for: session) ?? fallbackTitle(for: session)
        guard let latestClaudeResponse = ClaudeLatestResponseResolver.latestResponse(
            for: session.sessionId,
            transcriptPath: transcriptPath ?? session.transcriptPath
        ) else {
            return
        }

        let responseTextChanged = latestClaudeResponse.text != session.latestResponseText
        guard title != session.title
            || responseTextChanged
            || latestClaudeResponse.transcriptPath != session.transcriptPath
            || session.latestResponsePhase != "assistant" else {
            return
        }

        let refreshedAt = Date()
        store.apply(AgentEvent(
            agent: session.agent,
            sessionId: session.sessionId,
            state: session.state,
            title: title,
            cwd: session.cwd,
            event: session.event,
            terminal: session.terminal,
            pid: session.pid,
            updatedAt: updatedAtForClaudeResponseRefresh(
                session: session,
                responseTextChanged: responseTextChanged,
                now: refreshedAt
            ),
            parentSessionId: session.parentSessionId,
            subagentNickname: session.subagentNickname,
            subagentRole: session.subagentRole,
            subagentDepth: session.subagentDepth,
            transcriptPath: latestClaudeResponse.transcriptPath,
            latestResponseText: latestClaudeResponse.text,
            latestResponsePhase: "assistant"
        ))
    }

    private func refreshSessionTitles() {
        pruneHiddenSessions()
        store.expireStaleActiveSessions()

        for session in store.sessions {
            let title = resolvedTitle(for: session) ?? fallbackTitle(for: session)
            let latestClaudeResponse = session.agent == .claudeCode
                ? ClaudeLatestResponseResolver.latestResponse(
                    for: session.sessionId,
                    transcriptPath: session.transcriptPath
                )
                : nil
            let latestResponseText = latestClaudeResponse?.text ?? session.latestResponseText
            let latestResponsePhase = latestClaudeResponse == nil ? session.latestResponsePhase : "assistant"
            let transcriptPath = latestClaudeResponse?.transcriptPath ?? session.transcriptPath
            let responseTextChanged = latestClaudeResponse != nil
                && latestResponseText != session.latestResponseText

            guard title != session.title
                || latestResponseText != session.latestResponseText
                || latestResponsePhase != session.latestResponsePhase
                || transcriptPath != session.transcriptPath else {
                continue
            }

            let refreshedAt = Date()
            store.apply(AgentEvent(
                agent: session.agent,
                sessionId: session.sessionId,
                state: session.state,
                title: title,
                cwd: session.cwd,
                event: session.event,
                terminal: session.terminal,
                pid: session.pid,
                updatedAt: updatedAtForClaudeResponseRefresh(
                    session: session,
                    responseTextChanged: responseTextChanged,
                    now: refreshedAt
                ),
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

    private func updatedAtForClaudeResponseRefresh(
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
              elapsed <= Self.claudeResponseRefreshFreshnessWindow else {
            return session.updatedAt
        }

        return now
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
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        guard !session.isSubagent else {
            return session.title
        }

        return fallbackTitle(cwd: session.cwd, sessionId: session.sessionId)
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

    private func removeHiddenSession(_ event: AgentEvent) {
        store.removeSession(agent: event.agent, sessionId: event.sessionId)
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
                allowsUnresolvedLiveSession: true
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
    private static let appearanceAnimationOffset: CGFloat = 14
    private static let mouseProximityCheckInterval: TimeInterval = 1.0 / 30.0
    private static let mouseProximityMargin: CGFloat = 30
    private static let mouseProximityAnimationDuration: TimeInterval = 0.08

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
    private var mouseProximityTimer: Timer?
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
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
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
    }

    private func startRefreshTimer() {
        scheduleNextPopupCheck(visibleSessions: nil)
    }

    private func scheduleNextPopupCheck(visibleSessions: [AgentSession]?) {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let displayInterval = providerVisibility.popupDisplayInterval
        let now = Date()

        let sessions = visibleSessions ?? {
            let includedAgents = Set(AgentKind.allCases.filter { providerVisibility.isPopupVisible(for: $0) })
            return controller.store.popupParentSessions(
                now: now,
                displayInterval: displayInterval,
                includedAgents: includedAgents,
                limit: providerVisibility.popupParentSessionCount
            )
        }()

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
            closePopup()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        let now = Date()
        let includedAgents = Set(AgentKind.allCases.filter { providerVisibility.isPopupVisible(for: $0) })
        let sessions = controller.store.popupParentSessions(
            now: now,
            displayInterval: providerVisibility.popupDisplayInterval,
            includedAgents: includedAgents,
            limit: providerVisibility.popupParentSessionCount
        )
        guard !sessions.isEmpty else {
            closePopup()
            scheduleNextPopupCheck(visibleSessions: [])
            return
        }

        showPopup(sessions: sessions)
        scheduleNextPopupCheck(visibleSessions: sessions)
    }

    private func showPopup(sessions: [AgentSession]) {
        let renderSignature = popupRenderSignature(for: sessions)
        if panel?.isVisible == true,
           popupVisibilityState == .visible,
           renderedPopupSignature == renderSignature {
            updatePopupPanelAlpha(animated: false)
            return
        }

        let rootView = LatestParentSessionsPopupView(
            sessions: sessions,
            popupWidth: CGFloat(providerVisibility.popupWindowWidth),
            popupScale: CGFloat(providerVisibility.popupScale),
            glassEnabled: providerVisibility.popupGlassEnabled,
            glassOpacity: 1,
            textOpacity: 1,
            textShadowStrength: providerVisibility.effectivePopupTextShadowStrength,
            textShadowDistance: CGFloat(providerVisibility.effectivePopupTextShadowDistance),
            textShadowRadius: CGFloat(providerVisibility.effectivePopupTextShadowRadius),
            alignsHeaderTrailing: !providerVisibility.popupGlassEnabled
                && providerVisibility.popupWindowPosition.alignsPopupHeaderTrailing,
            placesNewestSessionAtBottom: providerVisibility.popupWindowPosition.placesNewestPopupSessionAtBottom,
            showsResponseBody: providerVisibility.popupShowsResponseBody,
            responseCharacterLimit: providerVisibility.popupResponseCharacterLimit,
            responseLineLimit: providerVisibility.popupResponseLineLimit
        )
        let hostingController = ensureHostingController(rootView: rootView)
        hostingController.rootView = rootView
        hostingController.view.frame.size.width = popupFrameWidth
        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.layoutSubtreeIfNeeded()

        let fittingSize = hostingController.view.fittingSize
        let panel = ensurePanel(hostingController: hostingController)
        let frame = positionedFrame(for: fittingSize, position: providerVisibility.popupWindowPosition)
        hostingController.view.frame.size = frame.size

        let shouldAnimateAppearance = !panel.isVisible || popupVisibilityState == .hidden || popupVisibilityState == .disappearing
        let appearanceAnimationGeneration: Int?
        if shouldAnimateAppearance {
            popupAnimationGeneration += 1
            popupVisibilityState = .appearing
            appearanceAnimationGeneration = popupAnimationGeneration
        } else {
            appearanceAnimationGeneration = nil
        }

        panel.setFrame(frame, display: true)
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
            "\(providerVisibility.effectivePopupTextShadowStrength)",
            "\(providerVisibility.effectivePopupTextShadowDistance)",
            "\(providerVisibility.effectivePopupTextShadowRadius)",
            "\(providerVisibility.popupWindowPosition.placesNewestPopupSessionAtBottom)",
            "\(providerVisibility.popupShowsResponseBody)",
            "\(providerVisibility.popupResponseCharacterLimit)",
            "\(providerVisibility.popupResponseLineLimit)"
        ]

        for session in sessions {
            parts.append(session.id)
            parts.append(session.state.rawValue)
            parts.append(session.displayTitle)
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

        guard mouseProximityTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: Self.mouseProximityCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePopupPanelAlpha(animated: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseProximityTimer = timer
    }

    private func stopMouseProximityTracking() {
        mouseProximityTimer?.invalidate()
        mouseProximityTimer = nil
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

    private func positionedFrame(for fittingSize: NSSize, position: PopupWindowPosition) -> NSRect {
        let width = popupFrameWidth
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
        if let iconView = view as? PopupAgentIconImageView {
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

    private var popupFrameWidth: CGFloat {
        CGFloat(providerVisibility.popupWindowWidth) * CGFloat(providerVisibility.popupScale)
    }
}

private struct LatestParentSessionsPopupView: View {
    let sessions: [AgentSession]
    let popupWidth: CGFloat
    let popupScale: CGFloat
    let glassEnabled: Bool
    let glassOpacity: Double
    let textOpacity: Double
    let textShadowStrength: Double
    let textShadowDistance: CGFloat
    let textShadowRadius: CGFloat
    let alignsHeaderTrailing: Bool
    let placesNewestSessionAtBottom: Bool
    let showsResponseBody: Bool
    let responseCharacterLimit: Int
    let responseLineLimit: Int

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
                    alignsHeaderTrailing: alignsHeaderTrailing,
                    showsResponseBody: showsResponseBody,
                    responseCharacterLimit: responseCharacterLimit,
                    responseLineLimit: responseLineLimit
                )
                .padding(.horizontal, metrics.horizontalPadding + metrics.shadowBleedPadding)
                .padding(.vertical, metrics.verticalPadding + metrics.shadowBleedPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if glassEnabled {
                        PopupLiquidGlassBackground(
                            metrics: metrics,
                            opacity: glassOpacity
                        )
                    }
                }
            }
        }
        .animation(Self.reorderAnimation, value: displayedSessionIDs)
        .frame(width: popupWidth * metrics.scale, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var displayedSessions: [AgentSession] {
        if placesNewestSessionAtBottom {
            return Array(sessions.reversed())
        }

        return sessions
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
    let opacity: Double

    var body: some View {
        let opacity = min(max(opacity, 0), 1)
        let shape = RoundedRectangle(cornerRadius: metrics.glassCornerRadius, style: .continuous)

        shape
            .fill(.clear)
            .glassEffect(nativeGlass(opacity: opacity), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.18 * opacity), lineWidth: metrics.glassBorderWidth)
            }
            .shadow(
                color: .black.opacity(0.025 * opacity),
                radius: metrics.glassShadowRadius,
                x: 0,
                y: metrics.glassShadowYOffset
            )
    }

    private func nativeGlass(opacity: Double) -> Glass {
        guard opacity > 0.001 else {
            return .identity
        }

        return Glass.clear
            .tint(.white.opacity(0.12 * opacity))
            .interactive(false)
    }
}

private struct PopupSessionRow: View {
    let session: AgentSession
    let metrics: PopupScaleMetrics
    let alignsHeaderTrailing: Bool
    let showsResponseBody: Bool
    let responseCharacterLimit: Int
    let responseLineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            HStack(alignment: .center, spacing: metrics.titleSpacing) {
                if alignsHeaderTrailing {
                    Spacer(minLength: 0)
                }

                providerIcon

                Text(titleText)
                    .font(.system(size: metrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(metrics.textOpacity))
                    .popupTextShadow(metrics)
                    .lineLimit(2)
                    .multilineTextAlignment(alignsHeaderTrailing ? .trailing : .leading)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal, metrics.titleHorizontalPadding)
                    .padding(.vertical, metrics.titleVerticalPadding)
                    .frame(
                        maxWidth: alignsHeaderTrailing ? nil : .infinity,
                        alignment: alignsHeaderTrailing ? .trailing : .leading
                    )
            }
            .padding(
                alignsHeaderTrailing ? .trailing : .leading,
                metrics.responseHorizontalPadding
            )
            .frame(
                maxWidth: .infinity,
                alignment: alignsHeaderTrailing ? .trailing : .leading
            )

            if let responseText {
                PopupJustifiedResponseText(
                    text: responseText,
                    fontSize: metrics.responseFontSize,
                    textOpacity: metrics.textOpacity,
                    lineLimit: responseLineLimit
                )
                    .popupTextShadow(metrics)
                    .padding(.horizontal, metrics.responseHorizontalPadding)
                    .padding(.vertical, metrics.responseVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var providerIcon: some View {
        PopupAgentIconView(
            agent: session.agent,
            state: session.state,
            iconSize: metrics.iconSize
        )
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .accessibilityHidden(true)
    }

    private var titleText: String {
        if session.state == .working,
           session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Thinking..."
        }

        return session.displayTitle
    }

    private var responseText: String? {
        guard showsResponseBody else {
            return nil
        }

        guard let text = AgentTextSanitizer.latestResponseText(session.latestResponseText) else {
            return nil
        }

        return Self.truncated(text, to: responseCharacterLimit)
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

private struct PopupAgentIconView: NSViewRepresentable {
    let agent: AgentKind
    let state: AgentState
    let iconSize: CGFloat

    func makeNSView(context: Context) -> PopupAgentIconImageView {
        let imageView = PopupAgentIconImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        imageView.configure(agent: agent, state: state, iconSize: iconSize)
        return imageView
    }

    func updateNSView(_ imageView: PopupAgentIconImageView, context: Context) {
        imageView.configure(agent: agent, state: state, iconSize: iconSize)
    }

    static func dismantleNSView(_ imageView: PopupAgentIconImageView, coordinator: ()) {
        imageView.stopAnimating()
    }
}

private final class PopupAgentIconImageView: NSImageView {
    private var renderedAgent: AgentKind?
    private var renderedState: AgentState?
    private var renderedIconSize: CGFloat = 0
    private var timer: Timer?
    private var renderedFrame: Int?

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

    func configure(agent: AgentKind, state: AgentState, iconSize: CGFloat) {
        let sizeChanged = abs(renderedIconSize - iconSize) > 0.001
        let identityChanged = renderedAgent != agent || renderedState != state

        renderedAgent = agent
        renderedState = state

        if sizeChanged {
            renderedIconSize = iconSize
            setFrameSize(NSSize(width: iconSize, height: iconSize))
            invalidateIntrinsicContentSize()
        }

        guard state == .working else {
            stopAnimating()
            renderStaticIcon(agent: agent, state: state, force: identityChanged)
            return
        }

        startAnimating()
        renderAnimatedIcon(agent: agent, at: Date(), force: identityChanged || image == nil)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        renderedFrame = nil
    }

    private func startAnimating() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: AgentIconAnimation.animatedRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let agent = self.renderedAgent, self.renderedState == .working else {
                    return
                }
                self.renderAnimatedIcon(agent: agent, at: Date(), force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func renderStaticIcon(agent: AgentKind, state: AgentState, force: Bool) {
        guard force || image == nil else {
            return
        }
        image = AgentImages.menuHeaderIcon(
            for: agent,
            color: true,
            state: state,
            highlightPhase: nil
        )
    }

    private func renderAnimatedIcon(agent: AgentKind, at date: Date, force: Bool) {
        let frame = AgentIconAnimation.highlightFrameIndex(at: date)
        guard force || frame != renderedFrame else {
            return
        }

        renderedFrame = frame
        image = AgentImages.menuHeaderIcon(
            for: agent,
            color: true,
            state: .working,
            highlightPhase: AgentIconAnimation.highlightPhase(forFrame: frame)
        )
    }
}

private struct PopupJustifiedResponseText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textOpacity: Double
    let lineLimit: Int

    func makeNSView(context: Context) -> WrappingTextField {
        let textField = WrappingTextField(labelWithString: "")
        textField.drawsBackground = false
        textField.isBezeled = false
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.cell?.usesSingleLineMode = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: WrappingTextField, context: Context) {
        configure(textField)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WrappingTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }

        configure(nsView)
        nsView.preferredMaxLayoutWidth = width

        let bounds = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let measuredHeight = nsView.cell?.cellSize(forBounds: bounds).height
            ?? nsView.intrinsicContentSize.height
        let cappedHeight = min(measuredHeight, maximumHeight(for: nsView.font))

        return CGSize(width: width, height: cappedHeight)
    }

    private func configure(_ textField: NSTextField) {
        let font = NSFont.systemFont(ofSize: fontSize)
        textField.font = font
        textField.maximumNumberOfLines = max(lineLimit, 1)
        textField.lineBreakMode = .byWordWrapping
        textField.attributedStringValue = attributedText(font: font)
    }

    private func attributedText(font: NSFont) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(min(max(textOpacity, 0), 1)),
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func maximumHeight(for font: NSFont?) -> CGFloat {
        let font = font ?? NSFont.systemFont(ofSize: fontSize)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return lineHeight * CGFloat(max(lineLimit, 1))
    }

    final class WrappingTextField: NSTextField {
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
        }

        override var intrinsicContentSize: NSSize {
            guard preferredMaxLayoutWidth.isFinite, preferredMaxLayoutWidth > 0 else {
                let size = super.intrinsicContentSize
                return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
            }

            let bounds = NSRect(
                x: 0,
                y: 0,
                width: preferredMaxLayoutWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            let size = cell?.cellSize(forBounds: bounds) ?? super.intrinsicContentSize
            return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
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
    var titleSpacing: CGFloat { 3 * scale }
    var horizontalPadding: CGFloat { 4 * scale }
    var verticalPadding: CGFloat { 3 * scale }
    var titleHorizontalPadding: CGFloat { 5 * scale }
    var titleVerticalPadding: CGFloat { 2 * scale }
    var responseHorizontalPadding: CGFloat { 6 * scale }
    var responseVerticalPadding: CGFloat { 3 * scale }
    var shadowBleedPadding: CGFloat { textShadowRadius + textShadowDistance + 2 * scale }
    var glassCornerRadius: CGFloat { 22 * scale }
    var glassBorderWidth: CGFloat { max(0.75, 0.85 * scale) }
    var glassShadowRadius: CGFloat { 14 * scale }
    var glassShadowYOffset: CGFloat { 5 * scale }
    var iconSize: CGFloat { 16 * scale }
    var titleFontSize: CGFloat { 12 * scale }
    var responseFontSize: CGFloat { 11 * scale }

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
    private let menuRefreshClock = DropdownMenuRefreshClock(interval: 1)
    private let menu = NSMenu()
    private var statusItems: [AgentKind: NSStatusItem] = [:]
    private var fallbackStatusItem: NSStatusItem?
    private var statusIconRefreshTimer: Timer?
    private var statusIconRefreshInterval: TimeInterval?
    private var statusIconAnimationStartDate = Date()
    private var statusIconDisplayStates: [AgentKind: AgentState] = [:]
    private var statusIconRenderKeys: [AgentKind: StatusIconRenderKey] = [:]
    private var lastStatusIconStateRefreshDate = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var isMenuOpen = false
    private var needsMenuRebuild = true
    private var isMenuResizeScheduled = false
    private var hostedViews: [NSView] = []
    private static let statusItemHorizontalPadding: CGFloat = 1
    private static let menuLayoutSizeEpsilon: CGFloat = 0.5
    private static let idleStatusIconRefreshInterval: TimeInterval = 1
    private static let statusIconStateRefreshInterval: TimeInterval = 1
    private static let animatedStatusIconRefreshInterval = AgentIconAnimation.animatedRefreshInterval

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

        providerVisibility.$popupWindowPosition
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
        let label = agent.map { "Agent Sessions - \($0.displayName)" } ?? "Agent Sessions"
        button.toolTip = label
        button.setAccessibilityLabel(label)
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
    }

    private func updateStatusIcons(refreshDisplayStates: Bool = true) {
        let now = Date()
        let shouldRefreshDisplayStates = refreshDisplayStates
            || now.timeIntervalSince(lastStatusIconStateRefreshDate) >= Self.statusIconStateRefreshInterval
        let hasAnimatedIcon = renderStatusIcons(now: now, refreshDisplayStates: shouldRefreshDisplayStates)
        if shouldRefreshDisplayStates {
            lastStatusIconStateRefreshDate = now
        }
        updateStatusIconRefreshTimer(animated: hasAnimatedIcon)
    }

    private func renderStatusIcons(now: Date, refreshDisplayStates: Bool) -> Bool {
        var hasAnimatedIcon = false

        for (agent, statusItem) in statusItems {
            let displayState = statusIconDisplayState(for: agent, now: now, refreshDisplayState: refreshDisplayStates)
            hasAnimatedIcon = hasAnimatedIcon || displayState == .working
            let highlightFrame = displayState == .working
                ? statusIconHighlightFrame(at: now)
                : nil
            let renderKey = StatusIconRenderKey(
                state: displayState,
                highlightFrame: highlightFrame
            )
            guard statusIconRenderKeys[agent] != renderKey else {
                continue
            }

            let status = AgentMenuBarStatus(
                agent: agent,
                state: displayState
            )
            let image = AgentImages.menuBarStatus(
                [status],
                highlightPhase: highlightFrame.map(AgentIconAnimation.highlightPhase(forFrame:))
            )
            statusItem.button?.image = image
            statusItem.length = image.size.width + Self.statusItemHorizontalPadding
            statusIconRenderKeys[agent] = renderKey
        }

        if let fallbackStatusItem {
            let image = AgentImages.menuBarStatus([])
            fallbackStatusItem.button?.image = image
            fallbackStatusItem.length = image.size.width + Self.statusItemHorizontalPadding
        }

        return hasAnimatedIcon
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
                self?.updateStatusIcons(refreshDisplayStates: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusIconRefreshTimer = timer
        statusIconRefreshInterval = interval
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

    private func statusIconHighlightFrame(at date: Date) -> Int {
        AgentIconAnimation.highlightFrameIndex(at: date, startDate: statusIconAnimationStartDate)
    }

    private struct StatusIconRenderKey: Equatable {
        let state: AgentState
        let highlightFrame: Int?
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
        menu.addItem(popupPositionMenuItem())
        menu.addItem(actionItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit Agent Sessions", action: #selector(quit), keyEquivalent: "q"))
    }

    private func popupToggleMenuItem() -> NSMenuItem {
        let item = actionItem(title: "Popup", action: #selector(togglePopup))
        item.image = menuSymbol(named: "bubble.left", accessibilityDescription: "Popup")
        item.state = providerVisibility.popupEnabled ? .on : .off
        return item
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

    @objc private func togglePopup() {
        providerVisibility.setPopupEnabled(!providerVisibility.popupEnabled)
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

private struct AgentHeaderView: View {
    let agent: AgentKind
    let state: AgentState
    let workingSessionCounts: AgentWorkingSessionCounts
    let animatesWorkingIcon: Bool

    var body: some View {
        HStack(spacing: 7) {
            iconView

            Text(agent.menuHeaderTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(workingCountText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(workingSessionCounts.total > 0 ? Color(nsColor: AgentColors.working(for: agent)) : .secondary)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 3)
    }

    @ViewBuilder
    private var iconView: some View {
        if state == .working, animatesWorkingIcon {
            TimelineView(.periodic(from: Date(), by: AgentIconAnimation.animatedRefreshInterval)) { timeline in
                headerIcon(highlightPhase: AgentIconAnimation.highlightPhase(at: timeline.date))
            }
        } else {
            headerIcon(highlightPhase: nil)
        }
    }

    private func headerIcon(highlightPhase: CGFloat?) -> some View {
        Image(nsImage: AgentImages.menuHeaderIcon(
            for: agent,
            color: true,
            state: state,
            highlightPhase: highlightPhase
        ))
        .resizable()
        .renderingMode(.original)
        .foregroundStyle(.primary)
        .aspectRatio(contentMode: .fit)
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
    let onLayoutMayChange: () -> Void

    var body: some View {
        let now = refreshClock.now
        let rows = store.displayRows(for: agent, now: now)
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
                animatesWorkingIcon: refreshClock.isRunning
            )

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
                            subagentLatestResponseLineLimit: subagentLatestResponseLineLimit,
                            latestResponseHideAfterInterval: latestResponseHideAfterInterval
                        )
                    }
                }
            }
        }
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
                    latestResponseText: visibleLatestResponseText(for: session, now: now)
                )
            }
        })
    }

    private func visibleLatestResponseText(for session: AgentSession, now: Date) -> String? {
        guard effectiveLatestResponseLineLimit(for: session) > 0 else {
            return nil
        }

        guard shouldShowLatestResponseText(for: session, now: now),
              let text = AgentTextSanitizer.latestResponseText(session.latestResponseText),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func shouldShowLatestResponseText(for session: AgentSession, now: Date) -> Bool {
        let responseUpdatedAt = session.latestResponseUpdatedAt ?? session.updatedAt
        return now.timeIntervalSince(responseUpdatedAt) <= latestResponseHideAfterInterval
    }

    private func effectiveLatestResponseLineLimit(for session: AgentSession) -> Int {
        session.isSubagent ? subagentLatestResponseLineLimit : latestResponseLineLimit
    }

    private struct LayoutSignature: Equatable {
        var rows: [RowLayoutSignature]
    }

    private struct RowLayoutSignature: Equatable {
        var id: String
        var indentLevel: Int
        var latestResponseLineLimit: Int
        var latestResponseText: String?
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

        let hasRecentStartupSession = store.visibleSessions(for: agent, now: now).contains { session in
            session.state == .idle
                && startupIdleEvents.contains(session.event)
                && now.timeIntervalSince(session.updatedAt) <= recentStartupWorkingInterval
        }

        return hasRecentStartupSession ? .working : aggregateState
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
    let latestResponseHideAfterInterval: TimeInterval

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

    private var latestResponseFontSize: CGFloat {
        10
    }

    private var verticalPadding: CGFloat {
        3
    }

    private var symbolColor: Color {
        agentStateSymbolColor(for: session.state, agent: session.agent)
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
        if shouldShowPendingTitle {
            return "Thinking..."
        }

        return session.isSubagent ? session.subagentSessionTitle : session.displayTitle
    }

    private var shouldShowPendingTitle: Bool {
        guard !session.isSubagent,
              session.agent == .codex,
              session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return session.state == .working || session.event == "SessionStart" || session.event == "JSONLWatch"
    }

    private var latestResponseText: String? {
        guard effectiveLatestResponseLineLimit > 0 else {
            return nil
        }

        guard shouldShowLatestResponseText,
              let text = AgentTextSanitizer.latestResponseText(session.latestResponseText),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private var shouldShowLatestResponseText: Bool {
        let responseUpdatedAt = session.latestResponseUpdatedAt ?? session.updatedAt
        return now.timeIntervalSince(responseUpdatedAt) <= latestResponseHideAfterInterval
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

private func agentStateSymbolColor(for state: AgentState, agent: AgentKind) -> Color {
    switch state {
    case .working:
        return Color(nsColor: AgentColors.working(for: agent))
    case .waiting:
        return Color(nsColor: AgentColors.waiting)
    case .idle, .ended:
        return .secondary
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

private enum AgentIconAnimation {
    static let framesPerSecond = 10
    static let animatedRefreshInterval: TimeInterval = 1.0 / Double(framesPerSecond)
    private static let highlightDuration: TimeInterval = 1.15
    static let highlightFrameCount = max(
        1,
        Int((highlightDuration * Double(framesPerSecond)).rounded(.toNearestOrAwayFromZero))
    )

    static func highlightPhase(at date: Date, startDate: Date) -> CGFloat {
        highlightPhase(forFrame: highlightFrameIndex(at: date, startDate: startDate))
    }

    static func highlightPhase(at date: Date) -> CGFloat {
        highlightPhase(forFrame: highlightFrameIndex(at: date))
    }

    static func highlightFrameIndex(at date: Date, startDate: Date) -> Int {
        highlightFrameIndex(elapsed: date.timeIntervalSince(startDate))
    }

    static func highlightFrameIndex(at date: Date) -> Int {
        highlightFrameIndex(elapsed: date.timeIntervalSinceReferenceDate)
    }

    static func highlightFrameIndex(forPhase phase: CGFloat) -> Int {
        let clampedPhase = min(max(phase, 0), 1)
        let frame = Int((clampedPhase * CGFloat(max(highlightFrameCount - 1, 1))).rounded())
        return min(max(frame, 0), highlightFrameCount - 1)
    }

    static func highlightPhase(forFrame frame: Int) -> CGFloat {
        guard highlightFrameCount > 1 else {
            return 0
        }
        return CGFloat(frame) / CGFloat(highlightFrameCount - 1)
    }

    private static func highlightFrameIndex(elapsed: TimeInterval) -> Int {
        let normalizedElapsed = elapsed.truncatingRemainder(dividingBy: highlightDuration)
        let rawFrame = Int((normalizedElapsed / highlightDuration) * Double(highlightFrameCount))
        return min(max(rawFrame, 0), highlightFrameCount - 1)
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
    private static let renderedImageCache = RenderedImageCache()
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
        let highlightFrame = highlightPhase.map(AgentIconAnimation.highlightFrameIndex(forPhase:))
        let cacheKey = menuBarStatusCacheKey(statuses: statuses, highlightFrame: highlightFrame)

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
                    canvasHeight: size.height,
                        highlightPhase: status.state == .working ? phase(forHighlightFrame: highlightFrame) : nil
                )
                x += displaySize.width + menuBarLogoGap
            }
            }
        }
    }

    static func menuHeaderIcon(for agent: AgentKind, color: Bool = false) -> NSImage {
        renderedImageCache.image(for: "menuHeader|\(agent.rawValue)|color:\(color)|state:base") {
            let icons = iconSet(for: agent)
            let source = color ? icons.color : icons.mono
            guard let image = source.copy() as? NSImage else {
                return source
            }
            image.isTemplate = !color
            return image
        }
    }

    static func menuHeaderIcon(
        for agent: AgentKind,
        color: Bool = false,
        state: AgentState,
        highlightPhase: CGFloat? = nil
    ) -> NSImage {
        guard state == .working else {
            return menuHeaderIcon(for: agent, color: color)
        }

        let icons = iconSet(for: agent)
        let size = icons.mono.size
        let highlightFrame = highlightPhase.map(AgentIconAnimation.highlightFrameIndex(forPhase:))
        let cacheKey = "menuHeader|\(agent.rawValue)|color:\(color)|state:\(state.rawValue)|frame:\(highlightFrame ?? -1)"

        return renderedImageCache.image(for: cacheKey) {
            renderImage(size: size, isTemplate: false) {
                drawAgentLogo(
                    icons,
                    state: state,
                    size: size,
                    x: 0,
                    canvasHeight: size.height,
                    highlightPhase: phase(forHighlightFrame: highlightFrame)
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

    private static func menuBarStatusCacheKey(statuses: [AgentMenuBarStatus], highlightFrame: Int?) -> String {
        let statusKey = statuses
            .map { "\($0.agent.rawValue):\($0.state.rawValue)" }
            .joined(separator: ",")
        return "menuBarStatus|\(statusKey)|frame:\(highlightFrame ?? -1)"
    }

    private static func phase(forHighlightFrame frame: Int?) -> CGFloat? {
        guard let frame else {
            return nil
        }
        return AgentIconAnimation.highlightPhase(forFrame: frame)
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
