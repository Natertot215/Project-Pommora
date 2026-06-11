import Foundation

/// Per-nexus tier label configuration. Singular + plural labels per tier
/// (Capacities-style); exposed toggle hides a tier from UI; `taggingStyle`
/// is currently vestigial — the parent-Area indicator it controlled was
/// removed with containment.
struct TierConfig: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var tiers: [Tier]
    var taggingStyle: TaggingStyle

    struct Tier: Codable, Equatable, Hashable, Sendable {
        var level: Int
        var singular: String
        var plural: String
        var exposed: Bool
    }

    enum TaggingStyle: String, Codable, CaseIterable, Hashable, Sendable {
        case color, symbol, both
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tiers
        case taggingStyle = "tagging_style"
    }

    static func defaultSeed() -> TierConfig {
        TierConfig(
            schemaVersion: 1,
            tiers: [
                Tier(level: 1, singular: "Area", plural: "Areas", exposed: true),
                Tier(level: 2, singular: "Topic", plural: "Topics", exposed: true),
                Tier(level: 3, singular: "Project", plural: "Projects", exposed: true),
            ],
            taggingStyle: .color
        )
    }
}
