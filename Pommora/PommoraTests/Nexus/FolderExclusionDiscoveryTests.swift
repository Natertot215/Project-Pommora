import GRDB
import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("FolderExclusionDiscovery") struct FolderExclusionDiscoveryTests {

    /// Writes `excluded_folders` into the nexus settings file on disk so
    /// FolderFilter.load(for:) picks it up.
    private func setExcluded(_ paths: [String], in nexus: Nexus) throws {
        var s = Settings.defaultSeed()
        s.excludedFolders = paths
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))
    }

    /// Creates a PageType folder on disk (sidecar idiom — mirrors LoadAllIndexSyncTests).
    private func makePageType(_ title: String, id: String, in nexus: Nexus) throws {
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pt = PageType(id: id, title: title, icon: nil, properties: [], views: [], modifiedAt: Date())
        try pt.save(to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
    }

    @Test func excludedFolderAbsentFromIndexAfterBuild() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        // Pass the filter explicitly — populate defaults to .empty (no exclusions).
        try await IndexBuilder.populate(index: index, from: nexus, filter: FolderFilter.load(for: nexus))

        let notesID = "PT_NOTES"
        let archiveID = "PT_ARCHIVE"
        let notes = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?", arguments: [notesID]) ?? -1
        }
        let archive = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?", arguments: [archiveID]) ?? -1
        }
        #expect(notes == 1)
        #expect(archive == 0)
    }
}
