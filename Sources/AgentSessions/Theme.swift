import AppKit
import SwiftUI
import AgentSessionsCore

/// Central design tokens for all UI surfaces (popup, dropdown menu, menu bar, settings).
/// Colors are exposed as NSColor (AppKit/CALayer contexts) with SwiftUI mirrors below.
enum Theme {
    // MARK: - Palette

    /// Brand hues stay recognizable in light mode; dark mode lifts lightness so the
    /// colors read as neon against glass instead of sinking into the backdrop.
    private static let codexWorking = dynamic(
        light: NSColor(srgbRed: 0x00 / 255, green: 0x6E / 255, blue: 0xFE / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x4D / 255, green: 0xA3 / 255, blue: 0xFF / 255, alpha: 1)
    )
    private static let claudeWorking = dynamic(
        light: NSColor(srgbRed: 0xCF / 255, green: 0x83 / 255, blue: 0x66 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0xF5 / 255, green: 0x9E / 255, blue: 0x80 / 255, alpha: 1)
    )
    private static let codexGlow = NSColor(srgbRed: 0x66 / 255, green: 0xB2 / 255, blue: 0xFF / 255, alpha: 1)
    private static let claudeGlow = NSColor(srgbRed: 0xFF / 255, green: 0xB0 / 255, blue: 0x8A / 255, alpha: 1)

    static let waiting = NSColor(srgbRed: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)

    /// Waiting color for text on light backgrounds, where pure #FFD60A lacks contrast.
    static let waitingText = dynamic(
        light: NSColor(srgbRed: 0xE6 / 255, green: 0xA7 / 255, blue: 0x00 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
    )

    /// App-wide accent (settings controls, section chips).
    static let accent = dynamic(
        light: NSColor(srgbRed: 0x00 / 255, green: 0x71 / 255, blue: 0xE3 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x45 / 255, green: 0xA8 / 255, blue: 0xFF / 255, alpha: 1)
    )

    static func provider(_ agent: AgentKind) -> NSColor {
        switch agent {
        case .codex:
            codexWorking
        case .claudeCode:
            claudeWorking
        }
    }

    /// Brighter variant used for neon glow shadows around lamps/badges.
    static func providerGlow(_ agent: AgentKind) -> NSColor {
        switch agent {
        case .codex:
            codexGlow
        case .claudeCode:
            claudeGlow
        }
    }

    static func state(_ state: AgentState, agent: AgentKind) -> NSColor {
        switch state {
        case .working:
            provider(agent)
        case .waiting:
            waiting
        case .idle:
            .secondaryLabelColor
        case .ended:
            .tertiaryLabelColor
        }
    }

    // MARK: - SwiftUI mirrors

    static func providerColor(_ agent: AgentKind) -> Color {
        Color(nsColor: provider(agent))
    }

    static func providerGlowColor(_ agent: AgentKind) -> Color {
        Color(nsColor: providerGlow(agent))
    }

    static func stateColor(_ state: AgentState, agent: AgentKind) -> Color {
        Color(nsColor: Self.state(state, agent: agent))
    }

    static var waitingColor: Color {
        Color(nsColor: waiting)
    }

    static var waitingTextColor: Color {
        Color(nsColor: waitingText)
    }

    static var accentColor: Color {
        Color(nsColor: accent)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }
    }

    // MARK: - Typography
    // UI text stays on the standard system font so Japanese and Latin glyphs
    // share one family; only digit alignment is customized.

    enum Fonts {
        static func meta(_ size: CGFloat) -> Font {
            Font.system(size: size, weight: .medium).monospacedDigit()
        }
    }

    // MARK: - Motion / accessibility

    enum Motion {
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        static var reduceTransparency: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }

        static let lampPulsePeriod: TimeInterval = 1.8
        static let sweepDuration: TimeInterval = 1.75
    }
}

extension View {
    /// Layered neon glow for lamps and badges. Do not animate the shadow parameters
    /// themselves (expensive) — pulse the glowing element's opacity instead.
    func neonGlow(_ color: Color, intensity: Double = 1, radius: CGFloat = 4) -> some View {
        self
            .shadow(color: color.opacity(0.85 * intensity), radius: max(radius * 0.35, 0.5))
            .shadow(color: color.opacity(0.45 * intensity), radius: radius)
            .shadow(color: color.opacity(0.18 * intensity), radius: radius * 2.4)
    }
}

/// CALayer counterpart of `neonGlow` for AppKit-rendered lamps.
enum NeonGlowLayer {
    static func apply(to layer: CALayer, color: NSColor, intensity: CGFloat, radius: CGFloat = 4) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = Float(min(max(0.6 * intensity, 0), 1))
        layer.shadowRadius = radius
        layer.shadowOffset = .zero
    }
}
