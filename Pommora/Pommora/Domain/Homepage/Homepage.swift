import Foundation

/// Singleton composed-blocks dashboard. One per Nexus, fixed location:
/// `.nexus/homepage.json`. No id / tier / parents — the location IS the identity.
struct Homepage: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var banner: String?  // nexus-relative banner image path (full-bleed background)
    var blocks: [ContextBlock]  // composed-blocks tree
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, banner, blocks
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> Homepage {
        Homepage(
            schemaVersion: SchemaVersion.homepage,
            icon: "house",
            banner: nil,
            blocks: [],
            modifiedAt: Date()
        )
    }
}
