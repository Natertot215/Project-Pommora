import Foundation

/// Tier-2 Context entity — subject area. Multi-parent across Spaces.
/// On disk: `.nexus/topics/<Title>/_topic.json` (folder = title; no title on disk).
struct Topic: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 2
    var title: String  // derived from parent folder name on load
    var parents: [String]  // Space IDs (multi-valued; may be empty)
    var icon: String?  // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    // Persisted Subtopic display order (v0.2.8.0). Nil until the user reorders
    // Subtopics inside this Topic; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var subtopicOrder: [String]?

    init(
        id: String,
        title: String,
        parents: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date,
        subtopicOrder: [String]? = nil
    ) {
        self.id = id
        self.tier = 2
        self.title = title
        self.parents = parents
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
        self.subtopicOrder = subtopicOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, parents, icon, blocks
        case modifiedAt = "modified_at"
        case subtopicOrder = "subtopic_order"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 2
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.subtopicOrder = try c.decodeIfPresent([String].self, forKey: .subtopicOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(2, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(subtopicOrder, forKey: .subtopicOrder)
    }
}

extension Topic {
    /// Loads `_topic.json` and derives `title` from the parent folder name.
    static func load(from metadataURL: URL) throws -> Topic {
        var topic = try AtomicJSON.decode(Topic.self, from: metadataURL)
        topic.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return topic
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
