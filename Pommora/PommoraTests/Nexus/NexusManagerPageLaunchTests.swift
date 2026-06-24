//
//  NexusManagerPageLaunchTests.swift
//  PommoraTests
//
//  Page-side launch-tail integration coverage (PagesV2 P8) — replaces the
//  item-side `NexusManagerLaunchIntegrationTests` deleted in `caaae19`.
//
//  THIS IS A MIRROR of the `openExisting` / `openPicked` launch tail
//  (`NexusManager.runLaunchMigrations` → `openIndex`), NOT a call into it.
//  The real tail is gated behind a security-scoped-bookmark resolve
//  (`NexusBookmark.startAccessing`) and an `NSOpenPanel` fallback that the
//  XCTest host cannot satisfy without a modal (quirk #16): a plain temp URL
//  has no security scope, so the real `openExisting` falls into `pickNexus()`
//  → `NSOpenPanel`. So this re-runs the SAME post-bookmark steps in the SAME
//  order — `runAdoptionIfNeeded` → `autoTagMissingSidecars` (with the loaded
//  `FolderFilter`) → `openIndex(for:)`. LOAD-BEARING: if `runLaunchMigrations`
//  ever re-orders these steps or `openIndex` regains a rebuild flag, this
//  mirror MUST be updated in lockstep or it will silently drift from
//  production.
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("NexusManagerPageLaunchTests")
struct NexusManagerPageLaunchTests {

    // MARK: - Fixture helpers

    /// A pre-initialized nexus root with `.nexus/nexus.json` written.
    private func makeInitializedNexusRoot() throws -> (root: URL, nexus: Nexus) {
        let nexus = try TempNexus.make()
        let identity = NexusIdentity(id: nexus.id)
        try identity.save(
            to: nexus.rootURL.appendingPathComponent(".nexus/nexus.json", isDirectory: false))
        return (nexus.rootURL, nexus)
    }

    /// A Finder-built vault: a bare folder (no sidecar) holding one
    /// frontmatter-less `.md` page. Never touched by CRUD.
    private func makeFinderVault(
        in root: URL, folder: String, page: String
    ) throws -> URL {
        let vault = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FixtureFiles.write("# \(page)\n", to: vault.appendingPathComponent("\(page).md"))
        return vault
    }

    /// Drives the post-bookmark launch tail exactly as `runLaunchMigrations` +
    /// `openIndex` do, awaiting the adoption-preview continuation when a
    /// preview is expected. `expectsPreview` is computed by the caller from the
    /// same scan rules `runAdoptionIfNeeded` uses (fresh sidecars never trip
    /// the gate; legacy `_vault.json` renames do), so the resolve is
    /// deterministic — no racy poll-or-not.
    private func runLaunchTail(
        _ manager: NexusManager, at root: URL, nexus: Nexus,
        confirm: Bool, expectsPreview: Bool
    ) async {
        // `runAdoptionIfNeeded` suspends on the preview continuation only when
        // a preview is warranted. Run it concurrently; if a preview is
        // expected, spin until the sheet state publishes, then resolve.
        async let adoption: Void = manager.runAdoptionIfNeeded(at: root)
        if expectsPreview {
            while manager.pendingAdoption == nil {
                await Task.yield()
            }
            manager.resolveAdoption(confirm)
        }
        await adoption

        let tempNexus = Nexus(id: "", rootURL: root)
        let filter = FolderFilter.load(for: tempNexus)
        NexusAdopter.autoTagMissingSidecars(at: root, filter: filter)
        await manager.openIndex(for: nexus)
    }

    private func pageCount(_ manager: NexusManager, title: String) async throws -> Int {
        try await #require(manager.currentIndex).dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM pages WHERE title = ?", arguments: [title]) ?? -1
        }
    }

    // MARK: - Finder-built vault + page indexed on launch open

    @Test("a page dropped into a Finder-built vault (never CRUD-created) is indexed on launch open")
    func finderDroppedPageIndexedOnLaunchOpen() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let vault = try makeFinderVault(in: root, folder: "Notes", page: "Dropped")

        let manager = NexusManager()
        // A sidecar-less fresh folder is excluded from `hasAnythingToAdopt` —
        // the launch is silent, no consent gate.
        await runLaunchTail(
            manager, at: root, nexus: nexus, confirm: true, expectsPreview: false)

        // autoTag stamped the Finder folder as a vault...
        #expect(
            FileManager.default.fileExists(
                atPath: vault.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename).path))
        // ...and the frontmatter-less page is in the index on THIS launch
        // (`IndexBuilder` reads members via `PageFile.loadLenient`).
        #expect(try await pageCount(manager, title: "Dropped") == 1)
    }

    // MARK: - Decline path still auto-tags + indexes

    @Test("declining the adoption preview still auto-tags + indexes the Finder page")
    func declineStillAutoTagsAndIndexesPage() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A legacy `_vault.json` folder forces the adoption preview (an
        // `inPlaceRename` trips `hasAnythingToAdopt`), giving the test a real
        // consent gate to DECLINE. Independently, a Finder-built folder holds
        // the page the silent tail must still pick up.
        let legacy = root.appendingPathComponent("OldNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HLEGACYVAULT","title":"Legacy","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: legacy.appendingPathComponent("_vault.json"))
        let vault = try makeFinderVault(in: root, folder: "Inbox", page: "Dropped")

        let manager = NexusManager()
        await runLaunchTail(
            manager, at: root, nexus: nexus, confirm: false, expectsPreview: true)

        // The decline gates ONLY the adoption apply — `autoTagMissingSidecars`
        // and `openIndex` run unconditionally after it.
        #expect(
            FileManager.default.fileExists(
                atPath: vault.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename).path))
        #expect(try await pageCount(manager, title: "Dropped") == 1)
    }
}
