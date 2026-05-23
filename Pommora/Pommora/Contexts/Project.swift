import Foundation

/// Tier-3 Context entity — specifics within a Topic.
/// On disk: `.nexus/topics/<TopicTitle>/<Title>.subtopic.json`.
/// File-structural parent (the enclosing Topic folder) IS the parent — single-valued.
/// Additional Context relations live in `linkedRelations`.
struct Subtopic: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 3
    var title: String  // derived from filename on load
    var parents: [String]  // exactly one Topic ID; enforced by validator
    var linkedRelations: [String]  // additional Topic/Space/Subtopic IDs (multi-tier)
    var icon: String?
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        parents: [String],
        linkedRelations: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 3
        self.title = title
        self.parents = parents
        self.linkedRelations = linkedRelations
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, parents
        case linkedRelations = "linked_relations"
        case icon, blocks
        case modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 3
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.linkedRelations = try c.decodeIfPresent([String].self, forKey: .linkedRelations) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(3, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encode(linkedRelations, forKey: .linkedRelations)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Subtopic {
    static func load(from url: URL) throws -> Subtopic {
        var st = try AtomicJSON.decode(Subtopic.self, from: url)
        // "GTD method.subtopic.json" → strip both extensions → "GTD method"
        st.title = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        return st
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
