import Foundation
import Testing

@testable import Pommora

/// Manager-level tests for the Task 7 sidebar surfacing of PageSets —
/// the stub-and-inline-rename creation flow driven by the `pageSet` label
/// (the SwiftUI rows themselves aren't unit-testable here).
@MainActor
@Suite("PageSetSidebarTests")
struct PageSetSidebarTests {

    // MARK: - Fixtures

    private struct Fixture {
        let nexus: Nexus
        let typeManager: PageCollectionManager
        let setManager: PageSetManager
        let collection: PageSet
    }

    /// Collection "Notes" + Collection "Inbox" via CRUD; both managers loaded.
    private func makeFixture() async throws -> Fixture {
        let nexus = try TempNexus.make()
        let typeManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak typeManager] in typeManager?.types ?? [] }
        typeManager.pageSetManager = setManager
        await typeManager.loadAll()
        try await typeManager.createPageCollection(name: "Notes", icon: nil)
        let pageCollection = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageCollection: pageCollection)
        let collection = typeManager.pageCollections(in: pageCollection).first!
        await setManager.loadAll(types: typeManager.types)
        return Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            collection: collection
        )
    }

    // MARK: - Stub-creation default titles

    @Test("Stub-create resolves \"New Set\" then \"New Set 2\" via the pageSet label")
    func stubCreateDefaultTitles() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }
        let label = SettingsLabels.defaults().pageSet.singular

        // First stub: no siblings → bare default.
        let first = DefaultTitleResolver.resolve(
            label: label,
            existingTitles: fx.setManager.pageSets(in: fx.collection).map(\.title)
        )
        #expect(first == "New Set")
        try await fx.setManager.createPageSet(name: first, in: fx.collection)

        // Second stub: bare default taken → lowest free numbered slot.
        let second = DefaultTitleResolver.resolve(
            label: label,
            existingTitles: fx.setManager.pageSets(in: fx.collection).map(\.title)
        )
        #expect(second == "New Set 2")
        try await fx.setManager.createPageSet(name: second, in: fx.collection)

        // Compare as a Set — display order is OrderResolver's concern,
        // not creation order (ULID-flake footgun).
        let titles = Set(fx.setManager.pageSets(in: fx.collection).map(\.title))
        #expect(titles == ["New Set", "New Set 2"])
    }

    @Test("Stub-create default follows a customized pageSet label")
    func stubCreateFollowsCustomLabel() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let settings = SettingsManager(nexus: fx.nexus)
        await settings.loadOrSeed()
        await settings.updateLabel(\.pageSet, to: LabelPair(singular: "Bundle", plural: "Bundles"))

        let title = DefaultTitleResolver.resolve(
            label: settings.settings.labels.pageSet.singular,
            existingTitles: fx.setManager.pageSets(in: fx.collection).map(\.title)
        )
        #expect(title == "New Bundle")
    }
}
