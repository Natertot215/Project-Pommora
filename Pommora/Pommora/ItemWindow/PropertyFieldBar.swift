import SwiftUI

/// The Item Window's pinned-property "Property Field" bar — a horizontal row that
/// reads like a native macOS **segmented control**: ONE rounded `quaternaryFill`
/// container, each segment separated from its neighbour by a thin vertical bar.
/// Each segment is one pinned select/multiSelect property; it shows the property's
/// **title when empty** and a **value chip when filled**, and tapping a segment
/// opens that property's chip dropdown (the same `ChipDropdown` the cell editor
/// uses). No per-segment icon. v1 surfaces select + multiSelect only (Pool A).
///
/// A real `NSSegmentedControl` can't host per-segment popovers or chip content, so
/// this replicates the native segmented *look* in SwiftUI while keeping the
/// segment-as-dropdown-button behavior (the "build upon" latitude per Nathan).
///
/// **Data-driven, not VM-coupled** — it takes the schema (`itemType` + optional
/// `collection`), a snapshot of the current draft values, and an `onChange`
/// callback (wired to `vm.handlePropertyChange`). That keeps it a clean,
/// Component-Library-style asset the renderer pulls in.
///
/// **Quirk #12 (GRDB `String` `SQLSpecificExpressible` pollution):** all segment
/// computation + id matching live in plain-value helpers OUTSIDE any `@ViewBuilder`
/// body, using `first(where:)` / `firstIndex(of:)` rather than `contains` /
/// `==` inside a view. Mirrors the `ContextPicker.swift` pattern.
struct PropertyFieldBar: View {
    let itemType: ItemType
    let collection: ItemCollection?
    /// Current draft values (a snapshot; the renderer re-passes `vm.draftProperties`
    /// whenever the VM mutates, so the bar re-renders against fresh values).
    let values: [String: PropertyValue]
    /// Routes a single segment's edit back to the VM (`vm.handlePropertyChange`).
    let onChange: (String, PropertyValue) -> Void

    var body: some View {
        let entries = Self.segments(itemType: itemType, collection: collection)
        // Empty bar collapses — no rounded container when nothing is pinned.
        if !entries.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.definition.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }
                    PropertyFieldSegment(
                        definition: entry.definition,
                        value: values[entry.definition.id],
                        onChange: onChange
                    )
                }
            }
            .frame(maxWidth: .infinity)
            // ONE rounded segmented container on quaternaryFill (the window
            // behind is glass; this fill reads as a native segmented track).
            .background(
                Color(.quaternarySystemFill),
                in: RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
            )
            // Inset to match the body card's rail. Lives INSIDE the populated
            // branch so the collapsed (no-segment) case adds no gap between the
            // header divider and the body.
            .padding(.horizontal, PUI.Spacing.xl)
            .padding(.top, PUI.Spacing.xl)
        }
    }

    // MARK: - Per-pool slice (plain value code — OUTSIDE any @ViewBuilder, quirk #12-safe)

    /// The segment list, defensively capped per pool so a malformed template can't
    /// overflow the row. Takes the v1-checkable promoted entries
    /// (`TemplateResolver.promotedForField`, already filtered to select/multiSelect
    /// and in partition order), groups them by `ItemWindowZoneConfig.pool(for:)`,
    /// and keeps at most each pool's cap — NOT a single global `.prefix`.
    ///
    /// Today every surviving entry is select/multiSelect (Pool A, `combinedTotal(6)`),
    /// so this caps the visible row at 6; written per-pool so a future pool widening
    /// stays safe. Pure value code — `first(where:)` (no `contains`), no `==` in a view.
    static func segments(
        itemType: ItemType, collection: ItemCollection?
    ) -> [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        let promoted = TemplateResolver.promotedForField(type: itemType, collection: collection)
        var keptPerPool: [Int: Int] = [:]  // pool index → count kept so far
        var result: [(promotion: PromotedProperty, definition: PropertyDefinition)] = []
        for entry in promoted {
            guard let poolIndex = poolIndex(for: entry.definition.type),
                let cap = cap(forPoolIndex: poolIndex)
            else { continue }
            let kept = keptPerPool[poolIndex] ?? 0
            if kept < cap {
                keptPerPool[poolIndex] = kept + 1
                result.append(entry)
            }
        }
        return result
    }

    /// Index of the pool a type belongs to (`first(where:)`, never `contains`).
    private static func poolIndex(for type: PropertyType) -> Int? {
        ItemWindowZoneConfig.pools.firstIndex(where: { $0.types.first(where: { $0 == type }) != nil })
    }

    /// The numeric cap for a pool index. `combinedTotal(n)` and `perType(n)` both
    /// floor the bar's count at `n`; per-type vs combined distinction is the
    /// Templates pane's muting concern, not the bar's overflow guard.
    private static func cap(forPoolIndex index: Int) -> Int? {
        guard index >= 0, index < ItemWindowZoneConfig.pools.count else { return nil }
        switch ItemWindowZoneConfig.pools[index].rule {
        case .combinedTotal(let n): return n
        case .perType(let n): return n
        }
    }
}

