import Foundation

/// Tier-3 Context entity — specifics within a Topic.
/// On disk: `.nexus/topics/<TopicTitle>/<Title>.project.json`.
/// File-structural parent (the enclosing Topic folder) IS the parent — single-valued.
/// Additional Context links live in `projectLinks`.
///
/// Renamed from `Subtopic` per ParadigmV2 (tier-3 label is now "Project").
struct Project: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 3
    var title: String  // derived from filename on load
    var parents: [String]  // exactly one Topic ID; enforced by validator
    var projectLinks: [String]  // additional Topic/Space/Project IDs (multi-tier)
    var icon: String?
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        parents: [String],
        projectLinks: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 3
        self.title = title
        self.parents = parents
        self.projectLinks = projectLinks
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    // Custom Codable for dual-key decode tolerance on projectLinks:
    // accepts both "project_links" (new) and legacy "linked_relations" key,
    // always writes "project_links".

    private enum CodingKeys: String, CodingKey {
        case id, tier, parents, icon, blocks
        case projectLinks = "project_links"
        case modifiedAt = "modified_at"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case linkedRelations = "linked_relations"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 3
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        // Prefer new "project_links" key; fall back to legacy "linked_relations".
        if let newLinks = try c.decodeIfPresent([String].self, forKey: .projectLinks) {
            self.projectLinks = newLinks
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            self.projectLinks = try legacy.decodeIfPresent([String].self, forKey: .linkedRelations) ?? []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(3, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encode(projectLinks, forKey: .projectLinks)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Project {
    static func load(from url: URL) throws -> Project {
        var p = try AtomicJSON.decode(Project.self, from: url)
        // "GTD method.project.json" → strip both extensions → "GTD method"
        p.title = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        return p
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
