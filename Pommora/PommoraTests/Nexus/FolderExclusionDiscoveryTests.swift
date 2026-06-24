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

    /// Creates a PageCollection folder on disk (sidecar idiom — mirrors LoadAllIndexSyncTests).
    private func makePageCollection(_ title: String, id: String, in nexus: Nexus) throws {
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pt = PageCollection(id: id, title: title, icon: nil, properties: [], views: [], modifiedAt: Date())
        try pt.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
    }

    /// autoTag's depth-1 `cleanupLegacyOrphans` must not delete legacy sidecars
    /// inside a user-excluded NESTED folder ("never touched" at any depth).
    @Test func autoTagKeepsLegacySidecarsInExcludedNestedFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // A recognized (kept) Type folder...
        try makePageCollection("MyVault", id: "PT_V", in: nexus)
        // ...with a depth-1 sub-folder carrying a legacy collection sidecar that
        // cleanupLegacyOrphans would normally delete as an orphan.
        let priv = NexusPaths.vaultFolderURL(forTitle: "MyVault", in: nexus)
            .appendingPathComponent("Private")
        try FileManager.default.createDirectory(at: priv, withIntermediateDirectories: true)
        let legacy = priv.appendingPathComponent("_collection.json")
        try FixtureFiles.write("{}", to: legacy)
        try setExcluded(["MyVault/Private"], in: nexus)

        _ = NexusAdopter.autoTagMissingSidecars(
            at: nexus.rootURL, filter: FolderFilter.load(for: nexus))
        // Excluded nested folder → cleanup never reaches it; the sidecar survives.
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func excludedFolderAbsentFromIndexAfterBuild() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageCollection("Notes", id: "PT_NOTES", in: nexus)
        try makePageCollection("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        // Pass the filter explicitly — populate defaults to .empty (no exclusions).
        try await IndexBuilder.populate(index: index, from: nexus, filter: FolderFilter.load(for: nexus))

        let notesID = "PT_NOTES"
        let archiveID = "PT_ARCHIVE"
        let notes = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections WHERE id = ?", arguments: [notesID]) ?? -1
        }
        let archive = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections WHERE id = ?", arguments: [archiveID]) ?? -1
        }
        #expect(notes == 1)
        #expect(archive == 0)
    }

    // MARK: - PageCollectionManager.loadAll(filter:) exclusion tests

    @Test func excludedTypeAbsentFromPageCollectionLoadAll() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageCollection("Notes", id: "PT_NOTES", in: nexus)
        try makePageCollection("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let mgr = PageCollectionManager(nexus: nexus)
        await mgr.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(mgr.types.contains { $0.title == "Notes" })
        #expect(!mgr.types.contains { $0.title == "Archive" })
    }

    @Test func removingFromListReExposesType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageCollection("Archive", id: "PT_ARCHIVE", in: nexus)

        try setExcluded(["Archive"], in: nexus)
        let m1 = PageCollectionManager(nexus: nexus)
        await m1.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(!m1.types.contains { $0.title == "Archive" })

        try setExcluded([], in: nexus)
        let m2 = PageCollectionManager(nexus: nexus)
        await m2.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(m2.types.contains { $0.title == "Archive" })
    }

    @Test func excludedNestedCollectionAbsent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Create the "Notes" PageCollection.
        try makePageCollection("Notes", id: "PT_NOTES_COL", in: nexus)

        // Create two sub-folder collections inside "Notes": "Inbox" and "Archive".
        let inboxFolder = NexusPaths.collectionFolderURL(
            forTitle: "Inbox", inVaultTitled: "Notes", in: nexus)
        let archiveFolder = NexusPaths.collectionFolderURL(
            forTitle: "Archive", inVaultTitled: "Notes", in: nexus)
        try FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        let inbox = PageSet(
            id: ULID.generate(),
            parentID: "PT_NOTES_COL",
            title: "Inbox",
            folderURL: inboxFolder,
            modifiedAt: Date()
        )
        let archive = PageSet(
            id: ULID.generate(),
            parentID: "PT_NOTES_COL",
            title: "Archive",
            folderURL: archiveFolder,
            modifiedAt: Date()
        )
        try inbox.save(to: inboxFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try archive.save(to: archiveFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        // Exclude the nested "Notes/Archive" sub-folder.
        try setExcluded(["Notes/Archive"], in: nexus)

        let filter = FolderFilter.load(for: nexus)
        let mgr = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak mgr] in mgr?.types ?? [] }
        mgr.pageSetManager = setManager
        await mgr.loadAll(filter: filter)
        await setManager.loadAll(types: mgr.types, filter: filter)

        let notesType = try #require(mgr.types.first { $0.title == "Notes" })
        let cols = mgr.pageCollections(in: notesType)
        #expect(cols.contains { $0.title == "Inbox" })
        #expect(!cols.contains { $0.title == "Archive" })
    }

    // MARK: - PageContentManager type-root roll-up exclusion

    @Test func excludedNestedFolderPagesDoNotRollUp() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageCollection("Notes", id: "PT_NOTES", in: nexus)

        // A kept page directly in Notes/ — should remain visible.
        let notesFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
        try FixtureFiles.write("# kept", to: notesFolder.appendingPathComponent("kept.md"))

        // A page inside an excluded nested sub-folder — must NOT roll up.
        let scratch = notesFolder.appendingPathComponent("Scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FixtureFiles.write("# secret", to: scratch.appendingPathComponent("secret.md"))

        try setExcluded(["Notes/Scratch"], in: nexus)

        let pt = PageCollection(id: "PT_NOTES", title: "Notes", icon: nil, properties: [], views: [], modifiedAt: Date())
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
        var s = Settings.defaultSeed()
        s.excludedFolders = ["Archive"]
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL, filter: FolderFilter.load(for: nexus))
        let names = plan.freshSidecars.map { $0.folderURL.lastPathComponent }
        #expect(names.contains("Notes"))
        #expect(!names.contains("Archive"))
    }

    // MARK: - Convention skips + TopicManager exemption

    /// (a) Built-in convention skips (.obsidian, _internal, node_modules) work with
    ///     an empty user exclusion list — they are never surfaced as Page Types.
    /// (b) A root-level "topics" exclusion must NOT suppress the .nexus/topics
    ///     Contexts read — TopicManager.loadAll() is the exempt internal path that
    ///     bypasses FolderFilter entirely.
    @Test func conventionsHoldAndContextsSurviveTopicsExclusion() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // (a) Convention skips hold with an empty user list.
        for name in [".obsidian", "_internal", "node_modules"] {
            try FileManager.default.createDirectory(
                at: nexus.rootURL.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try makePageCollection("Notes", id: "PT_NOTES", in: nexus)
        let ptm = PageCollectionManager(nexus: nexus)
        await ptm.loadAll(filter: FolderFilter.load(for: nexus))  // empty user exclusion list
        #expect(ptm.types.contains { $0.title == "Notes" })
        #expect(!ptm.types.contains { $0.title == ".obsidian" })
        #expect(!ptm.types.contains { $0.title == "_internal" })
        #expect(!ptm.types.contains { $0.title == "node_modules" })

        // (b) A root-level "topics" exclusion must NOT suppress TopicManager.loadAll().
        let tm = TopicManager(nexus: nexus)
        try await tm.create(name: "Research", icon: nil)

        try setExcluded(["topics"], in: nexus)

        let tm2 = TopicManager(nexus: nexus)
        await tm2.loadAll()  // exempt — no filter param
        #expect(tm2.topics.contains { $0.title == "Research" })
    }

    // MARK: - NexusAdopter.autoTagMissingSidecars exclusion

    /// autoTagMissingSidecars must NOT write a sidecar into (or otherwise touch)
    /// a folder that is excluded by the user.
    ///
    /// Without exclusion, autoTag would write `_pagetype.json` into the bare
    /// "Archive" folder (tagDepth0IfMissing). With the filter, that must be
    /// suppressed and the loose .md left byte-identical.
    @Test func autoTagDoesNotTouchExcludedFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // A top-level folder with no sidecar — autoTag would tag it as a PageCollection.
        let archive = nexus.rootURL.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        // A bare .md file inside it — autoTag's stampClassPass would stamp Class: page.
        let stray = archive.appendingPathComponent("loose.md")
        try FixtureFiles.write("# loose\n\nbody", to: stray)

        // Exclude "Archive" via settings.
        var s = Settings.defaultSeed()
        s.excludedFolders = ["Archive"]
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))

        let before = try String(contentsOf: stray, encoding: .utf8)

        let tempNexus = Nexus(id: "", rootURL: nexus.rootURL)
        _ = NexusAdopter.autoTagMissingSidecars(
            at: nexus.rootURL, filter: FolderFilter.load(for: tempNexus))

        // Sidecar must NOT have been written — the folder stays untagged.
        let sidecar = archive.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))

        // The .md file must be untouched — same path, same content.
        #expect(FileManager.default.fileExists(atPath: stray.path))
        let after = try String(contentsOf: stray, encoding: .utf8)
        #expect(after == before)
    }
}
