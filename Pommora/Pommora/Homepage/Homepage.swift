import Foundation

/// Singleton composed-blocks dashboard. One per Nexus, fixed location:
/// `.nexus/homepage.json`. No id / tier / parents — the location IS the identity.
struct Homepage: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var blocks: [ContextBlock]  // composed-blocks tree (editor lands v0.9)
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, blocks
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> Homepage {
        Homepage(
            schemaVersion: 1,
            icon: "house",
            blocks: [],
            modifiedAt: Date()
        )
    }
}
