import Foundation

/// YAML frontmatter for `.md` Page files. Mirrors Item shape minus `description`
/// (Pages put long-form text in the body) plus `created_at` (Items have it; Pages
/// gain it for parity per Handoff "Known Spec Gaps").
struct PageFrontmatter: Codable, Equatable, Hashable, Sendable {
    var id: String
    var icon: String?
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, tier1, tier2, tier3, properties
        case createdAt = "created_at"
    }

    init(
        id: String, icon: String?,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date
    ) {
        self.id = id
        self.icon = icon
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is load-bearing — missing id should throw rather than silently
        // becoming "". Pages without an id were a 2026-05-15 transitional state
        // that's now an error.
        self.id = try c.decode(String.self, forKey: .id)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(properties, forKey: .properties)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
