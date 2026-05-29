import Foundation
import GRDB
import Testing

@testable import Pommora

/// Context-delete cascade (Phase 18b): `unlinkTier(contextID:tier:index:)` on the
/// four content managers. When a Context (Space / Topic / Project) is deleted,
/// every operational entity that tier-links to it must have that Context's ID
/// removed from the relevant tier array — on disk, in the in-memory cache, and in
/// the SQLite index's `relations` rows.
///
/// High-stakes (mutates user files): every case persists via real CRUD, runs the
/// cascade, then RELOADS from disk to assert the on-disk truth (never trusting the
/// in-memory copy alone). Mirrors the temp-nexus + IndexUpdater harness in the
/// PageContentManager / ItemContentManager CRUD suites.
///
/// Suite/struct name matches the filename so `-only-testing:PommoraTests/UnlinkTierTests`
/// resolves a non-zero executed count (quirk #18).
@MainActor
@Suite("UnlinkTierTests")
struct UnlinkTierTests {

    // Stable Context IDs reused across cases.
    private let spaceA = "ctx_space_A"
    private let spaceB = "ctx_space_B"

    // MARK: - Page (Type-root)

    @Test("unlinkTier removes the Context from tier1 of every Type-root Page")
    func pageTypeRootUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        // Two Pages, both tagged tier1 == [spaceA, spaceB].
        let p1 = try await manager.createPage(name: "Alpha", inVaultRoot: vault)
        let p2 = try await manager.createPage(name: "Beta", inVaultRoot: vault)
        try await setPageTier(manager, p1, tier: 1, ids: [spaceA, spaceB], vault: vault)
        try await setPageTier(manager, p2, tier: 1, ids: [spaceA, spaceB], vault: vault)

        // Sanity: the index sees both Pages as referencing spaceA before the cascade.
        let before = try await IndexQuery(index).incomingRelations(targetID: spaceA)
        #expect(Set(before.map(\.id)) == [p1.id, p2.id])

        try await manager.unlinkTier(contextID: spaceA, tier: 1, index: index)

        // Reload BOTH from disk — assert spaceA gone, spaceB retained, order preserved.
        let reloaded1 = try PageFile.load(from: p1.url).frontmatter
        let reloaded2 = try PageFile.load(from: p2.url).frontmatter
        #expect(reloaded1.tier1 == [spaceB])
        #expect(reloaded2.tier1 == [spaceB])
        #expect(manager.pendingError == nil)

