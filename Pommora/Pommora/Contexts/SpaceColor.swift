import SwiftUI

/// Palette options for Spaces. Stored as lowercase string in JSON; mapped
/// to SwiftUI `Color` for rendering. `.blue` is the Pommora-brand accent
/// (tracks `Color.accentColor` so brand-accent changes propagate). `.accent`
/// is a legacy enum case retained for backward-compat with previously-saved
/// data; it maps to the same accent color as `.blue` and is no longer
/// surfaced in the picker — the picker's rainbow swatch now means
/// "no color" (nil) instead.
enum SpaceColor: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red, accent

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .gray: return Color.gray
        case .brown: return Color.brown
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .blue: return Color.accentColor
        case .purple: return Color.purple
        case .pink: return Color.pink
        case .red: return Color.red
        case .accent: return Color.accentColor
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
