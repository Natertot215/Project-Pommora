import Foundation
import Testing

@testable import Pommora

/// Phase 10.3b: the relation create-draft save path in `EditPropertyPane`.
///
/// SwiftUI view internals aren't unit-testable, so the build-draft → addProperty
/// save logic was factored into `RelationDraftBuilder`. These tests exercise that
/// helper directly, then drive the same `addProperty` the pane calls and assert
/// the pair lands on disk — mirroring `PairedRelationTargetsTests`.
///
/// GAP: the SwiftUI binding wiring (target Menu, name/icon TextFields, Save-button
/// enablement) is not unit-tested — it's view-bound. `canSaveRelationDraft`'s gate
/// (name + target + reverse all non-empty) is verified indirectly via the builder's
/// own trimming + nil-target rejection.
@MainActor
@Suite("EditPropertyPaneRelation")
struct EditPropertyPaneRelationTests {

    // MARK: - RelationDraftBuilder.targetTypeID

    @Test("targetTypeID: container Types return their ULID")
    func targetTypeIDContainer() {
        #expect(RelationDraftBuilder.targetTypeID(for: .pageType("PT_1")) == "PT_1")
        #expect(RelationDraftBuilder.targetTypeID(for: .itemType("IT_1")) == "IT_1")
    }

    @Test("targetTypeID: Agenda singletons return their reserved ID")
    func targetTypeIDAgenda() {
        #expect(RelationDraftBuilder.targetTypeID(for: .agendaTasks) == ReservedTypeID.agendaTasks)
        #expect(RelationDraftBuilder.targetTypeID(for: .agendaEvents) == ReservedTypeID.agendaEvents)
    }

    @Test("targetTypeID: tier / legacy Collection targets are not paired targets (nil)")
    func targetTypeIDRejected() {
        #expect(RelationDraftBuilder.targetTypeID(for: .contextTier(1)) == nil)
        #expect(RelationDraftBuilder.targetTypeID(for: .pageCollection("C")) == nil)
        #expect(RelationDraftBuilder.targetTypeID(for: .itemCollection("C")) == nil)
    }

    // MARK: - RelationDraftBuilder.makeFinishedDraft

    @Test("makeFinishedDraft: produces a relation def with the target + reverse-name dualProperty")
    func makeFinishedDraftShape() throws {
        let draft = try #require(
            RelationDraftBuilder.makeFinishedDraft(
                existingID: "",
                name: "  Authors  ",
                icon: "person",
                target: .itemType("IT_42"),
                reverseName: "  Notes  "
            )
        )

