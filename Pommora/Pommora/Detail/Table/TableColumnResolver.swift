import Foundation

/// A fully-resolved table column: the ordered, sized, icon-bearing descriptor
/// the custom table renders. Produced by `TableColumnResolver` from a
/// `SavedView` + a PageType's property schema.
struct ResolvedColumn: Equatable, Hashable, Sendable, Identifiable {
    /// Column kind — drives default width, header icon, and cell rendering.
    /// Modeled as an enum + switch (HARD RULE: condensed exhaustive control
    /// flow) rather than loose booleans/strings.
    enum Kind: Equatable, Hashable, Sendable {
        case title
        case property
        case tier
        case modified
    }

    /// Stable identifier — the reserved ID (`_title` / `_modified_at` /
    /// `_tierN`) or the user property's schema ID. Drives diffing + width lookup.
    let id: String
    let kind: Kind
    /// Display label for the header cell.
    let title: String
    /// SF Symbol for the header cell.
    let iconName: String
    /// Resolved column width in points (already clamped to the 60pt minimum).
    let width: Double
}

/// Resolves a `SavedView` + property schema into the ordered `[ResolvedColumn]`
/// the custom table renders. A pure (static) resolver — no actor isolation.
///
/// Resolution rules:
///   - `propertyOrder` is consumed VERBATIM — Title may sit anywhere; the
///     resolver does NOT force it first.
///   - `hiddenProperties` excludes a column, EXCEPT `_title` (never hidden) and
///     `cover` (never a column at all, regardless of order/hidden state).
///   - Tiers (`_tier1/2/3`) + `_modified_at` are DEFAULT-ON: appended unless
///     hidden or already placed by `propertyOrder` (native-table parity). Users
///     hide them via the Layout visibility list (→ `hiddenProperties`).
///   - Unaccounted schema properties (present in the schema but absent from
///     `propertyOrder` and not hidden) APPEND as visible columns at the end,
///     so a freshly-created property shows immediately.
///   - An order entry referencing an ID absent from the schema is skipped
///     (defensive stale-reference tolerance), EXCEPT the reserved `_title` /
///     `_modified_at` which render without a schema def.
enum TableColumnResolver {
    static func resolve(view: SavedView, schema: [PropertyDefinition]) -> [ResolvedColumn] {
        let hiddenSet = Set(view.hiddenProperties)
        var emittedIDs = Set<String>()
        var result: [ResolvedColumn] = []

        func append(id: String, def: PropertyDefinition?) {
            guard !emittedIDs.contains(id) else { return }
            guard let column = makeColumn(id: id, def: def, view: view) else { return }
            emittedIDs.insert(id)
            result.append(column)
        }

        // Pass 1 + Pass 2 — the shared visible-property skeleton resolves the
        // ordered ids (saved order verbatim, then unaccounted schema props). The
        // table renders `_title` / `_modified_at` WITHOUT a schema def, and keeps
        // tiers + Modified out of Pass 2 (they're supplied default-on by Pass 3
        // below), so Pass 2 excludes all reserved ids.
        let orderedIDs = VisiblePropertyOrder.resolve(
            view: view, schema: schema,
            defLessReserved: [ReservedPropertyID.title, ReservedPropertyID.modifiedAt],
            pass2ExcludesReserved: true)
        for id in orderedIDs {
            append(id: id, def: schema.first(where: { $0.id == id }))
        }

        // Pass 3 — the hideable reserved columns (tier links + Modified) are shown
        // by DEFAULT (parity with the native table, which always renders them) when
        // not hidden and not already placed by an explicit `propertyOrder`. Users
        // hide them via the Layout visibility list (→ `hiddenProperties`), which
        // Pass 1 honors; this only supplies the default-on reserved column set.
        // Tier order matches the native table: Projects, Topics, Areas (tier3→1),
        // then Modified last.
        for id in [
            ReservedPropertyID.tier3, ReservedPropertyID.tier2, ReservedPropertyID.tier1,
            ReservedPropertyID.modifiedAt,
        ] where !emittedIDs.contains(id) && !hiddenSet.contains(id) {
            append(id: id, def: schema.first(where: { $0.id == id }))
        }

        // Structural guarantee: Title is always present and never hidden,
        // regardless of `propertyOrder` contents (which may be hand-edited or
        // agent-written without `_title`). If neither pass emitted it, build the
        // reserved Title column (def nil) and insert it at the FRONT.
        if !emittedIDs.contains(ReservedPropertyID.title),
            let titleColumn = makeColumn(id: ReservedPropertyID.title, def: nil, view: view)
        {
            result.insert(titleColumn, at: 0)
        }

        return result
    }

    /// Builds one `ResolvedColumn`, mapping ID + schema def → kind, label, icon,
    /// and width. Returns nil when a non-reserved ID has no usable def.
    private static func makeColumn(
        id: String,
        def: PropertyDefinition?,
        view: SavedView
    ) -> ResolvedColumn? {
        let kind = kind(forID: id)
        let width = max(60, view.columnWidths?[id] ?? defaultWidth(for: kind))

        switch kind {
        case .title:
            return ResolvedColumn(
                id: id, kind: .title, title: "Title", iconName: "textformat", width: width)
        case .modified:
            return ResolvedColumn(
                id: id, kind: .modified, title: "Modified", iconName: "clock", width: width
            )
        case .tier:
            guard let def else { return nil }
            return ResolvedColumn(
                id: id, kind: .tier, title: def.name, iconName: tierIcon(forID: id), width: width
            )
        case .property:
            guard let def else { return nil }
            return ResolvedColumn(
                id: id, kind: .property, title: def.name, iconName: def.displayIcon, width: width
            )
        }
    }

    /// Maps an ID + optional schema def to its column kind.
    private static func kind(forID id: String) -> ResolvedColumn.Kind {
        switch id {
        case ReservedPropertyID.title: return .title
        case ReservedPropertyID.modifiedAt: return .modified
        case ReservedPropertyID.tier1, ReservedPropertyID.tier2, ReservedPropertyID.tier3:
            return .tier
        default: return .property
        }
    }

    /// SF Symbol for a tier column's header — mirrors `EditPropertyPane`'s
    /// per-tier icons (Areas / Topics / Projects).
    private static func tierIcon(forID id: String) -> String {
        switch ReservedPropertyID.tierNumber(forID: id) {
        case 1: return "square.stack.3d.up"
        case 2: return "folder"
        default: return "list.bullet.rectangle"
        }
    }

    /// Default column width per kind, used when `columnWidths` has no entry.
    /// Derived from the native vault `Table`'s ideal widths (property 120/ideal,
    /// Modified 180/ideal); Title leads wider; tiers match user properties.
    static func defaultWidth(for kind: ResolvedColumn.Kind) -> Double {
        switch kind {
        case .title: return 240
        case .property: return 160
        case .tier: return 160
        case .modified: return 180
        }
    }
}
