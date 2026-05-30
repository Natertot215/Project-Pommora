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
    /// Forward-compat: pre-v0.3.0 sidecars decode as `0`. Per EC2.
    var schemaVersion: Int

    /// Per-Set icon (SF Symbol name), editable post-creation. #45.
    var icon: String?

    // Persisted display order for direct child Items. Nil until the user
    // reorders inside this ItemCollection; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var itemOrder: [String]?

    /// Property IDs (from the parent ItemType schema) that are pinned to appear
    /// in the row preview for items in this collection. Empty by default.
    /// Encoded as `pinned_properties` (snake_case). Legacy sidecars missing the
    /// field decode as `[]` — no migration needed; the user-visible default is
    /// "no pinned properties".
    var pinnedProperties: [String]

    /// Per-Collection saved views. Each Collection is INDEPENDENT of its parent
    /// ItemType (locked decision): its own `views[0]` config separate from the
    /// ItemType's. Empty array on legacy sidecars; Task 5's loadAll default-view
    /// migration mints a fresh Table view when empty.
    var views: [SavedView] = []

    enum CodingKeys: String, CodingKey {
        case id, views, icon
        case typeID = "type_id"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case itemOrder = "item_order"
        case pinnedProperties = "pinned_properties"
    }

    init(
        id: String,
        typeID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        schemaVersion: Int = 1,
        icon: String? = nil,
        itemOrder: [String]? = nil,
        pinnedProperties: [String] = [],
        views: [SavedView] = []
    ) {
        self.id = id
        self.typeID = typeID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.icon = icon
        self.itemOrder = itemOrder
        self.pinnedProperties = pinnedProperties
        self.views = views
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.typeID = try c.decode(String.self, forKey: .typeID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.itemOrder = try c.decodeIfPresent([String].self, forKey: .itemOrder)
        // Legacy decode: field absent in pre-J.2 sidecars → default to empty.
        self.pinnedProperties = (try? c.decode([String].self, forKey: .pinnedProperties)) ?? []
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(itemOrder, forKey: .itemOrder)
        // Always encode pinnedProperties (even when empty) so the field is
        // always present in freshly-written sidecars — makes later reads unambiguous.
        try c.encode(pinnedProperties, forKey: .pinnedProperties)
        try c.encode(views, forKey: .views)
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
