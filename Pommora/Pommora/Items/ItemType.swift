import Foundation

/// Item Type — folder + `_itemtype.json` sidecar that defines the property
/// schema shared by every Item inside. The Items-side schema-bearing container,
/// parallel to PageType on the Pages side.
///
/// On disk: `<nexus>/<Title>/_itemtype.json` (folder name = title; no title on disk).
struct ItemType: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var title: String  // derived from folder name (not persisted)
    /// Capacities-style singular display label — drives "+ Add <singular>"
    /// button labels at every Item Types add affordance. nil falls back to
    /// `title`. Item Types only; Pages aren't renameable concepts (locked
    /// decision #11). Persisted as `singular` in `_itemtype.json`.
    var singular: String?
    var icon: String?  // SF Symbol name
    var properties: [PropertyDefinition]  // schema shared across Items
    var views: [SavedView]  // saved views (empty placeholder in v0.2)
    var templateConfig: ItemTemplateConfig?  // reserved for post-v1 templates
    var modifiedAt: Date
    /// Forward-compat: pre-v0.3.0 sidecars decode as `0`. Per EC2.
    var schemaVersion: Int

    // Persisted display order for direct children. Nil until the user reorders
    // inside that container; missing entries fall through to OrderResolver's
    // alphabetic tail. (Mirrors PageType's order fields, minus pageOrder —
    // Item Types hold Items, not Pages.)
    var collectionOrder: [String]?
    var itemOrder: [String]?
    /// Persisted default sort for this Item Type's list view. Nil → callers
    /// fall back to `DefaultSortConfig.legacyDefault` (`_modified_at desc`).
    /// Phase J wires this to column-header sort persistence.
    var defaultSort: DefaultSortConfig?

    enum CodingKeys: String, CodingKey {
        case id, singular, icon, properties, views
        case templateConfig = "template_config"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case collectionOrder = "collection_order"
        case itemOrder = "item_order"
        case defaultSort = "default_sort"
    }

    init(
        id: String,
        title: String,
        icon: String?,
        properties: [PropertyDefinition],
        views: [SavedView],
        templateConfig: ItemTemplateConfig? = nil,
        modifiedAt: Date,
        schemaVersion: Int = 1,
        collectionOrder: [String]? = nil,
        itemOrder: [String]? = nil,
        defaultSort: DefaultSortConfig? = nil,
        singular: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.properties = properties
        self.views = views
        self.templateConfig = templateConfig
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.collectionOrder = collectionOrder
        self.itemOrder = itemOrder
        self.defaultSort = defaultSort
        self.singular = singular
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.singular = try c.decodeIfPresent(String.self, forKey: .singular)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.templateConfig = try c.decodeIfPresent(ItemTemplateConfig.self, forKey: .templateConfig)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.collectionOrder = try c.decodeIfPresent([String].self, forKey: .collectionOrder)
        self.itemOrder = try c.decodeIfPresent([String].self, forKey: .itemOrder)
        self.defaultSort = try c.decodeIfPresent(DefaultSortConfig.self, forKey: .defaultSort)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(singular, forKey: .singular)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encodeIfPresent(templateConfig, forKey: .templateConfig)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(collectionOrder, forKey: .collectionOrder)
        try c.encodeIfPresent(itemOrder, forKey: .itemOrder)
        try c.encodeIfPresent(defaultSort, forKey: .defaultSort)
    }
}

/// Reserved for post-v1 per-Item-Type template feature. All fields optional —
/// nothing renders for this in v0.3.0; struct exists so the on-disk shape is
/// stable when templates ship.
struct ItemTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: String?
    var descriptionCap: Int?
    var defaultDescription: String?

    enum CodingKeys: String, CodingKey {
        case layout
        case descriptionCap = "description_cap"
        case defaultDescription = "default_description"
    }
}

extension ItemType {
    static func load(from metadataURL: URL) throws -> ItemType {
        var t = try AtomicJSON.decode(ItemType.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
