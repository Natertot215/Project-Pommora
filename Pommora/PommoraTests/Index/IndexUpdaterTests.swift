import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Test helpers

private func makeIndex(at nexus: Nexus) throws -> PommoraIndex {
    let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
    return idx
}

private func countRows(in table: String, db index: PommoraIndex) throws -> Int {
    try index.dbQueue.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
    }
}

private func firstRow(in table: String, db index: PommoraIndex, where clause: String = "1=1") throws -> Row? {
    try index.dbQueue.read { db in
        try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE \(clause)")
    }
}

// MARK: - Minimal entity factories

private func makePageType(title: String = "Notes") -> PageType {
    PageType(
        id: ULID.generate(), title: title, icon: nil,
        properties: [], views: [], modifiedAt: Date()
    )
}

private func makeItemType(title: String = "Tasks") -> ItemType {
    ItemType(
        id: ULID.generate(), title: title, icon: nil,
        properties: [], views: [], modifiedAt: Date()
    )
}

private func makePageCollection(typeID: String, title: String = "Archive") -> PageCollection {
    let folderURL = URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)")
    return PageCollection(id: ULID.generate(), typeID: typeID, title: title, folderURL: folderURL, modifiedAt: Date())
}

private func makeItemCollection(typeID: String, title: String = "Backlog") -> ItemCollection {
    let folderURL = URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)")
    return ItemCollection(id: ULID.generate(), typeID: typeID, title: title, folderURL: folderURL, modifiedAt: Date())
}

private func makeAgendaTask(title: String = "Buy milk") -> AgendaTask {
    let now = Date()
    return AgendaTask(
        id: ULID.generate(), title: title, icon: nil,
        description: "",
        dueAt: nil, dueFloating: false, dueAllDay: false,
        startAt: nil, completed: false, completedAt: nil,
        priority: 0, recurrence: nil, alarmOffsets: [],
        calendarID: nil, eventkitUUID: nil,
        tier1: [], tier2: [], tier3: [],
        createdAt: now, modifiedAt: now,
        properties: [:]
    )
}

private func makeAgendaEvent(title: String = "Team meeting") -> AgendaEvent {
    let now = Date()
    let later = now.addingTimeInterval(3600)
    return AgendaEvent(
        id: ULID.generate(), title: title, icon: nil,
        description: "",
        startAt: now, endAt: later, allDay: false,
        location: nil, recurrence: nil,
        alarmOffsets: [], alarmAbsolute: [],
        calendarID: nil, eventkitUUID: nil,
        tier1: [], tier2: [], tier3: [],
        createdAt: now, modifiedAt: now,
        properties: [:]
    )
}

private func makeItem(title: String = "Widget") -> Item {
    let now = Date()
    return Item(
        id: ULID.generate(), title: title, icon: nil, description: "",
        tier1: [], tier2: [], tier3: [],
        properties: [:],
        createdAt: now, modifiedAt: now
    )
}

private func makePageMeta(id: String = ULID.generate(), title: String = "Hello") -> PageMeta {
    let url = URL(fileURLWithPath: "/tmp/\(id).md")
    let frontmatter = PageFrontmatter(
        id: id, icon: nil,
        tier1: [], tier2: [], tier3: [],
        properties: [:],
        createdAt: Date()
    )
    return PageMeta(id: id, title: title, url: url, frontmatter: frontmatter)
}

// MARK: - Suite

@Suite("IndexUpdater")
@MainActor
struct IndexUpdaterTests {

    // MARK: - PageType

