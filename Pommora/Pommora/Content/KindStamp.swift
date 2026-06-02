import Foundation

/// Reserved, UI-hidden, NON-authoritative on-disk stamp distinguishing the two
/// forms of one entity-type. Serialized as the frontmatter key `Class`. Folder
/// sidecar is the authority; this stamp self-heals (see the launch stamp pass).
enum KindStamp: String, Codable, Sendable, Equatable {
    case item
    case page
}

extension KeyedDecodingContainer {
    /// Lenient `Class`-stamp decode shared by `ItemFrontmatter` + `PageFrontmatter`:
    /// decodes the raw string and maps it, defaulting on a missing OR unknown value.
    /// A naive `decodeIfPresent(KindStamp.self)` would THROW on a foreign
    /// `Class: widget` and brick the load — this swallows only the unknown-enum-case,
    /// not other decode failures. The two sides differ only in their default.
    func decodeKind(forKey key: Key, default fallback: KindStamp) throws -> KindStamp {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return fallback }
        return KindStamp(rawValue: raw) ?? fallback
    }
}
