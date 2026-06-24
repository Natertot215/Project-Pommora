import Foundation

/// Pure grouping engine. Turns `[ViewItem]` + a `GroupConfig` + a `ViewScope`
/// into `[ResolvedGroup]`, sorting WITHIN each group (and each child group). No
/// disk, no SwiftUI.
///
/// Stable id scheme (load-bearing for collapse + selection):
///   - structural: container ULID (Collection or Set id)
///   - property bucket: the option value (or `"true"/"false"` for checkbox)
///   - ungrouped band / no-value bucket: `"_ungrouped"`
enum GroupResolver {
    static let ungroupedID = "_ungrouped"

    /// `sort` is the active sort criterion (nil = manual, input order preserved).
    /// `collapsed` is the set of collapsed group ids — a collapsed group still
    /// appears (header) with `isCollapsed = true`; the renderer hides its items.
    static func resolve(
        items: [ViewItem],
        config: GroupConfig?,
        scope: ViewScope,
        sort: SortCriterion? = nil,
        schema: [PropertyDefinition] = [],
        collapsed: Set<String> = []
    ) -> [ResolvedGroup] {
        let sorter = ViewSortComparator.sorter(for: sort, schema: schema)

        switch config {
        case .none, .some(.structural):
            return structural(items, scope: scope, sorter: sorter, collapsed: collapsed)
        case .some(.property(let grouping)):
            guard schema.contains(where: { $0.id == grouping.propertyID }) else {
                return structural(items, scope: scope, sorter: sorter, collapsed: collapsed)
            }
            return property(
                items, grouping: grouping, schema: schema,
                sorter: sorter, collapsed: collapsed)
        case .some(.flat):
            return flat(items, sorter: sorter, collapsed: collapsed)
        }
    }

    // MARK: - Sorting within a group

    /// Applies the group sorter, preserving input order when nil (manual). The
    /// sorter is itself stable (ties hold input order).
    private static func sorted(
        _ items: [ViewItem], _ sorter: ViewSortComparator.GroupSorter?
    )
        -> [ViewItem]
    {
        guard let sorter else { return items }
        return sorter(items)
    }

    // MARK: - Flat

    private static func flat(
        _ items: [ViewItem], sorter: ViewSortComparator.GroupSorter?, collapsed: Set<String>
    ) -> [ResolvedGroup] {
        guard !items.isEmpty else { return [] }
        return [
            ResolvedGroup(
                id: ungroupedID,
                title: "",
                kind: .ungrouped,
                items: sorted(items, sorter),
                isCollapsed: collapsed.contains(ungroupedID)
            )
        ]
    }

    // MARK: - Structural

    private static func structural(
        _ items: [ViewItem],
        scope: ViewScope,
        sorter: ViewSortComparator.GroupSorter?,
        collapsed: Set<String>
    ) -> [ResolvedGroup] {
        switch scope {
        case .vault: return structuralVault(items, sorter: sorter, collapsed: collapsed)
        case .collection:
            return structuralCollection(items, sorter: sorter, collapsed: collapsed)
        }
    }

