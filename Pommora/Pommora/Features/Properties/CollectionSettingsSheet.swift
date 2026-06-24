import SwiftUI

// MARK: - CollectionSettingsViewModel

/// View-model backing `CollectionSettingsSheet`. Stages all edits as a local draft
/// so the manager is only called on explicit Save, not on every interaction.
///
/// Tracks a sequence of pending operations that are replayed against the manager
/// in the correct order (deletes → renames → type-changes → reorders → adds).
@Observable
@MainActor
final class CollectionSettingsViewModel {

    // MARK: - Draft state

    /// Live draft of the property list — reflects all pending edits.
    var draftProperties: [PropertyDefinition]

    /// Pending error surfaced from the manager.
    var pendingError: (any Error)?

    /// Whether the sheet is currently showing the type picker for a new property.
    var showingTypePicker: Bool = false

    /// Type chosen in the picker; drives the inline config sub-view.
    var pendingNewType: PropertyType? = nil

    /// Name for the in-progress new property.
    var pendingNewName: String = ""

    /// Pending options for select / multi-select / status new property.
    var pendingSelectOptions: [PropertyDefinition.SelectOption] = []
    var pendingStatusGroups: [PropertyDefinition.StatusGroup] = PropertyDefinition.StatusGroup.defaultSeed()
    var pendingNumberFormat: PropertyDefinition.NumberFormat = .decimal
    var pendingAccept: String = ""

    // MARK: - Inline editing state

    /// Property being renamed inline.
    var renamingID: String? = nil
    var renameBuffer: String = ""

    // MARK: - Private tracking

    /// The page-type ID these edits apply to.
    let collectionID: String

    /// The original snapshot — used to detect no-op Saves.
    private let originalProperties: [PropertyDefinition]

    // Pending operation log — order matters for replay.
    private var pendingDeletes: [String] = []  // propertyIDs
    private var pendingRenames: [(id: String, name: String)] = []
    private var pendingAdds: [PropertyDefinition] = []
    private var pendingReorders: [(id: String, toIndex: Int)] = []

    // MARK: - Init

    init(pageCollection: PageCollection) {
        self.collectionID = pageCollection.id
        self.draftProperties = pageCollection.properties
        self.originalProperties = pageCollection.properties
    }

    // MARK: - Draft mutations

    /// Commits the current rename buffer for the given property ID.
    func commitRename(_ propertyID: String, newName: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        draftProperties[idx].name = trimmed
        // Record rename op (dedup: latest wins).
        pendingRenames.removeAll { $0.id == propertyID }
        pendingRenames.append((id: propertyID, name: trimmed))
        renamingID = nil
        renameBuffer = ""
    }

    /// Deletes a property from the draft by its ID.
    func deleteDraft(_ propertyID: String) {
        draftProperties.removeAll { $0.id == propertyID }
        // If it was a pending add, just remove from adds (net no-op on manager).
        if pendingAdds.contains(where: { $0.id == propertyID }) {
            pendingAdds.removeAll { $0.id == propertyID }
        } else {
            pendingDeletes.append(propertyID)
        }
        // Clean up any pending rename for this ID.
        pendingRenames.removeAll { $0.id == propertyID }
    }

    /// Moves a property up one slot.
    func moveUp(_ propertyID: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }), idx > 0
        else { return }
        draftProperties.swapAt(idx, idx - 1)
        recordReorders()
    }

    /// Moves a property down one slot.
    func moveDown(_ propertyID: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }),
            idx < draftProperties.count - 1
        else { return }
        draftProperties.swapAt(idx, idx + 1)
        recordReorders()
    }

    /// Records the full draft order as pending reorder ops.
    private func recordReorders() {
        pendingReorders = draftProperties.enumerated().map { (idx, def) in
            (id: def.id, toIndex: idx)
        }
    }

    /// Appends a new property definition to the draft.
    func addDraft(_ definition: PropertyDefinition) {
        draftProperties.append(definition)
        pendingAdds.append(definition)
        resetNewPropertyState()
    }

    /// Resets ephemeral new-property UI state.
    func resetNewPropertyState() {
        pendingNewType = nil
        pendingNewName = ""
        pendingSelectOptions = []
        pendingStatusGroups = PropertyDefinition.StatusGroup.defaultSeed()
        pendingNumberFormat = .decimal
        pendingAccept = ""
        showingTypePicker = false
    }

    // MARK: - Queries

    var hasChanges: Bool {
        !pendingDeletes.isEmpty
            || !pendingRenames.isEmpty
            || !pendingAdds.isEmpty
            || !pendingReorders.isEmpty
    }

    /// Whether the pending new-property config is ready to commit.
    var canCommitNewProperty: Bool {
        guard let type = pendingNewType else { return false }
        let name = pendingNewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        switch type {
        case .select, .multiSelect:
            return !pendingSelectOptions.isEmpty
        default:
            return true
        }
    }

    // MARK: - Save

    /// Replays all pending operations against the manager in safe order.
    /// Deletes first (to avoid name-collision on re-adds), then renames, then
    /// type-changes, then reorders, then adds.
    func save(manager: PageCollectionManager) async {
        guard hasChanges else { return }

        do {
            // 1. Deletes
            for propID in pendingDeletes {
                try await manager.deleteProperty(id: propID, in: collectionID)
            }
            // 2. Renames
            for op in pendingRenames {
                try await manager.renameProperty(id: op.id, in: collectionID, to: op.name)
            }
            // 3. Reorders — replay in index order
            for op in pendingReorders {
                try await manager.reorderProperty(id: op.id, in: collectionID, toIndex: op.toIndex)
            }
            // 4. Adds
            for def in pendingAdds {
                try await manager.addProperty(def, to: collectionID)
            }

            // Clear pending ops after successful save.
            pendingDeletes = []
            pendingRenames = []
            pendingReorders = []
            pendingAdds = []
        } catch {
            pendingError = error
        }
    }
}

