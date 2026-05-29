import Foundation
import Testing

@testable import Pommora

/// Phase 10.3a: Tests that `PageTypeManager.addProperty` / `ItemTypeManager.addProperty`
/// create paired relations for ALL user target kinds — not just same-side. Each test
/// resolves the target `TypeKind` from `def.relationTarget` and asserts the reverse
/// property lands on the *target's* sidecar pointing back at the source.
///
/// Cross-side targets (page → item, item → page) live outside the calling manager's
/// in-memory `types`; resolution walks the Nexus root via `ItemType.find` / `PageType.find`.
/// Agenda targets load the singleton schema from `_taskconfig.json` / `_eventconfig.json`.
@MainActor
@Suite("PairedRelationTargets")
struct PairedRelationTargetsTests {

    // MARK: - Helpers

    /// Seeds an `AgendaTaskSchema` on disk (default seed) and returns it.
    @discardableResult
    private static func seedTaskSchema(nexus: Nexus) throws -> AgendaTaskSchema {
        try NexusPaths.ensureDirectoryExists(NexusPaths.tasksDir(in: nexus))
        let schema = AgendaTaskSchema.defaultSeed()
        try AtomicJSON.write(schema, to: NexusPaths.taskSchemaURL(in: nexus))
        return schema
    }

    /// Seeds an `AgendaEventSchema` on disk (default seed) and returns it.
    @discardableResult
    private static func seedEventSchema(nexus: Nexus) throws -> AgendaEventSchema {
        try NexusPaths.ensureDirectoryExists(NexusPaths.eventsDir(in: nexus))
        let schema = AgendaEventSchema.defaultSeed()
        try AtomicJSON.write(schema, to: NexusPaths.eventSchemaURL(in: nexus))
        return schema
    }

    // MARK: - page → item (cross-side, target loaded from disk)

    @Test("page → item: source PageType + target ItemType both gain reverse-linked relations")
    func pageToItemCrossSide() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageManager = PageTypeManager(nexus: nexus)
        let itemManager = ItemTypeManager(nexus: nexus)
        await pageManager.loadAll()
        await itemManager.loadAll()

        try await pageManager.createPageType(name: "Notes", icon: nil)
        try await itemManager.createItemType(name: "Authors", icon: nil)

        let notes = pageManager.types.first { $0.title == "Notes" }!
        let authors = itemManager.types.first { $0.title == "Authors" }!

