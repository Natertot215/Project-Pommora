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
            .onMove { source, destination in
                contentManager.reorderPages(
                    inVault: pageType, fromOffsets: source, toOffset: destination
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
            .onMove { source, destination in
                pageTypeManager.reorderPageCollections(
                    in: pageType, fromOffsets: source, toOffset: destination
                )
            }
        } label: {
            label
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
                Button("New \(collectionLabel) (in This \(pageTypeLabel))") {
                    presentedSheet = .newCollection(pageType: pageType)
                }
                Button("New Page (in This \(pageTypeLabel) root)") {
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
