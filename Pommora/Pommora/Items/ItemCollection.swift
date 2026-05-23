import Foundation

/// Item Collection — sub-folder inside an ItemType with a `_itemcollection.json`
/// sidecar. Holds Items only (Pages live in PageCollections under a PageType).
/// Title derives from folder name (filename-as-title rule).
///
/// UI label: "Set" by default (renameable via Settings); code always says
/// "Collection." On disk:
/// `<nexus>/<ItemType>/<ItemCollection>/_itemcollection.json`.
struct ItemCollection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _itemcollection.json
    var typeID: String  // ULID of parent ItemType
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var modifiedAt: Date

    // Persisted display order for direct child Items. Nil until the user
    // reorders inside this ItemCollection; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var itemOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case typeID = "type_id"
        case modifiedAt = "modified_at"
        case itemOrder = "item_order"
    }

    init(
        id: String,
        typeID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        itemOrder: [String]? = nil
    ) {
        self.id = id
        self.typeID = typeID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.itemOrder = itemOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.typeID = try c.decode(String.self, forKey: .typeID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.itemOrder = try c.decodeIfPresent([String].self, forKey: .itemOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(itemOrder, forKey: .itemOrder)
    }
}

extension ItemCollection {
    /// Loads `_itemcollection.json` and derives `title` from the parent folder
    /// name, and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> ItemCollection {
        var c = try AtomicJSON.decode(ItemCollection.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        c.folderURL = folderURL
        c.title = folderURL.lastPathComponent
        return c
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
