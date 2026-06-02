import Foundation
import GRDB
import Testing

@testable import Pommora

/// Launch-path integration tests — the seam the Task-10c review found UNCOVERED.
///
/// The two prior half-tests each exercised ONE side of the migration → rebuild
/// join in isolation (`NexusManagerIndexTests.forceRebuildRepopulatesCurrentIndex`
/// hardcodes `forceRebuild: true`; `ItemMarkdownTransitionTests`
/// `migratedItemIndexedSameLaunch` calls `IndexBuilder.populate` directly). A
/// dropped flag in the real launch wiring left BOTH green. These tests drive the
/// actual `NexusManager` launch seam — `runAdoptionIfNeeded` →
/// `autoTagMissingSidecars` → `runFormatMigration` → `openIndex(forceRebuild:)`,
/// the exact tail that `openExisting` / `openPicked` run (minus the modal
/// bookmark/NSOpenPanel work guarded out per quirk #16) — and assert:
///   (a) the DECLINE path STILL converts + indexes a legacy `.json` Item
///       (locked decision #8 — the migration is NOT consent-gated);
///   (b) the migratedItems → forceRebuild → repopulate join works end-to-end
///       (a dropped flag would fail this);
///   (c) a `.unsorted` relocation forces a same-launch rebuild (SHOULD-FIX 3).
@MainActor
@Suite("NexusManagerLaunchIntegration")
struct NexusManagerLaunchIntegrationTests {

    // MARK: - Fixture helpers

    /// A pre-initialized nexus root with `.nexus/nexus.json` written.
    private func makeInitializedNexusRoot() throws -> (root: URL, nexus: Nexus) {
        let nexus = try TempNexus.make()
        let identity = NexusIdentity(id: nexus.id)
        try identity.save(
            to: nexus.rootURL.appendingPathComponent(".nexus/nexus.json", isDirectory: false))
        return (nexus.rootURL, nexus)
    }

