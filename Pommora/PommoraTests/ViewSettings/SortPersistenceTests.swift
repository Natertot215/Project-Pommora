import Foundation
import Testing

@testable import Pommora

/// Sort-pane persistence (Views Task 12).
///
/// Asserts the contract the Sort pane writes through `updateView`:
///   - selecting a preset REPLACES `sort` with a single-element array (never
///     appends to a prior selection);
///   - **Manual** writes `sort = nil`;
///   - a property sort writes exactly one `SortCriterion` with the right id +
///     direction;
///   - `loadAll`'s default-view mint folds `PageCollection.defaultSort` into the
///     minted view's `sort`.
///
/// The first three exercise the real disk-backed `updateView` path (mirrors
/// `UpdateViewClobberTests`); the mint test seeds a `default_sort` sidecar and
/// asserts the migrated view carries it.
@MainActor
@Suite("SortPersistenceTests")
struct SortPersistenceTests {

    // MARK: - updateView write contract

    @Test("Selecting a property sort writes exactly one criterion with the right id + direction")
    func propertySortWritesSingleCriterion() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: viewID)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in
            v.sort = [SortCriterion(propertyID: "prop_due", direction: .ascending)]
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        let sort = try #require(fresh.views.first(where: { $0.id == viewID })?.sort)
        #expect(sort.count == 1)
        #expect(sort.first?.propertyID == "prop_due")
        #expect(sort.first?.direction == .ascending)
    }

    @Test("Selecting a preset REPLACES the prior single-element sort (does not append)")
    func presetReplacesExistingSort() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [SavedView(id: viewID, sort: [SortCriterion(propertyID: "prop_due", direction: .ascending)])]
        )

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        // Pick "Title A→Z" over an existing property sort.
        try await types.updateView(viewID, in: collection.id) { v in
            v.sort = [SortCriterion(propertyID: ReservedPropertyID.title, direction: .ascending)]
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        let sort = try #require(fresh.views.first(where: { $0.id == viewID })?.sort)
        #expect(sort.count == 1)
        #expect(sort.first?.propertyID == ReservedPropertyID.title)
        #expect(sort.first?.direction == .ascending)
    }

    @Test("Manual writes sort = nil")
    func manualClearsSort() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [
                SavedView(
                    id: viewID, sort: [SortCriterion(propertyID: ReservedPropertyID.title, direction: .descending)])
            ]
        )

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in
            v.sort = nil
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.sort == nil)
    }

    // MARK: - defaultSort fold (Step 3)

    @Test("defaultTable folds PageCollection.defaultSort into the minted view's sort")
    func defaultTableFoldsDefaultSort() {
        let config = DefaultSortConfig(propertyID: "_modified_at", direction: .descending)
        let view = SavedView.defaultTable(visiblePropertyIDs: ["prop_a"], defaultSort: config)
        #expect(view.sort?.count == 1)
        #expect(view.sort?.first?.propertyID == "_modified_at")
        #expect(view.sort?.first?.direction == .descending)
    }

    @Test("defaultTable leaves sort nil when no defaultSort is present")
    func defaultTableNoSortWhenAbsent() {
        let view = SavedView.defaultTable(visiblePropertyIDs: ["prop_a"], defaultSort: nil)
        #expect(view.sort == nil)
    }

    @Test("loadAll mint carries the vault's default_sort into the minted view")
    func loadAllMintCarriesDefaultSort() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Collection with a default_sort sidecar field and NO views (forces mint).
        _ = try makePageCollection(
            nexus: nexus, title: "Notes", views: [],
            defaultSort: DefaultSortConfig(propertyID: "_id", direction: .ascending)
        )

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        let minted = try #require(types.types.first(where: { $0.title == "Notes" })?.views.first)
        let sort = try #require(minted.sort)
        #expect(sort.count == 1)
        #expect(sort.first?.propertyID == "_id")
        #expect(sort.first?.direction == .ascending)
    }

    // MARK: - Fixtures

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        views: [SavedView],
        defaultSort: DefaultSortConfig? = nil
    ) throws -> PageCollection {
        let collection = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: views, modifiedAt: Date(),
            defaultSort: defaultSort
        )
        let folderURL = NexusPaths.collectionFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
        return collection
    }

    private func reloadCollection(nexus: Nexus, title: String) throws -> PageCollection {
        try PageCollection.load(from: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
    }
}