        // Add a relation on the PageType pointing at the cross-side ItemType.
        let def = PropertyDefinition(
            id: "",
            name: "Authors",
            type: .relation,
            relationTarget: .itemType(authors.id),
            reverseName: "Notes",  // reverse display name (add-time)
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",  // coordinator mints the reverse ID
                syncedPropertyDefinedOnTypeID: authors.id
            )
        )
        try await pageManager.addProperty(def, to: notes.id)

        // Source PageType sidecar gained the relation pointing at the ItemType.
        let diskNotes = try PageType.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        let sourceProp = diskNotes.properties.first { $0.type == .relation }
        #expect(sourceProp != nil)
        #expect(sourceProp?.relationTarget == .itemType(authors.id))
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == authors.id)

        // Target ItemType sidecar gained a reverse relation pointing back at the PageType.
        let diskAuthors = try ItemType.load(
            from: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Authors"))
        let reverseProp = diskAuthors.properties.first { $0.type == .relation }
        #expect(reverseProp != nil)
        #expect(reverseProp?.name == "Notes")
        #expect(reverseProp?.relationTarget == .pageType(notes.id))
        #expect(reverseProp?.dualProperty?.syncedPropertyDefinedOnTypeID == notes.id)

        // IDs cross-reference.
        #expect(sourceProp?.dualProperty?.syncedPropertyID == reverseProp?.id)
        #expect(reverseProp?.dualProperty?.syncedPropertyID == sourceProp?.id)
    }

    // MARK: - page → agendaTasks (Agenda singleton, loaded from disk)

    @Test("page → agendaTasks: AgendaTaskSchema sidecar gains the reverse property")
    func pageToAgendaTasks() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageManager = PageTypeManager(nexus: nexus)
        await pageManager.loadAll()
        try await pageManager.createPageType(name: "Notes", icon: nil)
        try Self.seedTaskSchema(nexus: nexus)

        let notes = pageManager.types.first { $0.title == "Notes" }!

        let def = PropertyDefinition(
            id: "",
            name: "RelatedTask",
            type: .relation,
            relationTarget: .agendaTasks,
            reverseName: "Notes",
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",
                syncedPropertyDefinedOnTypeID: ReservedTypeID.agendaTasks
            )
        )
        try await pageManager.addProperty(def, to: notes.id)

        // Source PageType sidecar.
        let diskNotes = try PageType.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        let sourceProp = diskNotes.properties.first { $0.type == .relation }
        #expect(sourceProp != nil)
        #expect(sourceProp?.relationTarget == .agendaTasks)
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaTasks)

        // Reloaded AgendaTaskSchema gained the reverse property pointing back at the PageType.
        let reloadedTaskSchema = try AtomicJSON.decode(
            AgendaTaskSchema.self, from: NexusPaths.taskSchemaURL(in: nexus))
        let reverseProp = reloadedTaskSchema.properties.first { $0.type == .relation }
        #expect(reverseProp != nil)
        #expect(reverseProp?.name == "Notes")
        #expect(reverseProp?.relationTarget == .pageType(notes.id))
        #expect(reverseProp?.dualProperty?.syncedPropertyDefinedOnTypeID == notes.id)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == reverseProp?.id)
        #expect(reverseProp?.dualProperty?.syncedPropertyID == sourceProp?.id)
    }

    // MARK: - item → page (cross-side, target loaded from disk)

    @Test("item → page: source ItemType + target PageType both gain reverse-linked relations")
    func itemToPageCrossSide() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageManager = PageTypeManager(nexus: nexus)
        let itemManager = ItemTypeManager(nexus: nexus)
        await pageManager.loadAll()
        await itemManager.loadAll()

        try await itemManager.createItemType(name: "Books", icon: nil)
        try await pageManager.createPageType(name: "Reviews", icon: nil)

        let books = itemManager.types.first { $0.title == "Books" }!
        let reviews = pageManager.types.first { $0.title == "Reviews" }!

        let def = PropertyDefinition(
            id: "",
            name: "Reviews",
            type: .relation,
            relationTarget: .pageType(reviews.id),
            reverseName: "Books",
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",
                syncedPropertyDefinedOnTypeID: reviews.id
            )
        )
        try await itemManager.addProperty(def, to: books.id)

        // Source ItemType sidecar gained the relation pointing at the PageType.
        let diskBooks = try ItemType.load(
            from: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Books"))
        let sourceProp = diskBooks.properties.first { $0.type == .relation }
        #expect(sourceProp != nil)
        #expect(sourceProp?.relationTarget == .pageType(reviews.id))
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == reviews.id)

        // Target PageType sidecar gained a reverse relation pointing back at the ItemType.
        let diskReviews = try PageType.load(
            from: NexusPaths.vaultMetadataURL(forTitle: "Reviews", in: nexus))
        let reverseProp = diskReviews.properties.first { $0.type == .relation }
        #expect(reverseProp != nil)
        #expect(reverseProp?.name == "Books")
        #expect(reverseProp?.relationTarget == .itemType(books.id))
        #expect(reverseProp?.dualProperty?.syncedPropertyDefinedOnTypeID == books.id)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == reverseProp?.id)
        #expect(reverseProp?.dualProperty?.syncedPropertyID == sourceProp?.id)
    }

    // MARK: - item → agendaEvents (Agenda singleton, loaded from disk)

    @Test("item → agendaEvents: AgendaEventSchema sidecar gains the reverse property")
    func itemToAgendaEvents() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let itemManager = ItemTypeManager(nexus: nexus)
        await itemManager.loadAll()
        try await itemManager.createItemType(name: "Books", icon: nil)
        try Self.seedEventSchema(nexus: nexus)

        let books = itemManager.types.first { $0.title == "Books" }!

        let def = PropertyDefinition(
            id: "",
            name: "RelatedEvent",
            type: .relation,
            relationTarget: .agendaEvents,
            reverseName: "Books",
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",
                syncedPropertyDefinedOnTypeID: ReservedTypeID.agendaEvents
            )
        )
        try await itemManager.addProperty(def, to: books.id)

        // Source ItemType sidecar.
        let diskBooks = try ItemType.load(
            from: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Books"))
        let sourceProp = diskBooks.properties.first { $0.type == .relation }
        #expect(sourceProp != nil)
        #expect(sourceProp?.relationTarget == .agendaEvents)
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaEvents)

        // Reloaded AgendaEventSchema gained the reverse property pointing back at the ItemType.
        let reloadedEventSchema = try AtomicJSON.decode(
            AgendaEventSchema.self, from: NexusPaths.eventSchemaURL(in: nexus))
        let reverseProp = reloadedEventSchema.properties.first { $0.type == .relation }
        #expect(reverseProp != nil)
        #expect(reverseProp?.name == "Books")
        #expect(reverseProp?.relationTarget == .itemType(books.id))
        #expect(reverseProp?.dualProperty?.syncedPropertyDefinedOnTypeID == books.id)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == reverseProp?.id)
        #expect(reverseProp?.dualProperty?.syncedPropertyID == sourceProp?.id)
    }
}
