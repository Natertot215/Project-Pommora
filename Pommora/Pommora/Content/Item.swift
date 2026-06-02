import Foundation
import Yams

/// Item — a `.md` file inside an Item Type / Set folder (legacy `.json` items
/// still load during the transition). The Markdown body is the Item's
/// `description`; frontmatter carries id / icon / tier1-3 / properties. Carries
/// tier1/2/3 multi-relations to Contexts.
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

    /// Format-agnostic strict load. `.md` files decode through the
    /// `ItemFrontmatter` envelope (body → `description`); legacy `.json` files
    /// stay on the original `AtomicJSON` path unchanged. Both coexist during the
    /// transition window (until Task 10 migrates remaining `.json` Items).
    static func load(from url: URL) throws -> Item {
        if url.pathExtension == "md" {
            let (fm, body): (ItemFrontmatter, String) =
                try AtomicYAMLMarkdown.load(ItemFrontmatter.self, from: url)
            return Item(frontmatter: fm, body: body, url: url)
        }
        var i = try AtomicJSON.decode(Item.self, from: url)
        i.title = url.deletingPathExtension().lastPathComponent
        return i
    }

    /// Tolerant load. For `.md`, decodes a partial frontmatter shape (every field
    /// optional, missing/legacy fields default to empty) and backfills missing
    /// timestamps from file attributes; for `.json`, falls back to the strict
    /// `AtomicJSON` decode (the legacy JSON shape is already fully specified).
    /// Does NOT write back — the on-disk file stays byte-identical.
    static func loadLenient(from url: URL) throws -> Item {
        guard url.pathExtension == "md" else {
            return try load(from: url)
        }
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

        // An id-less `.md` Item is an adoption-era edge (full adoption is Task 10);
        // synthesize a stable per-path id so it at least loads. Deterministic
        // (process-seed-independent) FNV-1a over the standardized path.
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

    /// Format-aware write.
    ///
    /// - `.md` (the canonical format for all new Items): preserving write —
    ///   re-reads the file already at `url` (if present) so foreign / plugin
    ///   frontmatter survives and key order stays stable; a brand new Item (no
    ///   file at `url` yet) falls back to a plain envelope — identical bytes to a
    ///   fresh write. `renameItem` renames oldURL → newURL THEN saves to newURL,
    ///   so `preservingFrom: url` reads the post-rename file.
    /// - legacy `.json` (transition only): writes back through the original
    ///   `AtomicJSON` path so a not-yet-migrated `.json` Item is updated in place
    ///   in its native format — no orphan `.md` twin, no envelope written into a
    ///   `.json` file. Task 10 migrates these to `.md`.
    func save(to url: URL) throws {
        if url.pathExtension == "json" {
            try AtomicJSON.write(self, to: url)
            return
        }
        try AtomicYAMLMarkdown.write(
            frontmatter: frontmatter, body: description, to: url,
            preservingFrom: url, modeledKeys: ItemFrontmatter.modeledKeys)
    }

    /// De-dups Item file URLs by a key, preferring the `.md`-sourced value when a
    /// `.md` and a legacy `.json` twin share a key (e.g. a partially-migrated
    /// nexus). The `.md` value wins regardless of enumeration order; values are
    /// returned in stable first-seen order, and a `nil` from `make` (unreadable /
    /// undecodable file) is skipped. Transitional: the `.json` arm retires with
    /// Task 10. Shared by `ItemContentManager.loadAll` (→ `[Item]`) and
    /// `IndexBuilder.collectItemsInFolder` (→ `[ItemSnapshot]`).
    static func dedupedPreferringMarkdown<T>(
        _ urls: [URL],
        make: (URL) -> T?,
        key: (T) -> String
    ) -> [T] {
        var byKey: [String: T] = [:]
        var isMarkdown: [String: Bool] = [:]
        var order: [String] = []
        for url in urls {
            guard let value = make(url) else { continue }
            let k = key(value)
            let md = url.pathExtension == "md"
            if let existingIsMD = isMarkdown[k] {
                // Already have a twin — replace only if the new one is `.md` and
                // the held one isn't. Otherwise keep the first/`.md` winner.
                if md && !existingIsMD {
                    byKey[k] = value
                    isMarkdown[k] = true
                }
            } else {
                byKey[k] = value
                isMarkdown[k] = md
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
