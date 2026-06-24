import Foundation
import Testing

@testable import Pommora

/// Filter + Group pane persistence (Views Task 13).
///
/// Asserts the write contracts the Filter and Group panes drive through
/// `updateView`, plus the Table's collapse-group persistence:
///   - Filter: adding / removing a rule rewrites the whole `FilterGroup`;
///     toggling `MatchMode` persists; an emptied filter clears to `nil`.
///   - Group: Default writes `.structural`; a property writes
///     `.property(PropertyGrouping(propertyID:))`; Remove Grouping writes `.flat`.
///   - Collapse: a chevron toggle persists the group id into / out of
///     `collapsedGroups`.
///
/// Every test exercises the real disk-backed `updateView` path (mirrors
/// `SortPersistenceTests`).
@MainActor
@Suite("FilterGroupPaneTests")
struct FilterGroupPaneTests {

    // MARK: - Filter write contract

    @Test("Adding a rule writes the whole FilterGroup")
    func addRuleWritesGroup() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: viewID)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in
            v.filter = FilterGroup(
                match: .all,
                rules: [FilterRule(propertyID: "prop_status", op: "is", value: "open")])
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        let filter = try #require(fresh.views.first(where: { $0.id == viewID })?.filter)
        #expect(filter.match == .all)
        #expect(filter.rules.count == 1)
        #expect(filter.rules.first?.propertyID == "prop_status")
        #expect(filter.rules.first?.op == "is")
        #expect(filter.rules.first?.value == "open")
    }

    @Test("Removing the last rule clears filter to nil")
    func removeLastRuleClearsFilter() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [
                SavedView(
                    id: viewID,
                    filter: FilterGroup(
                        match: .all, rules: [FilterRule(propertyID: "prop_a", op: "is", value: "x")]))
            ])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        // Pane clears `filter` to nil when the rewritten group is empty + .all.
        try await types.updateView(viewID, in: collection.id) { v in v.filter = nil }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.filter == nil)
    }

    @Test("Toggling MatchMode persists")
    func matchModePersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [
                SavedView(
                    id: viewID,
                    filter: FilterGroup(
                        match: .all, rules: [FilterRule(propertyID: "prop_a", op: "is", value: "x")]))
            ])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in
            v.filter?.match = .any
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.filter?.match == .any)
    }

    // MARK: - Group write contract

    @Test("Default writes GroupConfig.structural")
    func groupDefaultWritesStructural() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [SavedView(id: viewID, group: .flat)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in v.group = .structural }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.group == .structural)
    }

    @Test("Selecting a property writes GroupConfig.property")
    func groupPropertyWritesProperty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: viewID)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in
            v.group = .property(PropertyGrouping(propertyID: "prop_status", order: nil))
        }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        guard case .some(.property(let grouping)) = fresh.views.first(where: { $0.id == viewID })?.group
        else {
            Issue.record("expected .property grouping")
            return
        }
        #expect(grouping.propertyID == "prop_status")
    }

    @Test("Remove Grouping writes GroupConfig.flat")
    func groupRemoveWritesFlat() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(
            nexus: nexus, title: "Notes",
            views: [SavedView(id: viewID, group: .structural)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        try await types.updateView(viewID, in: collection.id) { v in v.group = .flat }

        let fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.group == .flat)
    }

    // MARK: - Collapse persistence

    @Test("Toggling a group chevron persists its id into collapsedGroups")
    func collapseTogglePersistsID() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let viewID = "view_\(ULID.generate())"
        let collection = try makePageCollection(nexus: nexus, title: "Notes", views: [SavedView(id: viewID)])

        let types = PageCollectionManager(nexus: nexus)
        await types.loadAll()

        // Collapse: id present.
        try await types.updateView(viewID, in: collection.id) { v in v.collapsedGroups = ["grp_a"] }
        var fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.collapsedGroups == ["grp_a"])

        // Expand back to empty: cleared to nil (the persistCollapsed contract).
        try await types.updateView(viewID, in: collection.id) { v in v.collapsedGroups = nil }
        fresh = try reloadCollection(nexus: nexus, title: "Notes")
        #expect(fresh.views.first(where: { $0.id == viewID })?.collapsedGroups == nil)
    }

    // MARK: - Fixtures

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        views: [SavedView]
    ) throws -> PageCollection {
        let collection = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: views, modifiedAt: Date())
        let folderURL = NexusPaths.collectionFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
        return collection
    }

    private func reloadCollection(nexus: Nexus, title: String) throws -> PageCollection {
        try PageCollection.load(from: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
    }
}
