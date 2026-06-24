import Foundation
import GRDB
import Testing

@testable import Pommora

/// Set pages surfacing through the editor + detail views (Sets Task 8):
/// the editor's save path must route through the Set-scoped `updatePage`
/// (the gap regression — a Collection-scoped save re-points the index row's
/// `page_set_id` to nil), the table cell-commit path must keep `page_set_id`,
/// and `resolveParent` must return the Set for a Set page on both the index
/// path and the URL fallback.
///
/// Also covers the v0.4.1 live-testing fix for the identity-only
/// `SelectionTag.set` (never matches, never resolves — the sidebar
/// selection-bleed fix). Structural set/root grouping is covered by
/// `GroupResolverTests`.
///
/// Fixtures mirror `PageSetContentTests`.
@MainActor
@Suite("PageSetDetailTests")
struct PageSetDetailTests {

    // MARK: - Editor save path (the gap regression)

    @Test("Editor saver with a Set routes through the Set-scoped updatePage, preserving page_set_id")
    func editorSaverPreservesSetID() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)
        let meta = try await manager.createPage(name: "Draft", in: set, collection: coll, vault: vault)

        // The exact object PageEditorHost builds for a resolved Set page.
        let saver = ContentManagerPageSaver(
            contentManager: manager, vault: vault, collection: coll, set: set)
        try await saver.save(page: meta, body: "edited body")

        let pageID = meta.id  // hoist before the dbQueue closure (@Sendable)
        let collID = coll.id
        let setID = set.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == collID)
        #expect(row?["page_set_id"] as String? == setID)
        #expect(try PageFile.load(from: meta.url).body == "edited body")
    }

    @Test("Saver resolves the live scope per-save, so a stale captured scope can't drop page_set_id")
    func saverPerSaveResolutionOverridesStaleCapture() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)
        let meta = try await manager.createPage(name: "Draft", in: set, collection: coll, vault: vault)

        // Managers the saver resolves the Page's live scope against.
        let typeMgr = PageTypeManager(nexus: nexus)
        typeMgr.indexUpdater = IndexUpdater(index)
        let setMgr = PageSetManager(nexus: nexus)
        setMgr.pageTypeProvider = { [weak typeMgr] in typeMgr?.types ?? [] }
        typeMgr.pageSetManager = setMgr
        await typeMgr.loadAll()
        await setMgr.loadAll(types: typeMgr.types)

        // Captured scope is STALE — it claims Collection-scoped (set: nil), which a
        // captured-only saver would route through, nulling page_set_id. With managers,
        // the save resolves the live scope (the Set) per-save instead.
        let saver = ContentManagerPageSaver(
            contentManager: manager, vault: vault, collection: coll, set: nil,
            pageTypeManager: typeMgr, pageSetManager: setMgr)
        try await saver.save(page: meta, body: "edited")

        let pageID = meta.id
        let setID = set.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(
                db, sql: "SELECT page_set_id FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_set_id"] as String? == setID)
    }

    // MARK: - Cell-commit path

    @Test("updatePageProperty with a Set keeps page_set_id and refreshes the Set cache")
    func updatePagePropertyKeepsSetID() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)
        let meta = try await manager.createPage(name: "Doc", in: set, collection: coll, vault: vault)

        try await manager.updatePageProperty(
            meta, propertyID: "prop_x", newValue: .select("hello"),
            vault: vault, collection: coll, set: set)

        let pageID = meta.id  // hoist before the dbQueue closure (@Sendable)
        let setID = set.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_set_id"] as String? == setID)

        // The in-memory Set bucket carries the fresh frontmatter.
        let cached = manager.pages(in: set).first { $0.id == pageID }
        #expect(cached?.frontmatter.properties["prop_x"] == PropertyValue.select("hello"))
    }

    // MARK: - Parent resolution

    @Test("resolveParent returns the Set via the index for a Set page")
    func resolveParentReturnsSetViaIndex() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)
        let meta = try await manager.createPage(name: "Doc", in: set, collection: coll, vault: vault)

        let vaultManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak vaultManager] in vaultManager?.types ?? [] }
        vaultManager.pageSetManager = setManager
        await vaultManager.loadAll()
        await setManager.loadAll(types: [vault])

        let result = manager.resolveParent(
            for: meta, pageTypeManager: vaultManager, pageSetManager: setManager)
        #expect(result?.vault.id == vault.id)
        #expect(result?.collection?.id == coll.id)
        #expect(result?.set?.id == set.id)
    }

    @Test("resolveParent URL fallback returns the Set when no index is wired")
    func resolveParentReturnsSetViaURLFallback() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageType(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let set = try makePageSet(title: "Drafts", in: coll)
        let pageID = try writePage(titled: "Doc", in: set.folderURL)

        // manager.indexUpdater is nil — URL prefix matching only.
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })

        let vaultManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak vaultManager] in vaultManager?.types ?? [] }
        vaultManager.pageSetManager = setManager
        await vaultManager.loadAll()
        await setManager.loadAll(types: [vault])

        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(
            id: pageID, title: "Doc",
            url: NexusPaths.pageFileURL(forTitle: "Doc", in: set.folderURL),
            frontmatter: fm)

        let result = manager.resolveParent(
            for: page, pageTypeManager: vaultManager, pageSetManager: setManager)
        #expect(result?.vault.id == vault.id)
        #expect(result?.collection?.id == coll.id)
        #expect(result?.set?.id == set.id)
    }

    // MARK: - SelectionTag.set (v0.4.1 — sidebar selection bleed)

    @Test(".set tag matches NO selection — even a collection or page selection carrying the same id")
    func setTagNeverMatches() {
        let id = ULID.generate()
        let coll = PageSet(
            id: id, parentID: ULID.generate(), title: "Inbox",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date()
        )
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(id: id, title: "Doc", url: URL(fileURLWithPath: "/"), frontmatter: fm)

        let tag = SelectionTag.set(id)
        #expect(!tag.matches(.none))
        #expect(!tag.matches(.collection(coll)))
        #expect(!tag.matches(.page(page)))
    }

    @Test(".set tag resolves to no SidebarSelection — SidebarView's onChange guard makes it a no-op")
    func setTagResolvesNil() {
        let lookup = SidebarLookupBundle(
            content: nil, pageType: nil, area: nil, topic: nil, project: nil)
        #expect(SidebarSelection(tag: .set(ULID.generate()), lookup: lookup) == nil)
    }

    @Test("a Set page resolves through .page tags — pagesBySet is part of the sidebar lookup")
    func setPageResolvesThroughLookup() {
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(
            id: pageID, title: "In Set", url: URL(fileURLWithPath: "/"), frontmatter: fm)
        let cm = PageContentManager(
            nexus: Nexus(id: ULID.generate(), rootURL: URL(fileURLWithPath: "/")),
            contextProvider: { NexusContext.empty })
        cm.pagesBySet[ULID.generate()] = [page]

        let lookup = SidebarLookupBundle(
            content: cm, pageType: nil, area: nil, topic: nil, project: nil)
        #expect(SidebarSelection(tag: .page(pageID), lookup: lookup) == .page(page))
    }

    // MARK: - Fixtures (mirror PageSetContentTests)

    @discardableResult
    private func makePageType(
        nexus: Nexus,
        title: String,
        index: PommoraIndex? = nil
    ) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        if let index { try IndexUpdater(index).upsertPageType(vault) }
        return vault
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        in vault: PageType,
        index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: vault.title, in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: vault.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageCollection(coll) }
        return coll
    }

    @discardableResult
    private func makePageSet(
        title: String,
        in collection: PageSet,
        index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = collection.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: collection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageSet(set) }
        return set
    }

    /// Writes a `.md` Page with proper frontmatter into `folder`; returns its id.
    private func writePage(titled title: String, in folder: URL) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }
}
