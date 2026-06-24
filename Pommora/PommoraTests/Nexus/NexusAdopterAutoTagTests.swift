import Foundation
import Testing

@testable import Pommora

/// Silent auto-sidecar-tagging tests.
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` walks the Nexus root three
/// levels deep on every launch and writes missing per-kind sidecars so
/// Finder-built structure (Types + Collections + Sets) is first-class without
/// any user-facing prompt. These tests cover:
///   - Two-tier round-trip (Type / Collection auto-tagged)
///   - Three-tier round-trip (Set auto-tagged; depth-3+ stays sidecar-less)
///   - Idempotence (second pass produces identical disk state)
///   - Exclusion rules (dotfile + underscore prefixes + FolderFilter left alone)
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

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: ptMeta.path))
        let pt = try PageType.load(from: ptMeta)
        #expect(!pt.id.isEmpty)
        #expect(pt.title == "Research")

        let pcMeta = collFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename
        )
        #expect(FileManager.default.fileExists(atPath: pcMeta.path))
        let pc = try PageSet.load(from: pcMeta)
        #expect(!pc.id.isEmpty)
        #expect(pc.parentID == pt.id)
        #expect(pc.title == "Sources")

        // The markdown file at the collection path is preserved.
        #expect(
            FileManager.default.fileExists(
                atPath: collFolder.appendingPathComponent("paper.md").path
            )
        )
    }

    // MARK: - Three-tier Pages round-trip

    @Test("three-tier structure auto-tags Type + Collection + Set; depth-3 also gets a Set sidecar")
    func threeTierRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Hand-built: Research/Sources/Drafts/Deep/note.md — zero sidecars.
        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        let setFolder = collFolder.appendingPathComponent("Drafts", isDirectory: true)
        let deepFolder = setFolder.appendingPathComponent("Deep", isDirectory: true)
        try FileManager.default.createDirectory(
            at: deepFolder, withIntermediateDirectories: true
        )
        try FixtureFiles.write(
            "# Note\n", to: deepFolder.appendingPathComponent("note.md")
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // All three sidecars exist with correct parent-id chaining.
        let pt = try PageType.load(
            from: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
        let pc = try PageSet.load(
            from: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )
        let ps = try PageSet.load(
            from: setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        )
        #expect(pc.parentID == pt.id)
        #expect(ps.parentID == pc.id)
        #expect(ps.title == "Drafts")

        // Depth-3 folder also gets a _pageset.json, parented to the depth-2 Set.
        let deepSet = try PageSet.load(
            from: deepFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        )
        #expect(deepSet.parentID == ps.id)
        #expect(deepSet.title == "Deep")
    }

    @Test("an existing _pageset.json is not overwritten on re-run")
    func existingSetSidecarPreserved() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let setFolder = nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Drafts")
        try FileManager.default.createDirectory(
            at: setFolder, withIntermediateDirectories: true
        )

        // Pass 1 tags all three tiers; pass 2 must leave the Set id alone.
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let psMeta = setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let ps1 = try PageSet.load(from: psMeta)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let ps2 = try PageSet.load(from: psMeta)

        #expect(ps1.id == ps2.id)
        #expect(ps1.parentID == ps2.parentID)
    }

    @Test("a FolderFilter-excluded folder at depth 2 is untouched")
    func skipsExcludedDepth2() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collFolder = nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
        let excluded = collFolder.appendingPathComponent("Private", isDirectory: true)
        let included = collFolder.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)

        let filter = FolderFilter(
            nexusRoot: nexus.rootURL, excludedFolders: ["Research/Sources/Private"]
        )
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL, filter: filter)

        // Sibling Set gets its sidecar; the excluded folder gets nothing.
        #expect(
            FileManager.default.fileExists(
                atPath: included.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: excluded.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path
            )
        )
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

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let ptMeta = collFolder.deletingLastPathComponent()
            .appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let pcMeta = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let pt1 = try PageType.load(from: ptMeta)
        let pc1 = try PageSet.load(from: pcMeta)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pt2 = try PageType.load(from: ptMeta)
        let pc2 = try PageSet.load(from: pcMeta)

        // IDs preserved across passes — sidecars not rewritten.
        #expect(pt1.id == pt2.id)
        #expect(pc1.id == pc2.id)
        #expect(pc1.parentID == pc2.parentID)
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
        let pc = try PageSet.load(from: pcMeta)
        #expect(pc.parentID == knownID)
    }

    // MARK: - Arbitrary-depth recursion (task 1.6)

    @Test("Type/A/B/C/page.md — A gets _pagecollection, B and C get _pageset, page stays in C")
    func deepRecursionABC() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Vault", isDirectory: true)
        let aFolder = typeFolder.appendingPathComponent("A", isDirectory: true)
        let bFolder = aFolder.appendingPathComponent("B", isDirectory: true)
        let cFolder = bFolder.appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: cFolder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Page\n", to: cFolder.appendingPathComponent("page.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let pt = try PageType.load(
            from: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
        let pa = try PageSet.load(
            from: aFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )
        let pb = try PageSet.load(
            from: bFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        )
        let pc = try PageSet.load(
            from: cFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        )

        #expect(pa.parentID == pt.id)
        #expect(pb.parentID == pa.id)
        #expect(pc.parentID == pb.id)
        #expect(FileManager.default.fileExists(atPath: cFolder.appendingPathComponent("page.md").path))
    }

    @Test("deep recursion is idempotent — second pass is a no-op")
    func deepRecursionIdempotent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Vault", isDirectory: true)
        let cFolder = typeFolder
            .appendingPathComponent("A", isDirectory: true)
            .appendingPathComponent("B", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: cFolder, withIntermediateDirectories: true)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pcMeta = cFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let pc1 = try PageSet.load(from: pcMeta)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let pc2 = try PageSet.load(from: pcMeta)

        #expect(pc1.id == pc2.id)
        #expect(pc1.parentID == pc2.parentID)
    }

    @Test("Finder-duplicate at depth — Set nested inside another Set gets fresh ULID on load")
    func finderDuplicateDeepSet() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak typeManager] in typeManager?.types ?? [] }
        typeManager.pageSetManager = setManager

        await typeManager.loadAll()
        try await typeManager.createPageType(name: "Vault", icon: nil)
        let pageType = typeManager.types.first!
        try await typeManager.createPageCollection(name: "A", inPageType: pageType)
        let collection = typeManager.pageCollections(in: pageType).first!
        let parentSet = try await setManager.createPageSet(name: "B", in: collection)
        let deepSet = try await setManager.createPageSet(name: "C", in: parentSet)

        // Finder-duplicate the deep (depth-3) Set folder next to its sibling.
        let copyFolder = parentSet.folderURL.appendingPathComponent("C 2", isDirectory: true)
        try FileManager.default.copyItem(at: deepSet.folderURL, to: copyFolder)

        await setManager.loadAll(types: typeManager.types)

        let deepSets = setManager.pageSets(in: parentSet)
        #expect(deepSets.count == 2)
        #expect(Set(deepSets.map(\.id)).count == 2)
        #expect(deepSets.filter { $0.id == deepSet.id }.count == 1)
    }
}
