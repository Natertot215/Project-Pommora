import SwiftUI
import SwiftData

struct RecentsContentView: View {
    @Binding var selectedFileID: UUID?

    @Query(
        filter: #Predicate<FileReference> { $0.lastOpenedAt != nil },
        sort: \FileReference.lastOpenedAt,
        order: .reverse
    )
    private var files: [FileReference]

    @State private var displayedIDs: [UUID] = []

    private static let cap = 50

    private var capped: [FileReference] {
        Array(files.prefix(Self.cap))
    }

    private var displayedFiles: [FileReference] {
        let lookup = Dictionary(uniqueKeysWithValues: capped.map { ($0.id, $0) })
        return displayedIDs.compactMap { lookup[$0] }
    }

    private struct Bucket: Identifiable {
        let id: String
        let label: String
        let files: [FileReference]
    }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        let now = Date.now
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now

        var today: [FileReference] = []
        var yesterday: [FileReference] = []
        var previous7: [FileReference] = []
        var older: [FileReference] = []

        for file in displayedFiles {
            guard let date = file.lastOpenedAt else { continue }
            if cal.isDateInToday(date) {
                today.append(file)
            } else if cal.isDateInYesterday(date) {
                yesterday.append(file)
            } else if date >= sevenDaysAgo {
                previous7.append(file)
            } else {
                older.append(file)
            }
        }

        var result: [Bucket] = []
        if !today.isEmpty { result.append(Bucket(id: "today", label: "Today", files: today)) }
        if !yesterday.isEmpty { result.append(Bucket(id: "yesterday", label: "Yesterday", files: yesterday)) }
        if !previous7.isEmpty { result.append(Bucket(id: "p7", label: "Previous 7 Days", files: previous7)) }
        if !older.isEmpty { result.append(Bucket(id: "older", label: "Older", files: older)) }
        return result
    }

    var body: some View {
        Group {
            if displayedFiles.isEmpty {
                ContentUnavailableView(
                    "No Recent Files",
                    systemImage: "clock",
                    description: Text("Files you open appear here.")
                )
            } else {
                List(selection: $selectedFileID) {
                    ForEach(buckets) { bucket in
                        Section(bucket.label) {
                            ForEach(bucket.files) { file in
                                SidebarFileRow(file: file)
                                    .tag(file.id)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .navigationTitle("Recents")
        .onAppear { refreshSnapshot() }
        .onChange(of: files.count) { _, _ in refreshSnapshotForNewFiles() }
    }

    private func refreshSnapshot() {
        displayedIDs = capped.map(\.id)
    }

    private func refreshSnapshotForNewFiles() {
        let known = Set(displayedIDs)
        let newcomers = capped.map(\.id).filter { !known.contains($0) }
        let surviving = displayedIDs.filter { id in capped.contains(where: { $0.id == id }) }
        displayedIDs = newcomers + surviving
    }
}
