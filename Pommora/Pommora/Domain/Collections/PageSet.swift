import Foundation

struct PageSet: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var parentID: String
    var title: String
    var folderURL: URL
    var modifiedAt: Date
    var schemaVersion: Int
    var icon: String?
    var pageOrder: [String]?
    var setOrder: [String]?
    var views: [SavedView] = []
    var banner: String?

    enum CodingKeys: String, CodingKey {
        case id, icon, views, banner
        case parentID = "parent_id"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case pageOrder = "page_order"
        case setOrder = "set_order"
        // Pre-Phase-3 parent-ref spellings — decode-only, retained so the
        // one-shot SidecarRenameMigration can read legacy sidecars and rewrite
        // them to `parent_id`. Never encoded; discovery only ever sees the
        // canonical key post-migration.
        case legacyVaultID = "vault_id"
        case legacyTypeID = "type_id"
        case legacyCollectionID = "collection_id"
    }

    init(
        id: String,
        parentID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date,
        schemaVersion: Int = SchemaVersion.pageSet,
        icon: String? = nil,
        pageOrder: [String]? = nil,
        setOrder: [String]? = nil,
        views: [SavedView] = [],
        banner: String? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.icon = icon
        self.pageOrder = pageOrder
        self.setOrder = setOrder
        self.views = views
        self.banner = banner
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        if let v = try c.decodeIfPresent(String.self, forKey: .parentID) {
            self.parentID = v
        } else if let v = try c.decodeIfPresent(String.self, forKey: .legacyVaultID) {
            self.parentID = v
        } else if let v = try c.decodeIfPresent(String.self, forKey: .legacyTypeID) {
            self.parentID = v
        } else if let v = try c.decodeIfPresent(String.self, forKey: .legacyCollectionID) {
            self.parentID = v
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.parentID,
                .init(codingPath: decoder.codingPath, debugDescription: "No parent id key found")
            )
        }
        self.title = ""
        self.folderURL = URL(fileURLWithPath: "/")
        self.modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? (decoder.userInfo[.fileModificationDate] as? Date) ?? Date()
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
        self.setOrder = try c.decodeIfPresent([String].self, forKey: .setOrder)
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.banner = try c.decodeIfPresent(String.self, forKey: .banner)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(parentID, forKey: .parentID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
        try c.encodeIfPresent(setOrder, forKey: .setOrder)
        try c.encode(views, forKey: .views)
        try c.encodeIfPresent(banner, forKey: .banner)
    }
}


extension PageSet {
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
