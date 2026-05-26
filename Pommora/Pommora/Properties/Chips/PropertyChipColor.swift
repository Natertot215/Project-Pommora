import SwiftUI

/// Closed enum of every chip color the user can pick.
///
/// Organized in two tiers (for Figma palette + UIX grouping purposes):
///
/// **Primary** — the everyday workhorse palette. Mostly Apple system accents,
/// with two Pommora-custom overrides where Apple's defaults read poorly on
/// the chip surface:
///   - `pink` = `#E89EB8` (Pommora pink — Apple has no `systemPink` we like
///     for this surface; this hex is the brand value)
///   - `yellow` = `#FFDE21` (brighter than `Color(.systemYellow)`, reads
///     better against white chip foreground)
///
/// **Secondary** — softer / cooler accents. All Apple system colors so they
/// inherit Light/Dark/Increased-Contrast adaptation for free.
///
/// v1 is hardcoded; per-Nexus color customization is post-v1.
enum PropertyChipColor: String, Codable, CaseIterable, Sendable, Hashable {
    // Primary tier
    case `default`
    case blue
    case indigo
    case purple
    case pink
    case red
    case yellow
    case brown
    case gray

    // Secondary tier
    case cyan
    case mint
    case green
    case teal

    var swiftUIColor: Color {
        switch self {
        // Primary
        case .default: return Color(.tertiaryLabelColor)
        case .blue: return Color(.systemBlue)
        case .indigo: return Color(.systemIndigo)
        case .purple: return Color(.systemPurple)
        case .pink: return Color(hex: 0xE8_9E_B8)        // Pommora pink
        case .red: return Color(.systemRed)
        case .yellow: return Color(hex: 0xFF_DE_21)      // Pommora yellow
        case .brown: return Color(.systemBrown)
        case .gray: return Color(.systemGray)

        // Secondary
        case .cyan: return Color(.systemCyan)
        case .mint: return Color(.systemMint)
        case .green: return Color(.systemGreen)
        case .teal: return Color(.systemTeal)
        }
    }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .brown: return "Brown"
        case .gray: return "Gray"
        case .cyan: return "Cyan"
        case .mint: return "Mint"
        case .green: return "Green"
        case .teal: return "Teal"
        }
    }

    /// Which palette tier this color belongs to. Drives grouping in the
    /// Pommora UIX Chips gallery (two visually separated rows) and any
    /// future palette-picker UI.
    var tier: Tier {
        switch self {
        case .default, .blue, .indigo, .purple, .pink, .red, .yellow, .brown, .gray:
            return .primary
        case .cyan, .mint, .green, .teal:
            return .secondary
        }
    }

    enum Tier: String, Sendable, Hashable {
        case primary
        case secondary
    }
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
