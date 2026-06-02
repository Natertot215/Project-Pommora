import Foundation
import Testing
import Yams

@testable import Pommora

/// Task 8 — launch auto-tag self-heals co-located orphan sidecars.
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` runs `cleanupLegacyOrphans` per
/// top-level folder, between `walkDepth1` and the `Class`-stamp pass. This
/// deletes the 12 inert depth-0 `_pagecollection.json` strays (dangling shared
/// `type_id`, from an old wrapper auto-tag→unwrap) that sit alongside a real
/// `_itemtype.json`. The deletion is safe: `IndexBuilder` reads
/// `_pagecollection.json` only at depth 1, so a depth-0 stray is inert; the
/// authoritative Type sidecar (`recognizedSidecarsAt.first`) is kept and every
/// other co-located per-kind sidecar is removed.
///
/// These tests drive the public auto-tag entry over a temp nexus and assert the
/// resulting on-disk state — stray gone, Type sidecar survives, clean folders
/// untouched, idempotent — plus the cleanup-before-stamp ordering interaction.
@MainActor
@Suite("AutoTagOrphanCleanup")
struct AutoTagOrphanCleanupTests {

    // MARK: - Helpers

    private func writeItemTypeSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCITEMTYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        )
    }

    private func writePageTypeSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCPAGETYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
    }

    /// Writes a depth-0 stray `_pagecollection.json` — the inert orphan shape
    /// (dangling `type_id` pointing at nothing reachable here). Auto-tag must
    /// delete it because it is co-located with a real Type sidecar.
    private func writeStrayPageCollectionSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCSTRAYCOLL","type_id":"01HDANGLING","modified_at":"2026-05-28T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Lenient `Class`-key read — mirrors production's `readClassStamp`.
    private func classValue(at url: URL) throws -> String? {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        guard !fm.isEmpty, case .mapping(let m)? = try Yams.compose(yaml: fm) else {
            return nil
        }
        return m[Node("Class")]?.string
    }

    // MARK: - 1. Stray deleted, Item Type survives

    @Test("co-located stray _pagecollection.json beside _itemtype.json is deleted, Type survives")
    func strayDeletedItemTypeSurvives() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Metrics/ holds the real `_itemtype.json` + an inert depth-0 stray.
        let typeFolder = nexus.rootURL.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)
        try writeStrayPageCollectionSidecar(at: typeFolder)

        let itMeta = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        // Pre-condition: both present.
        #expect(exists(itMeta))
        #expect(exists(strayMeta))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Stray gone; the authoritative Type sidecar survives unchanged.
        #expect(!exists(strayMeta))
        #expect(exists(itMeta))
        let it = try ItemType.load(from: itMeta)
        #expect(it.id == "01HABCITEMTYPE")
    }

    // MARK: - 2. Clean folder untouched (Item Type)

    @Test("clean _itemtype.json-only folder is left untouched")
    func cleanItemTypeFolderUntouched() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        let itMeta = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Type sidecar still present; no stray was conjured.
        #expect(exists(itMeta))
        #expect(!exists(strayMeta))
        let it = try ItemType.load(from: itMeta)
        #expect(it.id == "01HABCITEMTYPE")
    }

    // MARK: - 3. Clean folder untouched (Page Type)

    @Test("clean _pagetype.json-only folder is left untouched")
    func cleanPageTypeFolderUntouched() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageTypeSidecar(at: typeFolder)

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let pcMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(exists(ptMeta))
        #expect(!exists(pcMeta))
        let pt = try PageType.load(from: ptMeta)
        #expect(pt.id == "01HABCPAGETYPE")
    }

    // MARK: - 4. Idempotent

    @Test("running auto-tag twice produces no further change and never crashes")
    func idempotentSecondRun() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)
        try writeStrayPageCollectionSidecar(at: typeFolder)

        let itMeta = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        #expect(!exists(strayMeta))
        #expect(exists(itMeta))
        let firstRunSidecar = try Data(contentsOf: itMeta)

        // Second run: stray still gone, Type sidecar byte-identical, no crash.
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        #expect(!exists(strayMeta))
        #expect(exists(itMeta))
        let secondRunSidecar = try Data(contentsOf: itMeta)
        #expect(firstRunSidecar == secondRunSidecar)
    }

    // MARK: - 5. Cleanup-before-stamp ordering — .md stamps `Class: item`, not `page`

    @Test("after stray removal from an _itemtype.json folder, the .md stamps Class: item")
    func cleanupBeforeStampStampsItem() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // An Item Type folder polluted by a depth-0 stray `_pagecollection.json`,
        // holding a stampless `.md`. Cleanup must remove the stray BEFORE the
        // stamp pass so the folder reads unambiguously as an Item Type and the
        // file is stamped `Class: item` (the ordering guarantee).
        let typeFolder = nexus.rootURL.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)
        try writeStrayPageCollectionSidecar(at: typeFolder)

        let file = typeFolder.appendingPathComponent("entry.md")
        try FixtureFiles.write(
            """
            ---
            note: to-self
            ---
            Body stays.
            """, to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Stray gone, and the file is stamped item (proving cleanup ran first).
        #expect(!exists(typeFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)))
        #expect(try classValue(at: file) == "item")
    }

    // MARK: - 6. Tier-1 boundary — stray beside _pagetype.json deleted, stamps `Class: page`

    @Test("co-located stray beside _pagetype.json is deleted, Type survives, .md stamps Class: page")
    func tier1StrayDeletedStampsPage() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // The tier-1 dual the plan flagged: `_pagetype.json` + a stray
        // `_pagecollection.json` at depth 0. `recognizedSidecarsAt.first`
        // resolves `.pageType`, so cleanup keeps the Page Type and deletes the
        // stray; the stamp pass then stamps `Class: page` — correct, not a
        // mis-stamp. Documented as in-scope and handled safely (not asserted
        // out of scope).
        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageTypeSidecar(at: typeFolder)
        try writeStrayPageCollectionSidecar(at: typeFolder)

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        let file = typeFolder.appendingPathComponent("page.md")
        try FixtureFiles.write("# Heading\n", to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(!exists(strayMeta))
        #expect(exists(ptMeta))
        let pt = try PageType.load(from: ptMeta)
        #expect(pt.id == "01HABCPAGETYPE")
        #expect(try classValue(at: file) == "page")
    }

    // MARK: - 7. Legitimate depth-1 collection sidecar is spared

    @Test("a legitimate depth-1 _pagecollection.json inside a Page Type is NOT deleted")
    func legitimateDepth1CollectionSpared() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Notes/Sources/ — a real collection: depth-0 `_pagetype.json`, depth-1
        // `_pagecollection.json`. Cleanup must spare the depth-1 sidecar (it is
        // the sole recognized sidecar in its own folder).
        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        try writePageTypeSidecar(at: typeFolder)
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCREALCOLL","type_id":"01HABCPAGETYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )

        let pcMeta = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        #expect(exists(pcMeta))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // The legitimate depth-1 collection sidecar survives.
        #expect(exists(pcMeta))
        let pc = try PageCollection.load(from: pcMeta)
        #expect(pc.id == "01HABCREALCOLL")
    }
}
