import SwiftUI

// MARK: - TypeSettingsViewModel

/// View-model backing `TypeSettingsSheet`. Parallel to `VaultSettingsViewModel` on the
/// Items side. Stages all edits as a local draft; manager is only called on Save.
@Observable
@MainActor
final class TypeSettingsViewModel {

    // MARK: - Draft state

    var draftProperties: [PropertyDefinition]
    var pendingError: (any Error)?
    var showingTypePicker: Bool = false
    var pendingNewType: PropertyType? = nil
    var pendingNewName: String = ""
    var pendingSelectOptions: [PropertyDefinition.SelectOption] = []
    var pendingStatusGroups: [PropertyDefinition.StatusGroup] = PropertyDefinition.StatusGroup.defaultSeed()
    var pendingNumberFormat: PropertyDefinition.NumberFormat = .decimal
    var pendingAccept: String = ""

    // MARK: - Inline editing state

    var renamingID: String? = nil
    var renameBuffer: String = ""

    // MARK: - Private tracking

    let typeID: String
    private let originalProperties: [PropertyDefinition]

    private var pendingDeletes: [String] = []
    private var pendingRenames: [(id: String, name: String)] = []
    private var pendingAdds: [PropertyDefinition] = []
    private var pendingReorders: [(id: String, toIndex: Int)] = []

    // MARK: - Init

    init(itemType: ItemType) {
        self.typeID = itemType.id
        self.draftProperties = itemType.properties
        self.originalProperties = itemType.properties
    }

    // MARK: - Draft mutations

    func commitRename(_ propertyID: String, newName: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        draftProperties[idx].name = trimmed
        pendingRenames.removeAll { $0.id == propertyID }
        pendingRenames.append((id: propertyID, name: trimmed))
        renamingID = nil
        renameBuffer = ""
    }

    func deleteDraft(_ propertyID: String) {
        draftProperties.removeAll { $0.id == propertyID }
        if pendingAdds.contains(where: { $0.id == propertyID }) {
            pendingAdds.removeAll { $0.id == propertyID }
        } else {
            pendingDeletes.append(propertyID)
        }
        pendingRenames.removeAll { $0.id == propertyID }
    }

    func moveUp(_ propertyID: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }), idx > 0
        else { return }
        draftProperties.swapAt(idx, idx - 1)
        recordReorders()
    }

    func moveDown(_ propertyID: String) {
        guard let idx = draftProperties.firstIndex(where: { $0.id == propertyID }),
              idx < draftProperties.count - 1
        else { return }
        draftProperties.swapAt(idx, idx + 1)
        recordReorders()
    }

    private func recordReorders() {
        pendingReorders = draftProperties.enumerated().map { (idx, def) in
            (id: def.id, toIndex: idx)
        }
    }

    func addDraft(_ definition: PropertyDefinition) {
        draftProperties.append(definition)
        pendingAdds.append(definition)
        resetNewPropertyState()
    }

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

    func save(manager: ItemTypeManager) async {
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
            // 3. Reorders
            for op in pendingReorders {
                try await manager.reorderProperty(id: op.id, in: typeID, toIndex: op.toIndex)
            }
            // 4. Adds
            for def in pendingAdds {
                try await manager.addProperty(def, to: typeID)
            }

            pendingDeletes = []
            pendingRenames = []
            pendingReorders = []
            pendingAdds = []
        } catch {
            pendingError = error
        }
    }
}

// MARK: - TypeSettingsSheet

/// Schema editor sheet for an ItemType (Items side). Parallel to `VaultSettingsSheet`
/// on the Pages side.
///
/// Save-required semantics: all edits are staged in a local draft; Save replays the
/// diff against `itemTypeManager`. Cancel discards the draft.
///
/// One-at-a-time concurrency guard (concurrent-open forbidden per J.9 spec)
/// is enforced by the caller — this sheet does not implement it internally.
@MainActor
struct TypeSettingsSheet: View {
    let itemType: ItemType
    let itemTypeManager: ItemTypeManager
    let nexus: Nexus
    let index: PommoraIndex?
    let onDismiss: () -> Void

    @State private var vm: TypeSettingsViewModel
    @State private var isSaving: Bool = false

    init(
        itemType: ItemType,
        itemTypeManager: ItemTypeManager,
        nexus: Nexus,
        index: PommoraIndex?,
        onDismiss: @escaping () -> Void
    ) {
        self.itemType = itemType
        self.itemTypeManager = itemTypeManager
        self.nexus = nexus
        self.index = index
        self.onDismiss = onDismiss
        self._vm = State(wrappedValue: TypeSettingsViewModel(itemType: itemType))
    }

    var body: some View {
        VStack(spacing: 0) {
            TypeSettingsSheetHeader(
                hasChanges: vm.hasChanges,
                isSaving: isSaving,
                onCancel: { onDismiss() },
                onSave: {
                    isSaving = true
                    Task {
                        await vm.save(manager: itemTypeManager)
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
                    TypeSettingsPropertiesSection(vm: vm)
                    TypeSettingsTemplatesPlaceholder()
                }
                .padding(16)
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

// MARK: - TypeSettingsSheetHeader

private struct TypeSettingsSheetHeader: View {
    let hasChanges: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.borderless)
            Spacer()
            Text("Type Settings")
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

// MARK: - TypeSettingsPropertiesSection

private struct TypeSettingsPropertiesSection: View {
    @Bindable var vm: TypeSettingsViewModel

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
                        TypeSettingsPropertyRow(
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

            // New-property inline config
            if vm.pendingNewType != nil {
                TypeSettingsNewPropertyConfig(vm: vm)
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
                                // Relation creation is handled by the View Settings popover
                                // (PropertyTypePickerPane → EditPropertyPane .newRelation route).
                                // Silently cancel here rather than entering a broken wizard path.
                                vm.resetNewPropertyState()
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

// MARK: - TypeSettingsPropertyRow

private struct TypeSettingsPropertyRow: View {
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
            if let icon = definition.icon {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

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
                TypePropertyTypeBadge(type: definition.type)
            }

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

// MARK: - TypePropertyTypeBadge

private struct TypePropertyTypeBadge: View {
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

// MARK: - TypeSettingsNewPropertyConfig

private struct TypeSettingsNewPropertyConfig: View {
    @Bindable var vm: TypeSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New \(vm.pendingNewType?.displayName ?? "") property")
                .font(.callout)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Property name", text: $vm.pendingNewName)
                    .textFieldStyle(.roundedBorder)
            }

            if let type = vm.pendingNewType {
                switch type {
                case .select, .multiSelect:
                    SelectOptionsEditor(
                        options: $vm.pendingSelectOptions,
                        onAddOption: {
                            let value = ULID.generate()
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

// Per-type editor sub-views (SelectOptionsEditor / StatusGroupsEditor /
// NumberFormatPicker / FileAcceptEditor) extracted to
// `Pommora/Properties/Editor/` (Task 8). Both this sheet and VaultSettingsSheet
// now share the same definitions; future View Settings popover panes reuse
// them too.

// MARK: - TypeSettingsTemplatesPlaceholder

private struct TypeSettingsTemplatesPlaceholder: View {
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