    @Test func createPageTypeIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let count = try countRows(in: "page_types", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "page_types", db: idx)
        #expect(row?["id"] as String? == pt.id)
        #expect(row?["title"] as String? == "Notes")
    }

    @Test func deletePageTypeRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)
        try updater.deletePageType(id: pt.id)

        let count = try countRows(in: "page_types", db: idx)
        #expect(count == 0)
    }

    // MARK: - PageCollection

    @Test func createPageCollectionIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)
        let pc = makePageCollection(typeID: pt.id)
        try updater.upsertPageCollection(pc)

        let count = try countRows(in: "page_collections", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "page_collections", db: idx)
        #expect(row?["id"] as String? == pc.id)
        #expect(row?["page_type_id"] as String? == pt.id)
    }

    @Test func deletePageCollectionRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)
        let pc = makePageCollection(typeID: pt.id)
        try updater.upsertPageCollection(pc)
        try updater.deletePageCollection(id: pc.id)

        let count = try countRows(in: "page_collections", db: idx)
        #expect(count == 0)
    }

    // MARK: - ItemType

    @Test func createItemTypeIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)

        let count = try countRows(in: "item_types", db: idx)
        #expect(count == 1)
    }

    @Test func deleteItemTypeRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)
        try updater.deleteItemType(id: it.id)

        let count = try countRows(in: "item_types", db: idx)
        #expect(count == 0)
    }

    // MARK: - PageType title rename updates index

    @Test func renamePageTypeUpdatesIndexedTitle() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        var pt = makePageType(title: "Old Name")
        try updater.upsertPageType(pt)

        pt.title = "New Name"
        pt.modifiedAt = Date()
        try updater.upsertPageType(pt)

        let count = try countRows(in: "page_types", db: idx)
        #expect(count == 1, "upsert should replace — not duplicate")
        let row = try firstRow(in: "page_types", db: idx)
        #expect(row?["title"] as String? == "New Name")
    }

    // MARK: - AgendaTask

    @Test func createAgendaTaskIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let task = makeAgendaTask()
        try updater.upsertAgendaTask(task)

        let count = try countRows(in: "agenda_tasks", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "agenda_tasks", db: idx)
        #expect(row?["id"] as String? == task.id)
        #expect(row?["title"] as String? == "Buy milk")
    }

    @Test func deleteAgendaTaskRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let task = makeAgendaTask()
        try updater.upsertAgendaTask(task)
        try updater.deleteAgendaTask(id: task.id)

        let count = try countRows(in: "agenda_tasks", db: idx)
        #expect(count == 0)
    }

    // MARK: - AgendaEvent

    @Test func createAgendaEventIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let event = makeAgendaEvent()
        try updater.upsertAgendaEvent(event)

        let count = try countRows(in: "agenda_events", db: idx)
        #expect(count == 1)
    }

    @Test func deleteAgendaEventRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let event = makeAgendaEvent()
        try updater.upsertAgendaEvent(event)
        try updater.deleteAgendaEvent(id: event.id)

        let count = try countRows(in: "agenda_events", db: idx)
        #expect(count == 0)
    }

    // MARK: - PropertyDefinition

    @Test func addPropertyIndexesAPropertyDefinitionRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let def = PropertyDefinition(
            id: ReservedPropertyID.mintUserPropertyID(),
            name: "Priority",
            type: .number
        )
        try updater.upsertPropertyDefinition(def, owningTypeID: pt.id, owningTypeKind: "page_type", position: 0)

        let count = try countRows(in: "property_definitions", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "property_definitions", db: idx)
        #expect(row?["name"] as String? == "Priority")
        #expect(row?["type"] as String? == "number")
    }

    @Test func renamePropertyUpdatesIndexedName() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        var def = PropertyDefinition(
            id: ReservedPropertyID.mintUserPropertyID(),
            name: "Old Name",
            type: .url
        )
        try updater.upsertPropertyDefinition(def, owningTypeID: pt.id, owningTypeKind: "page_type", position: 0)

        def.name = "New Name"
        try updater.upsertPropertyDefinition(def, owningTypeID: pt.id, owningTypeKind: "page_type", position: 0)

        let count = try countRows(in: "property_definitions", db: idx)
        #expect(count == 1, "rename should upsert, not duplicate")
        let row = try firstRow(in: "property_definitions", db: idx)
        #expect(row?["name"] as String? == "New Name")
    }

    @Test func deletePropertyRemovesPropertyDefinitionRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let def = PropertyDefinition(
            id: ReservedPropertyID.mintUserPropertyID(),
            name: "Tags",
            type: .multiSelect,
            selectOptions: [
                PropertyDefinition.SelectOption(value: "alpha", label: "Alpha", color: nil)
            ]
        )
        try updater.upsertPropertyDefinition(def, owningTypeID: pt.id, owningTypeKind: "page_type", position: 0)
        try updater.deletePropertyDefinition(id: def.id)

        let count = try countRows(in: "property_definitions", db: idx)
        #expect(count == 0)
    }

    // MARK: - Item upsert with relation extraction

    @Test func upsertItemIndexesItemRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)

        let item = makeItem()
        try updater.upsertItem(item, itemTypeID: it.id, itemCollectionID: nil)

        let count = try countRows(in: "items", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "items", db: idx)
        #expect(row?["title"] as String? == "Widget")
        #expect(row?["item_type_id"] as String? == it.id)
    }

    @Test func upsertItemWithRelationPropertyIndexesRelationRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)

        let targetID = ULID.generate()
        let propID = ReservedPropertyID.mintUserPropertyID()
        let now = Date()
        let item = Item(
            id: ULID.generate(), title: "Widget", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [propID: .relation(targetID)],
            createdAt: now, modifiedAt: now
        )
        try updater.upsertItem(item, itemTypeID: it.id, itemCollectionID: nil)

        let relCount = try countRows(in: "relations", db: idx)
        #expect(relCount == 1)
        let rel = try firstRow(in: "relations", db: idx)
        #expect(rel?["source_id"] as String? == item.id)
        #expect(rel?["target_id"] as String? == targetID)
        #expect(rel?["property_id"] as String? == propID)
    }

    // MARK: - Page upsert with tier-link extraction

    @Test func upsertPageWithTierLinksIndexesTierLinkRows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let contextID = ULID.generate()
        let pageID = ULID.generate()
        let url = URL(fileURLWithPath: "/tmp/\(pageID).md")
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [contextID], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        let meta = PageMeta(id: pageID, title: "Doc", url: url, frontmatter: frontmatter)
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)

        let tierCount = try countRows(in: "tier_links", db: idx)
        #expect(tierCount == 1)
        let link = try firstRow(in: "tier_links", db: idx)
        #expect(link?["entity_id"] as String? == pageID)
        #expect(link?["tier"] as Int? == 1)
        #expect(link?["target_id"] as String? == contextID)
    }
}
