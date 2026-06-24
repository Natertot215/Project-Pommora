import Foundation
import Testing

@testable import Pommora

/// Covers the multi-saved-view CRUD managers on `PageCollectionManager` (Views Task
/// 17): `addView`, `duplicateView`, `deleteView`, `renameView`.
///
/// Each test hits real disk (mirrors `UpdateViewClobberTests`) and asserts on
/// the sidecar read FRESH from disk so a missed read-modify-write surfaces.
@MainActor
@Suite("ViewCRUDTests")
struct ViewCRUDTests {

    // MARK: - deleteView guard (≥1 view must remain)

    @Test("deleteView of the LAST view throws and leaves the views array unchanged")
    func deleteLastViewIsGuarded() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let vault = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: viewID)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        await #expect(throws: PageCollectionManagerError.cannotDeleteLastView) {
            try await types.deleteView(viewID, in: vault.id)
        }

        // No mutation — disk still holds the single view.
        let fresh = try PageCollection.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        #expect(fresh.views.count == 1)
        #expect(fresh.views.first?.id == viewID)
    }

    @Test("deleteView removes a non-last view and leaves the rest")
    func deleteNonLastView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let a = "view_\(ULID.generate())"
        let b = "view_\(ULID.generate())"
        let vault = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [SavedView(id: a), SavedView(id: b)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.deleteView(a, in: vault.id)

        let fresh = try PageCollection.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        #expect(fresh.views.map(\.id) == [b])
    }

    // MARK: - addView naming + gallery mints

    @Test("addView(.table) appends a view named Untitled View")
    func addTableView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let seed = "view_\(ULID.generate())"
        let vault = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: seed)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        let added = try await types.addView(type: .table, to: vault.id)

        #expect(added.name == "Untitled View")
        #expect(added.type == .table)
        let fresh = try PageCollection.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        #expect(fresh.views.count == 2)
        #expect(fresh.views.last?.id == added.id)
    }

    @Test("addView(.gallery) mints cardSize == .medium and showCover nil")
    func addGalleryView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let seed = "view_\(ULID.generate())"
        let vault = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: seed)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        let added = try await types.addView(type: .gallery, to: vault.id)

        #expect(added.type == .gallery)
        #expect(added.cardSize == .medium)
        #expect(added.showCover == nil)
    }

    // MARK: - duplicateView copies all v2 fields with a fresh id

    @Test("duplicateView copies every v2 field with a fresh, different id")
    func duplicateViewCopiesAllFields() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let original = SavedView(
            id: viewID,
            name: "Source",
            icon: "star",
            type: .gallery,
            propertyOrder: ["_title", "prop_a", "prop_b"],
            hiddenProperties: ["prop_b"],
            columnWidths: ["_title": 200, "prop_a": 120],
            collapsedGroups: ["groupX"],
            cardSize: .large,
            showCover: true,
            sort: [SortCriterion(propertyID: "prop_a", direction: .descending)],
            filter: FilterGroup(
                match: .all,
                rules: [FilterRule(propertyID: "prop_a", op: "eq", value: "v")]),
            group: .property(PropertyGrouping(propertyID: "prop_a", order: ["x", "y"]))
        )
        let vault = try makePageCollection(nexus: nexus, title: "Notes", views: [original])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        let copy = try await types.duplicateView(viewID, in: vault.id)

        #expect(copy.id != original.id)
        #expect(copy.id.hasPrefix("view_"))
        #expect(copy.propertyOrder == original.propertyOrder)
        #expect(copy.hiddenProperties == original.hiddenProperties)
        #expect(copy.sort == original.sort)
        #expect(copy.filter == original.filter)
        #expect(copy.group == original.group)
        #expect(copy.columnWidths == original.columnWidths)
        #expect(copy.collapsedGroups == original.collapsedGroups)
        #expect(copy.cardSize == original.cardSize)
        #expect(copy.showCover == original.showCover)
        #expect(copy.type == original.type)

        let fresh = try PageCollection.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        #expect(fresh.views.count == 2)
        #expect(fresh.views.contains(where: { $0.id == copy.id }))
    }

    // MARK: - renameView

    @Test("renameView writes the new name to the sidecar")
    func renameView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let vault = try makePageCollection(
            nexus: nexus, title: "Notes", views: [SavedView(id: viewID, name: "Old")])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.renameView(viewID, in: vault.id, to: "New")

        let fresh = try PageCollection.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        #expect(fresh.views.first(where: { $0.id == viewID })?.name == "New")
    }

    // MARK: - Collection container parity

    @Test("addView resolves a PageSet container too")
    func addViewOnCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let seed = "view_\(ULID.generate())"
        let vault = try makePageCollection(nexus: nexus, title: "Notes", views: [])
        let coll = try makePageSet(
            nexus: nexus, title: "Inbox", in: vault, views: [SavedView(id: seed)])

        let types = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak types] in types?.types ?? [] }
        types.pageSetManager = setManager
        await types.loadAll()
        await setManager.loadAll(types: types.types)

        let added = try await types.addView(type: .table, to: coll.id)

        let sidecarURL = coll.folderURL.appendingPathComponent(
            NexusPaths.pageSetSidecarFilename)
        let fresh = try PageSet.load(from: sidecarURL)
        #expect(fresh.views.count == 2)
        #expect(fresh.views.last?.id == added.id)
    }

    // MARK: - Fixtures (mirror UpdateViewClobberTests)

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String, views: [SavedView]) throws -> PageCollection {
        var vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date())
        vault.views = views
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageSet(
        nexus: Nexus, title: String, in pageCollection: PageCollection, views: [SavedView]
    ) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date())
        coll.views = views
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return coll
    }
}
