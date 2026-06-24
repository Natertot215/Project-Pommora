import Foundation
import GRDB
import Testing

@testable import Pommora

/// D2: a rename must refresh the denormalized `EntityStateRef.title` cached in
/// the Pinned + Recents stores so pins/recents no longer show the old name.
///
/// Fixture mirrors `ConnectionLiveUpdateTests.setup()` (TempNexus + PommoraIndex
/// + one PageCollection + one PageSet seeded into the index + a
/// `PageContentManager` with `indexUpdater` set), plus a `PinnedManager` +
/// `RecentsManager` injected onto the manager.
@MainActor
@Suite("RenamePinRefreshTests")
struct RenamePinRefreshTests {

    private func setup() async throws -> (
        nexus: Nexus,
        pageCollection: PageCollection,
        coll: PageSet,
        manager: PageContentManager,
        pinned: PinnedManager,
        recents: RecentsManager
    ) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.setFolderURL(forTitle: "C", inCollectionTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: collection.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let updater = IndexUpdater(index)
        try updater.upsertPageCollection(collection)
        try updater.upsertPageCollection(coll)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = updater

        let pinned = PinnedManager(nexus: nexus)
        let recents = RecentsManager(nexus: nexus)
        manager.pinnedManager = pinned
        manager.recentsManager = recents

        return (nexus, collection, coll, manager, pinned, recents)
    }

    /// Rename "Old" → "New" refreshes the pinned + recents entry titles in place,
    /// matched by (kind, id) — order/count preserved.
    @Test("rename refreshes pinned + recents titles in place")
    func renameRefreshesTitles() async throws {
        let (nexus, collection, coll, manager, pinned, recents) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let page = try await manager.createPage(name: "Old", in: coll, pageCollection: collection)

        pinned.toggle(EntityStateRef(kind: .page, id: page.id, title: "Old"))
        recents.record(EntityStateRef(kind: .page, id: page.id, title: "Old"))

        let pinnedCountBefore = pinned.entries.count
        let recentsCountBefore = recents.entries.count

        try await manager.renamePage(page, to: "New", in: coll, pageCollection: collection)

        #expect(pinned.entries.first?.title == "New")
        #expect(recents.entries.first(where: { $0.id == page.id })?.title == "New")

        // updateTitle must replace in place, not append.
        #expect(pinned.entries.count == pinnedCountBefore)
        #expect(recents.entries.count == recentsCountBefore)
    }
}
