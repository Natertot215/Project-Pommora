import Foundation

/// YAML frontmatter for `.md` Page files (long-form text lives in the body).
///
/// Per L6: `modifiedAt` (`modified_at`) ships at v0.3.0 to power the spec's
/// "Last Edited Time" virtual property + the per-Type default sort. Legacy
/// decode (Pages without the field) yields `nil` — `PageContentManager.load`
/// backfills from the file's mtime + the next save writes the now-present
/// field through.
struct PageFrontmatter: Codable, Equatable, Hashable, Sendable {
    var id: String
    var icon: String?
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    var createdAt: Date
    /// ISO-8601 timestamp updated on any frontmatter or body edit. Optional on the
    /// type so legacy `.md` files (pre-v0.3.0) decode without it; manager load path
    /// backfills from file mtime and the next save persists the field. Per the spec,
    /// surfaces in the property panel as the "Last Edited Time" virtual property.
    var modifiedAt: Date?
    /// Per-Page editor display state: exact heading source lines (e.g. `"## Foo"`)
    /// whose content is currently collapsed in the editor. Nil/missing = no folds.
    /// UI-only — never reflected in the body Markdown. See
    /// `.claude/Features/Pages.md` "Foldable headings" and
    /// `.claude/Guidelines/Markdown.md` §9.x for the rationale.
    var foldedHeadings: [String]?
    /// Nexus-relative POSIX path (`.nexus/assets/<id>/<file>`) of this Page's
    /// cover image. Nil/missing = no cover. Copied in by `CoverAssetStore`;
    /// surfaced by the cover gallery (Views cluster).
    var cover: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, icon, tier1, tier2, tier3, properties, cover
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case foldedHeadings = "folded_headings"
    }

    /// The set of top-level frontmatter keys this type owns (the on-disk `rawValue`
    /// of every `CodingKey`). Passed to `AtomicYAMLMarkdown`'s preserving codec so
    /// foreign (plugin / non-modeled) frontmatter survives a save while modeled
    /// keys are substituted or cleared. Derived from `CodingKeys.allCases` so it
    /// can never drift from the actual model.
    static let modeledKeys = Set(CodingKeys.allCases.map(\.rawValue))

    init(
        id: String, icon: String?,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date,
        modifiedAt: Date? = nil,
        foldedHeadings: [String]? = nil,
        cover: String? = nil
    ) {
        self.id = id
        self.icon = icon
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.foldedHeadings = foldedHeadings
        self.cover = cover
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
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
        self.foldedHeadings = try c.decodeIfPresent([String].self, forKey: .foldedHeadings)
        self.cover = try c.decodeIfPresent(String.self, forKey: .cover)
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
        try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(cover, forKey: .cover)
        // Encode-if-present-and-non-empty so an empty array doesn't pollute the
        // YAML with `folded_headings: []`. The editor caller is expected to set
        // the field to nil when emptied, but defending in depth here is cheap.
        if let folded = foldedHeadings, !folded.isEmpty {
            try c.encode(folded, forKey: .foldedHeadings)
        }
    }
}

/// Relation read/write routing (tiers at root, user relations in `properties`)
/// comes from the shared `TierRelationCarrying` default implementations.
extension PageFrontmatter: TierRelationCarrying {}