    /// VAULT scope: group by Collection; that Collection's Sets nest as `children`.
    /// Pages not in any Set sit in the Collection group's own `items`. Pages at the
    /// vault root (no Collection) collect in a trailing ungrouped band.
    private static func structuralVault(
        _ items: [ViewItem],
        sorter: ViewSortComparator.GroupSorter?,
        collapsed: Set<String>
    ) -> [ResolvedGroup] {
        var collectionOrder: [String] = []
        var collections: [String: PageSet] = [:]
        var directItems: [String: [ViewItem]] = [:]  // collectionID → loose pages
        var setOrder: [String: [String]] = [:]  // collectionID → ordered set ids
        var sets: [String: PageSet] = [:]  // setID → set
        var setItems: [String: [ViewItem]] = [:]  // setID → pages
        var rootItems: [ViewItem] = []

        for item in items {
            switch item.parent {
            case .vaultRoot:
                rootItems.append(item)
            case .collection(let coll, _):
                register(coll, &collectionOrder, &collections)
                directItems[coll.id, default: []].append(item)
            case .set(let set, let coll, _):
                register(coll, &collectionOrder, &collections)
                if sets[set.id] == nil {
                    sets[set.id] = set
                    setOrder[coll.id, default: []].append(set.id)
                }
                setItems[set.id, default: []].append(item)
            }
        }

        var groups: [ResolvedGroup] = collectionOrder.map { cid in
            let coll = collections[cid]!
            let children: [ResolvedGroup] = (setOrder[cid] ?? []).map { sid in
                let set = sets[sid]!
                return ResolvedGroup(
                    id: set.id,
                    title: set.title,
                    kind: .structuralSet(set),
                    items: sorted(setItems[sid] ?? [], sorter),
                    isCollapsed: collapsed.contains(set.id)
                )
            }
            return ResolvedGroup(
                id: coll.id,
                title: coll.title,
                kind: .structuralCollection(coll),
                items: sorted(directItems[cid] ?? [], sorter),
                children: children.isEmpty ? nil : children,
                isCollapsed: collapsed.contains(coll.id)
            )
        }

        if !rootItems.isEmpty {
            groups.append(
                ResolvedGroup(
                    id: ungroupedID,
                    title: "",
                    kind: .ungrouped,
                    items: sorted(rootItems, sorter),
                    isCollapsed: collapsed.contains(ungroupedID)
                ))
        }
        return groups
    }

    /// COLLECTION scope: one group per Set + a root "ungrouped" band for pages in
    /// no Set. If the collection has ZERO Sets → ONE ungrouped band with NO header
    /// (today's flat look).
    private static func structuralCollection(
        _ items: [ViewItem],
        sorter: ViewSortComparator.GroupSorter?,
        collapsed: Set<String>
    ) -> [ResolvedGroup] {
        var setOrder: [String] = []
        var sets: [String: PageSet] = [:]
        var setItems: [String: [ViewItem]] = [:]
        var rootItems: [ViewItem] = []

        for item in items {
            if case .set(let set, _, _) = item.parent {
                if sets[set.id] == nil {
                    sets[set.id] = set
                    setOrder.append(set.id)
                }
                setItems[set.id, default: []].append(item)
            } else {
                rootItems.append(item)
            }
        }

        // Zero sets → a single headerless ungrouped band (flat look).
        guard !setOrder.isEmpty else {
            guard !rootItems.isEmpty else { return [] }
            return [
                ResolvedGroup(
                    id: ungroupedID,
                    title: "",
                    kind: .ungrouped,
                    items: sorted(rootItems, sorter),
                    isCollapsed: collapsed.contains(ungroupedID)
                )
            ]
        }

        var groups: [ResolvedGroup] = setOrder.map { sid in
            let set = sets[sid]!
            return ResolvedGroup(
                id: set.id,
                title: set.title,
                kind: .structuralSet(set),
                items: sorted(setItems[sid] ?? [], sorter),
                isCollapsed: collapsed.contains(set.id)
            )
        }
        if !rootItems.isEmpty {
            groups.append(
                ResolvedGroup(
                    id: ungroupedID,
                    title: "",
                    kind: .ungrouped,
                    items: sorted(rootItems, sorter),
                    isCollapsed: collapsed.contains(ungroupedID)
                ))
        }
        return groups
    }

    private static func register(
        _ coll: PageSet,
        _ order: inout [String],
        _ map: inout [String: PageSet]
    ) {
        if map[coll.id] == nil {
            map[coll.id] = coll
            order.append(coll.id)
        }
    }

    // MARK: - Property buckets

