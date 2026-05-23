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

    // Persisted display order for direct children (v0.2.8.0). All nil until the
    // user reorders inside that container; missing entries fall through to
    // OrderResolver's alphabetic tail. (Post-ParadigmV2 PageTypes hold only
    // Pages, so there is no `itemOrder` field — Items live under ItemType.)
    var collectionOrder: [String]?
    var pageOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case modifiedAt = "modified_at"
        case collectionOrder = "collection_order"
        case pageOrder = "page_order"
    }

    init(
        id: String, title: String, icon: String?,
        properties: [PropertyDefinition], views: [SavedView], modifiedAt: Date,
        collectionOrder: [String]? = nil,
        pageOrder: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.properties = properties
        self.views = views
        self.modifiedAt = modifiedAt
        self.collectionOrder = collectionOrder
        self.pageOrder = pageOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.collectionOrder = try c.decodeIfPresent([String].self, forKey: .collectionOrder)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(collectionOrder, forKey: .collectionOrder)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
    }
}

extension PageType {
    static func load(from metadataURL: URL) throws -> PageType {
        var t = try AtomicJSON.decode(PageType.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
