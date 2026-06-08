import SwiftUI

/// The Item Window's pinned-property "Property Field" bar — a horizontal row that
/// reads like a native macOS **segmented control**: ONE rounded
/// `quaternarySystemFill` track (the SAME fill the body text-box uses, so bar +
/// body read as one material) that spans the FULL content rail, its content-sized
/// cells filling that fixed width separated by thin vertical dividers (see
/// `SegmentedTrackLayout`). Each cell is one pinned select/multiSelect property; it
/// shows the property's **title when empty** and a **value chip when filled**, and
/// tapping a cell opens that property's chip dropdown (the same `ChipDropdown` the
/// cell editor uses). No per-segment icon. v1 surfaces select + multiSelect only
/// (Pool A).
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

    /// Native `NSSegmentedControl` track height — every segment + divider sits
    /// inside this fixed band so the bar reads as the system control, not a tall
    /// custom field. (28pt is AppKit's standard segmented-control height.)
    private static let trackHeight: CGFloat = 28

    var body: some View {
        let entries = Self.segments(itemType: itemType, collection: collection)
        // Empty bar collapses — no rounded container when nothing is pinned.
        if !entries.isEmpty {
            // Content-sized, variable-width cells that FILL a fixed full-width track,
            // separated by thin vertical dividers — Apple's
            // `NSSegmentedControl.apportionsSegmentWidthsByContent` look, but stretched
            // to a fixed frame. `SegmentedTrackLayout` measures each cell's content
            // width and distributes the track's full width proportionally, so a longer
            // chip yields a wider cell while the cells together consume the entire rail
            // (no trailing gap). The dividers are placed at their native hairline width
            // in the gaps. Subviews arrive interleaved `[cell, divider, cell, …]`; the
            // layout tells them apart by index parity (even = cell, odd = divider).
            SegmentedTrackLayout(trackHeight: Self.trackHeight) {
                ForEach(Array(entries.enumerated()), id: \.element.definition.id) { index, entry in
                    if index > 0 {
                        // Vertical inter-segment hairline. An explicit 1pt-wide
                        // `Rectangle` (not a bare `Divider`, whose axis is ambiguous
                        // inside a custom `Layout` and renders as a horizontal rule)
                        // guarantees a full-height vertical separator: the layout reads
                        // its 1pt ideal width as the divider's fixed slot, and the
                        // `.separator`-colored fill at `trackHeight - Spacing.md` height
                        // (inset top/bottom) reads like the native control's hairline.
                        Rectangle()
                            .fill(Color(.separatorColor))
                            .frame(width: 1, height: Self.trackHeight - PUI.Spacing.md)
                    }
                    PropertyFieldSegment(
                        definition: entry.definition,
                        value: values[entry.definition.id],
                        onChange: onChange
                    )
                }
            }
            // Fixed 28pt track. NO `.fixedSize` — the bar spans the FULL rail width
            // (`maxWidth: .infinity`), not the summed cell widths; the layout fills
            // that width with its content-sized cells.
            .frame(maxWidth: .infinity)
            .frame(height: Self.trackHeight)
            // ONE rounded track filled with `quaternarySystemFill` — the SAME fill the
            // body text-box uses (`bodyZone`) so the bar and the body read as one
            // material — plus a hairline stroke. The window behind is glass; this sits
            // on top as the native segmented-control track.
            .background(
                Color(.quaternarySystemFill),
                in: RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
            // Rail inset only — the full-width track aligns to the body card's rail
            // (matches the body + separators). Inset lives INSIDE the populated branch
            // so the collapsed case adds no header/body gap; the top/bottom symmetry
            // (equal gap above + below) is owned by the renderer's `mainColumn`.
            .padding(.horizontal, PUI.Spacing.xl)
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

// MARK: - Segmented track layout (content-sized cells that FILL a fixed width)

/// The bar's layout engine: content-sized segment cells that together FILL a fixed
/// full-width track, separated by fixed-width hairline dividers — Apple's
/// `NSSegmentedControl.apportionsSegmentWidthsByContent` behavior, but stretched so
/// the cells consume the *entire* proposed width (no trailing gap) instead of hugging.
///
/// **Mechanism.** `sizeThatFits` claims the full proposed width (so the bar spans the
/// rail, not its content) at a fixed `trackHeight`. `placeSubviews` measures each
/// cell's *ideal* (content) width, subtracts the dividers' fixed widths, then hands
/// the remaining width to the cells **proportionally to their content widths** — a
/// cell whose content is twice as wide gets twice the slice. Each cell is then placed
/// filling its slice; each divider keeps its native hairline width. The cells are the
/// variable-width parts; the track width is fixed.
///
/// **Interleaving.** The `@ViewBuilder` emits `[cell, divider, cell, divider, …]`, so
/// subviews alternate cell / divider. The layout distinguishes them purely by index
/// parity — even index = a segment cell (flexes), odd index = a divider (fixed) — so
/// no view-identity inspection is needed (and nothing here touches `String`/`==`,
/// quirk #12-safe by construction).
private struct SegmentedTrackLayout: Layout {
    let trackHeight: CGFloat

    /// Full proposed width × fixed track height. Claiming `proposal.width` (rather than
    /// the summed cell widths) is what makes the bar fill the rail. Falls back to the
    /// content sum only when the parent proposes an unspecified/`nil` width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let contentWidth = subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        return CGSize(width: proposal.width ?? contentWidth, height: trackHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        guard !subviews.isEmpty else { return }

        // Split subviews into flexing cells (even indices) and fixed dividers (odd).
        // `idealWidths[i]` is each subview's content width; dividers keep theirs, cells
        // share the leftover proportionally to theirs.
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        var dividerWidth: CGFloat = 0
        var cellIdealTotal: CGFloat = 0
        for (i, width) in idealWidths.enumerated() {
            if i.isMultiple(of: 2) {
                cellIdealTotal += width  // a cell
            } else {
                dividerWidth += width  // a divider
            }
        }

        // Width the cells share = full track minus the (fixed) dividers, never < 0.
        let availableForCells = max(0, bounds.width - dividerWidth)

        var x = bounds.minX
        for (i, subview) in subviews.enumerated() {
            let placedWidth: CGFloat
            if i.isMultiple(of: 2) {
                // Cell — proportional slice of the leftover (equal split if all cells
                // somehow report zero ideal width, so a degenerate case still fills).
                let share = cellIdealTotal > 0 ? idealWidths[i] / cellIdealTotal : 1 / cellCount(subviews.count)
                placedWidth = availableForCells * share
            } else {
                // Divider — its own fixed hairline width.
                placedWidth = idealWidths[i]
            }
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: placedWidth, height: trackHeight)
            )
            x += placedWidth
        }
    }

    /// Count of cells given the interleaved `[cell, divider, …]` ordering: cells sit at
    /// even indices, so there are `ceil(total / 2)` of them. Used only for the
    /// all-zero-ideal degenerate fallback (equal split).
    private func cellCount(_ total: Int) -> CGFloat { CGFloat((total + 1) / 2) }
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
            // The cell's CONTENT width (label + horizontal gutter) is its ideal size,
            // which `SegmentedTrackLayout` measures (`sizeThatFits(.unspecified)`) to
            // proportion the slices — a longer chip yields a wider cell. `maxWidth:
            // .infinity` does NOT inflate that ideal (an unspecified proposal resolves
            // to the content width); it only lets the cell EXPAND to fill the wider
            // slice the layout then places it into, so the whole slice is tappable and
            // the dividers sit flush at the slice boundaries. `maxHeight: .infinity`
            // centers the label within the fixed 28pt track.
            label
                .padding(.horizontal, PUI.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
