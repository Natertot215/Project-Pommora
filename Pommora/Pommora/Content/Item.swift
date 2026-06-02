import Foundation
import Yams

/// Item — a `.md` file inside an Item Type / Set folder. The Markdown body is
/// the Item's `description`; frontmatter carries id / icon / tier1-3 /
/// properties. Carries tier1/2/3 multi-relations to Contexts. (Legacy `.json`
/// Items are converted to `.md` at launch by `ItemFormatMigration`; only that
/// migration reads the legacy `.json` shape — see `decodeLegacyJSON`.)
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
    /// Builds the `.md` serialization frontmatter from this composite Item.
    /// `description` becomes the body (handled by the caller), not a frontmatter
    /// key, so it is deliberately absent here.
    var frontmatter: ItemFrontmatter {
        ItemFrontmatter(
            id: id, icon: icon,
            tier1: tier1, tier2: tier2, tier3: tier3,
            properties: properties,
            createdAt: createdAt, modifiedAt: modifiedAt,
            kind: .item
        )
    }

    /// Composes an `Item` from a decoded `ItemFrontmatter` + the Markdown body
    /// (→ `description`) + the filename-derived title. Missing timestamps on the
    /// frontmatter are backfilled by the caller from file attributes; if a caller
    /// passes `nil` they fall back to the file-attribute dates resolved here, and
    /// ultimately to `Date()` so the composite's non-optional timestamps are never
    /// the 1970 epoch (which would show as a wrong "created" date at the ItemWindow).
    fileprivate init(frontmatter fm: ItemFrontmatter, body: String, url: URL) {
        let (createdFallback, modifiedFallback) = Item.fileTimestamps(of: url)
        self.init(
            id: fm.id,
            title: url.deletingPathExtension().lastPathComponent,
            icon: fm.icon,
            description: body,
            tier1: fm.tier1, tier2: fm.tier2, tier3: fm.tier3,
            properties: fm.properties,
            createdAt: fm.createdAt ?? createdFallback,
            modifiedAt: fm.modifiedAt ?? modifiedFallback
        )
    }

    /// Reads the file's creation + modification dates from FileManager
    /// attributes, falling back to `Date()` when unavailable. Used to backfill
    /// missing `created_at` / `modified_at` on a `.md` Item rather than letting
    /// them default to the 1970 epoch.
    private static func fileTimestamps(of url: URL) -> (created: Date, modified: Date) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let created = (attrs?[.creationDate] as? Date) ?? Date()
        let modified = (attrs?[.modificationDate] as? Date) ?? created
        return (created, modified)
    }

    /// Deterministic, process-seed-independent FNV-1a hash → hex string. Used only
    /// to synthesize an id for an id-less adopted `.md` Item.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Strict load of a canonical `.md` Item — decodes through the
    /// `ItemFrontmatter` envelope (body → `description`). Items are `.md`-only;
    /// the legacy `.json` shape is read ONLY by the launch migrations (via
    /// `decodeLegacyJSON`), never through this general read path.
    static func load(from url: URL) throws -> Item {
        let (fm, body): (ItemFrontmatter, String) =
            try AtomicYAMLMarkdown.load(ItemFrontmatter.self, from: url)
        return Item(frontmatter: fm, body: body, url: url)
    }

    /// Migration-only legacy `.json` decode. Reads a pre-conversion `.json` Item
    /// (the original fixed-shape typed record) so `ItemFormatMigration` can
    /// convert it to `.md`, and so `PropertyIDMigration` can re-key any `.json`
    /// member that still exists when it runs (it precedes the format migration in
    /// the launch sequence). The title is derived from the filename. NOT a general
    /// read path — the general `load` / `loadLenient` are `.md`-only.
    ///
    /// INVARIANT: this is the SOLE sanctioned legacy-JSON decode call site below
    /// (migration-scoped, callers above). Grepping for the canonical Item JSON
    /// decode must return exactly 1 hit — this single legitimate legacy-`.json`
    /// migration read, NOT a general-path regression (general paths are `.md`-only).
    static func decodeLegacyJSON(from url: URL) throws -> Item {
        // Routes through the canonical ISO-8601 JSON helper (DRY — one source of
        // JSON decode config); only the title-from-filename step is migration-local.
        var i = try AtomicJSON.decode(Item.self, from: url)
        i.title = url.deletingPathExtension().lastPathComponent
        return i
    }

    /// Tolerant load of a canonical `.md` Item — decodes a partial frontmatter
    /// shape (every field optional, missing/legacy fields default to empty) and
    /// backfills missing timestamps from file attributes. Does NOT write back —
    /// the on-disk file stays byte-identical. `.md`-only.
    static func loadLenient(from url: URL) throws -> Item {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fmText, body) = (try? AtomicYAMLMarkdown.split(raw)) ?? ("", raw)

        let shape: LenientItemFrontmatter
        if fmText.isEmpty {
            shape = LenientItemFrontmatter()
        } else {
            shape =
                (try? YAMLDecoder().decode(LenientItemFrontmatter.self, from: fmText))
                ?? LenientItemFrontmatter()
        }

        // An id-less `.md` Item is an adoption edge (a Finder-authored file with
        // no Pommora frontmatter); synthesize a stable per-path id so it at least
        // loads. Deterministic (process-seed-independent) FNV-1a over the
        // standardized path.
        let synthesizedID = "adopted-item-" + Item.stableHash(url.standardizedFileURL.path)
        let fm = ItemFrontmatter(
            id: shape.id ?? synthesizedID,
            icon: shape.icon,
            tier1: shape.tier1 ?? [],
            tier2: shape.tier2 ?? [],
            tier3: shape.tier3 ?? [],
            properties: shape.properties ?? [:],
            createdAt: shape.createdAt,
            modifiedAt: shape.modifiedAt
        )
        return Item(frontmatter: fm, body: body, url: url)
    }

    /// Preserving `.md` write (the only Item format). Re-reads the file already
    /// at `url` (if present) so foreign / plugin frontmatter survives and key
    /// order stays stable; a brand new Item (no file at `url` yet) falls back to a
    /// plain envelope — identical bytes to a fresh write. `renameItem` renames
    /// oldURL → newURL THEN saves to newURL, so `preservingFrom: url` reads the
    /// post-rename file.
    func save(to url: URL) throws {
        try AtomicYAMLMarkdown.write(
            frontmatter: frontmatter, body: description, to: url,
            preservingFrom: url, modeledKeys: ItemFrontmatter.modeledKeys)
    }

    /// De-dups Item file URLs by a key, keeping the first-seen value per key in
    /// stable order; a `nil` from `make` (unreadable / undecodable file) is
    /// skipped. Items are `.md`-only, so this only collapses the (external-Finder)
    /// edge of two `.md` files sharing an id. Shared by
    /// `ItemContentManager.loadAll` (→ `[Item]`) and
    /// `IndexBuilder.collectItemsInFolder` (→ `[ItemSnapshot]`).
    static func dedupedByID<T>(
        _ urls: [URL],
        make: (URL) -> T?,
        key: (T) -> String
    ) -> [T] {
        var byKey: [String: T] = [:]
        var order: [String] = []
        for url in urls {
            guard let value = make(url) else { continue }
            let k = key(value)
            if byKey[k] == nil {
                byKey[k] = value
                order.append(k)
            }
        }
        return order.compactMap { byKey[$0] }
    }
}

/// Tolerant frontmatter shape for `Item.loadLenient` — every field optional so a
/// `.md` Item with missing or partial Pommora frontmatter still decodes; consumers
/// fill in synthesized defaults.
private struct LenientItemFrontmatter: Codable {
    var id: String?
    var icon: String?
    var tier1: [String]?
    var tier2: [String]?
    var tier3: [String]?
    var properties: [String: PropertyValue]?
    var createdAt: Date?
    var modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, icon, tier1, tier2, tier3, properties
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

/// Relation read/write routing (tiers at root, user relations in `properties`)
/// comes from the shared `TierRelationCarrying` default implementations.
extension Item: TierRelationCarrying {}
