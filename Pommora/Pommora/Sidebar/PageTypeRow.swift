import SwiftUI

struct PageTypeRow: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Page-Type-root Pages render ABOVE Collections per spec
            // (PageTypes.md:112-114). PageRow is a leaf — not selectable in v0.2.
            ForEach(contentManager.pages(in: pageType)) { page in
                PageRow(
                    page: page,
                    parent: .vaultRoot(pageType),
                    selection: $selection,
                    editingID: $editingID
                )
            }
            ForEach(pageTypeManager.pageCollections(in: pageType)) { coll in
                PageCollectionRow(
                    collection: coll,
                    parentVault: pageType,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
        } label: {
            // .reorderable wraps the label only — not the whole DisclosureGroup —
            // so the chevron tap area stays free for expand/collapse. Applying
            // .draggable to the outer view swallows chevron clicks as drag-init.
            label.reorderable(
                kind: .vault,
                id: pageType.id,
                containerID: nil,
                nexusID: pageTypeManager.nexusID,
                symbol: pageType.icon ?? "tray.2",
                title: pageType.title,
                accent: nil,
                onDrop: { payload, position in
                    let arr = pageTypeManager.types
                    guard
                        let from = arr.firstIndex(where: { $0.id == payload.id }),
                        let targetIdx = arr.firstIndex(where: { $0.id == pageType.id })
                    else { return }
                    let toOffset = position == .above ? targetIdx : targetIdx + 1
                    pageTypeManager.reorderPageTypes(
                        fromOffsets: IndexSet(integer: from),
                        toOffset: toOffset
                    )
                }
            )
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.pageType(pageType.id).matches(selection)
            )
        )
        // Load Page-Type-root Pages when the row appears, regardless of
        // disclosure state. `.task` fires once on appearance; if it were
        // attached to the disclosure children it would only fire on expand.
        .task {
            await contentManager.loadAll(for: pageType)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == pageType.id {
            renamingRow
        } else {
            SelectableRow(
                title: pageType.title,
                symbol: pageType.icon ?? "tray.2",
                tag: SelectionTag.pageType(pageType.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .pageType(pageType) }
            )
            .contextMenu {
                let pageTypeLabel = settingsManager.settings.labels.pageType.singular
                let collectionLabel = settingsManager.settings.labels.pageCollection.singular
                Button("New \(pageTypeLabel)") { presentedSheet = .newPageType }
                Button("New \(collectionLabel)") {
                    presentedSheet = .newCollection(pageType: pageType)
                }
                Button("New Page") {
                    presentedSheet = .newPageInPageType(pageType: pageType)
                }
                Divider()
                Button("Rename") { editingID = pageType.id }
                Button("Change Icon") { presentedSheet = .editIcon(.pageType(pageType)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = pageTypeManager.pageCollections(in: pageType).count
                    confirmingDelete = .deleteVault(pageType, collectionCount: cols)
                }
            }
        }
    }

    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: pageType.icon ?? "tray.2")
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
                    if !focused && !isCommitting && editingID == pageType.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = pageType.title
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
        guard draft != pageType.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await pageTypeManager.renamePageType(pageType, to: draft)
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
