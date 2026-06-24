import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageCollectionManagerSchemaCRUD")
struct PageCollectionManagerSchemaCRUDTests {

    // MARK: - Helper

    /// Builds a minimal PropertyDefinition fixture with a minted ID.
    private func makeNumberProp(name: String = "Score") -> PropertyDefinition {
        PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: name, type: .number)
    }

    // MARK: - Test 1: addProperty mints ID and persists

    @Test("addProperty with empty id mints prop_ ID and persists to sidecar")
    func addPropertyMintsIDAndPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Notes", icon: nil)
        let pageCollection = manager.types.first!

        // Pass id: "" — addProperty should mint a new ID.
        let def = PropertyDefinition(id: "", name: "Priority", type: .number)
        try await manager.addProperty(def, to: pageCollection.id)

        let updated = manager.types.first { $0.id == pageCollection.id }!
        #expect(updated.properties.count == 1)
        let stored = updated.properties[0]
        #expect(stored.name == "Priority")
        #expect(stored.id.hasPrefix("prop_"))

        let meta = NexusPaths.collectionMetadataURL(forTitle: "Notes", in: nexus)
        let reloaded = try PageCollection.load(from: meta)
        #expect(reloaded.properties.count == 1)
        #expect(reloaded.properties[0].name == "Priority")
        #expect(reloaded.properties[0].id.hasPrefix("prop_"))
    }

    // MARK: - Test 2: rename does not rewrite member files

    @Test("renameProperty updates schema only — member files are untouched")
    func renameDoesNotRewriteMemberFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Notes", icon: nil)
        let pageCollection = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: pageCollection.id)
        let storedPropID = manager.types.first { $0.id == pageCollection.id }!.properties[0].id

        // Write a fake Page file into the PageCollection folder referencing the property.
        let pageTypeFolder = NexusPaths.collectionFolderURL(forTitle: "Notes", in: nexus)
        let pageFile = pageTypeFolder.appendingPathComponent("Page1.md")
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [storedPropID: .number(42)],
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "Hello", to: pageFile)

        let dataBefore = try Data(contentsOf: pageFile)

        try await manager.renameProperty(id: storedPropID, in: pageCollection.id, to: "Rating")

        // Member file must be byte-identical.
        let dataAfter = try Data(contentsOf: pageFile)
        #expect(dataBefore == dataAfter)

        let updatedType = manager.types.first { $0.id == pageCollection.id }!
        #expect(updatedType.properties[0].name == "Rating")
        let meta = NexusPaths.collectionMetadataURL(forTitle: "Notes", in: nexus)
        let reloaded = try PageCollection.load(from: meta)
        #expect(reloaded.properties[0].name == "Rating")
    }

    // MARK: - Test 3: changeType same type is lossless (no confirmation needed)

    @Test("changeType same type is treated as lossless — no throw")
    func changeTypeSameTypeNoOpIsLossless() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Tracker", icon: nil)
        let pageCollection = manager.types.first!

        let prop = makeNumberProp()
        try await manager.addProperty(prop, to: pageCollection.id)
        let storedPropID = manager.types.first { $0.id == pageCollection.id }!.properties[0].id

        // number → number: lossless, no dropConflictingValues required.
        try await manager.changeType(
            of: storedPropID, in: pageCollection.id, to: .number, dropConflictingValues: false
        )

        let updatedType = manager.types.first { $0.id == pageCollection.id }!
        #expect(updatedType.properties[0].type == .number)
    }

    // MARK: - Test 4: changeType lossy with dropConflictingValues strips member-file values

    @Test("changeType lossy with dropConflictingValues=true removes value from member files")
    func changeTypeLossyDropsValuesViaSchemaTransaction() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Tracker", icon: nil)
        let pageCollection = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: pageCollection.id)
        let storedPropID = manager.types.first { $0.id == pageCollection.id }!.properties[0].id

        // Write a fake Page file with a numeric value for the property.
        let pageTypeFolder = NexusPaths.collectionFolderURL(forTitle: "Tracker", in: nexus)
        let pageFile = pageTypeFolder.appendingPathComponent("Entry1.md")
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [storedPropID: .number(99)],
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "Body text", to: pageFile)

        // Change number → checkbox, with value drop.
        try await manager.changeType(
            of: storedPropID, in: pageCollection.id, to: .checkbox, dropConflictingValues: true
        )

        let updatedType = manager.types.first { $0.id == pageCollection.id }!
        #expect(updatedType.properties[0].type == .checkbox)

        // Member file: property key must be GONE.
        let (reloadedFm, _) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageFile)
        #expect(reloadedFm.properties[storedPropID] == nil)
    }

    // MARK: - Test 5 (optional): changeType lossy without confirmation throws

    @Test("changeType lossy without dropConflictingValues throws lossyChangeRequiresConfirmation")
    func changeTypeLossyWithoutConfirmThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Tracker", icon: nil)
        let pageCollection = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: pageCollection.id)
        let storedPropID = manager.types.first { $0.id == pageCollection.id }!.properties[0].id

        await #expect(throws: PageCollectionManagerError.lossyChangeRequiresConfirmation) {
            try await manager.changeType(
                of: storedPropID, in: pageCollection.id, to: .checkbox, dropConflictingValues: false
            )
        }
    }
}
