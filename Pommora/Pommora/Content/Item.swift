import Foundation

/// Item — `.json` inside a Vault Collection. Carries description, properties
/// (per Vault schema), tier1/2/3 multi-relations to Contexts.
struct Item: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String  // derived from filename on load
    var icon: String?
    var description: String
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    var createdAt: Date
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, description, tier1, tier2, tier3, properties
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?, description: String,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date, modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.description = description
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(description, forKey: .description)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(properties, forKey: .properties)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Item {
    static func load(from url: URL) throws -> Item {
        var i = try AtomicJSON.decode(Item.self, from: url)
        i.title = url.deletingPathExtension().lastPathComponent
        return i
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}

extension Item {
    /// Canonical READ for any relation-typed property, including the three built-in
    /// tier properties whose values live at the item root.
    func relationIDs(forPropertyID id: String) -> [String] {
        switch id {
        case ReservedPropertyID.tier1: return tier1
        case ReservedPropertyID.tier2: return tier2
        case ReservedPropertyID.tier3: return tier3
        default:
            if case .relation(let ids)? = properties[id] { return ids }
            return []
        }
    }

    /// Canonical WRITE. Tier IDs route to the root field; user relations route to
    /// `properties`. An empty user-relation value OMITS the key (no empty array on
    /// disk) so the schema-blind decoder never sees an ambiguous `[]`.
    mutating func setRelationIDs(_ ids: [String], forPropertyID id: String) {
        switch id {
        case ReservedPropertyID.tier1: tier1 = ids
        case ReservedPropertyID.tier2: tier2 = ids
        case ReservedPropertyID.tier3: tier3 = ids
        default: properties[id] = ids.isEmpty ? nil : .relation(ids)
        }
    }
}
