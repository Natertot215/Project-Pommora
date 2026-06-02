import Foundation
import Testing

@testable import Pommora

/// Silent auto-sidecar-tagging tests.
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` walks the Nexus root two
/// levels deep on every launch and writes missing per-kind sidecars so
/// Finder-built structure (Types + Collections) is first-class without any
/// user-facing prompt. These tests cover:
///   - Two-tier round-trip (Type / Collection auto-tagged)
///   - Items-side stops at two tiers
///   - Idempotence (second pass produces identical disk state)
///   - Exclusion rules (dotfile + underscore prefixes left alone)
@MainActor
@Suite("NexusAdopter+AutoTag")
struct NexusAdopterAutoTagTests {

    // MARK: - Two-tier Pages round-trip

    @Test("Finder-built two-tier Pages structure round-trips to fully-tagged tree")
    func twoTierPagesRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Hand-built: Research/Sources/paper.md — zero sidecars.
        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: collFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.write(
            "# Paper\n", to: collFolder.appendingPathComponent("paper.md")
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

        // The markdown file at the collection path is preserved.
        #expect(
            FileManager.default.fileExists(
                atPath: collFolder.appendingPathComponent("paper.md").path
            )
        )
    }

    // MARK: - Items side stops at two tiers

    @Test("Items side auto-tags Set + stops at two tiers when Type sidecar is present")
    func itemsSideTwoTiersOnly() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Hand-built: Books/Reading/Q2/buy-milk.md — with an `_itemtype.json`
        // sidecar at depth 0. Items-as-Markdown change: Item-Type identity now
        // comes ONLY from the sidecar — content-sniffing a sidecar-less folder
        // always yields a Page Type. So to exercise the Items-side two-tier
        // auto-tag rule we declare the Type explicitly via its sidecar; the
        // auto-tagger then derives the Set (depth 1) from the parent kind and
        // stops there (no third tier). Pre-Task-4 the Type was inferred from
        // `.json` content with no sidecar.
        let typeFolder = nexus.rootURL.appendingPathComponent("Books", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Reading", isDirectory: true)
        let deepFolder = collFolder.appendingPathComponent("Q2", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deepFolder, withIntermediateDirectories: true
        )
        // Declare the Item Type via its sidecar (the new sole source of
        // Item-Type identity).
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCITEMTYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        )
        try FixtureFiles.write(
            "Buy milk\n", to: deepFolder.appendingPathComponent("buy-milk.md")
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // ItemType sidecar at depth 0 is preserved (auto-tag never overwrites
        // an existing recognized sidecar).
        let itMeta = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: itMeta.path))
        let it = try ItemType.load(from: itMeta)
        #expect(it.id == "01HABCITEMTYPE")

        // ItemCollection sidecar at depth 1 — derived from the parent's
        // declared ItemType kind, NOT from content inference.
        let icMeta = collFolder.appendingPathComponent(
            NexusPaths.itemCollectionSidecarFilename
        )
        #expect(FileManager.default.fileExists(atPath: icMeta.path))

        // No sidecar inside the depth-2 folder — Items side has no third
        // tier (and Pages-side third-tier auto-tagging was removed).
        let depth2ItemColl = deepFolder.appendingPathComponent(
            NexusPaths.itemCollectionSidecarFilename
        )
        #expect(!FileManager.default.fileExists(atPath: depth2ItemColl.path))
    }

    // MARK: - Idempotence

    @Test("running auto-tag twice produces identical disk state")
    func idempotence() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collFolder = nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
        try FileManager.default.createDirectory(
            at: collFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.write(
            "# Paper\n", to: collFolder.appendingPathComponent("paper.md")
        )

        // Pass 1
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let ptMeta = collFolder.deletingLastPathComponent()
            .appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let pcMeta = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let pt1 = try PageType.load(from: ptMeta)
        let pc1 = try PageCollection.load(from: pcMeta)

        // Pass 2
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pt2 = try PageType.load(from: ptMeta)
        let pc2 = try PageCollection.load(from: pcMeta)

        // IDs preserved across passes — sidecars not rewritten.
        #expect(pt1.id == pt2.id)
        #expect(pc1.id == pc2.id)
        #expect(pc1.typeID == pc2.typeID)
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
