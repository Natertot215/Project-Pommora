import Foundation
import GRDB
import Testing

@testable import Pommora

/// Depth-1 view rule (Task 1.5): only Collections (direct children of a top-tier
/// PageCollection) carry and render views. Deeper Sub-Sets are plain — stray `views[]`
/// in their sidecars are ignored (not rendered). Moves and promotion behave
/// correctly without rewriting sidecars.
@MainActor
@Suite("PageSetDepthViewTests")
struct PageSetDepthViewTests {

    // MARK: - Fixtures

    @discardableResult
    private func makePageCollection(
        nexus: Nexus, title: String, index: PommoraIndex? = nil
    ) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        if let index { try IndexUpdater(index).upsertPageCollection(vault) }
        return vault
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus, title: String, in pageCollection: PageCollection, index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: pageCollection.title, in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageCollection(coll) }
        return coll
    }

    @discardableResult
    private func makePageSet(
        title: String, in parent: PageSet, index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = parent.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: parent.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageSet(set) }
        return set
    }

    // MARK: - topTierIDs

    @Test("topTierIDs is populated from types after loadAll")
    func topTierIDsPopulatedOnLoad() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vaultA = try makePageCollection(nexus: nexus, title: "Notes")
        let vaultB = try makePageCollection(nexus: nexus, title: "Tasks")
        _ = try makePageCollection(nexus: nexus, title: "Inbox", in: vaultA)

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vaultA, vaultB])

        #expect(setManager.topTierIDs == Set([vaultA.id, vaultB.id]))
    }

    // MARK: - View seeding — depth-1 gets seeded, depth-2+ does not

    @Test("depth-1 Collection seeds views on first loadAll")
    func depth1CollectionSeedsViews() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vault])

        let loaded = setManager.pageCollections(in: vault).first(where: { $0.id == coll.id })
        #expect(loaded != nil)
        #expect(!(loaded?.views.isEmpty ?? true), "depth-1 Collection must get a default view seeded")
        #expect(setManager.topTierIDs.contains(loaded!.parentID))
    }

    @Test("depth-2 Sub-Set with hand-placed views[] does NOT render them (not in topTierIDs)")
    func depth2SubSetWithViewsIsNotEligible() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        // Hand-place a views[] on the sub-set sidecar (simulating stray data).
        let subSetFolder = coll.folderURL.appendingPathComponent("SubSet", isDirectory: true)
        try FileManager.default.createDirectory(at: subSetFolder, withIntermediateDirectories: true)
        var subSetWithViews = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "SubSet",
            folderURL: subSetFolder, modifiedAt: Date()
        )
        subSetWithViews.views = [SavedView.defaultTable(visiblePropertyIDs: [])]
        try subSetWithViews.save(
            to: subSetFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vault])

        let loaded = setManager.pageSets(in: coll).first(where: { $0.id == subSetWithViews.id })
        #expect(loaded != nil)
        // The views are still in the sidecar (not stripped), but eligibility is false.
        #expect(!loaded!.views.isEmpty, "views[] stay in sidecar — no stripping")
        #expect(!setManager.topTierIDs.contains(loaded!.parentID), "depth-2 Sub-Set must NOT be view-eligible")
    }

    @Test("depth-2 Sub-Set is NOT seeded views by loadAll even when views[] is empty")
    func depth2SubSetNotSeededByLoadAll() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        _ = try makePageSet(title: "SubSet", in: coll)

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vault])

        let loaded = setManager.pageSets(in: coll).first
        #expect(loaded != nil)
        #expect(loaded!.views.isEmpty, "loadAll must NOT seed views for depth-2 Sub-Sets")
        #expect(!setManager.topTierIDs.contains(loaded!.parentID))
    }

    // MARK: - Move: depth changes flip eligibility (views dormant, sidecar unchanged)

    @Test("moving a depth-2 Set under another depth-2 Set keeps it ineligible; sidecar views[] unchanged")
    func moveSetBetweenSetsKeepsIneligible() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let vault = try makePageCollection(nexus: nexus, title: "Notes", index: index)
        let collA = try makePageCollection(nexus: nexus, title: "Alpha", in: vault, index: index)
        let collB = try makePageCollection(nexus: nexus, title: "Beta", in: vault, index: index)
        // Drafts starts under collA (depth-2); Archive is under collB (depth-2) — destination.
        let drafts = try makePageSet(title: "Drafts", in: collA, index: index)
        let archive = try makePageSet(title: "Archive", in: collB, index: index)

        // Hand-place views[] on the Drafts sidecar (stray dormant data).
        var draftsWithViews = drafts
        draftsWithViews.views = [SavedView.defaultTable(visiblePropertyIDs: [])]
        try draftsWithViews.save(
            to: drafts.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        contentManager.indexUpdater = updater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(types: [vault])

        let loadedDrafts = try #require(setManager.pageSets(in: collA).first(where: { $0.id == drafts.id }))
        #expect(!setManager.topTierIDs.contains(loadedDrafts.parentID), "depth-2 Drafts must be ineligible before move")

        // Move Drafts to become a child of Archive (depth-3).
        let loadedArchive = try #require(setManager.pageSets(in: collB).first(where: { $0.id == archive.id }))
        try await setManager.moveSet(
            loadedDrafts, to: loadedArchive,
            destinationPageCollection: vault, sourcePageCollection: vault,
            contentManager: contentManager
        )

        // Still ineligible at depth-3.
        let movedSet = setManager.pageSets(in: loadedArchive).first(where: { $0.id == drafts.id })
        #expect(movedSet != nil)
        #expect(!setManager.topTierIDs.contains(movedSet!.parentID), "depth-3 Set must still be ineligible")

        // Sidecar views[] are unchanged on disk — dormant, not stripped.
        let newFolder = archive.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        let reloadedSidecar = try PageSet.load(
            from: newFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        #expect(!reloadedSidecar.views.isEmpty, "views[] must survive the move unchanged on disk")
    }

    @Test("topTierIDs.contains flips when parentID changes from non-top-tier to top-tier (O(1) render-time check)")
    func eligibilityFlipsWithParentIDChange() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vault])

        // A Set whose parent is the collection (depth-2) — ineligible.
        let depthTwoSet = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "Sub",
            folderURL: coll.folderURL.appendingPathComponent("Sub"), modifiedAt: Date()
        )
        #expect(!setManager.topTierIDs.contains(depthTwoSet.parentID))

        // Same Set, re-parented to the vault (depth-1) — eligible.
        var promoted = depthTwoSet
        promoted.parentID = vault.id
        #expect(setManager.topTierIDs.contains(promoted.parentID))
    }

    // MARK: - Promotion: delete intermediate Set → depth-2 child becomes depth-1

    @Test("promotion: deleting intermediate Set (setOnly) re-surfaces dormant views on the promoted child")
    func promotionViaSetsOnlyDeleteResurfacesViews() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let vault = try makePageCollection(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)

        // Build: Inbox/Intermediate/SubSet — SubSet is depth-3, ineligible.
        let intermFolder = coll.folderURL.appendingPathComponent("Intermediate", isDirectory: true)
        try FileManager.default.createDirectory(at: intermFolder, withIntermediateDirectories: true)
        var interm = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "Intermediate",
            folderURL: intermFolder, modifiedAt: Date()
        )
        try interm.save(to: intermFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try updater.upsertPageSet(interm)

        let subFolder = intermFolder.appendingPathComponent("SubSet", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        // Give SubSet a views[] in its sidecar (dormant at depth-3).
        var subSet = PageSet(
            id: ULID.generate(), parentID: interm.id, title: "SubSet",
            folderURL: subFolder, modifiedAt: Date()
        )
        subSet.views = [SavedView.defaultTable(visiblePropertyIDs: [])]
        try subSet.save(to: subFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try updater.upsertPageSet(subSet)

        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(types: [vault])

        let loadedInterm = try #require(setManager.pageSets(in: coll).first(where: { $0.id == interm.id }))
        let loadedSub = try #require(setManager.pageSets(in: loadedInterm).first(where: { $0.id == subSet.id }))
        #expect(!setManager.topTierIDs.contains(loadedSub.parentID), "SubSet starts ineligible at depth-3")

        // Deleting the intermediate Set (setOnly) rehomes SubSet's folder into Inbox.
        // (setOnly rehomes .md Pages, not Sub-Sets — the folder move is the promotion.)
        // We simulate the promotion manually: move SubSet up to Inbox level and re-load.
        let promotedFolder = coll.folderURL.appendingPathComponent("SubSet", isDirectory: true)
        try FileManager.default.moveItem(at: subFolder, to: promotedFolder)

        // Fix SubSet sidecar parentID to point at coll (as deleteSet(.setOnly) + re-adopt would).
        var promoted = try PageSet.load(
            from: promotedFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        promoted.parentID = coll.id
        try promoted.save(to: promotedFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        // Delete the (now empty) intermediate folder.
        try FileManager.default.removeItem(at: intermFolder)

        // Reload — the promoted SubSet is now depth-2 (parentID = coll.id).
        // coll.id is NOT in topTierIDs (vault.id is), so still ineligible at depth-2.
        await setManager.loadAll(types: [vault])
        let reloadedSub = setManager.pageSets(in: coll).first(where: { $0.id == subSet.id })
        #expect(reloadedSub != nil)
        // depth-2: parentID = coll.id (a Collection, not a PageCollection) → still ineligible
        #expect(!setManager.topTierIDs.contains(reloadedSub!.parentID), "depth-2 is still ineligible")
        // The sidecar views[] are still present — dormant, not stripped.
        #expect(!reloadedSub!.views.isEmpty, "dormant views must survive on disk")
    }

    @Test("true promotion to depth-1: child of Collection becomes direct child of PageCollection (eligible)")
    func truePromotionToDepth1BecomesEligible() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        // SubSet starts at depth-2 (parent = coll), ineligible.
        let subFolder = coll.folderURL.appendingPathComponent("SubSet", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        var subSet = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "SubSet",
            folderURL: subFolder, modifiedAt: Date()
        )
        subSet.views = [SavedView.defaultTable(visiblePropertyIDs: [])]
        try subSet.save(to: subFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [vault])

        let loadedSub = try #require(setManager.pageSets(in: coll).first(where: { $0.id == subSet.id }))
        #expect(!setManager.topTierIDs.contains(loadedSub.parentID), "depth-2 must be ineligible")

        // Promote SubSet to depth-1: move its folder to the vault root, re-point parentID.
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
        let promotedFolder = vaultFolder.appendingPathComponent("SubSet", isDirectory: true)
        try FileManager.default.moveItem(at: subFolder, to: promotedFolder)
        var promoted = try PageSet.load(
            from: promotedFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        promoted.parentID = vault.id
        try promoted.save(to: promotedFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        // Reload — SubSet is now depth-1 (parentID = vault.id ∈ topTierIDs).
        await setManager.loadAll(types: [vault])

        let elevatedColl = setManager.pageCollections(in: vault).first(where: { $0.id == subSet.id })
        #expect(elevatedColl != nil, "promoted Set must appear as a Collection")
        #expect(setManager.topTierIDs.contains(elevatedColl!.parentID), "promoted to depth-1 must be view-eligible")
        // dormant views re-surface at render time — no re-serialization needed.
        #expect(!elevatedColl!.views.isEmpty, "dormant views must re-surface on eligibility flip")
    }

    // MARK: - Cross-vault move at depth-2 strips off-schema properties

    @Test("cross-PageCollection move at depth-2 strips off-schema properties")
    func crossVaultMoveAtDepth2Strips() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        // vaultA has "Status" (only); vaultB has none.
        let onlyA = PropertyDefinition(id: "prop_only_a", name: "Status", type: .status)
        let vaultAFolderURL = NexusPaths.vaultFolderURL(forTitle: "VaultA", in: nexus)
        try FileManager.default.createDirectory(at: vaultAFolderURL, withIntermediateDirectories: true)
        let vaultAWithProp = PageCollection(
            id: ULID.generate(), title: "VaultA", icon: nil,
            properties: [onlyA], views: [], modifiedAt: Date()
        )
        try vaultAWithProp.save(to: NexusPaths.vaultMetadataURL(forTitle: "VaultA", in: nexus))
        try updater.upsertPageCollection(vaultAWithProp)

        let vaultB = try makePageCollection(nexus: nexus, title: "VaultB", index: index)

        let collA = try makePageCollection(nexus: nexus, title: "CollA", in: vaultAWithProp, index: index)
        let collB = try makePageCollection(nexus: nexus, title: "CollB", in: vaultB, index: index)

        // Depth-2 Sub-Set lives under collA.
        let subSet = try makePageSet(title: "SubSet", in: collA, index: index)

        // Write a Page with the off-schema property inside the sub-set.
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: ["prop_only_a": .status("done")], createdAt: Date()
        )
        let pageURL = NexusPaths.pageFileURL(forTitle: "Doc", in: subSet.folderURL)
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: pageURL)

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        contentManager.indexUpdater = updater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(types: [vaultAWithProp, vaultB])

        let loadedSubSet = try #require(
            setManager.pageSets(in: collA).first(where: { $0.id == subSet.id }))

        try await setManager.moveSet(
            loadedSubSet, to: collB,
            destinationPageCollection: vaultB, sourcePageCollection: vaultAWithProp,
            contentManager: contentManager
        )

        // The moved Page must have the off-schema property stripped.
        let newFolder = collB.folderURL.appendingPathComponent("SubSet", isDirectory: true)
        let movedPageURL = NexusPaths.pageFileURL(forTitle: "Doc", in: newFolder)
        let movedPage = try PageFile.load(from: movedPageURL)
        #expect(movedPage.frontmatter.properties["prop_only_a"] == nil,
                "off-schema property must be stripped on cross-vault move at depth-2")
    }
}
