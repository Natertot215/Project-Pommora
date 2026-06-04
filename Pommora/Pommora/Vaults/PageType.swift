import Foundation

/// Page Type — folder + `_pagetype.json` sidecar that defines the property
/// schema shared by every Page inside. The Pages-side schema-bearing container,
/// parallel to ItemType on the Items side (introduced Phase 5).
///
/// On disk: `<nexus>/<Title>/_pagetype.json` (folder name = title; no title on disk).
struct PageType: Codable, Equatable, Identifiable, Hashable, Sendable {
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
    // OrderResolver's alphabetic tail. (Post-ParadigmV2 PageTypes hold only
    // Pages, so there is no `itemOrder` field — Items live under ItemType.)
    var collectionOrder: [String]?
    var pageOrder: [String]?
    /// Persisted default sort for this Page Type's list view. Nil → callers
    /// fall back to `DefaultSortConfig.legacyDefault` (`_modified_at desc`).
    /// Phase J wires this to column-header sort persistence.
    var defaultSort: DefaultSortConfig?
    /// Page-side template config — reserved parity with ItemType (symmetric-code
    /// HARD RULE). All optional; absent in pre-T1.4 sidecars (decodeIfPresent → nil).
    var templateConfig: PageTemplateConfig?

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case collectionOrder = "collection_order"
        case pageOrder = "page_order"
        case defaultSort = "default_sort"
        case templateConfig = "template_config"
    }

    init(
        id: String, title: String, icon: String?,
        properties: [PropertyDefinition], views: [SavedView], modifiedAt: Date,
        schemaVersion: Int = 2,
        collectionOrder: [String]? = nil,
        pageOrder: [String]? = nil,
        defaultSort: DefaultSortConfig? = nil,
        templateConfig: PageTemplateConfig? = nil
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
        self.templateConfig = templateConfig
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.collectionOrder = try c.decodeIfPresent([String].self, forKey: .collectionOrder)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
        self.defaultSort = try c.decodeIfPresent(DefaultSortConfig.self, forKey: .defaultSort)
        self.templateConfig = try c.decodeIfPresent(PageTemplateConfig.self, forKey: .templateConfig)
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
        try c.encodeIfPresent(templateConfig, forKey: .templateConfig)
    }
}

extension PageType {
    static func load(from metadataURL: URL) throws -> PageType {
        var t = try AtomicJSON.decode(PageType.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    /// Finds the PageType whose `id` matches `id` by walking the Nexus root —
    /// the same flat-layout discovery `loadAll` / `IndexBuilder.collectPageTypes`
    /// use (root child folders, skip `.`/`_` prefixes, require `_pagetype.json`).
    /// Returns nil if no folder carries a matching sidecar. Used for cross-side
    /// paired-relation resolution (ItemTypeManager → PageType target), where the
    /// target lives outside the calling manager's in-memory `types`.
    static func find(id: String, in nexus: Nexus) -> PageType? {
        let topLevel = (try? Filesystem.childFolders(of: nexus.rootURL)) ?? []
        for folder in topLevel
        where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let pageType = try? PageType.load(from: metaURL),
                pageType.id == id
            else { continue }
            return pageType
        }
        return nil
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }

    /// Stored `properties` plus the three pre-configured tier relation properties
    /// (Spaces/Topics/Projects), merged via BuiltInRelationProperties. Surfaces that
    /// must SHOW tiers read this; everything that persists or mutates the schema
    /// keeps using the stored `properties`.
    func resolvedProperties(tierConfig: TierConfig) -> [PropertyDefinition] {
        BuiltInRelationProperties.merge(existing: properties, tierConfig: tierConfig, sourceTypeID: id)
    }
}
