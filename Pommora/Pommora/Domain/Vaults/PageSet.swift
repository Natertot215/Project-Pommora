import Foundation

/// PageSet — sub-folder inside a PageCollection with a `_pageset.json`
/// sidecar. Holds Pages.
/// Title derives from folder name (filename-as-title rule). On disk:
/// `<nexus>/<PageType>/<PageCollection>/<PageSet>/_pageset.json`.
struct PageSet: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _pageset.json
    var collectionID: String  // ULID of parent PageCollection
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var modifiedAt: Date
    var schemaVersion: Int

    /// Per-Set icon (SF Symbol name); nil renders the default "folder" symbol.
    var icon: String?

    // Persisted display order for direct child Pages. Nil until the user
    // reorders inside this PageSet; missing entries fall through to
    // OrderResolver's alphabetic tail.
    var pageOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id, icon
        case collectionID = "collection_id"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case pageOrder = "page_order"
    }

    init(
        id: String,
        collectionID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        schemaVersion: Int = SchemaVersion.pageSet,
        icon: String? = nil,
        pageOrder: [String]? = nil
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.icon = icon
        self.pageOrder = pageOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.collectionID = try c.decode(String.self, forKey: .collectionID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(collectionID, forKey: .collectionID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
    }
}

extension PageSet {
    /// Loads `_pageset.json` and derives `title` from the parent folder
    /// name, and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> PageSet {
        var s = try AtomicJSON.decode(PageSet.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        s.folderURL = folderURL
        s.title = folderURL.lastPathComponent
        return s
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
