import SwiftUI

struct PageCollectionRow: View {
    let collection: PageCollection
    let parentVault: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(contentManager.pages(in: collection)) { page in
                PageRow(
                    page: page,
                    parent: .collection(collection, vault: parentVault),
                    selection: $selection,
                    editingID: $editingID
                )
            }
        } label: {
            // .reorderable wraps the label only so the chevron tap area stays
            // free for expand/collapse (see PageTypeRow for full rationale).
            label.reorderable(
                kind: .collection,
                id: collection.id,
                containerID: parentVault.id,
                nexusID: vaultManager.nexusID,
                symbol: "folder",
                title: collection.title,
                accent: nil,
                onDrop: { payload, position in
                    let arr = vaultManager.pageCollections(in: parentVault)
                    guard
                        let from = arr.firstIndex(where: { $0.id == payload.id }),
                        let targetIdx = arr.firstIndex(where: { $0.id == collection.id })
                    else { return }
                    let toOffset = position == .above ? targetIdx : targetIdx + 1
                    vaultManager.reorderPageCollections(
                        in: parentVault,
                        fromOffsets: IndexSet(integer: from),
                        toOffset: toOffset
                    )
                }
            )
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.collection(collection.id).matches(selection)
            )
        )
        // Same pattern as PageTypeRow: load on row appearance so Pages are
        // available even when the disclosure is collapsed (count badges,
        // future search, etc.).
        .task {
            await contentManager.loadAll(for: collection)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == collection.id {
            renamingRow
        } else {
            SelectableRow(
                title: collection.title,
                symbol: "folder",
                tag: SelectionTag.collection(collection.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .collection(collection) }
            )
            .contextMenu {
                let collectionLabel = settingsManager.settings.labels.pageCollection.singular
                Button("New Page (in This \(collectionLabel))") {
                    presentedSheet = .newPage(collection: collection, pageType: parentVault)
                }
                Divider()
                Button("Rename") { editingID = collection.id }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteCollection(collection)
                }
            }
        }
    }

    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16, alignment: .center)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == collection.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = collection.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                try await vaultManager.renamePageCollection(collection, to: draft)
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
