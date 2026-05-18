import Foundation

/// Collection — sub-folder inside a Vault with a `_collection.json` sidecar.
/// Title derives from folder name (filename-as-title rule).
/// On disk: `<nexus>/<Vault>/<Collection>/_collection.json`.
struct Collection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID from _collection.json
    var vaultID: String  // ULID of parent Vault
    var title: String  // derived from folder name on load (not persisted)
    var folderURL: URL  // runtime only (not persisted)
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vaultID = "vault_id"
        case modifiedAt = "modified_at"
    }

    init(
        id: String,
        vaultID: String,
        title: String,
        folderURL: URL,
        modifiedAt: Date
    ) {
        self.id = id
        self.vaultID = vaultID
        self.title = title
        self.folderURL = folderURL
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.vaultID = try c.decode(String.self, forKey: .vaultID)
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.folderURL = URL(fileURLWithPath: "/")  // caller overwrites
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(vaultID, forKey: .vaultID)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Collection {
    /// Loads `_collection.json` and derives `title` from the parent folder name,
    /// and `folderURL` from the metadata URL's parent.
    static func load(from metadataURL: URL) throws -> Collection {
        var c = try AtomicJSON.decode(Collection.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        c.folderURL = folderURL
        c.title = folderURL.lastPathComponent
        return c
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
