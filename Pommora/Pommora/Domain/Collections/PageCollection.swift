import Foundation

/// Page Type — folder + `_pagetype.json` sidecar that defines the property
/// schema shared by every Page inside. The schema-bearing container of the
/// operational layer (introduced Phase 5).
///
/// On disk: `<nexus>/<Title>/_pagetype.json` (folder name = title; no title on disk).
struct PageCollection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var title: String  // derived from folder name
    var icon: String?  // SF Symbol name
    var properties: [PropertyDefinition]  // schema shared across Content
    var views: [SavedView]  // saved views (empty placeholder in v0.2)
    var modifiedAt: Date
    /// Forward-compat: pre-v0.3.0 sidecars decode as `0` (signal for migration).
    /// New sidecars write `PropertyIDMigration.currentTypeSchemaVersion` (2).
    /// PropertyIDMigration bumps existing sidecars to that version when it
    /// re-saves them (minting PropertyDefinition `id`s and/or normalizing legacy
    /// Relations JSON). Per EC2.
    var schemaVersion: Int

    // Persisted display order for direct children (v0.2.8.0). All nil until the
    // user reorders inside that container; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var collectionOrder: [String]?
    var pageOrder: [String]?
    /// Persisted default sort for this Page Type's list view. Nil → callers
    /// fall back to `DefaultSortConfig.legacyDefault` (`_modified_at desc`).
    /// Phase J wires this to column-header sort persistence.
    var defaultSort: DefaultSortConfig?
    /// Per-collection default for how Pages open: `.compact` (PagePreview window)
    /// or `.window` (main detail pane). Absent on legacy sidecars
    /// (decodeIfPresent → nil); callers default at read time.
    var openIn: OpenInMode?
    /// Nexus-relative POSIX path (`.nexus/assets/<id>/<file>`) of this Type's
    /// banner image. Nil/missing = no banner. Copied in by `CoverAssetStore`.
    var banner: String?

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views, banner
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case collectionOrder = "collection_order"
        case pageOrder = "page_order"
        case defaultSort = "default_sort"
        case openIn = "open_in"
    }

    init(
        id: String, title: String, icon: String?,
        properties: [PropertyDefinition], views: [SavedView], modifiedAt: Date,
        schemaVersion: Int = SchemaVersion.pageType,
        collectionOrder: [String]? = nil,
        pageOrder: [String]? = nil,
        defaultSort: DefaultSortConfig? = nil,
        openIn: OpenInMode? = nil,
        banner: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.properties = properties
        self.views = views
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.collectionOrder = collectionOrder
        self.pageOrder = pageOrder
        self.defaultSort = defaultSort
        self.openIn = openIn
        self.banner = banner
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = (try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? [])
            .droppingUserRelations()
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.collectionOrder = try c.decodeIfPresent([String].self, forKey: .collectionOrder)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
        self.defaultSort = try c.decodeIfPresent(DefaultSortConfig.self, forKey: .defaultSort)
        self.openIn = try c.decodeIfPresent(OpenInMode.self, forKey: .openIn)
        self.banner = try c.decodeIfPresent(String.self, forKey: .banner)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(collectionOrder, forKey: .collectionOrder)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
        try c.encodeIfPresent(defaultSort, forKey: .defaultSort)
        try c.encodeIfPresent(openIn, forKey: .openIn)
        try c.encodeIfPresent(banner, forKey: .banner)
    }
}

extension PageCollection {
    static func load(from metadataURL: URL) throws -> PageCollection {
        var t = try AtomicJSON.decode(PageCollection.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    /// Finds the PageCollection whose `id` matches `id` by walking the Nexus root —
    /// the same flat-layout discovery `loadAll` / `IndexBuilder.collectPageCollections`
    /// use (root child folders, skip `.`/`_` prefixes, require `_pagetype.json`).
    /// Returns nil if no folder carries a matching sidecar. Used for relation
    /// target resolution where the target lives outside the calling manager's
    /// in-memory `types`.
    static func find(id: String, in nexus: Nexus) -> PageCollection? {
        let topLevel = (try? Filesystem.childFolders(of: nexus.rootURL)) ?? []
        for folder in topLevel
        where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let pc = try? PageCollection.load(from: metaURL),
                pc.id == id
            else { continue }
            return pc
        }
        return nil
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }

    /// Stored `properties` plus the three pre-configured tier relation properties
    /// (Areas/Topics/Projects), merged via BuiltInContextLinkProperties. Surfaces that
    /// must SHOW tiers read this; everything that persists or mutates the schema
    /// keeps using the stored `properties`.
    func resolvedProperties(tierConfig: TierConfig) -> [PropertyDefinition] {
        BuiltInContextLinkProperties.merge(existing: properties, tierConfig: tierConfig, sourceTypeID: id)
    }
}
