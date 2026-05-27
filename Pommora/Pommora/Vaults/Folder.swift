import Foundation

/// Folder — third tier on the Pages side (PageType → PageCollection →
/// Folder → Page). Sits inside a PageCollection sub-folder via the
/// `_folder.json` sidecar; holds Pages only. Three layers MAX — no nested
/// Folders, no nested Collections inside Folders.
///
/// Mirrors PageCollection's shape with two additions:
///   - `collectionID` — ULID of the parent PageCollection.
///   - `icon` — user-customizable SF Symbol (Folders have per-folder icons,
///     a deliberate divergence from Collections which use a hardcoded
///     `folder` symbol).
///
/// **Schema inheritance:** Folders do NOT carry property definitions of
/// their own — they inherit from the grandparent PageType (mirroring how
/// Collections inherit). Only `views: [SavedView]` is per-Folder editable
/// (visibility / sort / filter / group inside `views[0]`).
///
/// **Fresh-Folder seed:** PageTypeManager.createFolder mints a default Table
/// view via `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))`
/// so the Folder has a sane starting point. View state is independent of
/// the parent Collection's `views`.
///
/// **On-disk:** `<nexus>/<PageType>/<PageCollection>/<Folder>/_folder.json`.
/// Title derives from folder name (filename-as-title rule). On disk keys
/// are snake_case for parity with the other per-kind sidecars.
struct Folder: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _folder.json
    var typeID: String  // ULID of grandparent PageType (FK convenience)
    var collectionID: String  // ULID of parent PageCollection
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var icon: String?  // SF Symbol — customizable per-Folder
    var modifiedAt: Date
    /// Forward-compat: pre-v0.3.2 sidecars (never existed in practice — Folders
    /// are new at v0.3.2) would decode as `0`. Per the established EC2 pattern.
    var schemaVersion: Int

    /// Per-Folder display order of child Pages. Nil until the user reorders;
    /// missing entries fall through to OrderResolver's alphabetic tail.
    var pageOrder: [String]?

    /// Per-Folder saved views. Each Folder is INDEPENDENT of its parent
    /// Collection's `views` (locked decision): its own `views[0]` config
    /// separate from the Collection's and the PageType's. Empty array on
    /// freshly-tagged Folders; PageTypeManager's loadAll default-view
    /// migration mints a Table view when empty.
    var views: [SavedView] = []

    enum CodingKeys: String, CodingKey {
        case id, icon, views
        case typeID = "type_id"
        case collectionID = "collection_id"
        case modifiedAt = "modified_at"
        case schemaVersion = "schema_version"
        case pageOrder = "page_order"
    }

    init(
        id: String,
        typeID: String,
        collectionID: String,
        title: String,
        folderURL: URL,
        icon: String? = nil,
        modifiedAt: Date,
        schemaVersion: Int = 1,
        pageOrder: [String]? = nil,
        views: [SavedView] = []
    ) {
        self.id = id
        self.typeID = typeID
        self.collectionID = collectionID
        self.title = title
        self.folderURL = folderURL
        self.icon = icon
        self.modifiedAt = modifiedAt
        self.schemaVersion = schemaVersion
        self.pageOrder = pageOrder
        self.views = views
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.typeID = try c.decode(String.self, forKey: .typeID)
        self.collectionID = try c.decode(String.self, forKey: .collectionID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 0
        self.pageOrder = try c.decodeIfPresent([String].self, forKey: .pageOrder)
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(typeID, forKey: .typeID)
        try c.encode(collectionID, forKey: .collectionID)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(pageOrder, forKey: .pageOrder)
        try c.encode(views, forKey: .views)
    }
}

extension Folder {
    /// Loads `_folder.json` and derives `title` from the parent folder name
    /// (filename-as-title rule), and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> Folder {
        var folder = try AtomicJSON.decode(Folder.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        folder.folderURL = folderURL
        folder.title = folderURL.lastPathComponent
        return folder
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
