import SwiftUI

/// View Settings → Layout — per-view layout controls for the ACTIVE SavedView.
///
/// Sections:
///   - **Display Banner** — per-view toggle. DEFAULT ON when the container has a
///     banner (`showBanner` nil/true shows it); writing `false` hides the
///     container banner in this view only. The row is disabled when the
///     container has no banner (nothing to show/hide).
///   - **Card Size** (Gallery only) — S/M/L segmented control, shown only when
///     the active view's `type == .gallery`; writes `cardSize`.
///   - **Property Visibility** — the per-view eye-list over ALL columns (user
///     properties + tier relations + Modified, Cover excluded). `_title` renders
///     pinned + non-hideable. Drag-reorders the visible section; eye toggles
///     hidden/visible via `SavedViewMutations.applyToggle`. This replaces the
///     retired standalone property-visibility pane.
///   - **Wrap Text** — muted placeholder (table only; functional wrapping is a
///     later pass).
///
/// Every read/write resolves the active view by stable ID off the live
/// `PageTypeManager` + `ActiveViewStore` and persists through `updateView`.
struct LayoutPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var commitError: String?

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let view = currentView() {
            sections(for: view)
        } else {
            ContentUnavailableView(
                "No view configured",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("loadAll should have minted a default Table view; reopen the popover.")
            )
        }
    }

    @ViewBuilder
    private func sections(for view: SavedView) -> some View {
        VStack(spacing: 0) {
            LayoutToggleRow(
                icon: "photo",
                title: "Display Banner",
                isOn: view.showBanner ?? true,
                isEnabled: containerHasBanner,
                onToggle: { value in Task { await setBanner(value) } }
            )

            if view.type == .gallery {
                CardSizeRow(
                    selected: view.cardSize ?? .medium,
                    onSelect: { value in Task { await setCardSize(value) } }
                )
            }

            PaneDivider()

            visibilityList(for: view)

            if view.type == .table {
                mutedRow(icon: "text.alignleft", title: "Wrap Text")
            }

            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
    }

    // MARK: - Property Visibility eye-list

    @ViewBuilder
    private func visibilityList(for view: SavedView) -> some View {
        let columns = SavedViewMutations.visibilityColumns(resolved: resolvedProperties())
        let hiddenSet = Set(view.hiddenProperties)
        // Visible section: explicit order first, then any column not yet
        // accounted for in propertyOrder/hidden (rendered as visible).
        let visibleOrdered = view.propertyOrder.compactMap { id in
            columns.first(where: { $0.id == id })
        }
        let unaccounted = columns.filter {
            !view.propertyOrder.contains($0.id) && !hiddenSet.contains($0.id)
        }
        let reorderable = visibleOrdered + unaccounted
        let hiddenOrdered = columns.filter { hiddenSet.contains($0.id) }

        ForEach(reorderable, id: \.id) { def in
            reorderableRow(def, in: reorderable)
        }
        ForEach(hiddenOrdered, id: \.id) { def in
            VisibilityRow(
                definition: def,
                isVisible: false,
                onToggle: { Task { await toggle(def.id, currentlyVisible: false) } }
            )
        }
    }

    /// One visible-section row. The pinned Title row is locked — it gets no
    /// drag handle and nothing may drop onto it (the reorder helper keeps
    /// `_title` front-pinned, so a drop here would be a no-op affordance). All
    /// other rows carry the full drag + drop reorder modifiers.
    @ViewBuilder
    private func reorderableRow(
        _ def: PropertyDefinition,
        in reorderable: [PropertyDefinition]
    ) -> some View {
        let row = VisibilityRow(
            definition: def,
            isVisible: true,
            onToggle: { Task { await toggle(def.id, currentlyVisible: true) } }
        )
        if def.id == ReservedPropertyID.title {
            row
        } else {
            row
                .draggable(def.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    guard let droppedID = droppedIDs.first else { return false }
                    return reorder(
                        currentOrder: reorderable.map(\.id),
                        droppedID: droppedID,
                        ontoTargetID: def.id
                    )
                }
        }
    }

    // MARK: - Muted placeholder row

    @ViewBuilder
    private func mutedRow(icon: String, title: String) -> some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: icon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.tertiary)
                .frame(width: PUI.Icon.leadingFrame)
            Text(title)
                .font(PUI.Typography.row)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }

    // MARK: - Commit

    private func setBanner(_ show: Bool) async {
        await write { $0.showBanner = show }
    }

    private func setCardSize(_ size: CardSize) async {
        await write { $0.cardSize = size }
    }

    private func toggle(_ propertyID: String, currentlyVisible: Bool) async {
        await write {
            SavedViewMutations.applyToggle(
                &$0, propertyID: propertyID, currentlyVisible: currentlyVisible)
        }
    }

    /// Reorders the visible-section property IDs by moving `droppedID` onto
    /// `ontoTargetID`, then persists. The reserved `_title` lead is kept at the
    /// front of `propertyOrder`; the reordered set replaces the rest.
    private func reorder(
        currentOrder: [String],
        droppedID: String,
        ontoTargetID: String
    ) -> Bool {
        let newOrder = PropertyIDReorder.move(currentOrder, moving: droppedID, onto: ontoTargetID)
        guard newOrder != currentOrder else { return false }
        Task {
            await write { v in
                let title = ReservedPropertyID.title
                let body = newOrder.filter { $0 != title }
                v.propertyOrder = newOrder.contains(title) ? [title] + body : body
            }
        }
        return true
    }

    private func write(_ transform: @escaping (inout SavedView) -> Void) async {
        guard let view = currentView(), let cid = containerID() else { return }
        let viewID = view.id
        do {
            try await pageTypeManager.updateView(viewID, in: cid, transform: transform)
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    // MARK: - Lookups (re-query live off the manager by stable ID)

    /// Resolves the ACTIVE view via the shared resolver — edits whichever view
    /// the user is viewing.
    private func currentView() -> SavedView? {
        guard let cid = containerID() else { return nil }
        return activeViewStore.resolvedActiveView(in: cid, manager: pageTypeManager)
    }

    /// The full toggleable column set: user properties + tier relations +
    /// Modified (Cover excluded), built once from the parent Type's resolved
    /// schema.
    private func resolvedProperties() -> [PropertyDefinition] {
        guard let typeID = parentTypeID() else { return [] }
        return pageTypeManager.types.first(where: { $0.id == typeID })?
            .resolvedProperties(tierConfig: tierConfigManager.config) ?? []
    }

    /// Whether the container backing this view actually has a banner — the
    /// Display Banner toggle is meaningless (and disabled) without one.
    private var containerHasBanner: Bool {
        guard let cid = containerID() else { return false }
        if let t = pageTypeManager.types.first(where: { $0.id == cid }) {
            return t.banner != nil
        }
        for cols in pageTypeManager.pageCollectionsByType.values {
            if let c = cols.first(where: { $0.id == cid }) { return c.banner != nil }
        }
        return false
    }

    private func containerID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }

    private func parentTypeID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.typeID
        default: return nil
        }
    }
}

