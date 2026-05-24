import Foundation

/// PageCollection — sub-folder inside a PageType with a `_pagecollection.json`
/// sidecar. Holds Pages only (Items live in ItemCollections under an ItemType).
/// Title derives from folder name (filename-as-title rule). On disk:
/// `<nexus>/<PageType>/<PageCollection>/_pagecollection.json`.
struct PageCollection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _pagecollection.json
    var typeID: String  // ULID of parent PageType
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var modifiedAt: Date
    /// Forward-compat: pre-v0.3.0 sidecars decode as `0`. Per EC2.
    var schemaVersion: Int

    // Persisted display order for direct child Pages (v0.2.8.0). Nil until the
    // user reorders inside this PageCollection; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var pageOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case typeID = "type_id"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case pageOrder = "page_order"
        // Pre-ParadigmV2 `_collection.json` used `vault_id`. Auto-migrated
        // sidecars renamed to `_pagecollection.json` still carry the old key
        // until a save() rewrites them; this decode-only fallback bridges
        // the gap.
        case legacyVaultID = "vault_id"
    }

    init(
        id: String,
        typeID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        schemaVersion: Int = 1,
        pageOrder: [String]? = nil
    ) {
        self.id = id
        self.typeID = typeID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.pageOrder = pageOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        // Flatlayout: prefer `type_id`; fall back to legacy `vault_id` from
        // pre-rename `_collection.json` files that have been auto-renamed to
        // `_pagecollection.json` but not yet re-saved.
        if let t = try? c.decode(String.self, forKey: .typeID) {
            self.typeID = t
        } else {
            self.typeID = try c.decode(String.self, forKey: .legacyVaultID)
        }
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
    }
}

extension PageCollection {
    /// Loads `_pagecollection.json` and derives `title` from the parent folder
    /// name, and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> PageCollection {
        var c = try AtomicJSON.decode(PageCollection.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        c.folderURL = folderURL
        c.title = folderURL.lastPathComponent
        return c
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
