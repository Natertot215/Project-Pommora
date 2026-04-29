import SwiftUI

struct EditorView: View {
    let file: FileReference?

    @State private var text: String = ""
    @State private var loadedFileID: UUID?

    var body: some View {
        Group {
            if let file {
                TextEditor(text: $text)
                    .onChange(of: file.id, initial: true) { _, _ in
                        loadCurrentFile(file)
                    }
            } else {
                Color.clear
            }
        }
        .scenePadding(.horizontal)
        .scenePadding(.vertical)
    }

    private func loadCurrentFile(_ file: FileReference) {
        guard loadedFileID != file.id else { return }
        do {
            text = try FileIO.read(file.url)
            loadedFileID = file.id
            file.lastOpenedAt = .now
        } catch {
            text = ""
            loadedFileID = file.id
        }
    }
}
