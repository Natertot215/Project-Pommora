import Foundation
import GRDB
import Testing

@testable import Pommora

/// Context-delete cascade (Phase 18b): `unlinkTier(contextID:tier:index:)` on the
/// content managers. When a Context (Area / Topic / Project) is deleted, every
/// operational entity that tier-links to it must have that Context's ID removed
/// from the relevant tier array — on disk, in the in-memory cache, and in the
/// SQLite index's `relations` rows.
///
/// High-stakes (mutates user files): every case persists via real CRUD, runs the
/// cascade, then RELOADS from disk to assert the on-disk truth (never trusting the
/// in-memory copy alone). Mirrors the temp-nexus + IndexUpdater harness in the
/// PageContentManager CRUD suites.
///
/// Suite/struct name matches the filename so `-only-testing:PommoraTests/UnlinkTierTests`
/// resolves a non-zero executed count (quirk #18).
@MainActor
@Suite("UnlinkTierTests")
struct UnlinkTierTests {

    // Stable Context IDs reused across cases.
    private let areaA = "ctx_area_A"
    private let areaB = "ctx_area_B"

    // MARK: - Page (Type-root)

    @Test("unlinkTier removes the Context from tier1 of every Type-root Page")
    func pageTypeRootUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        // Two Pages, both tagged tier1 == [areaA, areaB].
        let p1 = try await manager.createPage(name: "Alpha", inCollectionRoot: vault)
        let p2 = try await manager.createPage(name: "Beta", inCollectionRoot: vault)
        try await setPageTier(manager, p1, tier: 1, ids: [areaA, areaB], pageCollection: vault)
        try await setPageTier(manager, p2, tier: 1, ids: [areaA, areaB], pageCollection: vault)

        // Sanity: the index sees both Pages as referencing areaA before the cascade.
        let before = try await IndexQuery(index).incomingContextLinks(targetID: areaA)
        #expect(Set(before.map(\.id)) == [p1.id, p2.id])

        try await manager.unlinkTier(contextID: areaA, tier: 1, index: index)

        // Reload BOTH from disk — assert areaA gone, areaB retained, order preserved.
        let reloaded1 = try PageFile.load(from: p1.url).frontmatter
        let reloaded2 = try PageFile.load(from: p2.url).frontmatter
        #expect(reloaded1.tier1 == [areaB])
        #expect(reloaded2.tier1 == [areaB])
        #expect(manager.pendingError == nil)

