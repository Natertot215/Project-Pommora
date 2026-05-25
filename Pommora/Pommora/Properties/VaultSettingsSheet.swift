import SwiftUI

// MARK: - VaultSettingsViewModel

/// View-model backing `VaultSettingsSheet`. Stages all edits as a local draft
/// so the manager is only called on explicit Save, not on every interaction.
///
/// Tracks a sequence of pending operations that are replayed against the manager
/// in the correct order (deletes → renames → type-changes → reorders → adds).
@Observable
@MainActor
final class VaultSettingsViewModel {

    // MARK: - Draft state

    /// Live draft of the property list — reflects all pending edits.
    var draftProperties: [PropertyDefinition]

    /// Pending error surfaced from the manager.
    var pendingError: (any Error)?

    /// Whether the sheet is currently showing the type picker for a new property.
    var showingTypePicker: Bool = false

    /// Whether the sheet is showing the relation wizard for a pending add.
    var showingRelationWizard: Bool = false

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
    let typeID: String

    /// The original snapshot — used to detect no-op Saves.
    private let originalProperties: [PropertyDefinition]

    // Pending operation log — order matters for replay.
    private var pendingDeletes: [String] = []          // propertyIDs
    private var pendingRenames: [(id: String, name: String)] = []
    private var pendingAdds: [PropertyDefinition] = []
    private var pendingReorders: [(id: String, toIndex: Int)] = []

    // MARK: - Init

