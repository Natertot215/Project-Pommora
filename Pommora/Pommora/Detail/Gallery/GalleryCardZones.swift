import Foundation

/// Pure zone-partition logic for a gallery card. A card's visible properties are
/// split into three render zones — **chips** (select / multiSelect / status /
/// relation), **meta** (date / datetime / lastEditedTime / number / checkbox),
/// and **links** (url) — each preserving the view's `propertyOrder`, honoring
/// `hiddenProperties`, and ALWAYS excluding the `cover` field (covers render in
/// the card's image area, never as a property zone).
///
/// Mirrors `TableColumnResolver`'s visible-property resolution (order verbatim →
/// unaccounted-append), minus the `_title` column (the card renders title in its
/// header) and minus `_modified_at`-as-a-column (Modified flows into the meta
/// zone like any other timestamp via its schema def when present).
///
/// No SwiftUI, no disk — a pure value transform, exhaustively tested.
enum GalleryCardZones {

    /// A property's gallery render zone. Modeled as an enum + switch (HARD RULE:
    /// condensed exhaustive control flow) over `PropertyType`.
    enum Zone: Equatable, Sendable {
        case chips
        case meta
        case links
    }

    /// The cover sentinel — excluded unconditionally from every zone.
    private static let coverID = "cover"

    /// Maps a property type to its gallery zone.
    static func zone(for type: PropertyType) -> Zone {
        switch type {
        case .select, .multiSelect, .status, .relation:
            return .chips
        case .date, .datetime, .lastEditedTime, .number, .checkbox:
            return .meta
        case .url:
            return .links
        case .file:
            // File attachments have no card affordance yet — bucket with meta so
            // the switch stays exhaustive; the renderer simply renders nothing.
            return .meta
        }
    }

    /// The ordered, visible property definitions a card renders — the view's
    /// `propertyOrder` consumed verbatim (cover + `_title` + hidden excluded),
    /// then unaccounted schema properties appended. Reserved `_modified_at` and
    /// tiers resolve through their schema defs when present.
    static func visibleProperties(
        view: SavedView, schema: [PropertyDefinition]
    ) -> [PropertyDefinition] {
        let hiddenSet = Set(view.hiddenProperties)
        var emitted = Set<String>()
        var result: [PropertyDefinition] = []

        func append(_ def: PropertyDefinition) {
            guard !emitted.contains(def.id) else { return }
            emitted.insert(def.id)
            result.append(def)
        }

        // Pass 1 — saved order, verbatim. Cover + Title never yield a property;
        // everything else respects `hiddenProperties`.
        for propID in view.propertyOrder {
            guard propID != coverID, propID != ReservedPropertyID.title else { continue }
            guard !hiddenSet.contains(propID) else { continue }
            guard let def = schema.first(where: { $0.id == propID }) else { continue }
            append(def)
        }

        // Pass 2 — unaccounted, not-hidden schema properties append at the end.
        for def in schema
        where !emitted.contains(def.id)
            && !hiddenSet.contains(def.id)
            && def.id != coverID
            && def.id != ReservedPropertyID.title
        {
            append(def)
        }

        return result
    }

    /// The visible properties partitioned into the three zones, each keeping the
    /// `propertyOrder`-derived sequence. The cover field never appears (excluded
    /// in `visibleProperties`).
    static func partition(
        view: SavedView, schema: [PropertyDefinition]
    ) -> (chips: [PropertyDefinition], meta: [PropertyDefinition], links: [PropertyDefinition]) {
        var chips: [PropertyDefinition] = []
        var meta: [PropertyDefinition] = []
        var links: [PropertyDefinition] = []
        for def in visibleProperties(view: view, schema: schema) {
            switch zone(for: def.type) {
            case .chips: chips.append(def)
            case .meta: meta.append(def)
            case .links: links.append(def)
            }
        }
        return (chips, meta, links)
    }
}
