import Foundation

/// Vault — folder + `_vault.json` schema sidecar that defines the property
/// schema shared by every Page + Item inside.
///
/// On disk: `<nexus>/<Title>/_vault.json` (folder name = title; no title on disk).
struct Vault: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String                          // ULID
    var title: String                       // derived from folder name
    var icon: String?                       // SF Symbol name
    var properties: [PropertyDefinition]    // schema shared across Content
    var views: [VaultView]                  // saved views (empty placeholder in v0.2)
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?,
        properties: [PropertyDefinition], views: [VaultView], modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.properties = properties
        self.views = views
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        self.views = try c.decodeIfPresent([VaultView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Vault {
    static func load(from metadataURL: URL) throws -> Vault {
        var v = try AtomicJSON.decode(Vault.self, from: metadataURL)
        v.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return v
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
