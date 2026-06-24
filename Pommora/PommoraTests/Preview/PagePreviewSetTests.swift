import Foundation
import GRDB
import Testing

@testable import Pommora

/// PagePreview through the Set tier (Sets Task 8b): a Set page's tap must
/// route into a Set-carrying `PageRef`, that ref must resolve to the live
/// Set page + its on-disk file, and the preview's saver — built from the
/// resolved ref exactly as `PagePreviewContent.load` does — must route
/// through the Set-scoped `updatePage` so the index row's `page_set_id`
/// survives an in-preview edit. Pre-Set refs (no `setID` key) must keep
/// decoding for scene restoration.
///
/// On-disk fixtures mirror `PageSetDetailTests`.
@MainActor
@Suite("PagePreviewSetTests")
struct PagePreviewSetTests {

    // MARK: - Routing (pure — in-memory fixtures, /tmp URLs)

    @Test("routeOpen carries the Set into the preview ref")
    func routeOpenCarriesSet() {
        let vault = PageType(
            id: ULID.generate(), title: "Vault", icon: nil,
            properties: [], views: [], modifiedAt: Date(),
            openIn: .compact
        )
        let collection = PageSet(
            id: ULID.generate(), parentID: vault.id, title: "Inbox",
            folderURL: URL(fileURLWithPath: "/tmp/Vault/Inbox"), modifiedAt: Date()
        )
        let set = PageSet(
            id: ULID.generate(), parentID: collection.id, title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/Vault/Inbox/Drafts"), modifiedAt: Date()
        )
        let pageID = ULID.generate()
        let page = PageMeta(
            id: pageID,
            title: "Note",
            url: URL(fileURLWithPath: "/tmp/Vault/Inbox/Drafts/Note.md"),
            frontmatter: PageFrontmatter(
                id: pageID, icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date()
            )
        )
        var selection = SidebarSelection.collection(collection)
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, vault: vault, collection: collection, set: set, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .previewCard)
        #expect(opened == [PageRef(page: page, in: set, collection: collection, vault: vault)])
        #expect(opened.first?.setID == set.id)
    }

    @Test("A pre-Set ref payload (no setID key) still decodes — scene restoration")
    func legacyRefDecodesWithoutSetID() throws {
        let legacy = Data(#"{"pageID":"p1","vaultID":"v1","collectionID":"c1"}"#.utf8)
        let ref = try JSONDecoder().decode(PageRef.self, from: legacy)
        #expect(ref.collectionID == "c1")
        #expect(ref.setID == nil)
    }

    // MARK: - Ref resolution (on-disk)

    @Test("A Set page's PageRef resolves to the live Set page + its on-disk file")
    func setPageRefResolvesThroughManagers() async throws {
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

        // A COLD content manager + loadAll(for: set) mirrors the preview
        // opening a Set page before any sidebar/detail browse populated the
        // page cache (PagePreviewContent.loadContainer's lazy path).
        let coldManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await coldManager.loadAll(for: set)

        let ref = PageRef(page: meta, in: set, collection: coll, vault: vault)
        let resolved = ref.resolve(
            vaultManager: vaultManager, contentManager: coldManager, setManager: setManager)
        #expect(resolved?.page.id == meta.id)
        #expect(resolved?.page.url.standardizedFileURL == meta.url.standardizedFileURL)
        #expect(resolved?.vault.id == vault.id)
        #expect(resolved?.collection?.id == coll.id)
        #expect(resolved?.set?.id == set.id)
    }

    // MARK: - Preview saver (the gap regression, through the ref)

    @Test("Preview saver built from a resolved Set ref preserves page_set_id in the index")
    func previewSaverOnSetPagePreservesSetID() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)
        let meta = try await manager.createPage(name: "Draft", in: set, collection: coll, vault: vault)

        let vaultManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak vaultManager] in vaultManager?.types ?? [] }
        vaultManager.pageSetManager = setManager
        await vaultManager.loadAll()
        await setManager.loadAll(types: [vault])

        let ref = PageRef(page: meta, in: set, collection: coll, vault: vault)
        let resolved = try #require(
            ref.resolve(
                vaultManager: vaultManager, contentManager: manager, setManager: setManager))

        // The exact saver PagePreviewContent.load builds for a resolved Set ref.
        let saver = ContentManagerPageSaver(
            contentManager: manager, vault: resolved.vault,
            collection: resolved.collection, set: resolved.set)
        try await saver.save(page: resolved.page, body: "previewed edit")

        let pageID = meta.id  // hoist before the dbQueue closure (@Sendable)
        let collID = coll.id
        let setID = set.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == collID)
        #expect(row?["page_set_id"] as String? == setID)
        #expect(try PageFile.load(from: meta.url).body == "previewed edit")
    }

    // MARK: - Fixtures (mirror PageSetDetailTests)

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
}
