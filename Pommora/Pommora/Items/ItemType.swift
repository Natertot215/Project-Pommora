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
    var templateConfig: ItemTemplateConfig?  // per-Item-Type template config (layout + promoted props + cover + description cap)
    var modifiedAt: Date
    /// Forward-compat: pre-v0.3.0 sidecars decode as `0`. New sidecars write
    /// `PropertyIDMigration.currentTypeSchemaVersion` (2). Per EC2.
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
        schemaVersion: Int = 2,
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
        self.properties = (try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? [])
            .droppingUserRelations()
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

/// Per-Item-Type template config: the layout archetype, the promoted-property
/// display recipe (which properties surface on the Item Window panel + how),
/// the cover property, and the description cap/seed. All fields optional, so a
/// nil/empty config round-trips cleanly and older free-string `layout` values
/// still decode (LayoutArchetype tolerates any string).
struct ItemTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: LayoutArchetype?
    var promotedProperties: [PromotedProperty]?
    var coverPropertyID: String?
    var descriptionCap: Int?
    var defaultDescription: String?

    init(
        layout: LayoutArchetype? = nil, promotedProperties: [PromotedProperty]? = nil,
        coverPropertyID: String? = nil, descriptionCap: Int? = nil, defaultDescription: String? = nil
    ) {
        self.layout = layout
        self.promotedProperties = promotedProperties
        self.coverPropertyID = coverPropertyID
        self.descriptionCap = descriptionCap
        self.defaultDescription = defaultDescription
    }

    enum CodingKeys: String, CodingKey {
        case layout
        case promotedProperties = "promoted_properties"
        case coverPropertyID = "cover_property_id"
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

    /// Finds the ItemType whose `id` matches `id` by walking the Nexus root —
    /// the same flat-layout discovery `loadAll` / `IndexBuilder.collectItemTypes`
    /// use (root child folders, skip `.`/`_` prefixes, require `_itemtype.json`).
    /// Returns nil if no folder carries a matching sidecar. Used for cross-side
    /// relation target resolution (PageTypeManager → ItemType target), where the
    /// target lives outside the calling manager's in-memory `types`.
    static func find(id: String, in nexus: Nexus) -> ItemType? {
        let topLevel = (try? Filesystem.childFolders(of: nexus.rootURL)) ?? []
        for folder in topLevel
        where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let itemType = try? ItemType.load(from: metaURL),
                itemType.id == id
            else { continue }
            return itemType
        }
        return nil
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }

    /// Stored `properties` plus the three pre-configured tier relation properties
    /// (Spaces/Topics/Projects), merged via BuiltInContextLinkProperties. Surfaces that
    /// must SHOW tiers read this; everything that persists or mutates the schema
    /// keeps using the stored `properties`.
    func resolvedProperties(tierConfig: TierConfig) -> [PropertyDefinition] {
        BuiltInContextLinkProperties.merge(existing: properties, tierConfig: tierConfig, sourceTypeID: id)
    }
}
