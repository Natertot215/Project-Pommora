import Foundation
import Testing

@testable import Pommora

/// F.1.i — silent auto-sidecar-tagging tests.
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` walks the Nexus root three
/// levels deep on every launch and writes missing per-kind sidecars so
/// Finder-built structure is first-class without any user-facing prompt.
/// These tests cover:
///   - Three-tier round-trip (Type / Collection / Folder all auto-tagged)
///   - Items-side stops at two tiers (no `_folder.json` on depth-2)
///   - Idempotence (second pass produces identical disk state)
///   - Exclusion rules (dotfile + underscore prefixes left alone)
@MainActor
@Suite("NexusAdopter+AutoTag")
struct NexusAdopterAutoTagTests {

    // MARK: - Three-tier Pages round-trip

    @Test("Finder-built three-tier Pages structure round-trips to fully-tagged tree")
    func threeTierPagesRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Hand-built: Research/Sources/2026-Q2/paper.md — zero sidecars.
        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        let folderFolder = collFolder.appendingPathComponent("2026-Q2", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.write(
            "# Paper\n", to: folderFolder.appendingPathComponent("paper.md")
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Type sidecar
        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: ptMeta.path))
        let pt = try PageType.load(from: ptMeta)
        #expect(!pt.id.isEmpty)
        #expect(pt.title == "Research")

        // Collection sidecar
        let pcMeta = collFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename
        )
        #expect(FileManager.default.fileExists(atPath: pcMeta.path))
        let pc = try PageCollection.load(from: pcMeta)
        #expect(!pc.id.isEmpty)
        #expect(pc.typeID == pt.id)
        #expect(pc.title == "Sources")

        // Folder sidecar (the new third tier)
        let fMeta = folderFolder.appendingPathComponent(NexusPaths.folderSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: fMeta.path))
        let f = try Folder.load(from: fMeta)
        #expect(!f.id.isEmpty)
        #expect(f.typeID == pt.id)
        #expect(f.collectionID == pc.id)
        #expect(f.title == "2026-Q2")
    }

    @Test("auto-tag preserves the markdown file at the three-tier path")
    func threeTierPreservesPageFile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folderFolder = nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
            .appendingPathComponent("2026-Q2")
        try FileManager.default.createDirectory(
            at: folderFolder, withIntermediateDirectories: true
        )
        let paperURL = folderFolder.appendingPathComponent("paper.md")
        try FixtureFiles.write("# Paper\n", to: paperURL)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(FileManager.default.fileExists(atPath: paperURL.path))
    }

    // MARK: - Items side stops at two tiers

    @Test("Items side auto-tags Type + Set but NOT a third tier inside the Set")
    func itemsSideTwoTiersOnly() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Hand-built: Books/Reading/Q2/buy-milk.json — zero sidecars.
        let typeFolder = nexus.rootURL.appendingPathComponent("Books", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Reading", isDirectory: true)
        let deepFolder = collFolder.appendingPathComponent("Q2", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deepFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HABC"}"#,
            to: deepFolder.appendingPathComponent("buy-milk.json")
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // ItemType sidecar at depth 0
        let itMeta = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: itMeta.path))

        // ItemCollection sidecar at depth 1
        let icMeta = collFolder.appendingPathComponent(
            NexusPaths.itemCollectionSidecarFilename
        )
        #expect(FileManager.default.fileExists(atPath: icMeta.path))

        // No _folder.json AND no _itemcollection.json inside the depth-2
        // folder — Items side has no third tier.
        let depth2Folder = deepFolder.appendingPathComponent(NexusPaths.folderSidecarFilename)
        let depth2ItemColl = deepFolder.appendingPathComponent(
            NexusPaths.itemCollectionSidecarFilename
        )
        #expect(!FileManager.default.fileExists(atPath: depth2Folder.path))
        #expect(!FileManager.default.fileExists(atPath: depth2ItemColl.path))
    }

    // MARK: - Idempotence

    @Test("running auto-tag twice produces identical disk state")
    func idempotence() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folderFolder = nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
            .appendingPathComponent("2026-Q2")
        try FileManager.default.createDirectory(
            at: folderFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.write(
            "# Paper\n", to: folderFolder.appendingPathComponent("paper.md")
        )

        // Pass 1
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pcMeta = folderFolder.deletingLastPathComponent()
            .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let fMeta = folderFolder.appendingPathComponent(NexusPaths.folderSidecarFilename)
        let pc1 = try PageCollection.load(from: pcMeta)
        let f1 = try Folder.load(from: fMeta)

        // Pass 2
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pc2 = try PageCollection.load(from: pcMeta)
        let f2 = try Folder.load(from: fMeta)

        // IDs preserved across passes — sidecars not rewritten.
        #expect(pc1.id == pc2.id)
        #expect(f1.id == f2.id)
        #expect(f1.collectionID == f2.collectionID)
        #expect(f1.typeID == f2.typeID)
    }

    // MARK: - Exclusion rules

    @Test("dotfile-prefixed folders at root are left untouched")
    func skipsDotfilePrefix() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let obsidian = nexus.rootURL.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidian, withIntermediateDirectories: true)
        try FixtureFiles.write("# Plugin", to: obsidian.appendingPathComponent("config.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let metaURL = obsidian.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(!FileManager.default.fileExists(atPath: metaURL.path))
    }

    @Test("underscore-prefixed folders at root are left untouched")
    func skipsUnderscorePrefix() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let misc = nexus.rootURL.appendingPathComponent("_misc", isDirectory: true)
        try FileManager.default.createDirectory(at: misc, withIntermediateDirectories: true)
        try FixtureFiles.write("# Misc", to: misc.appendingPathComponent("stuff.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let metaURL = misc.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(!FileManager.default.fileExists(atPath: metaURL.path))
    }

    @Test("dotfile sub-folders inside an auto-tagged Type are skipped")
    func skipsDotfileChild() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Research/.obsidian/ — Research becomes a PageType, .obsidian stays untouched.
        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        let inner = typeFolder.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FixtureFiles.write("# Page", to: typeFolder.appendingPathComponent("Page.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(
            FileManager.default.fileExists(
                atPath: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: inner.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename).path
            )
        )
    }

    // MARK: - Mixed shape (only missing tiers get tagged)

    @Test("auto-tag only writes missing sidecars; existing ones are not rewritten")
    func writesOnlyMissing() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)

        // Pre-write a Type sidecar with a known ID — auto-tag must NOT rewrite it.
        let knownID = ULID.generate()
        let now = Date()
        let pt = PageType(
            id: knownID, title: "Research", icon: nil,
            properties: [], views: [], modifiedAt: now
        )
        try pt.save(to: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // Then add a Collection sub-folder WITHOUT a sidecar.
        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Type sidecar's ID is preserved.
        let reloadedPT = try PageType.load(
            from: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
        #expect(reloadedPT.id == knownID)

        // Collection sidecar now exists with FK to the existing Type.
        let pcMeta = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: pcMeta.path))
        let pc = try PageCollection.load(from: pcMeta)
        #expect(pc.typeID == knownID)
    }
}
