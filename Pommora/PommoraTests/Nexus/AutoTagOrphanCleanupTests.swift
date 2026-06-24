import Foundation
import Testing
import Yams

@testable import Pommora

/// Task 8 — launch auto-tag self-heals co-located orphan sidecars.
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` runs `cleanupLegacyOrphans` per
/// top-level folder after `walkDepth1`. This deletes inert depth-0
/// `_pagecollection.json` strays (dangling shared `type_id`, from an old
/// wrapper auto-tag→unwrap) that sit alongside a real Type sidecar. The
/// deletion is safe: `IndexBuilder` reads `_pagecollection.json` only at
/// depth 1, so a depth-0 stray is inert; the authoritative Type sidecar
/// (`recognizedSidecarsAt.first`) is kept and every other co-located per-kind
/// sidecar is removed.
///
/// These tests drive the public auto-tag entry over a temp nexus and assert the
/// resulting on-disk state — stray gone, Type sidecar survives, clean folders
/// untouched, idempotent. PagesV2: the retired `Class`-stamp pass must NOT
/// stamp anything (pinned below).
@MainActor
@Suite("AutoTagOrphanCleanup")
struct AutoTagOrphanCleanupTests {

    // MARK: - Helpers

    private func writePageCollectionSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCPAGETYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
    }

    /// Writes a depth-0 stray `_pagecollection.json` — the inert orphan shape
    /// (dangling `type_id` pointing at nothing reachable here). Auto-tag must
    /// delete it because it is co-located with a real Type sidecar.
    private func writeStrayPageSetSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCSTRAYCOLL","type_id":"01HDANGLING","modified_at":"2026-05-28T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Lenient `Class`-key read — used to pin that the retired stamp pass
    /// writes NOTHING.
    private func classValue(at url: URL) throws -> String? {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        guard !fm.isEmpty, case .mapping(let m)? = try Yams.compose(yaml: fm) else {
            return nil
        }
        return m[Node("Class")]?.string
    }

    // MARK: - 1. Clean folder untouched (Page Type)

    @Test("clean _pagetype.json-only folder is left untouched")
    func cleanPageCollectionFolderUntouched() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageCollectionSidecar(at: typeFolder)

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let pcMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(exists(ptMeta))
        #expect(!exists(pcMeta))
        let pt = try PageCollection.load(from: ptMeta)
        #expect(pt.id == "01HABCPAGETYPE")
    }

    // MARK: - 2. Stray deleted, Type survives; no Class stamp written

    @Test("co-located stray beside _pagetype.json is deleted, Type survives, .md gets NO Class stamp")
    func strayDeletedNoClassStamp() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // `_pagetype.json` + a stray `_pagecollection.json` at depth 0.
        // `recognizedSidecarsAt.first` resolves `.pageType`, so cleanup keeps
        // the Page Type and deletes the stray. The Class-stamp pass is retired
        // (PagesV2): the loose .md must stay byte-stamp-free.
        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageCollectionSidecar(at: typeFolder)
        try writeStrayPageSetSidecar(at: typeFolder)

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        let file = typeFolder.appendingPathComponent("page.md")
        try FixtureFiles.write("# Heading\n", to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(!exists(strayMeta))
        #expect(exists(ptMeta))
        let pt = try PageCollection.load(from: ptMeta)
        #expect(pt.id == "01HABCPAGETYPE")
        // PagesV2 pin: the retired stamp pass must NOT write a Class key.
        #expect(try classValue(at: file) == nil)
    }

    // MARK: - 3. Idempotent

    @Test("running auto-tag twice produces no further change and never crashes")
    func idempotentSecondRun() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageCollectionSidecar(at: typeFolder)
        try writeStrayPageSetSidecar(at: typeFolder)

        let ptMeta = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let strayMeta = typeFolder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        #expect(!exists(strayMeta))
        #expect(exists(ptMeta))
        let firstRunSidecar = try Data(contentsOf: ptMeta)

        // Second run: stray still gone, Type sidecar byte-identical, no crash.
        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        #expect(!exists(strayMeta))
        #expect(exists(ptMeta))
        let secondRunSidecar = try Data(contentsOf: ptMeta)
        #expect(firstRunSidecar == secondRunSidecar)
    }

    // MARK: - 4. Legitimate depth-1 collection sidecar is spared

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
        try writePageCollectionSidecar(at: typeFolder)
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCREALCOLL","type_id":"01HABCPAGETYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )

        let pcMeta = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        #expect(exists(pcMeta))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // The legitimate depth-1 collection sidecar survives.
        #expect(exists(pcMeta))
        let pc = try PageSet.load(from: pcMeta)
        #expect(pc.id == "01HABCREALCOLL")
    }
}
