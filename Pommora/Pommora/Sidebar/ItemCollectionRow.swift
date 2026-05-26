import SwiftUI

/// Sidebar leaf row for an Item Collection (user-labelled "Set").
///
/// Sets render as flat leaves — NO disclosure chevron. Per Nathan's directive:
/// Item Types are foldable toggles (like Vaults), but Sets are standard leaves
/// since Items themselves never render as sidebar rows (Items live in the
/// detail-pane Table, not the sidebar).
///
/// Mirrors `PageCollectionRow`'s rename + context menu shape minus the
/// DisclosureGroup wrapper. Selection chrome via `.listRowBackground`.
struct ItemCollectionRow: View {
    let collection: ItemCollection
    let parentType: ItemType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        label
            .listRowBackground(
                SelectionChrome(
                    isSelected: SelectionTag.itemCollection(collection.id).matches(selection)
                )
            )
    }

    @ViewBuilder
    private var label: some View {
        if editingID == collection.id {
            RenameableRow(
                symbol: "tray",
                initialTitle: collection.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == collection.id {
                        cancel()
                    }
                }
            )
        } else {
            SelectableRow(
                title: collection.title,
                symbol: "tray",
                tag: SelectionTag.itemCollection(collection.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                let setLabel = settingsManager.settings.labels.itemCollection.singular
                Button("New Item (in This \(setLabel))") {
                    presentedSheet = .newItem(collection: collection, type: parentType)
                }
                Divider()
                Button("Rename") { editingID = collection.id }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteItemCollection(collection)
                }
            }
        }
    }

    private func commit() {
        guard draft != collection.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await itemTypeManager.renameItemCollection(collection, to: draft)
                editingID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
                // editingID preserved on failure for retry.
            }
        }
    }

    private func cancel() {
        editingID = nil
    }
}
