import SwiftUI

/// Closed enum of every chip color the user can pick.
///
/// v0.3.1 cleanup (Task 5b): retired the 2-tier Primary/Secondary system in
/// favor of a flat 12-case palette. `.cyan` and `.mint` removed (overlap
/// Teal — both effectively the same family). `.gray` removed in favor of
/// `.default` as the nil/no-color render. `.orange` and `.accent` added.
///
/// **Final 12 cases:** `.default` (nil/grey fallback) / `.red` / `.orange` /
/// `.yellow` / `.green` / `.blue` / `.accent` (current Nexus accent) /
/// `.teal` / `.indigo` / `.purple` / `.pink` / `.brown`.
///
/// Apple system colors back most cases. Three exceptions:
///   - `.yellow` = `#FFDE21` (brighter than `Color(.systemYellow)`, reads
///     better against white chip foreground — Pommora brand value)
///   - `.pink` = `#E89EB8` (Pommora pink — Apple has no `systemPink` we like
///     for this surface)
///   - `.green` + `.teal` use the system color at reduced opacity (0.7) so
///     the chip fill is less screaming-saturated than the raw Apple defaults
///
/// `.default` and `.accent` are NOT user-pickable from the color grid —
/// `.default` represents "no color selected" (write `nil` to the option's
/// color binding) and `.accent` can't render reliably as a fixed swatch
/// because the Nexus accent is configurable. The 5×2 selection grid in
/// `OptionColorPicker` uses `selectablePalette` (10 cases) for that reason.
///
/// v1 is hardcoded; per-Nexus color customization is post-v1.
enum PropertyChipColor: String, Codable, CaseIterable, Sendable, Hashable {
    case `default`
    case red
    case orange
    case yellow
    case green
    case blue
    case accent
    case teal
    case indigo
    case purple
    case pink
    case brown

    var swiftUIColor: Color {
        switch self {
        case .default: return Color(.tertiaryLabelColor)
        case .red: return Color(.systemRed)
        case .orange: return Color(.systemOrange)
        case .yellow: return Color(hex: 0xFF_DE_21)  // Pommora yellow
        case .green: return Color(.systemGreen).opacity(0.7)  // softer than raw system
        case .blue: return Color(.systemBlue)
        case .accent: return Color.accentColor
        case .teal: return Color(.systemTeal).opacity(0.7)  // softer than raw system
        case .indigo: return Color(.systemIndigo)
        case .purple: return Color(.systemPurple)
        case .pink: return Color(hex: 0xE8_9E_B8)  // Pommora pink
        case .brown: return Color(.systemBrown)
        }
    }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .accent: return "Accent"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .brown: return "Brown"
        }
    }

    /// The 10 user-pickable colors rendered by `OptionColorPicker`'s 5×2
    /// swatch grid. Excludes `.default` (= "no color"; surfaced as a
    /// separate clear/None affordance) and `.accent` (= current Nexus
    /// accent; can't render reliably as a fixed swatch since it's a
    /// configurable runtime value, not a static color).
    static let selectablePalette: [PropertyChipColor] = [
        .red, .orange, .yellow, .green, .blue,
        .teal, .indigo, .purple, .pink, .brown,
    ]
}

// MARK: - Color hex helper (file-private)

extension Color {
    /// Initialize from a 24-bit RGB hex literal (e.g. `0xE89EB8`).
    /// File-private to avoid colliding with any future global hex helper.
    fileprivate init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