// MARK: - CollectionSettingsSheet

/// Schema editor sheet for a PageCollection (Pages side). Presents a live-editable
/// list of property definitions with inline add / rename / reorder / delete.
///
/// Save-required semantics: all edits are staged in a local draft; Save replays
/// the diff against `collectionManager`. Cancel discards the draft.
///
/// One-at-a-time concurrency guard (concurrent-open forbidden per J.8 spec)
/// is enforced by the caller — this sheet does not implement it internally.
@MainActor
struct CollectionSettingsSheet: View {
    let pageCollection: PageCollection
    let collectionManager: PageCollectionManager
    let nexus: Nexus
    let index: PommoraIndex?
    let onDismiss: () -> Void

    @State private var vm: CollectionSettingsViewModel
    @State private var isSaving: Bool = false

    init(
        pageCollection: PageCollection,
        collectionManager: PageCollectionManager,
        nexus: Nexus,
        index: PommoraIndex?,
        onDismiss: @escaping () -> Void
    ) {
        self.pageCollection = pageCollection
        self.collectionManager = collectionManager
        self.nexus = nexus
        self.index = index
        self.onDismiss = onDismiss
        self._vm = State(wrappedValue: CollectionSettingsViewModel(pageCollection: pageCollection))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CollectionSettingsSheetHeader(
                title: pageCollection.title,
                hasChanges: vm.hasChanges,
                isSaving: isSaving,
                onCancel: { onDismiss() },
                onSave: {
                    isSaving = true
                    Task {
                        await vm.save(manager: collectionManager)
                        isSaving = false
                        if vm.pendingError == nil {
                            onDismiss()
                        }
                    }
                }
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: PUI.Spacing.xxxl) {
                    // Properties section
                    CollectionSettingsPropertiesSection(vm: vm)

                    // Templates placeholder
                    CollectionSettingsTemplatesPlaceholder()
                }
                .padding(PUI.Spacing.xxl)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .alert(
            "Error",
            isPresented: Binding(
                get: { vm.pendingError != nil },
                set: { if !$0 { vm.pendingError = nil } }
            )
        ) {
            Button("OK") { vm.pendingError = nil }
        } message: {
            Text(vm.pendingError?.localizedDescription ?? "An unknown error occurred.")
        }
    }
}

// MARK: - CollectionSettingsSheetHeader

private struct CollectionSettingsSheetHeader: View {
    let title: String
    let hasChanges: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.borderless)
            Spacer()
            Text("\(title) — Settings")
                .font(.headline)
            Spacer()
            Button(isSaving ? "Saving…" : "Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges || isSaving)
        }
        .padding(.horizontal, PUI.Spacing.xxl)
        .padding(.vertical, PUI.Spacing.xl)
    }
}

// MARK: - CollectionSettingsPropertiesSection

private struct CollectionSettingsPropertiesSection: View {
    @Bindable var vm: CollectionSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            Text("Properties")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if vm.draftProperties.isEmpty {
                Text("No properties yet. Add one below.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, PUI.Spacing.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.draftProperties) { def in
                        CollectionSettingsPropertyRow(
                            definition: def,
                            isRenaming: vm.renamingID == def.id,
                            renameBuffer: vm.renamingID == def.id ? $vm.renameBuffer : .constant(""),
                            onStartRename: {
                                vm.renamingID = def.id
                                vm.renameBuffer = def.name
                            },
                            onCommitRename: {
                                vm.commitRename(def.id, newName: vm.renameBuffer)
                            },
                            onDelete: { vm.deleteDraft(def.id) },
                            onMoveUp: { vm.moveUp(def.id) },
                            onMoveDown: { vm.moveDown(def.id) }
                        )
                        Divider()
                    }
                }
                .background(Color(.windowBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: PUI.Radius.medium)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                )
            }

            // New-property inline config (shown after type is picked)
            if vm.pendingNewType != nil {
                CollectionSettingsNewPropertyConfig(vm: vm)
            }

            // Type picker or Add button
            if vm.showingTypePicker {
                VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                    Text("Choose a property type:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    PropertyTypePicker(
                        selected: $vm.pendingNewType,
                        onSelect: { _ in
                            vm.showingTypePicker = false
                        }
                    )
                    Button("Cancel") {
                        vm.resetNewPropertyState()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
                .padding(PUI.Spacing.xl)
                .background(Color(.windowBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.medium))
            } else if vm.pendingNewType == nil {
                Button {
                    vm.showingTypePicker = true
                } label: {
                    Label("Add property", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .padding(.top, PUI.Spacing.xs)
            }
        }
    }
}

