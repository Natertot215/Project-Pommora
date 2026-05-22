import Foundation

/// Collection — sub-folder inside a Vault with a `_collection.json` sidecar.
/// Title derives from folder name (filename-as-title rule).
/// On disk: `<nexus>/<Vault>/<Collection>/_collection.json`.
struct Collection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _collection.json
    var vaultID: String  // ULID of parent Vault
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var modifiedAt: Date

    // Persisted display order for direct children (v0.2.8.0). Nil until the
    // user reorders inside this Collection; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var pageOrder: [String]?
    var itemOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case vaultID = "vault_id"
        case modifiedAt = "modified_at"
        case pageOrder = "page_order"
        case itemOrder = "item_order"
    }

    init(
        id: String,
        vaultID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        pageOrder: [String]? = nil,
        itemOrder: [String]? = nil
    ) {
        self.id = id
        self.vaultID = vaultID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.pageOrder = pageOrder
        self.itemOrder = itemOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.vaultID = try c.decode(String.self, forKey: .vaultID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
        self.itemOrder = try c.decodeIfPresent([String].self, forKey: .itemOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(vaultID, forKey: .vaultID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
        try c.encodeIfPresent(itemOrder, forKey: .itemOrder)
    }
}

extension Collection {
    /// Loads `_collection.json` and derives `title` from the parent folder name,
    /// and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> Collection {
        var c = try AtomicJSON.decode(Collection.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        c.folderURL = folderURL
        c.title = folderURL.lastPathComponent
        return c
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