    /// An Item Type folder carrying a current-schema `_itemtype.json` (so
    /// PropertyIDMigration is a no-op and this drives format-conversion only).
    @discardableResult
    private func makeItemType(in root: URL, title: String) throws -> URL {
        let folder = root.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "id": "01HITEMTYPE\(UUID().uuidString.prefix(6))",
            "schema_version": 2,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": [],
            "views": [],
        ]
        try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            .write(
                to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename),
                options: [.atomic])
        return folder
    }

    /// Writes a legacy `.json` Item (the pre-conversion shape) via the production
    /// JSON writer.
    @discardableResult
    private func writeLegacyJSONItem(
        title: String, id: String, in folder: URL, description: String = ""
    ) throws -> URL {
        let now = Date()
        let item = Item(
            id: id, title: title, icon: nil, description: description,
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: now, modifiedAt: now)
        let url = folder.appendingPathComponent("\(title).json", isDirectory: false)
        try AtomicJSON.write(item, to: url)
        return url
    }

    /// A legacy `_vault.json` folder — triggers an `inPlaceRename`, so
    /// `plan.hasAnythingToAdopt == true` and the adoption preview is presented
    /// (giving the test a real consent gate to DECLINE).
    private func makeLegacyVaultFolder(in root: URL, title: String) throws {
        let folder = root.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"id":"01HLEGACYVAULT","title":"Legacy","modified_at":"2026-05-01T00:00:00Z"}"#.utf8)
            .write(to: folder.appendingPathComponent("_vault.json", isDirectory: false))
    }

    private func itemCount(_ manager: NexusManager, id: String) async throws -> Int {
        try await #require(manager.currentIndex).dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE id = ?", arguments: [id]) ?? -1
        }
    }

    /// Drives the post-bookmark launch tail exactly as `openExisting` /
    /// `openPicked` do, awaiting the adoption-preview continuation with `confirm`
    /// when a preview is expected. `expectsPreview` is computed by the caller from
    /// the same scan logic `runAdoptionIfNeeded` uses, so the resolve is
    /// deterministic (no racy poll-or-not).
    ///
    /// THIS IS A MIRROR of the `openExisting` / `openPicked` launch tail
    /// (`NexusManager.swift`), NOT a call into it. The real tail is gated behind a
    /// security-scoped-bookmark resolve (`NexusBookmark.startAccessing`) and an
    /// `NSOpenPanel` fallback that the XCTest host cannot satisfy without a modal
    /// (quirk #16): a plain temp URL has no security scope, so `startAccessing`
    /// returns `false` and the real `openExisting` falls into `pickNexus()` →
    /// `NSOpenPanel`. So this re-runs the SAME post-bookmark steps in the SAME
    /// order — `runAdoptionIfNeeded` → `autoTagMissingSidecars` →
    /// `runFormatMigration` → `openIndex(forceRebuild: migrated || relocated)`.
    /// LOAD-BEARING: if `openExisting` / `openPicked` ever re-order these steps,
    /// re-bury the unconditional `runFormatMigration` inside the consent gate, or
    /// change how the migrate/relocate flags feed `forceRebuild`, this mirror MUST
    /// be updated in lockstep or it will silently drift from production.
    private func runLaunchTail(
        _ manager: NexusManager, at root: URL, nexus: Nexus,
        confirm: Bool, expectsPreview: Bool
    ) async {
        // `runAdoptionIfNeeded` suspends on `presentAdoptionPreview` only when a
        // preview is warranted. Run it concurrently; if a preview is expected,
        // spin until the sheet state is published, then resolve the continuation.
        async let adoption: Void = manager.runAdoptionIfNeeded(at: root)
        if expectsPreview {
            while manager.pendingAdoption == nil {
                await Task.yield()
            }
            manager.resolveAdoption(confirm)
        }
        await adoption

        let relocated = NexusAdopter.autoTagMissingSidecars(at: root)
        let migrated = manager.runFormatMigration(at: root)
        await manager.openIndex(for: nexus, forceRebuild: migrated || relocated)
    }

    // MARK: - (a) Decline still runs the migration (locked decision #8)

    @Test("declining the adoption preview STILL converts + indexes a legacy .json Item")
    func declineStillMigratesAndIndexes() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A legacy `_vault.json` folder forces the adoption preview (so we can
        // decline it). Independently, an Item Type holds a legacy `.json` Item the
        // format migration must convert REGARDLESS of the decline.
        try makeLegacyVaultFolder(in: root, title: "OldNotes")
        let itemFolder = try makeItemType(in: root, title: "Bookmarks")
        let jsonURL = try writeLegacyJSONItem(
            title: "Swift", id: "01HDECLINEITEM", in: itemFolder, description: "body")

        let manager = NexusManager()
        await runLaunchTail(
            manager, at: root, nexus: nexus, confirm: false, expectsPreview: true)

        // Decline did NOT skip the format migration: the `.json` became `.md`...
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(Filesystem.fileExists(at: NexusPaths.itemFileURL(forTitle: "Swift", in: itemFolder)))
        // ...and is in the index on THIS launch (forceRebuild fired off the
        // migration signal even though adoption was declined).
        #expect(try await itemCount(manager, id: "01HDECLINEITEM") == 1)
    }

    // MARK: - (b) migratedItems → forceRebuild → repopulate join (confirm path)

    @Test("the migration → forceRebuild → repopulate join indexes a converted Item same-launch")
    func migrationForceRebuildJoinIndexesSameLaunch() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // No adoption work → no preview; the only same-launch-visibility driver is
        // the format-migration signal flowing into forceRebuild.
        let itemFolder = try makeItemType(in: root, title: "Bookmarks")

        // Build + STAMP a CURRENT-version index BEFORE the legacy `.json` exists
        // (mirrors (c)'s pre-stamp: `PommoraIndex.open` → `IndexBuilder.populate`
        // when `needsRebuild` → `markSchemaVersionCurrent()`). The Item Type folder
        // is present but holds NO `.md` Item yet, so the stamped index is empty of
        // `01HJOINITEM` and the launch-tail `openIndex` will see `needsRebuild ==
        // false`. This is what makes the assertion below GENUINE: with a current
        // index already on disk, the converted Item can ONLY reach the index via
        // the `migrated` → `forceRebuild` repopulate. A dropped `migrated` flag (or
        // `forceRebuild` hardcoded `false`) leaves `01HJOINITEM` absent → fails.
        // (Without this pre-stamp the launch-tail `open` hits a FRESH db with
        // `needsRebuild == true` and rebuilds REGARDLESS of `migrated` — a
        // tautology that passed even with the regression.)
        let manager = NexusManager()
        let (idx, needsRebuild) = try PommoraIndex.open(at: root)
        manager.currentIndex = idx
        if needsRebuild { try await IndexBuilder.populate(index: idx, from: nexus) }
        try idx.markSchemaVersionCurrent()
        #expect(try await itemCount(manager, id: "01HJOINITEM") == 0)

        // NOW write the legacy `.json` Item — the launch-tail format migration
        // converts it to `.md`; only `forceRebuild: migrated` can index it.
        try writeLegacyJSONItem(
            title: "Linker", id: "01HJOINITEM", in: itemFolder, description: "x")

        await runLaunchTail(
            manager, at: root, nexus: nexus, confirm: true, expectsPreview: false)

        // The converted Item is in the index on the same launch — the join held.
        // (Against the pre-stamped CURRENT-version index, a dropped `migrated` flag
        // would leave this 0 — the regression the prior half-tests missed.)
        #expect(try await itemCount(manager, id: "01HJOINITEM") == 1)
    }

    // MARK: - (c) a .unsorted relocation forces a same-launch rebuild (SHOULD-FIX 3)

    @Test("a .unsorted relocation drops the stale index row on the SAME launch")
    func unsortedRelocationForcesSameLaunchRebuild() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // An Item Type with one real `.md` Item (Keeper), AND a Class-disagreeing
        // `.md` (Mismatch, stamped `Class: page` inside an Item Type). IndexBuilder
        // indexes BOTH as items (it reads every `.md` leniently under an Item Type,
        // Class is non-authoritative), so the mismatch starts with a real index row.
        let itemFolder = try makeItemType(in: root, title: "Bookmarks")
        let keeper = Item(
            id: "01HKEEPER", title: "Keeper", icon: nil, description: "stays",
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(), modifiedAt: Date())
        try keeper.save(to: NexusPaths.itemFileURL(forTitle: "Keeper", in: itemFolder))
        // A `Class: page` file inside an Item Type folder → stamp-disagreement →
        // relocated to `.unsorted` by autoTagMissingSidecars.
        let mismatch = itemFolder.appendingPathComponent("Mismatch.md", isDirectory: false)
        try Data("---\nClass: page\nid: 01HMISMATCH\n---\nMisplaced.\n".utf8)
            .write(to: mismatch, options: [.atomic])

        // Build + STAMP a current-version index that contains BOTH items (so a
        // missing forceRebuild would leave the relocated id stale).
        let manager = NexusManager()
        let (idx, needsRebuild) = try PommoraIndex.open(at: root)
        manager.currentIndex = idx
        if needsRebuild { try await IndexBuilder.populate(index: idx, from: nexus) }
        try idx.markSchemaVersionCurrent()
        #expect(try await itemCount(manager, id: "01HMISMATCH") == 1)

        // Launch tail: no adoption preview; autoTag relocates the mismatch, which
        // forces a same-launch rebuild that drops the stale id row.
        await runLaunchTail(
            manager, at: root, nexus: nexus, confirm: true, expectsPreview: false)

        #expect(
            Filesystem.fileExists(at: NexusPaths.itemFileURL(forTitle: "Keeper", in: itemFolder)))
        #expect(try await itemCount(manager, id: "01HKEEPER") == 1)
        // The relocated file's stale row is GONE this launch (rebuild fired).
        #expect(try await itemCount(manager, id: "01HMISMATCH") == 0)
    }
}