// MARK: - Rows

/// A plain on/off layout toggle row (label left, `Toggle` right). Disabled rows
/// mute their label so the inert state reads tonally.
private struct LayoutToggleRow: View {
    let icon: String
    let title: String
    let isOn: Bool
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: icon)
                .font(PUI.Icon.leading)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: PUI.Icon.leadingFrame)
            Text(title)
                .font(PUI.Typography.row)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
            Spacer()
            Toggle(
                "",
                isOn: Binding(get: { isOn }, set: { onToggle($0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

/// Gallery-only card-size segmented control (Small / Medium / Large).
private struct CardSizeRow: View {
    let selected: CardSize
    let onSelect: (CardSize) -> Void

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: "rectangle.grid.2x2")
                .font(PUI.Icon.leading)
                .foregroundStyle(.primary)
                .frame(width: PUI.Icon.leadingFrame)
            Text("Card Size")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Picker(
                "Card Size",
                selection: Binding(get: { selected }, set: { onSelect($0) })
            ) {
                Text("S").tag(CardSize.small)
                Text("M").tag(CardSize.medium)
                Text("L").tag(CardSize.large)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

/// One column-visibility row — icon + name + an eye affordance. `_title` is
/// pinned (lock badge, disabled). Hidden rows mute + strike through.
private struct VisibilityRow: View {
    let definition: PropertyDefinition
    let isVisible: Bool
    let onToggle: () -> Void

    private var isPinned: Bool {
        definition.id == ReservedPropertyID.title
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: definition.displayIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(isVisible ? .primary : .tertiary)
                    .frame(width: PUI.Icon.leadingFrame)

                Text(definition.name)
                    .font(PUI.Typography.row)
                    .foregroundStyle(isVisible ? .primary : .tertiary)
                    .strikethrough(!isVisible, color: .secondary)
                    .lineLimit(1)

                Spacer()

                if isPinned {
                    Image(systemName: "lock.fill")
                        .font(PUI.Icon.lock)
                        .foregroundStyle(.tertiary)
                        .help("Always visible — the title column is pinned")
                } else {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(PUI.Icon.visibility)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPinned)
    }
}
