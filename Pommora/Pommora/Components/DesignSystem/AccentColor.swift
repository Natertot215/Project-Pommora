import AppKit
import SwiftUI

/// Accent-color plumbing — the single source of truth for the per-Nexus accent.
///
/// Two pieces:
/// 1. `SettingsAccentColor.color` — the enum→`Color` mapping (previously
///    inlined in `ContentView.currentAccent`; hoisted here so any call site
///    resolves the accent the same way).
/// 2. `EnvironmentValues.nexusAccent` — a plain `Color` environment value the
///    split-view root populates from `SettingsManager`, read by deep leaf
///    views (e.g. `DateTimePicker` selection fills) without threading the
///    manager through popovers. It carries a `Color` rather than the manager
///    so Component-Library previews render with the system accent and never
///    risk the `@Environment(SettingsManager.self)` not-injected trap.

extension SettingsAccentColor {
    /// The SwiftUI `Color` this accent maps to.
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

extension EnvironmentValues {
    /// The resolved per-Nexus accent color. Defaults to the system accent so
    /// previews and any subtree without a live Nexus still render correctly.
    @Entry var nexusAccent: Color = .accentColor
}

extension Color {
    /// Black or white — whichever stays legible as a foreground on top of this
    /// color. Uses perceptual (Rec. 601) luminance so light accents (yellow,
    /// gray) get dark text instead of unreadable white-on-light.
    var contrastingForeground: Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        let luminance = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
