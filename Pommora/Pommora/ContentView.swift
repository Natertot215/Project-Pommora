import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var allFiles: [FileReference]
    @Query private var folders: [VirtualFolder]

    @State private var sidebarSelection: SidebarSelection?
    @State private var middleColumnFileID: UUID?
    @State private var didBootstrap = false

    private var selectedFolder: VirtualFolder? {
        if case .folder(let id) = sidebarSelection {
            return folders.first(where: { $0.id == id })
        }
        return nil
    }

    private var sidebarSelectedFile: FileReference? {
        if case .file(let id) = sidebarSelection {
            return allFiles.first(where: { $0.id == id })
        }
        return nil
    }

    private var isShowingRecents: Bool {
        if case .recents = sidebarSelection { return true }
        return false
    }

    private var editorFile: FileReference? {
        if let sidebarSelectedFile { return sidebarSelectedFile }
        if let middleColumnFileID {
            return allFiles.first(where: { $0.id == middleColumnFileID })
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(sidebarSelection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            middleColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            EditorView(file: editorFile)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .title)
        .onAppear { bootstrapIfNeeded() }
    }

    @ViewBuilder
    private var middleColumn: some View {
        if let folder = selectedFolder {
            FolderContentView(folder: folder, selectedFileID: $middleColumnFileID)
        } else if isShowingRecents {
            RecentsContentView(selectedFileID: $middleColumnFileID)
        } else {
            Color.clear
        }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        for file in allFiles where !file.existsOnDisk {
            context.delete(file)
        }

        #if DEBUG
        DebugSeed.run(context: context)
        #endif
    }
}
