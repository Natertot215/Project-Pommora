import Foundation

/// Descriptor produced by `PropertyColumnBuilder` to drive Table column
/// declarations in the four storage detail views.
///
/// SwiftUI's macOS `Table` doesn't support dynamic column counts via
/// `TableColumnForEach` — `columns:` is a static result-builder. We work
/// around that by computing a struct array at the call-site level then
/// translating into a switch-based fixed column set per detail view. The
/// detail-view file owns the `Table { } columns: { ... }` declaration; the
/// builder owns the order + which user properties are in scope.
struct PropertyColumn: Identifiable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case title
        case userProperty(PropertyDefinition)
        case lastEditedTime
    }

    let kind: Kind

    /// Stable identifier for SwiftUI ForEach / Identifiable diffing.
    /// `title` and `lastEditedTime` use reserved IDs that match
    /// `ReservedPropertyID`. User properties use the schema's property ID.
    var id: String {
        switch kind {
        case .title: return "_title"
        case .userProperty(let def): return def.id
        case .lastEditedTime: return "_modified_at"
        }
    }
}

/// Computes the ordered TableColumn descriptors for a container's active
/// view. Reserved Title column always leads; reserved Last Edited Time
/// always trails. User properties appear in between: first the explicitly
/// `visibleProperties` (in order), then any "unaccounted" schema properties
/// (in neither visible nor hidden — e.g. freshly created) as visible-by-
/// default. Only `hiddenProperties` are excluded.
///
/// The three tier relation columns (Project / Topic / Area → `_tier3`,
/// `_tier2`, `_tier1`) are emitted rightmost-before-Modified, in that order,
/// after all user-property columns and immediately before the trailing
/// `.lastEditedTime`. Callers pass `resolvedProperties(tierConfig:)` so the
/// tier defs are present in `schema`; each tier is hideable (skipped when its
/// ID is in `hiddenProperties`) and only emitted when its def is actually in
/// `schema` (defensive — a schema without tiers gets no tier columns).
///
/// If `visibleProperties` references a property ID not present in `schema`
/// (e.g. property was deleted but the view config wasn't cleaned up), the
/// ID is silently skipped — defensive parity with quirk #15's "in-memory
/// state must tolerate stale on-disk references."
enum PropertyColumnBuilder {
    static func columns(view: SavedView, schema: [PropertyDefinition]) -> [PropertyColumn] {
        var result: [PropertyColumn] = [PropertyColumn(kind: .title)]
        let lastEditedID = "_modified_at"
        let hiddenSet = Set(view.hiddenProperties)

        // Explicitly-visible properties, in the view's saved order.
        for propID in view.visibleProperties {
            // Skip the reserved trailer — it's appended separately + locked-
            // always-visible per PropertyVisibilityPane's invariant.
            guard propID != lastEditedID else { continue }
            guard let def = schema.first(where: { $0.id == propID }) else { continue }
            result.append(PropertyColumn(kind: .userProperty(def)))
        }

        // "Unaccounted" properties — present in the schema but in NEITHER
        // visibleProperties nor hiddenProperties (e.g. a freshly-created
        // property, which `addProperty` writes to the schema only). Render
        // them as visible-by-default, matching how PropertyVisibilityPane
        // already treats them, so a new property shows as a column
        // immediately. Reserved IDs never become user-property columns.
        for def in schema where !view.visibleProperties.contains(def.id)
            && !hiddenSet.contains(def.id)
            && !ReservedPropertyID.isReserved(def.id) {
            result.append(PropertyColumn(kind: .userProperty(def)))
        }

        // Tier relation columns — rightmost content columns, before Modified.
        // Order is Project / Topic / Area (tier3, tier2, tier1). Each tier is
        // hideable via `hiddenProperties`, and only emitted when its def is
        // present in `schema` (callers pass `resolvedProperties(tierConfig:)`;
        // a schema without tiers gets none). They never appear as user-property
        // columns above because both user loops exclude reserved IDs.
        for tierID in [ReservedPropertyID.tier3, ReservedPropertyID.tier2, ReservedPropertyID.tier1] {
            guard !hiddenSet.contains(tierID) else { continue }
            guard let def = schema.first(where: { $0.id == tierID }) else { continue }
            result.append(PropertyColumn(kind: .userProperty(def)))
        }

        result.append(PropertyColumn(kind: .lastEditedTime))
        return result
    }
}
