import Foundation

/// Per-sidecar persisted default sort. Optional on each schema; when absent,
/// callers fall back to `_modified_at descending`. Stored as a tagged object
/// in the sidecar's `default_sort` field. Powers column-header sort
/// persistence (Phase J read site).
struct DefaultSortConfig: Codable, Equatable, Hashable, Sendable {
    var propertyID: String  // e.g. "_modified_at", "_id", "prop_<ulid>"
    var direction: Direction

    enum Direction: String, Codable, CaseIterable, Hashable, Sendable {
        case ascending, descending
    }

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case direction
    }

    /// Fallback when no `default_sort` is persisted on a sidecar.
    static let legacyDefault = DefaultSortConfig(
        propertyID: "_modified_at",
        direction: .descending
    )
}
