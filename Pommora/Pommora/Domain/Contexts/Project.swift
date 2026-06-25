import Foundation

/// Tier-3 Context entity — free-standing (Contexts Decoupling).
/// On disk: `.nexus/projects/<Title>/_project.json` (folder = title; no title on disk).
struct Project: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 3
    var title: String  // derived from parent folder name on load
    var icon: String?  // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 3
        self.title = title
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, icon, blocks
        case modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 3
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? (decoder.userInfo[.fileModificationDate] as? Date) ?? Date()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(3, forKey: .tier)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Project {
    /// Loads `_project.json` and derives `title` from the parent folder name.
    static func load(from metadataURL: URL) throws -> Project {
        var p = try AtomicJSON.decode(Project.self, from: metadataURL)
        p.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return p
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
