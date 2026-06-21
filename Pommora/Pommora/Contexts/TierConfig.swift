import Foundation

/// Per-nexus tier label configuration. Singular + plural labels per tier
/// (Capacities-style); exposed toggle hides a tier from UI.
struct TierConfig: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var tiers: [Tier]

    struct Tier: Codable, Equatable, Hashable, Sendable {
        var level: Int
        var singular: String
        var plural: String
        var exposed: Bool
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tiers
    }

    static func defaultSeed() -> TierConfig {
        TierConfig(
            schemaVersion: 1,
            tiers: [
                Tier(level: 1, singular: "Area", plural: "Areas", exposed: true),
                Tier(level: 2, singular: "Topic", plural: "Topics", exposed: true),
                Tier(level: 3, singular: "Project", plural: "Projects", exposed: true),
            ]
        )
    }
}
