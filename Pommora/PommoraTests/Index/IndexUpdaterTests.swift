import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Test helpers

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

// MARK: - Suite

@Suite("IndexUpdater")
@MainActor
struct IndexUpdaterTests {

    // MARK: - PageCollection

    @Test func createPageCollectionIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

        let count = try countRows(in: "page_collections", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "page_collections", db: idx)
        #expect(row?["id"] as String? == pt.id)
        #expect(row?["title"] as String? == "Notes")
    }

    @Test func deletePageCollectionRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        try updater.deletePageCollection(id: pt.id)

        let count = try countRows(in: "page_collections", db: idx)
        #expect(count == 0)
    }

    // MARK: - PageSet

    @Test func createPageSetIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetAsCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        let count = try countRows(in: "page_sets", db: idx)
        #expect(count == 1)
        let row = try firstRow(in: "page_sets", db: idx)
        #expect(row?["id"] as String? == pc.id)
        #expect(row?["parent_collection_id"] as String? == pt.id)
        #expect(row?["parent_set_id"] as String? == nil)
    }

    @Test func upsertPageSetPersistsEntitySchemaVersion() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

        // A schemaVersion ≠ the previously-hardcoded literal 1.
        let folderURL = URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)")
        let pc = PageSet(
            id: ULID.generate(), parentID: pt.id, title: "Migrated",
            folderURL: folderURL, modifiedAt: Date(), schemaVersion: 7)
        try updater.upsertPageCollection(pc)

        let row = try firstRow(in: "page_sets", db: idx, where: "id = '\(pc.id)'")
        #expect(row?["schema_version"] as Int? == 7)
    }

    @Test func deletePageSetRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetAsCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)
        try updater.deletePageSet(id: pc.id)

        let count = try countRows(in: "page_sets", db: idx)
        #expect(count == 0)
    }

    // MARK: - Contexts

    @Test func upsertContextGenericWritesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        try updater.upsertContext(id: "ctx-1", tier: 2, title: "Topic A", icon: nil)

        let row = try firstRow(in: "contexts", db: idx, where: "id = 'ctx-1'")
        #expect(row?["tier"] as Int? == 2)
        #expect(row?["title"] as String? == "Topic A")
    }

    // MARK: - pageIDs scope filtering (surgical-reconcile set-sync)

    @Test func pageIDsScopesPrecisely() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetAsCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        let rootPage = Fixtures.pageMeta(title: "Root")
        let collectionPage = Fixtures.pageMeta(title: "InCollection")
        try updater.upsertPage(rootPage, pageCollectionID: pt.id, pageSetID: nil)
        try updater.upsertPage(collectionPage, pageCollectionID: pt.id, pageSetID: pc.id)

        // Type-root scope excludes the Collection page.
        let rootIDs = try updater.pageIDs(pageCollectionID: pt.id, pageSetID: nil)
        #expect(rootIDs == [rootPage.id])

        // Collection scope returns only its own page.
        let colIDs = try updater.pageIDs(pageCollectionID: pt.id, pageSetID: pc.id)
        #expect(colIDs == [collectionPage.id])
    }

    // MARK: - PageCollection title rename updates index

    @Test func renamePageCollectionUpdatesIndexedTitle() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        var pt = Fixtures.pageCollection(title: "Old Name")
        try updater.upsertPageCollection(pt)

        pt.title = "New Name"
        pt.modifiedAt = Date()
        try updater.upsertPageCollection(pt)

        let count = try countRows(in: "page_collections", db: idx)
        #expect(count == 1, "upsert should update — not duplicate")
        let row = try firstRow(in: "page_collections", db: idx)
        #expect(row?["title"] as String? == "New Name")
    }

    // MARK: - AgendaTask

    @Test func createAgendaTaskIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let task = Fixtures.agendaTask()
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
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let task = Fixtures.agendaTask()
        try updater.upsertAgendaTask(task)
        try updater.deleteAgendaTask(id: task.id)

        let count = try countRows(in: "agenda_tasks", db: idx)
        #expect(count == 0)
    }

    // MARK: - AgendaEvent

    @Test func createAgendaEventIndexesARow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let event = Fixtures.agendaEvent()
        try updater.upsertAgendaEvent(event)

        let count = try countRows(in: "agenda_events", db: idx)
        #expect(count == 1)
    }

    @Test func deleteAgendaEventRemovesRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let event = Fixtures.agendaEvent()
        try updater.upsertAgendaEvent(event)
        try updater.deleteAgendaEvent(id: event.id)

        let count = try countRows(in: "agenda_events", db: idx)
        #expect(count == 0)
    }

    // MARK: - PropertyDefinition

    @Test func addPropertyIndexesAPropertyDefinitionRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

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
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

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
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

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

    // MARK: - Page upsert with tier-relation extraction

    @Test func upsertPageWithTierFieldsIndexesTierRelationRows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

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
        try updater.upsertPage(meta, pageCollectionID: pt.id)

        // The page's tier1 value emits one `context_links` row carrying the reserved
        // tier-1 property id and the Context as target.
        let relCount = try countRows(in: "context_links", db: idx)
        #expect(relCount == 1)
        let rel = try firstRow(in: "context_links", db: idx)
        #expect(rel?["source_id"] as String? == pageID)
        #expect(rel?["property_id"] as String? == ReservedPropertyID.tier1)
        #expect(rel?["target_id"] as String? == contextID)
    }
}
