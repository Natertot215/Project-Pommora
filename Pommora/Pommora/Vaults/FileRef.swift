import Foundation

/// File attachment reference stored inside a `.file` PropertyValue.
///
/// On attach, the source file is copied into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>`
/// and `path` records the nexus-relative location. `original_name` preserves the user-visible
/// filename even if the on-disk path is mangled for collision avoidance.
///
/// Snake-case CodingKeys keep on-disk shape aligned with the rest of Pommora's JSON conventions
/// (`original_name`, `added_at`, `mime_type`) — see `// Features/Properties.md` File / Attachment row.
public struct FileRef: Codable, Hashable, Sendable {
    public var path: String
    public var originalName: String
    public var addedAt: Date
    public var mimeType: String

    public init(path: String, originalName: String, addedAt: Date, mimeType: String) {
        self.path = path
        self.originalName = originalName
        self.addedAt = addedAt
        self.mimeType = mimeType
    }

    enum CodingKeys: String, CodingKey {
        case path
        case originalName = "original_name"
        case addedAt = "added_at"
        case mimeType = "mime_type"
    }
}
