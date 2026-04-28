import Foundation
import SwiftData
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum LibraryActions {

    @discardableResult
    static func addNewFolder(in folders: [VirtualFolder], context: ModelContext) -> VirtualFolder {
        let name = uniqueFolderName("New Folder", in: folders)
        for folder in folders {
            folder.order += 1
        }
        let folder = VirtualFolder(name: name, order: 0)
        context.insert(folder)
        return folder
    }

    static func presentOpenPanel() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedContentTypes()
        panel.message = "Choose markdown or plaintext files to add to Pommora."
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    static func addFiles(urls: [URL], target: VirtualFolder?, folders: [VirtualFolder], orphanFiles: [FileReference], context: ModelContext) {
        guard !urls.isEmpty else { return }

        if let target {
            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard isSupportedExtension(ext) else { continue }

                let path = url.path(percentEncoded: false)
                if target.files.contains(where: { $0.lastKnownPath == path }) { continue }

                let nextFileOrder = (target.files.map(\.order).max() ?? -1) + 1
                let ref = FileReference(
                    path: path,
                    displayName: url.lastPathComponent,
                    order: nextFileOrder
                )
                ref.folder = target
                context.insert(ref)
            }
        } else {
            var nextOrphanOrder = (orphanFiles.map(\.order).max() ?? -1) + 1
            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard isSupportedExtension(ext) else { continue }

                let path = url.path(percentEncoded: false)
                if orphanFiles.contains(where: { $0.lastKnownPath == path }) { continue }

                let ref = FileReference(
                    path: path,
                    displayName: url.lastPathComponent,
                    order: nextOrphanOrder
                )
                ref.folder = nil
                context.insert(ref)
                nextOrphanOrder += 1
            }
        }
    }

    static func moveToTopLevel(_ file: FileReference, orphanFiles: [FileReference]) {
        let nextOrder = (orphanFiles.map(\.order).max() ?? -1) + 1
        file.folder = nil
        file.order = nextOrder
    }

    static func moveFile(_ file: FileReference, intoFolder target: VirtualFolder) {
        guard file.folder?.id != target.id else { return }
        let nextOrder = (target.files.map(\.order).max() ?? -1) + 1
        file.folder = target
        file.order = nextOrder
    }

    static func liveMoveOrphanFile(draggingID: UUID, overID: UUID, orphanFiles: [FileReference]) {
        var sorted = orphanFiles.sorted(by: { $0.order < $1.order })
        guard let from = sorted.firstIndex(where: { $0.id == draggingID }),
              let to = sorted.firstIndex(where: { $0.id == overID }),
              from != to else { return }
        sorted.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for (i, file) in sorted.enumerated() { file.order = i }
    }

    static func moveFolders(_ folders: [VirtualFolder], from source: IndexSet, to destination: Int) {
        var reordered = folders.sorted(by: { $0.order < $1.order })
        reordered.move(fromOffsets: source, toOffset: destination)
        for (newOrder, folder) in reordered.enumerated() {
            folder.order = newOrder
        }
    }

    static func moveFiles(in folder: VirtualFolder, from source: IndexSet, to destination: Int) {
        var reordered = folder.files.sorted(by: { $0.order < $1.order })
        reordered.move(fromOffsets: source, toOffset: destination)
        for (newOrder, file) in reordered.enumerated() {
            file.order = newOrder
        }
    }

    static func liveMoveFolder(draggingID: UUID, overID: UUID, in folders: [VirtualFolder]) {
        var sorted = folders.sorted(by: { $0.order < $1.order })
        guard let from = sorted.firstIndex(where: { $0.id == draggingID }),
              let to = sorted.firstIndex(where: { $0.id == overID }),
              from != to else { return }
        sorted.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for (i, folder) in sorted.enumerated() { folder.order = i }
    }

    static func liveMoveFile(in folder: VirtualFolder, draggingID: UUID, overID: UUID) {
        var sorted = folder.files.sorted(by: { $0.order < $1.order })
        guard let from = sorted.firstIndex(where: { $0.id == draggingID }),
              let to = sorted.firstIndex(where: { $0.id == overID }),
              from != to else { return }
        sorted.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for (i, file) in sorted.enumerated() { file.order = i }
    }

    private static func isSupportedExtension(_ ext: String) -> Bool {
        switch ext {
        case "md", "markdown", "txt": return true
        default: return false
        }
    }

    private static func uniqueFolderName(_ baseName: String, in folders: [VirtualFolder]) -> String {
        var name = baseName
        var n = 1
        while folders.contains(where: { $0.name == name }) {
            n += 1
            name = "\(baseName) \(n)"
        }
        return name
    }

    private static func supportedContentTypes() -> [UTType] {
        var types: [UTType] = []
        for ext in ["md", "markdown"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        types.append(.plainText)
        return types
    }
}
