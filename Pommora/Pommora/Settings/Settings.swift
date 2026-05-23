import Foundation

/// Per-Nexus user preferences. On disk at `<nexus>/.nexus/settings.json`.
/// Loaded by SettingsManager; consumed by every UI label-rendering site.
///
/// Existing `tier-config.json` and `saved-config.json` stay separate for v0.3.0
/// (consolidation deferred to v0.6.0 Settings UI work).
struct Settings: Codable, Equatable, Hashable, Sendable {
    var version: Int
    var accentColor: SettingsAccentColor?
    var labels: SettingsLabels
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case accentColor = "accent_color"
        case labels
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> Settings {
        Settings(
            version: 1,
            accentColor: nil,  // nil = system default
            labels: SettingsLabels.defaults(),
            modifiedAt: Date()
        )
    }
}

enum SettingsAccentColor: String, Codable, CaseIterable, Hashable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray
}
