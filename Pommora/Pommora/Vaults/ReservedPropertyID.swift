import Foundation

/// Catalog of reserved property IDs. Built-in (Pommora-managed) properties use the `_` prefix
/// (`_id`, `_status`, `_tier1`, …); user-defined properties use the `prop_` prefix mints by
/// `mintUserPropertyID()`. The schema editor must block user attempts to claim a reserved ID.
///
/// Property display *names* are unrestricted — a user may rename a property to "_status"
/// freely. Only the ID field is reserved.
enum ReservedPropertyID {
    /// All reserved IDs Pommora knows about as of v0.3.0.
    static let all: Set<String> = [
        "_id", "_created_at", "_modified_at",
        "_status",
        "_type",
        "_tier1", "_tier2", "_tier3",
        "_wikilinks",
    ]

    /// True iff `id` is in the reserved catalog. Used by the schema-editor validator.
    static func isReserved(_ id: String) -> Bool {
        all.contains(id)
    }

    /// Mint a fresh user-defined property ID using the `prop_<ulid>` scheme.
    static func mintUserPropertyID() -> String {
        "prop_\(ULID.generate())"
    }
}
