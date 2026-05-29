import Foundation
import Testing

@testable import Pommora

@Suite("RelationTargetCatalogTests")
struct RelationTargetCatalogTests {

    // MARK: - Helpers

    private func makeItemType(id: String, title: String, icon: String? = nil) -> ItemType {
        ItemType(
            id: id,
            title: title,
            icon: icon,
            properties: [],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
    }

    private func makePageType(id: String, title: String, icon: String? = nil) -> PageType {
        PageType(
            id: id,
            title: title,
            icon: icon,
            properties: [],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
    }

    private func makeCatalog(
        itemTypes: [ItemType] = [],
        pageTypes: [PageType] = []
    ) -> RelationTargetCatalog {
        RelationTargetCatalog(pageTypes: pageTypes, itemTypes: itemTypes)
    }

    // MARK: - Test 1: exactly four sections in canonical order

    @Test("sections() returns exactly 4 sections with headers Items / Vaults / Events / Tasks")
    func fourSectionsInOrder() {
        let catalog = makeCatalog()
        let sections = catalog.sections()

        #expect(sections.count == 4)
        #expect(sections[0].header == "Items")
        #expect(sections[1].header == "Vaults")
        #expect(sections[2].header == "Events")
        #expect(sections[3].header == "Tasks")
    }

    // MARK: - Test 2: Items section mirrors itemTypes

    @Test("Items section has one row per ItemType with .itemType targets")
    func itemsSectionRows() {
        let types = [
            makeItemType(id: "it_01", title: "Tasks"),
            makeItemType(id: "it_02", title: "Contacts"),
        ]
        let catalog = makeCatalog(itemTypes: types)
        let items = catalog.sections()[0]

        #expect(items.rows.count == 2)
        #expect(items.rows[0].id == "it_01")
        #expect(items.rows[0].label == "Tasks")
        #expect(items.rows[0].target == .itemType("it_01"))
        #expect(items.rows[1].id == "it_02")
        #expect(items.rows[1].label == "Contacts")
        #expect(items.rows[1].target == .itemType("it_02"))
    }

    // MARK: - Test 3: Vaults section mirrors pageTypes

    @Test("Vaults section has one row per PageType with .pageType targets")
    func vaultsSectionRows() {
        let types = [
            makePageType(id: "pt_01", title: "Notes"),
            makePageType(id: "pt_02", title: "Docs"),
        ]
        let catalog = makeCatalog(pageTypes: types)
        let vaults = catalog.sections()[1]

        #expect(vaults.rows.count == 2)
        #expect(vaults.rows[0].id == "pt_01")
        #expect(vaults.rows[0].label == "Notes")
        #expect(vaults.rows[0].target == .pageType("pt_01"))
        #expect(vaults.rows[1].id == "pt_02")
        #expect(vaults.rows[1].label == "Docs")
        #expect(vaults.rows[1].target == .pageType("pt_02"))
    }

    // MARK: - Test 4: Events section is a single row with .agendaEvents

    @Test("Events section has exactly one row with .agendaEvents target and ReservedTypeID id")
    func eventsSectionSingleRow() {
        let catalog = makeCatalog()
        let events = catalog.sections()[2]

        #expect(events.rows.count == 1)
        #expect(events.rows[0].id == ReservedTypeID.agendaEvents)
        #expect(events.rows[0].target == .agendaEvents)
    }

    // MARK: - Test 5: Tasks section is a single row with .agendaTasks

    @Test("Tasks section has exactly one row with .agendaTasks target and ReservedTypeID id")
    func tasksSectionSingleRow() {
        let catalog = makeCatalog()
        let tasks = catalog.sections()[3]

        #expect(tasks.rows.count == 1)
        #expect(tasks.rows[0].id == ReservedTypeID.agendaTasks)
        #expect(tasks.rows[0].target == .agendaTasks)
    }

    // MARK: - Test 6: resolve finds itemType row

    @Test("resolve(.itemType(id)) returns the matching Items row")
    func resolveItemType() {
        let catalog = makeCatalog(
            itemTypes: [makeItemType(id: "it_99", title: "Expenses")]
        )
        let row = catalog.resolve(.itemType("it_99"))

        #expect(row != nil)
        #expect(row?.id == "it_99")
        #expect(row?.label == "Expenses")
        #expect(row?.target == .itemType("it_99"))
    }

    // MARK: - Test 7: resolve finds pageType row

    @Test("resolve(.pageType(id)) returns the matching Vaults row")
    func resolvePageType() {
        let catalog = makeCatalog(
            pageTypes: [makePageType(id: "pt_77", title: "Research")]
        )
        let row = catalog.resolve(.pageType("pt_77"))

        #expect(row != nil)
        #expect(row?.id == "pt_77")
        #expect(row?.label == "Research")
    }

    // MARK: - Test 8: resolve finds agendaEvents

    @Test("resolve(.agendaEvents) returns the Events singleton row")
    func resolveAgendaEvents() {
        let catalog = makeCatalog()
        let row = catalog.resolve(.agendaEvents)

        #expect(row != nil)
        #expect(row?.target == .agendaEvents)
        #expect(row?.id == ReservedTypeID.agendaEvents)
    }

    // MARK: - Test 9: resolve finds agendaTasks

    @Test("resolve(.agendaTasks) returns the Tasks singleton row")
    func resolveAgendaTasks() {
        let catalog = makeCatalog()
        let row = catalog.resolve(.agendaTasks)

        #expect(row != nil)
        #expect(row?.target == .agendaTasks)
        #expect(row?.id == ReservedTypeID.agendaTasks)
    }

    // MARK: - Test 10: resolve(nil) returns nil

    @Test("resolve(nil) returns nil")
    func resolveNilReturnsNil() {
        let catalog = makeCatalog(
            itemTypes: [makeItemType(id: "it_01", title: "X")],
            pageTypes: [makePageType(id: "pt_01", title: "Y")]
        )
        #expect(catalog.resolve(nil) == nil)
    }

    // MARK: - Test 11: resolve(.contextTier) returns nil (not offered)

    @Test("resolve(.contextTier(1)) returns nil — contextTier is not offered in the catalog")
    func resolveContextTierReturnsNil() {
        let catalog = makeCatalog()
        #expect(catalog.resolve(.contextTier(1)) == nil)
        #expect(catalog.resolve(.contextTier(2)) == nil)
        #expect(catalog.resolve(.contextTier(3)) == nil)
    }

    // MARK: - Test 12: default icons applied when icon is nil

    @Test("ItemType with nil icon falls back to 'shippingbox'; PageType with nil icon falls back to 'books.vertical'")
    func defaultIconFallback() {
        let catalog = makeCatalog(
            itemTypes: [makeItemType(id: "it_01", title: "Things", icon: nil)],
            pageTypes: [makePageType(id: "pt_01", title: "Notes", icon: nil)]
        )
        let sections = catalog.sections()
        #expect(sections[0].rows[0].icon == "shippingbox")
        #expect(sections[1].rows[0].icon == "books.vertical")
    }

    // MARK: - Test 13: custom icons are preserved

    @Test("ItemType and PageType custom icons are preserved in rows")
    func customIconPreserved() {
        let catalog = makeCatalog(
            itemTypes: [makeItemType(id: "it_01", title: "Tasks", icon: "checklist")],
            pageTypes: [makePageType(id: "pt_01", title: "Notes", icon: "note.text")]
        )
        let sections = catalog.sections()
        #expect(sections[0].rows[0].icon == "checklist")
        #expect(sections[1].rows[0].icon == "note.text")
    }

    // MARK: - Test 14: Events/Tasks rows use expected icons

    @Test("Events row uses 'calendar' icon; Tasks row uses 'checkmark.circle' icon")
    func singletonIcons() {
        let catalog = makeCatalog()
        let sections = catalog.sections()
        #expect(sections[2].rows[0].icon == "calendar")
        #expect(sections[3].rows[0].icon == "checkmark.circle")
    }

    // MARK: - Test 15: empty types produce empty item/vault sections

    @Test("Empty itemTypes and pageTypes produce 0-row Items and Vaults sections")
    func emptySections() {
        let catalog = makeCatalog()
        let sections = catalog.sections()
        #expect(sections[0].rows.isEmpty)
        #expect(sections[1].rows.isEmpty)
    }

    // MARK: - Test 16: header overrides respected

    @Test("Custom header labels are reflected in section.header and in resolve")
    func customHeaderLabels() {
        var catalog = makeCatalog()
        catalog.eventsHeader = "Calendar"
        catalog.tasksHeader = "Reminders"

        let sections = catalog.sections()
        #expect(sections[2].header == "Calendar")
        #expect(sections[3].header == "Reminders")
        // Singleton row labels also reflect the header override
        #expect(sections[2].rows[0].label == "Calendar")
        #expect(sections[3].rows[0].label == "Reminders")
    }
}
