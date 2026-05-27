import SwiftUI

/// Items-side sidebar row. Mirrors `PageTypeRow`'s DisclosureGroup pattern:
/// Item Type discloses to show its Item Collections (user-labelled "Sets")
/// as flat leaves beneath. Items themselves never render in the sidebar —
/// they live exclusively in the detail-pane Table.
///
/// Per Nathan's directive (post-flatten reversal): Item Types ARE foldable
/// toggles like Vaults / Topics; their Sets are standard leaves without
/// chevrons (since Sets have no further sidebar children to disclose).
///
/// Selection chrome via `.listRowBackground(SelectionChrome(...))` per quirk
/// #10. The Type stays selected-styled even when one of its child Sets is
/// the active selection, mirroring how Vaults keep their chrome lit while
/// drilled into a child Collection.
///
/// Context menu shape mirrors PageTypeRow: New Item / New Set / divider /
/// Type Settings / divider / Rename / Change Icon / divider / Delete. UI
/// labels read from `SettingsManager` so "Type" / "Set" default; both
/// renameable per Nexus.
struct ItemTypeRow: View {
    let itemType: ItemType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    let nexus: Nexus
    let index: PommoraIndex?

    @State private var expanded: Bool = false

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var showingTypeSettings: Bool = false
    @State private var isCreatingItem: Bool = false
    @State private var isCreatingCollection: Bool = false
    @State private var isCreatingItemType: Bool = false

    /// True when this Item Type is the active selection OR when any of its
    /// child ItemCollections is the active selection (drilled-in case).
    /// Mirrors the same trick PageTypeRow uses for its disclosure body.
    private var isSelected: Bool {
        if SelectionTag.itemType(itemType.id).matches(selection) { return true }
        if case .itemCollection(let coll) = selection,
           let parent = itemTypeManager.parentItemType(for: coll),
           parent.id == itemType.id {
            return true
        }
        return false
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(itemTypeManager.itemCollections(in: itemType)) { collection in
                ItemCollectionRow(
                    collection: collection,
                    parentType: itemType,
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                .tag(SelectionTag.itemCollection(collection.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    itemTypeManager.reorderItemCollections(
                        in: itemType,
                        fromOffsets: source,
                        toOffset: destination
                    )
                }
            }
        } label: {
            label
        }
        .listRowBackground(SelectionChrome(isSelected: isSelected))
        .sheet(isPresented: $showingTypeSettings) {
            TypeSettingsSheet(
                itemType: itemType,
                itemTypeManager: itemTypeManager,
                nexus: nexus,
                index: index,
                onDismiss: { showingTypeSettings = false }
            )
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == itemType.id {
            RenameableRow(
                symbol: itemType.icon ?? "tray.full",
                initialTitle: itemType.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == itemType.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == itemType.id
            )
        } else {
            SelectableRow(
                title: itemType.title,
                symbol: itemType.icon ?? "tray.full",
                tag: SelectionTag.itemType(itemType.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                let setLabel = settingsManager.settings.labels.itemCollection.singular
                Button("New Item") { createItem() }
                    .disabled(isCreatingItem)
                Button("New \(setLabel)") { createItemCollection() }
                    .disabled(isCreatingCollection)
                Divider()
                Button("Edit") {
                    showingTypeSettings = true
                }
                Divider()
                Button("Rename") { editingID = itemType.id }
                Button("Change Icon") { presentedSheet = .editIcon(.itemType(itemType)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let setCount = itemTypeManager.itemCollections(in: itemType).count
                    confirmingDelete = .deleteItemType(itemType, collectionCount: setCount)
                }
            }
        }
    }

    /// Stub-and-edit "New Item" trigger (Items live at the Type root when
    /// triggered from the ItemType row; the analogous "in This Set" trigger
    /// is on ItemCollectionRow).
    private func createItem() {
        guard !isCreatingItem else { return }
        isCreatingItem = true
        let existing = itemContentManager.items(in: itemType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Item", existingTitles: existing)
        Task {
            defer { isCreatingItem = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await itemContentManager.createItem(
                            name: title, inTypeRoot: itemType
                        )
                    },
                    onCreate: { newItem in
                        editingID = newItem.id
                        justCreatedID = newItem.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Stub-and-edit "New ItemCollection (Set)" trigger.
    private func createItemCollection() {
        guard !isCreatingCollection else { return }
        isCreatingCollection = true
        let label = settingsManager.settings.labels.itemCollection.singular
        let existing = itemTypeManager.itemCollections(in: itemType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingCollection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await itemTypeManager.createItemCollection(
                            name: title, inItemType: itemType
                        )
                    },
                    onCreate: { newCollection in
                        editingID = newCollection.id
                        justCreatedID = newCollection.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func commit() {
        guard draft != itemType.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await itemTypeManager.renameItemType(itemType, to: draft)
                editingID = nil
                justCreatedID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
                // editingID preserved on failure for retry.
            }
        }
    }

    private func cancel() {
        editingID = nil
        justCreatedID = nil
    }
}
