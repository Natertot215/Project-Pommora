import Foundation

/// Saved-section labels (Homepage / Calendar / Recents). Keys are fixed
/// in code; labels are user-renamable via the (future) Settings UI.
struct SavedConfig: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var items: [Item]

    struct Item: Codable, Equatable, Hashable, Identifiable, Sendable {
        var key: String       // "homepage" | "calendar" | "recents"
        var label: String     // user-renamable
        var id: String { key }
    }

    static func defaultSeed() -> SavedConfig {
        SavedConfig(
            schemaVersion: 1,
            items: [
                Item(key: "homepage", label: "Homepage"),
                Item(key: "calendar", label: "Calendar"),
                Item(key: "recents",  label: "Recents")
            ]
        )
    }
}