// MARK: - Segment (plain value props — isolated from GRDB String overloads, quirk #12)

/// One segment of the Property Field bar. A tappable button that shows the
/// property **title when empty** / the **value chip(s) when filled** (no icon),
/// and opens the property's `ChipDropdown` in a `.popover` on tap. A pinned
/// segment always renders — even empty — which is the whole point of the bar.
private struct PropertyFieldSegment: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let onChange: (String, PropertyValue) -> Void

    @State private var showDropdown = false
    /// Seeded `.onAppear` from the definition's options. A live `@State` binding so
    /// the multi-select dropdown can drag-reorder in-session (mirrors the cell
    /// editor's `multiOptionOrder`).
    @State private var opts: [PropertyChipOption] = []

    var body: some View {
        Button {
            showDropdown = true
        } label: {
            label
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PUI.Spacing.md)
                .padding(.vertical, PUI.Spacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDropdown, arrowEdge: .bottom) {
            // ChipDropdown draws its own Liquid-Glass panel — present chromeless
            // (clear background, no padding wrapper) so the popover doesn't stack
            // a second container around it (matches PropertyCellEditor).
            ChipDropdown(
                options: $opts,
                selectionMode: definition.type == .multiSelect ? .multi : .single,
                selectedIDs: Self.selectedIDs(from: value),
                onPick: { opt in apply(opt) },
                size: .compact
            )
            .presentationBackground(.clear)
        }
        .onAppear { opts = Self.allOptions(of: definition) }
    }

    // MARK: - Label (empty → title; filled → chip[s])

    @ViewBuilder
    private var label: some View {
        if ItemWindowViewModel.isFilled(value) {
            let chips = Self.filledChips(definition: definition, value: value)
            // Render the selected value(s) as compact pills. Single-select shows one;
            // multi-select shows each chosen option as its own pill in a row.
            HStack(spacing: PUI.Spacing.xs) {
                ForEach(chips) { chip in
                    PropertyChip(label: chip.label, color: chip.color, size: .compact)
                }
            }
        } else {
            // Empty segment = the property's title (secondary, native segmented feel).
            Text(definition.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - onPick toggle (mirrors PropertyCellEditor's select / multiSelect)

    /// Applies a dropdown pick. Mirrors `PropertyCellEditor` exactly:
    /// - `.single` (select) → set `.select(opt.id)`, then dismiss the dropdown.
    /// - `.multi` (multiSelect) → toggle `opt.id` in the current id set; an empty
    ///   result writes `.null` (clear), otherwise `.multiSelect(newIDs)`. The
    ///   dropdown stays open for further multi-toggles.
    private func apply(_ opt: PropertyChipOption) {
        switch definition.type {
        case .multiSelect:
            var ids = Self.currentMultiIDs(from: value)
            if let i = ids.firstIndex(of: opt.id) {
                ids.remove(at: i)
            } else {
                ids.append(opt.id)
            }
            onChange(definition.id, ids.isEmpty ? .null : .multiSelect(ids))
        default:
            onChange(definition.id, .select(opt.id))
            showDropdown = false
        }
    }

    // MARK: - Plain value helpers (OUTSIDE the @ViewBuilder body — quirk #12-safe)

    /// All options for this property, as chip options (the dropdown's source).
    static func allOptions(of definition: PropertyDefinition) -> [PropertyChipOption] {
        (definition.selectOptions ?? []).map { $0.asChipOption() }
    }

    /// The current selected ids as a `Set<String>` for the dropdown's `selectedIDs`.
    static func selectedIDs(from value: PropertyValue?) -> Set<String> {
        switch value {
        case .select(let id): return [id]
        case .multiSelect(let ids): return Set(ids)
        default: return []
        }
    }

    /// The current multi-select ids as an ordered array (for the toggle).
    static func currentMultiIDs(from value: PropertyValue?) -> [String] {
        if case .multiSelect(let ids) = value { return ids }
        return []
    }

    /// The chip option(s) to render for a filled value — resolved against the
    /// definition's options so each pill shows the option's current label + color.
    /// Uses `first(where:)` (never `contains`); a stored id with no matching option
    /// is dropped (defensive — a deleted option can't crash the bar).
    static func filledChips(
        definition: PropertyDefinition, value: PropertyValue?
    ) -> [PropertyChipOption] {
        let all = allOptions(of: definition)
        switch value {
        case .select(let id):
            return all.first(where: { $0.id == id }).map { [$0] } ?? []
        case .multiSelect(let ids):
            return ids.compactMap { id in all.first(where: { $0.id == id }) }
        default:
            return []
        }
    }
}
