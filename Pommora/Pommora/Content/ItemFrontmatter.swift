import Foundation

/// YAML frontmatter for `.md` Item files. Mirrors `PageFrontmatter` exactly,
/// minus two Page-only fields:
/// - **no `description`** — on an Item the long-form text lives in the Markdown
///   body (the `.md` body == `Item.description`). A foreign frontmatter
///   `description:` key would be a non-modeled key and survives as a preserved
///   foreign key, coexisting harmlessly with the body.
/// - **no `folded_headings`** — that is editor display-state for Pages only.
///
/// Both `created_at` and `modified_at` are optional on the type so legacy `.md`
/// Items (or hand-authored files) decode without them; the composite `Item`'s
/// timestamps are non-optional, so `Item.load` / `Item.loadLenient` backfill any
/// missing value from the file's creation / modification dates and the next save
/// persists the now-present field through.
struct ItemFrontmatter: Codable, Equatable, Hashable, Sendable {
    var id: String
    /// Reserved, UI-hidden on-disk stamp (frontmatter key `Class`) marking this
    /// file as the Item form of the entity. Every typed Item save emits it
    /// unconditionally; decode is lenient (missing OR unknown value → `.item`).
    /// Non-authoritative — the folder sidecar is the authority and the launch
    /// stamp pass self-heals a drifted value.
    var kind: KindStamp
    var icon: String?
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    /// Optional on the type so legacy `.md` Items (pre-conversion) decode without
    /// it; the manager / load path backfills from the file's creation date.
    var createdAt: Date?
    /// Optional on the type so legacy `.md` Items decode without it; backfilled
    /// from the file's modification date. Surfaces as the "Last Edited Time"
    /// virtual property.
    var modifiedAt: Date?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, icon, tier1, tier2, tier3, properties
        case kind = "Class"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    /// The set of top-level frontmatter keys this type owns (the on-disk `rawValue`
    /// of every `CodingKey`). Passed to `AtomicYAMLMarkdown`'s preserving codec so
    /// foreign (plugin / non-modeled) frontmatter survives a save while modeled
    /// keys are substituted or cleared. Derived from `CodingKeys.allCases` so it
    /// can never drift from the actual model. Note `description` is deliberately
    /// NOT in this set — a foreign `description:` key is preserved.
    static let modeledKeys = Set(CodingKeys.allCases.map(\.rawValue))

    init(
        id: String, icon: String?,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date?,
        modifiedAt: Date? = nil,
        kind: KindStamp = .item
    ) {
        self.id = id
        self.kind = kind
        self.icon = icon
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is load-bearing — missing id should throw rather than silently
        // becoming "".
        self.id = try c.decode(String.self, forKey: .id)
        // Lenient `Class` decode (defaults to `.item` on missing/unknown) — see
        // `KeyedDecodingContainer.decodeKind`.
        self.kind = try c.decodeKind(forKey: .kind, default: .item)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        // Unconditional — every typed Item save stamps `Class: item`.
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(properties, forKey: .properties)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
    }
}

/// Relation read/write routing (tiers at root, user relations in `properties`)
/// comes from the shared `TierRelationCarrying` default implementations.
extension ItemFrontmatter: TierRelationCarrying {}