        #expect(draft.type == .relation)
        #expect(draft.name == "Authors")  // trimmed
        #expect(draft.icon == "person")
        #expect(draft.reverseIcon == nil)  // not supplied → nil
        #expect(draft.relationTarget == .itemType("IT_42"))
        #expect(draft.id.hasPrefix("prop_"))  // minted because existingID empty
        // reverseName carries the trimmed reverse name; dualProperty is the pairing
        // signal with an empty syncedPropertyID (coordinator mints the reverse ID).
        #expect(draft.reverseName == "Notes")
        #expect(draft.dualProperty?.syncedPropertyID == "")
        #expect(draft.dualProperty?.syncedPropertyDefinedOnTypeID == "IT_42")
    }

    @Test("makeFinishedDraft: reverseIcon is preserved on the draft when supplied")
    func makeFinishedDraftReverseIcon() throws {
        let draft = try #require(
            RelationDraftBuilder.makeFinishedDraft(
                existingID: "",
                name: "Authors",
                icon: "person",
                target: .itemType("IT_42"),
                reverseName: "Notes",
                reverseIcon: "doc.text"
            )
        )
        #expect(draft.icon == "person")
        #expect(draft.reverseIcon == "doc.text")
    }

    @Test("makeFinishedDraft: keeps a supplied non-empty ID instead of minting")
    func makeFinishedDraftKeepsID() throws {
        let draft = try #require(
            RelationDraftBuilder.makeFinishedDraft(
                existingID: "prop_existing",
                name: "Rel",
                icon: nil,
                target: .agendaTasks,
                reverseName: "Reverse"
            )
        )
        #expect(draft.id == "prop_existing")
        #expect(draft.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaTasks)
    }

    @Test("makeFinishedDraft: returns nil for a non-paired target (tier)")
    func makeFinishedDraftRejectsTier() {
        let draft = RelationDraftBuilder.makeFinishedDraft(
            existingID: "",
            name: "Rel",
            icon: nil,
            target: .contextTier(2),
            reverseName: "Reverse"
        )
        #expect(draft == nil)
    }

    // MARK: - Full save: page → item (cross-side) via builder + addProperty

    @Test("create-save (page → item): builder draft + addProperty writes both sidecars")
    func createSavePageToItem() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageManager = PageTypeManager(nexus: nexus)
        let itemManager = ItemTypeManager(nexus: nexus)
        await pageManager.loadAll()
        await itemManager.loadAll()

        try await pageManager.createPageType(name: "Notes", icon: nil)
        try await itemManager.createItemType(name: "Authors", icon: nil)

        let notes = try #require(pageManager.types.first { $0.title == "Notes" })
        let authors = try #require(itemManager.types.first { $0.title == "Authors" })

        // Exactly what `EditPropertyPane.commitRelationDraft` builds + calls.
        let finished = try #require(
            RelationDraftBuilder.makeFinishedDraft(
                existingID: "",
                name: "Authors",
                icon: "person",
                target: .itemType(authors.id),
                reverseName: "Notes",
                reverseIcon: "doc.text"
            )
        )
        try await pageManager.addProperty(finished, to: notes.id)

        // Source PageType sidecar gained the relation pointing at the ItemType.
        let diskNotes = try PageType.load(
            from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        let sourceProp = try #require(diskNotes.properties.first { $0.type == .relation })
        #expect(sourceProp.relationTarget == .itemType(authors.id))
        #expect(sourceProp.icon == "person")
        #expect(sourceProp.dualProperty?.syncedPropertyDefinedOnTypeID == authors.id)

        // Target ItemType sidecar gained the reverse relation named "Notes" with icon "doc.text".
        let diskAuthors = try ItemType.load(
            from: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Authors"))
        let reverseProp = try #require(diskAuthors.properties.first { $0.type == .relation })
        #expect(reverseProp.name == "Notes")
        #expect(reverseProp.icon == "doc.text")
        #expect(reverseProp.relationTarget == .pageType(notes.id))

        // IDs cross-reference (the pair is fully wired).
        #expect(sourceProp.dualProperty?.syncedPropertyID == reverseProp.id)
        #expect(reverseProp.dualProperty?.syncedPropertyID == sourceProp.id)
    }

    // MARK: - Full save: item → agendaEvents via builder + addProperty

    @Test("create-save (item → agendaEvents): AgendaEventSchema gains the reverse property")
    func createSaveItemToAgendaEvents() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let itemManager = ItemTypeManager(nexus: nexus)
        await itemManager.loadAll()
        try await itemManager.createItemType(name: "Books", icon: nil)

        // Seed the Agenda Events singleton schema on disk.
        try NexusPaths.ensureDirectoryExists(NexusPaths.eventsDir(in: nexus))
        try AtomicJSON.write(
            AgendaEventSchema.defaultSeed(), to: NexusPaths.eventSchemaURL(in: nexus))

        let books = try #require(itemManager.types.first { $0.title == "Books" })

        let finished = try #require(
            RelationDraftBuilder.makeFinishedDraft(
                existingID: "",
                name: "Related Event",
                icon: nil,
                target: .agendaEvents,
                reverseName: "Books"
            )
        )
        try await itemManager.addProperty(finished, to: books.id)

        // Source ItemType sidecar.
        let diskBooks = try ItemType.load(
            from: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Books"))
        let sourceProp = try #require(diskBooks.properties.first { $0.type == .relation })
        #expect(sourceProp.relationTarget == .agendaEvents)
        #expect(sourceProp.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaEvents)

        // Reloaded AgendaEventSchema gained the reverse named "Books".
        let reloaded = try AtomicJSON.decode(
            AgendaEventSchema.self, from: NexusPaths.eventSchemaURL(in: nexus))
        let reverseProp = try #require(reloaded.properties.first { $0.type == .relation })
        #expect(reverseProp.name == "Books")
        #expect(reverseProp.relationTarget == .itemType(books.id))
        #expect(sourceProp.dualProperty?.syncedPropertyID == reverseProp.id)
        #expect(reverseProp.dualProperty?.syncedPropertyID == sourceProp.id)
    }
}
