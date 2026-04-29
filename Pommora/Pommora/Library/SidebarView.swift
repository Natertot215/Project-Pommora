import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VirtualFolder.order) private var folders: [VirtualFolder]
    @Query private var allFiles: [FileReference]

    @Binding var sidebarSelection: SidebarSelection?
    @State private var searchQuery: String = ""
    @State private var cache = LibrarySearchCache()
    @State private var results: LibrarySearch.Results = .empty
    @State private var expandedSections: [SidebarSection: Bool] = [
        .favorites: true, .folders: true, .files: true, .tags: true
    ]
    @State private var filenamesExpanded = true
    @State private var headingsExpanded = true
    @State private var draggingFolderID: UUID?
    @State private var draggingOrphanFileID: UUID?
    @State private var dropTargetFolderID: UUID?
    @AppStorage("sidebarSectionOrder") private var storedSectionOrder: String = SidebarSection.encode(SidebarSection.defaultOrder)

    private static let folderDragPrefix = "folder:"
    private static let fileDragPrefix = "file:"

    private var orderedSections: [SidebarSection] {
        SidebarSection.decode(storedSectionOrder)
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orphanFiles: [FileReference] {
        allFiles
            .filter { $0.folder == nil }
            .sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        List(selection: $sidebarSelection) {
            if !isSearching {
                recentsRow
            }
            if isSearching {
                searchResultsContent
            } else {
                sectionsContent
            }
        }
        .listStyle(.sidebar)
        .controlSize(.regular)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search")
        .overlay {
            if isSearching && results.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
        .contextMenu(forSelectionType: SidebarSelection.self) { selectedItems in
            if selectedItems.isEmpty {
                Button("New Folder") { addNewFolder() }
                Button("Add Files\u{2026}") { addFiles(into: nil) }
            }
        }
        .onChange(of: searchQuery) { _, _ in updateResults() }
        .onChange(of: allFiles.count) { _, _ in updateResults() }
        .onChange(of: folders.count) { _, _ in updateResults() }
    }

    private var recentsRow: some View {
        Label("Recents", systemImage: "clock")
            .tag(SidebarSelection.recents)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var sectionsContent: some View {
        ForEach(orderedSections) { section in
            switch section {
            case .favorites:
                Section(isExpanded: bindingForSection(.favorites)) {
                    EmptyView()
                } header: {
                    Text(section.title)
                }
            case .folders:
                Section(isExpanded: bindingForSection(.folders)) {
                    foldersContent
                } header: {
                    Text(section.title)
                }
            case .files:
                Section(isExpanded: bindingForSection(.files)) {
                    filesContent
                } header: {
                    filesSectionHeader(title: section.title)
                }
            case .tags:
                Section(isExpanded: bindingForSection(.tags)) {
                    EmptyView()
                } header: {
                    Text(section.title)
                }
            }
        }
        .onMove { source, destination in
            moveSections(from: source, to: destination)
        }
    }

    private func filesSectionHeader(title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                let handled = handleFilesSectionDrop(items: items)
                draggingFolderID = nil
                draggingOrphanFileID = nil
                return handled
            }
    }

    @ViewBuilder
    private var foldersContent: some View {
        ForEach(folders) { folder in
            folderRow(folder)
                .tag(SidebarSelection.folder(folder.id))
                .listRowBackground(folderRowBackground(for: folder))
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Add Files to \(folder.name)\u{2026}") {
                        addFiles(into: folder)
                    }
                }
                .draggable(captureFolderDragStart(folder.id))
                .dropDestination(for: String.self) { items, _ in
                    let handled = handleFolderRowDrop(items: items, target: folder)
                    draggingFolderID = nil
                    draggingOrphanFileID = nil
                    dropTargetFolderID = nil
                    return handled
                } isTargeted: { targeted in
                    if targeted && draggingFolderID == nil {
                        dropTargetFolderID = folder.id
                    } else if !targeted, dropTargetFolderID == folder.id {
                        dropTargetFolderID = nil
                    }
                    handleFolderDropTarget(targeted: targeted, overFolder: folder)
                }
                .listRowSeparator(.hidden)
        }
    }

    private func folderRow(_ folder: VirtualFolder) -> some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    @ViewBuilder
    private func folderRowBackground(for folder: VirtualFolder) -> some View {
        if dropTargetFolderID == folder.id {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.20))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var filesContent: some View {
        ForEach(orphanFiles) { file in
            SidebarFileRow(file: file)
                .tag(SidebarSelection.file(file.id))
                .listRowSeparator(.hidden)
                .draggable(captureOrphanFileDragStart(file.id))
                .dropDestination(for: String.self) { items, _ in
                    let handled = handleOrphanRowDrop(items: items)
                    draggingOrphanFileID = nil
                    draggingFolderID = nil
                    return handled
                } isTargeted: { targeted in
                    handleOrphanFileDropTarget(targeted: targeted, overFile: file)
                }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if !results.filenames.isEmpty {
            Section(isExpanded: $filenamesExpanded) {
                ForEach(results.filenames) { hit in
                    SidebarFileRow(file: hit.file, hit: hit)
                        .tag(SidebarSelection.file(hit.file.id))
                }
            } header: {
                Text("Filenames")
            }
        }
        if !results.headings.isEmpty {
            Section(isExpanded: $headingsExpanded) {
                ForEach(results.headings) { hit in
                    SidebarFileRow(file: hit.file, hit: hit)
                        .tag(SidebarSelection.file(hit.file.id))
                }
            } header: {
                Text("Headings")
            }
        }
    }

    private func handleFolderDropTarget(targeted: Bool, overFolder folder: VirtualFolder) {
        guard targeted,
              let dragging = draggingFolderID,
              dragging != folder.id else { return }
        withAnimation(.snappy) {
            LibraryActions.liveMoveFolder(draggingID: dragging, overID: folder.id, in: folders)
        }
    }

    private func handleFolderRowDrop(items: [String], target: VirtualFolder) -> Bool {
        var handled = false
        for item in items {
            if let fileID = parseFileID(item),
               let file = allFiles.first(where: { $0.id == fileID }) {
                withAnimation(.snappy) {
                    LibraryActions.moveFile(file, intoFolder: target)
                }
                handled = true
            } else if parseFolderID(item) != nil {
                handled = true
            }
        }
        return handled
    }

    private func handleFilesSectionDrop(items: [String]) -> Bool {
        var handled = false
        for item in items {
            guard let fileID = parseFileID(item),
                  let file = allFiles.first(where: { $0.id == fileID }),
                  file.folder != nil else { continue }
            withAnimation(.snappy) {
                LibraryActions.moveToTopLevel(file, orphanFiles: orphanFiles)
            }
            handled = true
        }
        return handled
    }

    private func handleOrphanRowDrop(items: [String]) -> Bool {
        var handled = false
        for item in items {
            guard let fileID = parseFileID(item) else { continue }
            if let file = allFiles.first(where: { $0.id == fileID }),
               file.folder != nil {
                withAnimation(.snappy) {
                    LibraryActions.moveToTopLevel(file, orphanFiles: orphanFiles)
                }
                handled = true
            } else {
                handled = true
            }
        }
        return handled
    }

    private func captureFolderDragStart(_ id: UUID) -> String {
        draggingFolderID = id
        return "\(Self.folderDragPrefix)\(id.uuidString)"
    }

    private func captureOrphanFileDragStart(_ id: UUID) -> String {
        draggingOrphanFileID = id
        return "\(Self.fileDragPrefix)\(id.uuidString)"
    }

    private func parseFileID(_ s: String) -> UUID? {
        guard s.hasPrefix(Self.fileDragPrefix) else { return nil }
        return UUID(uuidString: String(s.dropFirst(Self.fileDragPrefix.count)))
    }

    private func parseFolderID(_ s: String) -> UUID? {
        guard s.hasPrefix(Self.folderDragPrefix) else { return nil }
        return UUID(uuidString: String(s.dropFirst(Self.folderDragPrefix.count)))
    }

    private func handleOrphanFileDropTarget(targeted: Bool, overFile file: FileReference) {
        guard targeted,
              let dragging = draggingOrphanFileID,
              dragging != file.id else { return }
        guard orphanFiles.contains(where: { $0.id == dragging }) else { return }
        withAnimation(.snappy) {
            LibraryActions.liveMoveOrphanFile(draggingID: dragging, overID: file.id, orphanFiles: orphanFiles)
        }
    }

    private func bindingForSection(_ section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections[section] ?? true },
            set: { expandedSections[section] = $0 }
        )
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        var current = orderedSections
        current.move(fromOffsets: source, toOffset: destination)
        withAnimation(.snappy) {
            storedSectionOrder = SidebarSection.encode(current)
        }
    }

    private func updateResults() {
        results = LibrarySearch.run(query: searchQuery, folders: folders, orphanFiles: orphanFiles, cache: cache)
    }

    private func addNewFolder() {
        withAnimation(.snappy) {
            _ = LibraryActions.addNewFolder(in: folders, context: context)
        }
    }

    private func addFiles(into folder: VirtualFolder?) {
        let urls = LibraryActions.presentOpenPanel()
        guard !urls.isEmpty else { return }
        withAnimation(.snappy) {
            LibraryActions.addFiles(
                urls: urls,
                target: folder,
                folders: folders,
                orphanFiles: orphanFiles,
                context: context
            )
        }
    }
}
