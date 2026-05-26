import SwiftUI

/// Per-option editor pushed from any Select / Multi-Select / Status option
/// chevron in EditPropertyPane. Renders:
///   - Name TextField (editable label; option `value` is immutable post-create)
///   - OptionColorPicker (5×2 grid + No-color affordance — picks PropertyChipColor?)
///   - (Status only) Group selector (Upcoming / In Progress / Done — moves
///     the option between structural groups; cascades via the existing
///     `updateProperty(transform:)` flow which validates + persists)
///   - "Delete option" button — confirmation dialog enumerating affected
///     entity count (count lookup deferred until reverse-index is wired —
///     v0.3.1.x patch — currently shows a generic "Are you sure?" alert)
///
/// All edits commit via the existing `updateProperty(id:in:transform:)` method
/// on the relevant manager (PageTypeManager / ItemTypeManager). No
/// `updateOption(...)` helper — the transform closure handles the look-up.
///
/// Reachability: the EditOptionPane is registered as the
/// `.editOption(propertyID:optionValue:)` route's destination in
/// ViewSettingsPopover. At v0.3.1 the SelectOptionsEditor + StatusGroupsEditor
/// shared components still use inline edit rows (not chevron-push), so no
/// caller actually pushes the route in normal UX. A future v0.3.1.x patch
/// refactors those editors to push chevrons + that wires this pane up
/// end-to-end. Shipping the pane now means the refactor is a leaf-level
/// change that doesn't have to ship the destination too.
struct EditOptionPane: View {
    let scope: ViewSettingsScope
    let propertyID: String
    let optionValue: String
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var draftLabel: String = ""
    @State private var draftColor: PropertyChipColor?
    @State private var draftGroupID: PropertyDefinition.StatusGroupID?
    @State private var commitError: String?
    @State private var showingDeleteConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "Edit Option")

            Group {
                if let context = locate() {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PUI.Spacing.xxl) {
                            labelRow
                            colorRow
                            if context.isStatus { statusGroupRow(currentGroup: context.statusGroupID) }
                            deleteRow
                            if let err = commitError {
                                Text(err)
                                    .font(PUI.Typography.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, PUI.Pane.contentPadding)
                        .padding(.vertical, PUI.Pane.contentPadding)
                    }
                    .onAppear {
                        draftLabel = context.label
                        draftColor = context.color
                        draftGroupID = context.statusGroupID
                    }
                    .confirmationDialog(
                        "Delete option “\(context.label)”?",
                        isPresented: $showingDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            Task { await commitDelete(isStatus: context.isStatus) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Entities using this option will be cleared (per universal void-on-delete). Affected-entity count surfaces in a future v0.3.1.x patch.")
                    }
                } else {
                    ContentUnavailableView(
                        "Option not found",
                        systemImage: "questionmark.circle",
                        description: Text("The option may have been deleted or moved.")
                    )
                }
            }
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Sections

    @ViewBuilder
    private var labelRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Label")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Option label", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .onSubmit { Task { await commitLabel() } }
        }
    }

    @ViewBuilder
    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            OptionColorPicker(selection: $draftColor)
                .onChange(of: draftColor) { _, _ in Task { await commitColor() } }
        }
    }

    @ViewBuilder
    private func statusGroupRow(currentGroup: PropertyDefinition.StatusGroupID?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Group")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Group", selection: $draftGroupID) {
                Text("Upcoming").tag(PropertyDefinition.StatusGroupID?.some(.upcoming))
                Text("In Progress").tag(PropertyDefinition.StatusGroupID?.some(.inProgress))
                Text("Done").tag(PropertyDefinition.StatusGroupID?.some(.done))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: draftGroupID) { _, _ in Task { await commitGroup() } }
        }
    }

    @ViewBuilder
    private var deleteRow: some View {
        Divider()
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 18)
                Text("Delete option")
                    .font(.callout)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    // MARK: - Locate

    private struct OptionContext {
        let label: String
        let color: PropertyChipColor?
        let isStatus: Bool
        let statusGroupID: PropertyDefinition.StatusGroupID?
    }

    private func locate() -> OptionContext? {
        guard let typeID = parentTypeID(),
              let def = lookupDefinition(typeID: typeID)
        else { return nil }

        switch def.type {
        case .select, .multiSelect:
            guard let opt = def.selectOptions?.first(where: { $0.value == optionValue }) else { return nil }
            return OptionContext(
                label: opt.label,
                color: opt.color.map(propertyChipColor(from:)),
                isStatus: false,
                statusGroupID: nil
            )
        case .status:
            guard let groups = def.statusGroups else { return nil }
            for g in groups {
                if let opt = g.options.first(where: { $0.value == optionValue }) {
                    return OptionContext(
                        label: opt.label,
                        color: opt.color.map(propertyChipColor(from:)),
                        isStatus: true,
                        statusGroupID: opt.groupID
                    )
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Map the persistence-layer `SelectColor` to the UI-layer
    /// `PropertyChipColor`. The two enums overlap on the 9 cases shared
    /// across both; `.gray` (in SelectColor) maps to `.default` (the new
    /// nil-fallback case in PropertyChipColor after Task 5b's cleanup).
    private func propertyChipColor(from select: PropertyDefinition.SelectColor) -> PropertyChipColor {
        switch select {
        case .gray: return .default
        case .brown: return .brown
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        }
    }

    /// Reverse of `propertyChipColor(from:)`. UI lets the user pick from
    /// the 10 selectablePalette cases (+ no-color); only the cases that
    /// have a SelectColor counterpart get persisted, the rest fall back to
    /// the closest match. v0.3.1.x patch can split SelectColor + add
    /// missing cases (Indigo, Teal) to the persistence layer.
    private func selectColor(from chip: PropertyChipColor?) -> PropertyDefinition.SelectColor? {
        guard let chip else { return nil }
        switch chip {
        case .default, .accent: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .teal: return .blue  // closest match until SelectColor adds .teal
        case .indigo: return .purple  // closest match until SelectColor adds .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }

    private func lookupDefinition(typeID: String) -> PropertyDefinition? {
        switch scope {
        case .pageType, .pageCollection:
            return pageTypeManager.types
                .first(where: { $0.id == typeID })?
                .properties.first(where: { $0.id == propertyID })
        case .itemType, .itemCollection:
            return itemTypeManager.types
                .first(where: { $0.id == typeID })?
                .properties.first(where: { $0.id == propertyID })
        default:
            return nil
        }
    }

    private func parentTypeID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .itemType(let t): return t.id
        case .pageCollection(let c): return c.typeID
        case .itemCollection(let c): return c.typeID
        default: return nil
        }
    }

    private enum SideKind { case pages, items }
    private var side: SideKind? {
        switch scope {
        case .pageType, .pageCollection: return .pages
        case .itemType, .itemCollection: return .items
        default: return nil
        }
    }

    // MARK: - Commits

    private func commitLabel() async {
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        await applyTransform { def in
            mutateOption(in: &def) { $0.label = trimmed }
        }
    }

    private func commitColor() async {
        let mapped = selectColor(from: draftColor)
        await applyTransform { def in
            mutateOption(in: &def) { $0.color = mapped }
        }
    }

    private func commitGroup() async {
        guard let newGroup = draftGroupID else { return }
        await applyTransform { def in
            // Status group moves: re-bucket the StatusOption into the new group.
            guard def.type == .status, var groups = def.statusGroups else { return }
            var movingOption: PropertyDefinition.StatusOption?
            for gi in groups.indices {
                if let oi = groups[gi].options.firstIndex(where: { $0.value == optionValue }) {
                    movingOption = groups[gi].options.remove(at: oi)
                    break
                }
            }
            guard var opt = movingOption else { return }
            opt.groupID = newGroup
            if let targetIdx = groups.firstIndex(where: { $0.id == newGroup }) {
                groups[targetIdx].options.append(opt)
            }
            def.statusGroups = groups
        }
    }

    private func commitDelete(isStatus: Bool) async {
        await applyTransform { def in
            if isStatus {
                guard var groups = def.statusGroups else { return }
                for gi in groups.indices {
                    groups[gi].options.removeAll { $0.value == optionValue }
                }
                def.statusGroups = groups
            } else {
                def.selectOptions = (def.selectOptions ?? []).filter { $0.value != optionValue }
            }
        }
        if !path.isEmpty { path.removeLast() }
    }

    private func applyTransform(_ transform: @escaping (inout PropertyDefinition) -> Void) async {
        guard let typeID = parentTypeID(), let side else { return }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.updateProperty(id: propertyID, in: typeID, transform: transform)
            case .items:
                try await itemTypeManager.updateProperty(id: propertyID, in: typeID, transform: transform)
            }
            commitError = nil
        } catch {
            commitError = String(describing: error)
        }
    }

    /// Apply a single-option mutation inside a Select / Multi-Select
    /// option list. Status options aren't handled here — they're rebucketed
    /// by `commitGroup()` directly.
    private func mutateOption(
        in def: inout PropertyDefinition,
        _ mutate: (inout PropertyDefinition.SelectOption) -> Void
    ) {
        var opts = def.selectOptions ?? []
        if let idx = opts.firstIndex(where: { $0.value == optionValue }) {
            mutate(&opts[idx])
            def.selectOptions = opts
        }
    }
}
