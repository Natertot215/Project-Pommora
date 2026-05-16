import Foundation

/// Tier-2 Context entity — subject area. Multi-parent across Spaces.
/// On disk: `.nexus/topics/<Title>/_topic.json` (folder = title; no title on disk).
struct Topic: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String              // ULID
    var tier: Int               // always 2
    var title: String           // derived from parent folder name on load
    var parents: [String]       // Space IDs (multi-valued; may be empty)
    var icon: String?           // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        parents: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 2
        self.title = title
        self.parents = parents
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, parents, icon, blocks, modifiedAt = "modified_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 2
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(2, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
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
