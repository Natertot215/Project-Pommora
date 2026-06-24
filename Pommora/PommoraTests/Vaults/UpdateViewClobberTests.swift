import Foundation
import Testing

@testable import Pommora

/// Regression guard for the `updateView` page-order clobber (Views Task 3).
///
/// Drag-reorder persists `page_order` straight to the Collection sidecar via
/// `OrderPersister.setPageOrder` (a disk read-modify-write). `PageTypeManager`'s
/// in-memory `pageCollectionsByType` cache keeps the STALE pre-reorder order.
/// Before the fix, `updateView` saved that cached struct back to disk, clobbering
/// the freshly-written `page_order`. The fix makes `updateView` load the sidecar
/// FRESH from disk before transforming, so a concurrent reorder survives.
///
/// The fixture hits real disk (mirrors `PageSetContentTests`) and asserts on the
/// sidecar read FRESH from disk — a pure in-memory test would not catch the clobber.
@MainActor
@Suite("UpdateViewClobberTests")
struct UpdateViewClobberTests {

    @Test("updateView preserves a concurrently-written page_order on the Collection sidecar")
    func updateViewDoesNotClobberPageOrder() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Vault + Collection with one SavedView + two pages, all on disk.
        let viewID = "view_\(ULID.generate())"
        let vault = try makePageType(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(
            nexus: nexus, title: "Inbox", in: vault,
            views: [SavedView(id: viewID)]
        )
        _ = try writePage(titled: "One", in: coll.folderURL)
        _ = try writePage(titled: "Two", in: coll.folderURL)

        let pages = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await pages.loadAll(forCollection: coll)
        let initial = pages.pages(inCollection: coll).map(\.id)
        #expect(initial.count == 2)

        // Set manager caches the Collection BEFORE the reorder, so its
        // `pageCollectionsByType` entry holds the stale pre-reorder order — the
        // exact production precondition for the clobber.
        let types = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak types] in types?.types ?? [] }
        types.pageSetManager = setManager
        await types.loadAll()
        await setManager.loadAll(types: types.types)

        // Now drag-reorder: writes the new `page_order` straight to the sidecar
        // on disk. The set manager's cache is now stale.
        pages.reorderPages(inCollection: coll, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let reordered = pages.pages(inCollection: coll).map(\.id)
        #expect(reordered == [initial[1], initial[0]])

        // Edit a SavedView on the Collection — the path that used to clobber.
        try await types.updateView(viewID, in: coll.id) { $0.columnWidths = ["_title": 200] }

        // Assert on the sidecar read FRESH from disk (not either in-memory cache).
        let sidecarURL = coll.folderURL.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename)
        let fresh = try PageCollection.load(from: sidecarURL)
        #expect(fresh.pageOrder == reordered)
        #expect(fresh.views.first(where: { $0.id == viewID })?.columnWidths?["_title"] == 200)
    }

    // MARK: - Fixtures (mirror PageSetContentTests)

    @discardableResult
    private func makePageType(nexus: Nexus, title: String) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        in vault: PageType,
        views: [SavedView]
    ) throws -> PageCollection {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: vault.title, in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        coll.views = views
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        return coll
    }

    /// Writes a `.md` Page with proper frontmatter into `folder`; returns its id.
    @discardableResult
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
