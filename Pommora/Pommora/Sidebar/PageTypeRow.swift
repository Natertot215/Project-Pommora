import SwiftUI

struct PageTypeRow: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    let nexus: Nexus
    let index: PommoraIndex?
    @State private var expanded: Bool = false

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var showingVaultSettings: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Page-Type-root Pages render ABOVE Collections per spec
            // (PageTypes.md:112-114).
            ForEach(contentManager.pages(in: pageType)) { page in
                PageRow(
                    page: page,
                    parent: .vaultRoot(pageType),
                    selection: $selection,
                    editingID: $editingID
                )
                .tag(SelectionTag.page(page.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    contentManager.reorderPages(
                        inVault: pageType, fromOffsets: source, toOffset: destination
                    )
                }
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
                .tag(SelectionTag.collection(coll.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    pageTypeManager.reorderPageCollections(
                        in: pageType, fromOffsets: source, toOffset: destination
                    )
                }
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
        .sheet(isPresented: $showingVaultSettings) {
            VaultSettingsSheet(
                pageType: pageType,
                pageTypeManager: pageTypeManager,
                nexus: nexus,
                index: index,
                onDismiss: { showingVaultSettings = false }
            )
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == pageType.id {
            RenameableRow(
                symbol: pageType.icon ?? "tray.2",
                initialTitle: pageType.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == pageType.id {
                        cancel()
                    }
                }
            )
        } else {
            SelectableRow(
                title: pageType.title,
                symbol: pageType.icon ?? "tray.2",
                tag: SelectionTag.pageType(pageType.id),
                selection: $selection,
                accent: nil
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
                Button("\(pageTypeLabel) Settings…") {
                    showingVaultSettings = true
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
