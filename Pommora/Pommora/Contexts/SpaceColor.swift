import SwiftUI

/// The 9-color Notion-palette options for Spaces.
/// Stored as lowercase string in JSON; mapped to SwiftUI `Color` for rendering.
enum SpaceColor: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .gray:   return Color.gray
        case .brown:  return Color.brown
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green:  return Color.green
        case .blue:   return Color.blue
        case .purple: return Color.purple
        case .pink:   return Color.pink
        case .red:    return Color.red
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