// MARK: - CollectionSettingsPropertyRow

private struct CollectionSettingsPropertyRow: View {
    let definition: PropertyDefinition
    let isRenaming: Bool
    @Binding var renameBuffer: String
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            // Icon if set
            if let icon = definition.icon {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            // Name (inline rename or label)
            if isRenaming {
                TextField("Property name", text: $renameBuffer)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { onCommitRename() }
                Button("Done") { onCommitRename() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            } else {
                Text(definition.name)
                    .font(.callout)
                Spacer()
                // Type badge
                CollectionPropertyTypeBadge(type: definition.type)
            }

            // Row menu
            if !isRenaming {
                Menu {
                    Button("Edit Title") { onStartRename() }
                    Button("Move Up") { onMoveUp() }
                    Button("Move Down") { onMoveDown() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.md)
    }
}

// MARK: - CollectionPropertyTypeBadge

private struct CollectionPropertyTypeBadge: View {
    let type: PropertyType

    var body: some View {
        Text(type.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, PUI.Spacing.sm)
            .padding(.vertical, PUI.Spacing.xxs)
            .background(
                Capsule().fill(Color(.separatorColor).opacity(0.4))
            )
    }
}

// MARK: - CollectionSettingsNewPropertyConfig

/// Inline sub-view for configuring a new property before adding it.
/// Shown after a property type is chosen in `PropertyTypePicker`.
private struct CollectionSettingsNewPropertyConfig: View {
    @Bindable var vm: CollectionSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.lg) {
            Text("New \(vm.pendingNewType?.displayName ?? "") property")
                .font(.callout)
                .fontWeight(.medium)

            // Name field (always present)
            VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Property name", text: $vm.pendingNewName)
                    .textFieldStyle(.roundedBorder)
            }

            // Per-type config
            if let type = vm.pendingNewType {
                switch type {
                case .select, .multiSelect:
                    SelectOptionsEditor(
                        options: $vm.pendingSelectOptions,
                        onAddOption: {
                            let value = "opt_\(ULID.generate())"
                            vm.pendingSelectOptions.append(
                                .init(value: value, label: "New option", color: nil)
                            )
                        }
                    )
                case .status:
                    StatusGroupsEditor(
                        groups: $vm.pendingStatusGroups,
                        onAddOption: { groupID in
                            let value = "opt_\(ULID.generate())"
                            if let i = vm.pendingStatusGroups.firstIndex(where: { $0.id == groupID }) {
                                vm.pendingStatusGroups[i].options.append(
                                    .init(value: value, label: "New option", color: nil, groupID: groupID)
                                )
                            }
                        }
                    )
                case .number:
                    NumberFormatPicker(format: $vm.pendingNumberFormat)
                case .file:
                    FileAcceptEditor(accept: $vm.pendingAccept)
                default:
                    EmptyView()
                }
            }

            HStack {
                Button("Cancel") {
                    vm.resetNewPropertyState()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Add") {
                    commitNewProperty()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canCommitNewProperty)
            }
        }
        .padding(PUI.Spacing.xl)
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: PUI.Radius.medium)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func commitNewProperty() {
        guard let type = vm.pendingNewType else { return }
        let name = vm.pendingNewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        var def = PropertyDefinition(
            id: ReservedPropertyID.mintUserPropertyID(),
            name: name,
            type: type
        )

        switch type {
        case .select, .multiSelect:
            def.selectOptions = vm.pendingSelectOptions.isEmpty ? nil : vm.pendingSelectOptions
        case .status:
            def.statusGroups = vm.pendingStatusGroups
        case .number:
            def.numberFormat = vm.pendingNumberFormat
        case .file:
            let trimmed = vm.pendingAccept.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                def.accept = trimmed.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
            }
        default:
            break
        }

        vm.addDraft(def)
    }
}

// Per-type editor sub-views (SelectOptionsEditor / StatusGroupsEditor /
// NumberFormatPicker / FileAcceptEditor) extracted to
// `Pommora/Properties/Editor/` (Task 8). Both this sheet and TypeSettingsSheet
// now share the same definitions; future View Settings popover panes reuse
// them too.

// MARK: - CollectionSettingsTemplatesPlaceholder

private struct CollectionSettingsTemplatesPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            Text("Templates")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Templates — reserved post-v1")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}
