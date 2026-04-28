import SwiftUI
import SwiftData

struct FolderContentView: View {
    let folder: VirtualFolder
    @Binding var selectedFileID: UUID?

    @State private var draggingFileID: UUID?

    private static let fileDragPrefix = "file:"

    private var sortedFiles: [FileReference] {
        folder.files.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        Group {
            if sortedFiles.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc.text",
                    description: Text("Add files to \(folder.name) to start editing.")
                )
            } else {
                List(selection: $selectedFileID) {
                    ForEach(sortedFiles) { file in
                        SidebarFileRow(file: file)
                            .tag(file.id)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .draggable(captureFileDragStart(file.id))
                            .dropDestination(for: String.self) { _, _ in
                                draggingFileID = nil
                                return true
                            } isTargeted: { targeted in
                                handleFileDropTarget(targeted: targeted, overFile: file)
                            }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .navigationTitle(folder.name)
    }

    private func captureFileDragStart(_ id: UUID) -> String {
        draggingFileID = id
        return "\(Self.fileDragPrefix)\(id.uuidString)"
    }

    private func handleFileDropTarget(targeted: Bool, overFile file: FileReference) {
        guard targeted,
              let dragging = draggingFileID,
              dragging != file.id else { return }
        guard folder.files.contains(where: { $0.id == dragging }) else { return }
        withAnimation(.snappy) {
            LibraryActions.liveMoveFile(in: folder, draggingID: dragging, overID: file.id)
        }
    }
}