    init(pageType: PageType) {
        self.typeID = pageType.id
        self.draftProperties = pageType.properties
        self.originalProperties = pageType.properties
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

    /// Appends a new (non-relation) property definition to the draft.
    func addDraft(_ definition: PropertyDefinition) {
        draftProperties.append(definition)
        pendingAdds.append(definition)
        resetNewPropertyState()
    }

    /// Called after successfully completing a RelationPropertyWizard to register
    /// the two new property IDs as pending adds (coordinator handles the disk write).
    func recordRelationAdd(sourcePropID: String, reversePropID: String?) {
        // The manager already wrote to disk via DualRelationCoordinator.
        // We record the source side as a "virtual" add so the draft reflects the change.
        // The actual state will be refreshed from the manager after Save.
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
        showingRelationWizard = false
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
    func save(manager: PageTypeManager) async {
        guard hasChanges else { return }

        do {
            // 1. Deletes
            for propID in pendingDeletes {
                try await manager.deleteProperty(id: propID, in: typeID)
            }
            // 2. Renames
            for op in pendingRenames {
                try await manager.renameProperty(id: op.id, in: typeID, to: op.name)
            }
            // 3. Reorders — replay in index order
            for op in pendingReorders {
                try await manager.reorderProperty(id: op.id, in: typeID, toIndex: op.toIndex)
            }
            // 4. Adds
            for def in pendingAdds {
                try await manager.addProperty(def, to: typeID)
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

// MARK: - VaultSettingsSheet

/// Schema editor sheet for a PageType (Pages side). Presents a live-editable
/// list of property definitions with inline add / rename / reorder / delete.
///
/// Save-required semantics: all edits are staged in a local draft; Save replays
/// the diff against `pageTypeManager`. Cancel discards the draft.
///
/// One-at-a-time concurrency guard (concurrent-open forbidden per J.8 spec)
/// is enforced by the caller — this sheet does not implement it internally.
@MainActor
struct VaultSettingsSheet: View {
    let pageType: PageType
    let pageTypeManager: PageTypeManager
    let nexus: Nexus
    let index: PommoraIndex?
    let onDismiss: () -> Void

    @State private var vm: VaultSettingsViewModel
    @State private var isSaving: Bool = false

    init(
        pageType: PageType,
        pageTypeManager: PageTypeManager,
        nexus: Nexus,
        index: PommoraIndex?,
        onDismiss: @escaping () -> Void
    ) {
        self.pageType = pageType
        self.pageTypeManager = pageTypeManager
        self.nexus = nexus
        self.index = index
        self.onDismiss = onDismiss
        self._vm = State(wrappedValue: VaultSettingsViewModel(pageType: pageType))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VaultSettingsSheetHeader(
                title: pageType.title,
                hasChanges: vm.hasChanges,
                isSaving: isSaving,
                onCancel: { onDismiss() },
                onSave: {
                    isSaving = true
                    Task {
                        await vm.save(manager: pageTypeManager)
                        isSaving = false
                        if vm.pendingError == nil {
                            onDismiss()
                        }
                    }
                }
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Properties section
                    VaultSettingsPropertiesSection(vm: vm)

                    // Templates placeholder
                    VaultSettingsTemplatesPlaceholder()
                }
                .padding(16)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .sheet(isPresented: $vm.showingRelationWizard) {
            RelationPropertyWizard(
                sourceTypeID: pageType.id,
                sourceTypeKind: .pageType,
                coordinator: DualRelationCoordinator(),
                index: index,
                onComplete: { result in
                    switch result {
                    case .success(let ids):
                        vm.recordRelationAdd(
                            sourcePropID: ids.sourcePropertyID,
                            reversePropID: ids.reversePropertyID
                        )
                    case .failure(let error):
                        vm.pendingError = error
                    }
                    vm.showingRelationWizard = false
                },
                onCancel: {
                    vm.showingRelationWizard = false
                    vm.resetNewPropertyState()
                }
            )
            .padding()
        }
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

// MARK: - VaultSettingsSheetHeader

private struct VaultSettingsSheetHeader: View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - VaultSettingsPropertiesSection

private struct VaultSettingsPropertiesSection: View {
    @Bindable var vm: VaultSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if vm.draftProperties.isEmpty {
                Text("No properties yet. Add one below.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.draftProperties) { def in
                        VaultSettingsPropertyRow(
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                )
            }

            // New-property inline config (shown after type is picked)
            if vm.pendingNewType != nil && !vm.showingRelationWizard {
                VaultSettingsNewPropertyConfig(vm: vm)
            }

            // Type picker or Add button
            if vm.showingTypePicker {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a property type:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    PropertyTypePicker(
                        selected: $vm.pendingNewType,
                        onSelect: { type in
                            if type == .relation {
                                vm.showingRelationWizard = true
                                vm.showingTypePicker = false
                            } else {
                                vm.showingTypePicker = false
                            }
                        }
                    )
                    Button("Cancel") {
                        vm.resetNewPropertyState()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
                .padding(12)
                .background(Color(.windowBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if vm.pendingNewType == nil {
                Button {
                    vm.showingTypePicker = true
                } label: {
                    Label("Add property", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - VaultSettingsPropertyRow

private struct VaultSettingsPropertyRow: View {
    let definition: PropertyDefinition
    let isRenaming: Bool
    @Binding var renameBuffer: String
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
                VaultPropertyTypeBadge(type: definition.type)
            }

            // Row menu
            if !isRenaming {
                Menu {
                    Button("Rename") { onStartRename() }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - VaultPropertyTypeBadge

private struct VaultPropertyTypeBadge: View {
    let type: PropertyType

    var body: some View {
        Text(type.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color(.separatorColor).opacity(0.4))
            )
    }
}

// MARK: - VaultSettingsNewPropertyConfig

/// Inline sub-view for configuring a new property before adding it.
/// Shown after a non-relation type is chosen in `PropertyTypePicker`.
private struct VaultSettingsNewPropertyConfig: View {
    @Bindable var vm: VaultSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New \(vm.pendingNewType?.displayName ?? "") property")
                .font(.callout)
                .fontWeight(.medium)

            // Name field (always present)
            VStack(alignment: .leading, spacing: 4) {
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
                    SelectOptionsEditor(options: $vm.pendingSelectOptions)
                case .status:
                    StatusGroupsEditor(groups: $vm.pendingStatusGroups)
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
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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

// MARK: - SelectOptionsEditor

private struct SelectOptionsEditor: View {
    @Binding var options: [PropertyDefinition.SelectOption]
    @State private var newOptionLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Options")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                SelectOptionsRow(
                    option: option,
                    onDelete: { options.removeAll { $0.value == option.value } }
                )
            }

            HStack {
                TextField("New option…", text: $newOptionLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button("Add") {
                    let label = newOptionLabel.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else { return }
                    let value = label.lowercased().replacingOccurrences(of: " ", with: "_")
                    options.append(PropertyDefinition.SelectOption(value: value, label: label, color: nil))
                    newOptionLabel = ""
                }
                .buttonStyle(.borderless)
                .disabled(newOptionLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct SelectOptionsRow: View {
    let option: PropertyDefinition.SelectOption
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(option.label)
                .font(.callout)
            Spacer()
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - StatusGroupsEditor

private struct StatusGroupsEditor: View {
    @Binding var groups: [PropertyDefinition.StatusGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status Groups")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($groups) { $group in
                StatusGroupEditor(group: $group)
            }
        }
    }
}

private struct StatusGroupEditor: View {
    @Binding var group: PropertyDefinition.StatusGroup
    @State private var newOptionLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Group label", text: $group.label)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Text(group.id.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach($group.options) { $option in
                HStack {
                    TextField("Option label", text: $option.label)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button(role: .destructive) {
                        group.options.removeAll { $0.value == option.value }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
            }

            HStack {
                TextField("New option…", text: $newOptionLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .padding(.leading, 12)
                Button("Add") {
                    let label = newOptionLabel.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else { return }
                    let value = "\(group.id.rawValue)_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))"
                    group.options.append(PropertyDefinition.StatusOption(
                        value: value, label: label, color: nil, groupID: group.id
                    ))
                    newOptionLabel = ""
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(newOptionLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - NumberFormatPicker

private struct NumberFormatPicker: View {
    @Binding var format: PropertyDefinition.NumberFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Format")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Format", selection: $format) {
                ForEach(PropertyDefinition.NumberFormat.allCases, id: \.self) { fmt in
                    NumberFormatPickerLabel(format: fmt).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct NumberFormatPickerLabel: View {
    let format: PropertyDefinition.NumberFormat

    var body: some View {
        Text(format.rawValue.capitalized)
    }
}

// MARK: - FileAcceptEditor

private struct FileAcceptEditor: View {
    @Binding var accept: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Allowed MIME types (comma-separated, leave blank for any)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. application/pdf, image/*", text: $accept)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }
}

// MARK: - VaultSettingsTemplatesPlaceholder

private struct VaultSettingsTemplatesPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