        // Index reconciled: no `relations` row (page → spaceA, _tier1) remains;
        // the spaceB tier row is still present for both Pages.
        #expect(try await tierRelationCount(index, target: spaceA, propertyID: ReservedPropertyID.tier1) == 0)
        #expect(try await tierRelationCount(index, target: spaceB, propertyID: ReservedPropertyID.tier1) == 2)
    }

    // MARK: - Page (Collection-nested)

    @Test("unlinkTier removes the Context from a Collection-nested Page")
    func pageCollectionNestedUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index)
        let coll = try makePageCollection(in: nexus, vault: vault, index: index)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let page = try await manager.createPage(name: "Nested", in: coll, vault: vault)
        try await setPageTier(manager, page, tier: 1, ids: [spaceA], vault: vault, collection: coll)

        try await manager.unlinkTier(contextID: spaceA, tier: 1, index: index)

        // Reload from disk — proves the Collection URL derivation in `locatePageFile`.
        let reloaded = try PageFile.load(from: page.url).frontmatter
        #expect(reloaded.tier1.isEmpty)
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: spaceA, propertyID: ReservedPropertyID.tier1) == 0)
    }

    // MARK: - Item (Type-root, tier2)

    @Test("unlinkTier removes the Context from tier2 of a Type-root Item")
    func itemTypeRootUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let itemType = try makeItemType(in: nexus, index: index)
        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let item = try await manager.createItem(name: "Widget", inTypeRoot: itemType)
        try await manager.updateItemProperty(
            item, propertyID: ReservedPropertyID.tier2,
            newValue: .relation([spaceA, spaceB]),
            type: itemType, collection: nil
        )

        try await manager.unlinkTier(contextID: spaceA, tier: 2, index: index)

        // Reload from disk via the title-derived Type-root URL.
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        let url = NexusPaths.itemFileURL(forTitle: "Widget", in: folder)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.tier2 == [spaceB])
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: spaceA, propertyID: ReservedPropertyID.tier2) == 0)
        #expect(try await tierRelationCount(index, target: spaceB, propertyID: ReservedPropertyID.tier2) == 1)
    }

    // MARK: - Item (Collection-nested, tier1)

    @Test("unlinkTier removes the Context from a Collection-nested Item")
    func itemCollectionNestedUnlink() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let itemType = try makeItemType(in: nexus, index: index)
        let coll = try makeItemCollection(in: nexus, itemType: itemType, index: index)
        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let item = try await manager.createItem(name: "Gadget", in: coll, type: itemType)
        try await manager.updateItemProperty(
            item, propertyID: ReservedPropertyID.tier1,
            newValue: .relation([spaceA]),
            type: itemType, collection: coll
        )

        try await manager.unlinkTier(contextID: spaceA, tier: 1, index: index)

        let url = NexusPaths.itemFileURL(forTitle: "Gadget", in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.tier1.isEmpty)
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: spaceA, propertyID: ReservedPropertyID.tier1) == 0)
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
            tier1: [spaceA, spaceB], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(), properties: [:]
        )
        try await manager.createTask(task)

        try await manager.unlinkTier(contextID: spaceA, tier: 1, index: index)

        let url = NexusPaths.taskFileURL(forTitle: "Plan release", in: nexus)
        let reloaded = try AgendaTask.load(from: url)
        #expect(reloaded.tier1 == [spaceB])
        #expect(manager.pendingError == nil)
        #expect(try await tierRelationCount(index, target: spaceA, propertyID: ReservedPropertyID.tier1) == 0)
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

        // Page references ONLY spaceB.
        let page = try await manager.createPage(name: "Untouched", inVaultRoot: vault)
        try await setPageTier(manager, page, tier: 1, ids: [spaceB], vault: vault)

        // Capture the file's modification timestamp + content before the cascade.
        let mtimeBefore = try modificationDate(of: page.url)
        let bytesBefore = try Data(contentsOf: page.url)

        // Unlink a Context this Page never referenced.
        try await manager.unlinkTier(contextID: spaceA, tier: 1, index: index)

        // tier1 unchanged; file not rewritten (identical bytes + mtime).
        let reloaded = try PageFile.load(from: page.url).frontmatter
        #expect(reloaded.tier1 == [spaceB])
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

        let page = try await manager.createPage(name: "Solo", inVaultRoot: vault)
        try await setPageTier(manager, page, tier: 1, ids: [spaceA], vault: vault)
        let bytesBefore = try Data(contentsOf: page.url)

        // tier 4 has no `_tierN` mapping → ReservedPropertyID.tierPropertyID returns
        // nil → early return; nothing is touched.
        try await manager.unlinkTier(contextID: spaceA, tier: 4, index: index)

        #expect(try Data(contentsOf: page.url) == bytesBefore)
        #expect(manager.pendingError == nil)
    }

    // MARK: - Fixtures

    /// PageType folder + sidecar on disk + page_types row in the index (FK parent
    /// for subsequent `upsertPage`).
    private func makeVault(in nexus: Nexus, index: PommoraIndex) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))
        try IndexUpdater(index).upsertPageType(vault)
        return vault
    }

    private func makePageCollection(in nexus: Nexus, vault: PageType, index: PommoraIndex) throws -> PageCollection {
        let folder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: vault.title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: "C", folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        try IndexUpdater(index).upsertPageCollection(coll)
        return coll
    }

    private func makeItemType(in nexus: Nexus, index: PommoraIndex) throws -> ItemType {
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))
        try IndexUpdater(index).upsertItemType(itemType)
        return itemType
    }

    private func makeItemCollection(in nexus: Nexus, itemType: ItemType, index: PommoraIndex) throws -> ItemCollection {
        let folder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL, typeFolderName: itemType.title, collectionFolderName: "C"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(), typeID: itemType.id, title: "C", folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        try IndexUpdater(index).upsertItemCollection(coll)
        return coll
    }

    /// Sets a Page's tier array through the production write path
    /// (`updatePageProperty` → `setRelationIDs` adapter + index re-upsert).
    private func setPageTier(
        _ manager: PageContentManager, _ page: PageMeta, tier: Int, ids: [String],
        vault: PageType, collection: PageCollection? = nil
    ) async throws {
        let propID = ReservedPropertyID.tierPropertyID(forTier: tier)!
        try await manager.updatePageProperty(
            page, propertyID: propID, newValue: .relation(ids), vault: vault, collection: collection
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
                sql: "SELECT COUNT(*) FROM relations WHERE target_id = ? AND property_id = ?",
                arguments: [target, propertyID]
            ) ?? -1
        }
    }

    private func modificationDate(of url: URL) throws -> Date {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? Date.distantPast
    }
}