    /// Flat buckets ordered by `grouping.orderMode` + a no-value bucket (titled
    /// "No <Property>") placed per `emptyPlacement`. Checkbox nil values route to
    /// the "false" (Unchecked) bucket — no no-value bucket emitted for checkbox.
    private static func property(
        _ items: [ViewItem],
        grouping: PropertyGrouping,
        schema: [PropertyDefinition],
        sorter: ViewSortComparator.GroupSorter?,
        collapsed: Set<String>
    ) -> [ResolvedGroup] {
        let def = schema.first(where: { $0.id == grouping.propertyID })
        let isCheckbox = def?.type == .checkbox

        var buckets: [String: [ViewItem]] = [:]
        var noValue: [ViewItem] = []
        for item in items {
            if let key = bucketKey(item, grouping: grouping) {
                buckets[key, default: []].append(item)
            } else if isCheckbox {
                buckets["false", default: []].append(item)
            } else {
                noValue.append(item)
            }
        }

        let ordered = bucketOrder(grouping: grouping, def: def, present: Set(buckets.keys))

        var groups: [ResolvedGroup] = ordered.compactMap { key in
            guard let bucketItems = buckets[key] else { return nil }
            return ResolvedGroup(
                id: key,
                title: bucketTitle(key, def: def),
                kind: .propertyBucket(value: key),
                items: sorted(bucketItems, sorter),
                isCollapsed: collapsed.contains(key)
            )
        }

        // No-value ("No <Property>") bucket — inert for checkbox.
        if !isCheckbox && !noValue.isEmpty && !grouping.hideEmptyGroups {
            let noValueGroup = ResolvedGroup(
                id: ungroupedID,
                title: "No \(def?.name ?? "Value")",
                kind: .propertyBucket(value: nil),
                items: sorted(noValue, sorter),
                isCollapsed: collapsed.contains(ungroupedID)
            )
            if grouping.emptyPlacement == .top {
                groups.insert(noValueGroup, at: 0)
            } else {
                groups.append(noValueGroup)
            }
        }
        return groups
    }

    /// The single grouping key for an item's value (nil = no value → ungrouped).
    /// Shared with `RowDragCoordinator` so a drag's source-bucket resolution and
    /// group membership stay one source of truth.
    static func bucketKey(_ item: ViewItem, grouping: PropertyGrouping) -> String? {
        let granularity = grouping.dateGranularity ?? .month
        switch item.page.frontmatter.properties[grouping.propertyID] {
        case .select(let s), .status(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        case .date(let d), .datetime(let d): return DateBucket.key(for: d, granularity: granularity)
        case .none, .some(.null): return nil
        default: return nil
        }
    }

    /// Bucket display order driven by `grouping.orderMode`:
    ///   - `.manual`    — explicit `order` list first, then any remaining keys sorted
    ///   - `.configured` — schema option order, then checkbox false→true, else lexicographic
    ///   - `.reversed`  — `.configured` base order reversed
    /// Always filtered to keys that actually have items (compactMap upstream).
    private static func bucketOrder(
        grouping: PropertyGrouping, def: PropertyDefinition?, present: Set<String>
    ) -> [String] {
        switch grouping.orderMode {
        case .manual:
            let order = grouping.order ?? []
            let tail = present.subtracting(order).sorted()
            return order + tail

        case .configured:
            if let schemaOrder = schemaOptionOrder(def) {
                let tail = present.subtracting(schemaOrder).sorted()
                return schemaOrder + tail
            }
            if def?.type == .checkbox {
                return ["false", "true"]
            }
            return present.sorted()

        case .reversed:
            let base: [String]
            if let schemaOrder = schemaOptionOrder(def) {
                let tail = present.subtracting(schemaOrder).sorted()
                base = schemaOrder + tail
            } else if def?.type == .checkbox {
                base = ["false", "true"]
            } else {
                base = present.sorted()
            }
            return base.reversed()
        }
    }

    private static func schemaOptionOrder(_ def: PropertyDefinition?) -> [String]? {
        guard let def else { return nil }
        if let opts = def.selectOptions { return opts.map(\.value) }
        if let groups = def.statusGroups { return groups.flatMap { $0.options.map(\.value) } }
        return nil
    }

    /// Maps a bucket key to its display title via the schema (option label /
    /// checkbox phrasing), falling back to the raw key.
    private static func bucketTitle(_ key: String, def: PropertyDefinition?) -> String {
        if def?.type == .checkbox {
            return key == "true" ? "Checked" : "Unchecked"
        }
        if let label = def?.selectOptions?.first(where: { $0.value == key })?.label {
            return label
        }
        if let groups = def?.statusGroups {
            for group in groups {
                if let option = group.options.first(where: { $0.value == key }) {
                    return option.label
                }
            }
        }
        return key
    }
}
