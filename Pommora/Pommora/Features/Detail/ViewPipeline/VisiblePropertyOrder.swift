import Foundation

/// The shared visible-property ordering skeleton for the view renderers. Both
/// `TableColumnResolver` (columns) and `GalleryCardZones` (card zones) need the
/// SAME two-pass resolution — Pass 1 consumes the view's `propertyOrder`
/// VERBATIM (cover + caller-excluded ids skipped, `hiddenProperties` honored),
/// Pass 2 appends any unaccounted, not-hidden schema property at the end — so it
/// lives here once (HARD RULE: DRY) and each caller maps the resulting IDs to
/// its own shape (the table adds def-less reserved columns + Pass-3 default-on
/// tiers/Modified; the gallery partitions into zones).
///
/// Returns property **IDs**, not `PropertyDefinition`s, because the callers
/// diverge on whether a reserved id may render WITHOUT a schema def (the table
/// renders `_title` / `_modified_at` def-less; the gallery requires a def).
enum VisiblePropertyOrder {
    /// The ordered, de-duplicated visible property IDs.
    ///
    /// - `defLessReserved`: reserved IDs that may appear in Pass 1 even with no
    ///   schema def (the table's `_title` / `_modified_at`). Everything else
    ///   needs a backing def, so a stale `propertyOrder` reference is skipped.
    /// - `pass1Exclude`: IDs never surfaced in Pass 1 regardless (the cover
    ///   sentinel is always excluded; the caller may add more, e.g. `_title`).
    /// - `pass2ExcludesReserved`: when true, Pass 2 skips ALL reserved IDs (the
    ///   table supplies tiers + Modified via its own Pass 3); when false, Pass 2
    ///   only skips `_title` (the gallery surfaces tiers + Modified as zones).
    static func resolve(
        view: SavedView,
        schema: [PropertyDefinition],
        defLessReserved: Set<String> = [],
        pass1Exclude: Set<String> = [],
        pass2ExcludesReserved: Bool
    ) -> [String] {
        let hiddenSet = Set(view.hiddenProperties)
        let excludePass1 = pass1Exclude.union([ReservedPropertyID.cover])
        var emitted = Set<String>()
        var result: [String] = []

        func append(_ id: String) {
            guard !emitted.contains(id) else { return }
            emitted.insert(id)
            result.append(id)
        }

        // Pass 1 — the saved order, VERBATIM. Cover + caller-excluded ids never
        // yield a property; everything else respects `hiddenProperties`. A
        // non-`defLessReserved` id needs a schema def (stale references skip).
        for propID in view.propertyOrder {
            guard !excludePass1.contains(propID) else { continue }
            guard !hiddenSet.contains(propID) else { continue }
            if defLessReserved.contains(propID) {
                append(propID)
            } else if schema.contains(where: { $0.id == propID }) {
                append(propID)
            }
        }

        // Pass 2 — unaccounted, not-hidden schema properties append at the end.
        for def in schema
        where !emitted.contains(def.id)
            && !hiddenSet.contains(def.id)
            && def.id != ReservedPropertyID.cover
            && (pass2ExcludesReserved
                ? !ReservedPropertyID.isReserved(def.id)
                : def.id != ReservedPropertyID.title)
        {
            append(def.id)
        }

        return result
    }
}