        // Index reconciled: no `relations` row (page → areaA, _tier1) remains;
        // the areaB tier row is still present for both Pages.
        #expect(try await tierRelationCount(index, target: areaA, propertyID: ReservedPropertyID.tier1) == 0)
        #expect(try await tierRelationCount(index, target: areaB, propertyID: ReservedPropertyID.tier1) == 2)
    }

    // MARK: - Page (Collection-nested)

    @Test("unlinkTier removes the Context from a Collection-nested Page")
    func pageCollectionNestedUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let coll = try makePageSet(in: nexus, pageCollection: vault, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let page = try await manager.createPage(name: "Nested", in: coll, pageCollection: vault)
        try await setPageTier(manager, page, tier: 1, ids: [areaA], pageCollection: vault, collection: coll)

        try await manager.unlinkTier(contextID: areaA, tier: 1, index: index)

        // Reload from disk — proves the Collection URL derivation in `locatePageFile`.
        let reloaded = try PageFile.load(from: page.url).frontmatter
        #expect(reloaded.tier1.isEmpty)
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: areaA, propertyID: ReservedPropertyID.tier1) == 0)
    }

    // MARK: - Agenda Task

    @Test("unlinkTier removes the Context from tier1 of an AgendaTask")
    func agendaTaskUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let manager = AgendaTaskManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        await manager.loadAll()  // seeds the Tasks singleton + default schema

        let task = AgendaTask(
            id: ULID.generate(), title: "Plan release", icon: nil, description: "",
            dueAt: nil, dueFloating: false, dueAllDay: false, startAt: nil,
            completed: false, completedAt: nil, priority: 0,
            recurrence: nil, alarmOffsets: [], calendarID: nil, eventkitUUID: nil,
            tier1: [areaA, areaB], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(), properties: [:]
        )
        try await manager.createTask(task)

        try await manager.unlinkTier(contextID: areaA, tier: 1, index: index)

        let url = NexusPaths.taskFileURL(forTitle: "Plan release", in: nexus)
        let reloaded = try AgendaTask.load(from: url)
        #expect(reloaded.tier1 == [areaB])
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: areaA, propertyID: ReservedPropertyID.tier1) == 0)
    }

    // MARK: - No-op (unreferenced Context leaves files untouched)

    @Test("unlinkTier for an unreferenced Context is a no-op (no file rewrite)")
    func unreferencedContextIsNoOp() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        // Page references ONLY areaB.
        let page = try await manager.createPage(name: "Untouched", inCollectionRoot: vault)
        try await setPageTier(manager, page, tier: 1, ids: [areaB], pageCollection: vault)

        // Capture the file's modification timestamp + content before the cascade.
        let mtimeBefore = try modificationDate(of: page.url)
        let bytesBefore = try Data(contentsOf: page.url)

        // Unlink a Context this Page never referenced.
        try await manager.unlinkTier(contextID: areaA, tier: 1, index: index)

        // tier1 unchanged; file not rewritten (identical bytes + mtime).
        let reloaded = try PageFile.load(from: page.url).frontmatter
        #expect(reloaded.tier1 == [areaB])
        #expect(try Data(contentsOf: page.url) == bytesBefore)
        #expect(try modificationDate(of: page.url) == mtimeBefore)
        #expect(manager.pendingError == nil)
    }

    // MARK: - Invalid tier (guard)

    @Test("unlinkTier with an out-of-range tier is a guarded no-op")
    func invalidTierIsNoOp() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let page = try await manager.createPage(name: "Solo", inCollectionRoot: vault)
        try await setPageTier(manager, page, tier: 1, ids: [areaA], pageCollection: vault)
        let bytesBefore = try Data(contentsOf: page.url)

        // tier 4 has no `_tierN` mapping → ReservedPropertyID.tierPropertyID returns
        // nil → early return; nothing is touched.
        try await manager.unlinkTier(contextID: areaA, tier: 4, index: index)

        #expect(try Data(contentsOf: page.url) == bytesBefore)
        #expect(manager.pendingError == nil)
    }

    // MARK: - Fixtures

    /// PageCollection folder + sidecar on disk + page_types row in the index (FK parent
    /// for subsequent `upsertPage`).
    private func makeVault(in nexus: Nexus, index: PommoraIndex) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))
        try IndexUpdater(index).upsertPageCollection(vault)
        return vault
    }

    private func makePageSet(in nexus: Nexus, pageCollection: PageCollection, index: PommoraIndex) throws -> PageSet {
        let folder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: "C", folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        try IndexUpdater(index).upsertPageCollection(coll)
        return coll
    }

    /// Sets a Page's tier array through the production write path
    /// (`updatePageProperty` → `setRelationIDs` adapter + index re-upsert).
    private func setPageTier(
        _ manager: PageContentManager, _ page: PageMeta, tier: Int, ids: [String],
        pageCollection: PageCollection, collection: PageSet? = nil
    ) async throws {
        let propID = ReservedPropertyID.tierPropertyID(forTier: tier)!
        try await manager.updatePageProperty(
            page, propertyID: propID, newValue: .relation(ids), pageCollection: pageCollection, collection: collection
        )
    }

    // MARK: - Index assertion

    /// Count of `relations` rows pointing at `target` via the given tier property.
    /// Hoists String params to locals before the @Sendable read closure (quirk #5).
    private func tierRelationCount(_ index: PommoraIndex, target: String, propertyID: String) async throws -> Int {
        let target = target
        let propertyID = propertyID
        return try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM context_links WHERE target_id = ? AND property_id = ?",
                arguments: [target, propertyID]
            ) ?? -1
        }
    }

    private func modificationDate(of url: URL) throws -> Date {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? Date.distantPast
    }
}
