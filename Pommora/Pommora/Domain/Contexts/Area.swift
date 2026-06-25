import Foundation

/// Tier-1 Context entity — broad life domain.
/// On disk: `.nexus/areas/<Title>/_area.json` (folder name = title; no `title` field on disk).
struct Area: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 1
    var title: String  // populated from filename on load
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
        self.tier = 1
        self.title = title
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    // MARK: - Codable — omits `title` on disk; tier always written as 1

    enum CodingKeys: String, CodingKey {
        case id, tier, icon, blocks
        case modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 1
        self.title = ""  // caller (load(from:)) overwrites from filename
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? (decoder.userInfo[.fileModificationDate] as? Date) ?? Date()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(1, forKey: .tier)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Area {
    static func load(from url: URL) throws -> Area {
        var area = try AtomicJSON.decode(Area.self, from: url)
        // Derive title from parent folder name: `.nexus/areas/Personal/_area.json` → "Personal"
        area.title = url.deletingLastPathComponent().lastPathComponent
        return area
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
