import Foundation

/// Reserved, UI-hidden, NON-authoritative on-disk stamp distinguishing the two
/// forms of one entity-type. Serialized as the frontmatter key `Class`. Folder
/// sidecar is the authority; this stamp self-heals (see the launch stamp pass).
enum KindStamp: String, Codable, Sendable, Equatable {
    case item
    case page
}
