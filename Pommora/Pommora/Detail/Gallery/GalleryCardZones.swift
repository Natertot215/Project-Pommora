import Foundation

/// Pure zone-partition logic for a gallery card. A card's visible properties are
/// split into three render zones — **chips** (select / multiSelect / status /
/// relation), **meta** (date / datetime / lastEditedTime / number / checkbox),
/// and **links** (url) — each preserving the view's `propertyOrder`, honoring
/// `hiddenProperties`, and ALWAYS excluding the `cover` field (covers render in
/// the card's image area, never as a property zone).
///
/// Visible-property resolution is the shared `VisiblePropertyOrder.resolve`
/// skeleton (order verbatim → unaccounted-append) that `TableColumnResolver`
/// also consumes — here minus the `_title` column (the card renders title in its
/// header), with `_modified_at` flowing into the meta zone like any other
/// timestamp via its schema def when present.
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
        // The shared visible-property skeleton resolves the ordered ids (saved
        // order verbatim, then unaccounted schema props). The card renders the
        // title in its header (so `_title` is excluded) and requires a schema def
        // for every zone (no def-less reserved), but keeps tiers + Modified as
        // ordinary zone properties — so Pass 2 excludes only `_title`.
        VisiblePropertyOrder.resolve(
            view: view, schema: schema,
            pass1Exclude: [ReservedPropertyID.title],
            pass2ExcludesReserved: false
        )
        .compactMap { id in schema.first(where: { $0.id == id }) }
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
