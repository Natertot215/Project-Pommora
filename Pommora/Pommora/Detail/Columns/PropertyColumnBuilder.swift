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
/// always trails. User properties appear in between per
/// `view.visibleProperties` order. Hidden properties are excluded.
///
/// If `visibleProperties` references a property ID not present in `schema`
/// (e.g. property was deleted but the view config wasn't cleaned up), the
/// ID is silently skipped — defensive parity with quirk #15's "in-memory
/// state must tolerate stale on-disk references."
enum PropertyColumnBuilder {
    static func columns(view: SavedView, schema: [PropertyDefinition]) -> [PropertyColumn] {
        var result: [PropertyColumn] = [PropertyColumn(kind: .title)]
        let lastEditedID = "_modified_at"
        for propID in view.visibleProperties {
            // Skip the reserved trailer — it's appended separately + locked-
            // always-visible per Task 12's PropertyVisibilityPane invariant.
            guard propID != lastEditedID else { continue }
            guard let def = schema.first(where: { $0.id == propID }) else { continue }
            result.append(PropertyColumn(kind: .userProperty(def)))
        }
        result.append(PropertyColumn(kind: .lastEditedTime))
        return result
    }
}
