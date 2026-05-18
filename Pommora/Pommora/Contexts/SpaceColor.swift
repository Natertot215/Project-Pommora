import SwiftUI

/// The 10-color palette options for Spaces (9 Notion-palette colors + the app
/// accent). Stored as lowercase string in JSON; mapped to SwiftUI `Color` for
/// rendering. `.accent` maps to `Color.accentColor`, which tracks the
/// Pommora-brand accent and updates if the brand accent changes.
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
        case .blue: return Color.blue
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
