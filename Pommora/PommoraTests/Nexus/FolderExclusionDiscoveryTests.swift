import Foundation
import GRDB
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

    // MARK: - PageTypeManager.loadAll(filter:) exclusion tests

    @Test func excludedTypeAbsentFromPageTypeLoadAll() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let mgr = PageTypeManager(nexus: nexus)
        await mgr.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(mgr.types.contains { $0.title == "Notes" })
        #expect(!mgr.types.contains { $0.title == "Archive" })
    }

    @Test func removingFromListReExposesType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)

        try setExcluded(["Archive"], in: nexus)
        let m1 = PageTypeManager(nexus: nexus)
        await m1.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(!m1.types.contains { $0.title == "Archive" })

        try setExcluded([], in: nexus)
        let m2 = PageTypeManager(nexus: nexus)
        await m2.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(m2.types.contains { $0.title == "Archive" })
    }

    @Test func excludedNestedCollectionAbsent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Create the "Notes" PageType.
        try makePageType("Notes", id: "PT_NOTES_COL", in: nexus)

        // Create two sub-folder collections inside "Notes": "Inbox" and "Archive".
        let inboxFolder = NexusPaths.collectionFolderURL(
            forTitle: "Inbox", inVaultTitled: "Notes", in: nexus)
        let archiveFolder = NexusPaths.collectionFolderURL(
            forTitle: "Archive", inVaultTitled: "Notes", in: nexus)
        try FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        let inbox = PageCollection(
            id: ULID.generate(),
            typeID: "PT_NOTES_COL",
            title: "Inbox",
            folderURL: inboxFolder,
            modifiedAt: Date()
        )
        let archive = PageCollection(
            id: ULID.generate(),
            typeID: "PT_NOTES_COL",
            title: "Archive",
            folderURL: archiveFolder,
            modifiedAt: Date()
        )
        try inbox.save(to: inboxFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        try archive.save(to: archiveFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // Exclude the nested "Notes/Archive" sub-folder.
        try setExcluded(["Notes/Archive"], in: nexus)

        let mgr = PageTypeManager(nexus: nexus)
        await mgr.loadAll(filter: FolderFilter.load(for: nexus))

        let notesType = try #require(mgr.types.first { $0.title == "Notes" })
        let cols = mgr.pageCollections(in: notesType)
        #expect(cols.contains { $0.title == "Inbox" })
        #expect(!cols.contains { $0.title == "Archive" })
    }

    // MARK: - PageContentManager type-root roll-up exclusion

    @Test func excludedNestedFolderPagesDoNotRollUp() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)

        // A kept page directly in Notes/ — should remain visible.
        let notesFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
        try FixtureFiles.write("# kept", to: notesFolder.appendingPathComponent("kept.md"))

        // A page inside an excluded nested sub-folder — must NOT roll up.
        let scratch = notesFolder.appendingPathComponent("Scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FixtureFiles.write("# secret", to: scratch.appendingPathComponent("secret.md"))

        try setExcluded(["Notes/Scratch"], in: nexus)

        let pt = PageType(id: "PT_NOTES", title: "Notes", icon: nil, properties: [], views: [], modifiedAt: Date())
        let pcm = PageContentManager(nexus: nexus, contextProvider: { .empty })
        await pcm.loadAll(for: pt)

        let loaded = pcm.pages(in: pt)
        #expect(loaded.contains { $0.title == "kept" })
        #expect(!loaded.contains { $0.title == "secret" })
    }

    // MARK: - NexusAdopter.scan exclusion

    @Test func excludedFolderSkippedByAdoptionScan() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        for name in ["Notes", "Archive"] {
            let f = nexus.rootURL.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            try FixtureFiles.write("# x", to: f.appendingPathComponent("Note.md"))
        }
        var s = Settings.defaultSeed(); s.excludedFolders = ["Archive"]
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL, filter: FolderFilter.load(for: nexus))
        let names = plan.freshSidecars.map { $0.folderURL.lastPathComponent }
        #expect(names.contains("Notes"))
        #expect(!names.contains("Archive"))
    }
}
