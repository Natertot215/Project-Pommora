import Foundation
import Testing

@testable import Pommora

/// Cross-Type and between-Collection move tests for PageContentManager (Phase H.1).
///
/// Tests cover:
/// - Same-Type moves (no strip, just file relocation between Collections).
/// - Cross-Type moves (strip non-shared properties by name, retain shared ones).
/// - Cross-Type moves with paired-relation back-ref clearing.
/// - Rollback on mid-transaction failure.
@MainActor
@Suite("Move Page")
struct MovePageTests {

    // MARK: - H.1.1: Same-Type move preserves all properties

    @Test func moveBetweenCollectionsPreservesAllProperties() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Set up a PageType with 3 properties.
        let propA = PropertyDefinition(id: "prop_aaa", name: "Priority", type: .select)
        let propB = PropertyDefinition(id: "prop_bbb", name: "Status", type: .status)
        let propC = PropertyDefinition(id: "prop_ccc", name: "Due", type: .date)
        let vault = try makePageType(
            nexus: nexus, title: "Tasks",
            properties: [propA, propB, propC]
        )

        // CollectionA: source.
        let collA = try makePageCollection(
            nexus: nexus, title: "CollA", in: vault
        )
        // CollectionB: destination.
        let collB = try makePageCollection(
            nexus: nexus, title: "CollB", in: vault
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })

        // Create a page in CollA with all 3 property values set.
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [
                "prop_aaa": .select("high"),
                "prop_bbb": .status("in_progress"),
                "prop_ccc": .date(Date(timeIntervalSince1970: 1_000_000)),
            ],
            createdAt: Date()
        )
        let pageFile = PageFile(frontmatter: fm, body: "body", title: "MyPage")
        let srcURL = NexusPaths.pageFileURL(forTitle: "MyPage", in: collA.folderURL)
        try pageFile.save(to: srcURL)

        let page = PageMeta(id: pageID, title: "MyPage", url: srcURL, frontmatter: fm)
        manager.pagesByCollection[collA.id] = [page]
        manager.pagesByCollection[collB.id] = []

        // Move between collections.
        try await manager.movePageBetweenCollections(page, from: collA, to: collB, in: vault)

        // Source gone, destination exists.
        #expect(!FileManager.default.fileExists(atPath: srcURL.path))
        let dstURL = NexusPaths.pageFileURL(forTitle: "MyPage", in: collB.folderURL)
        #expect(FileManager.default.fileExists(atPath: dstURL.path))

        // All 3 property values intact after move.
        let loaded = try PageFile.load(from: dstURL)
        #expect(loaded.frontmatter.properties["prop_aaa"] == .select("high"))
        #expect(loaded.frontmatter.properties["prop_bbb"] == .status("in_progress"))
        #expect(loaded.frontmatter.properties["prop_ccc"] != nil)

        // In-memory cache updated.
        #expect(manager.pagesByCollection[collA.id]?.isEmpty == true)
        #expect(manager.pagesByCollection[collB.id]?.count == 1)
    }

    // MARK: - H.1.2: Cross-Type move strips non-shared properties

    @Test func moveAcrossTypesStripsNonShared() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // TypeA has [P1, P2, P3]; TypeB has [P1, P4].
        let p1 = PropertyDefinition(id: "prop_001", name: "Priority", type: .select)
        let p2 = PropertyDefinition(id: "prop_002", name: "Status", type: .status)
        let p3 = PropertyDefinition(id: "prop_003", name: "Due", type: .date)
        let p4 = PropertyDefinition(id: "prop_004", name: "Owner", type: .select)

        let typeA = try makePageType(nexus: nexus, title: "TypeA", properties: [p1, p2, p3])
        let typeB = try makePageType(nexus: nexus, title: "TypeB", properties: [p1, p4])

        // No collections — pages live at the Type root.
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [
                "prop_001": .select("high"),    // P1 — shared: KEEP
                "prop_002": .status("done"),    // P2 — TypeA only: STRIP
                "prop_003": .date(Date()),      // P3 — TypeA only: STRIP
            ],
            createdAt: Date()
        )
        let pageFile = PageFile(frontmatter: fm, body: "body text", title: "Doc")
        let srcURL = NexusPaths.pageFileURL(
            forTitle: "Doc",
            in: NexusPaths.vaultFolderURL(forTitle: "TypeA", in: nexus)
        )
        try pageFile.save(to: srcURL)

        let page = PageMeta(id: pageID, title: "Doc", url: srcURL, frontmatter: fm)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.pagesByTypeRoot[typeA.id] = [page]
        manager.pagesByTypeRoot[typeB.id] = []

        try await manager.movePageAcrossTypes(
            page,
            from: typeA, fromCollection: nil,
            to: typeB, toCollection: nil
        )

        // Source removed, destination written.
        #expect(!FileManager.default.fileExists(atPath: srcURL.path))
        let dstURL = NexusPaths.pageFileURL(
            forTitle: "Doc",
            in: NexusPaths.vaultFolderURL(forTitle: "TypeB", in: nexus)
        )
        #expect(FileManager.default.fileExists(atPath: dstURL.path))

        // P1 (shared by name "Priority") retained; P2, P3 stripped.
        let loaded = try PageFile.load(from: dstURL)
        #expect(loaded.frontmatter.properties["prop_001"] == .select("high"))
        #expect(loaded.frontmatter.properties["prop_002"] == nil)
        #expect(loaded.frontmatter.properties["prop_003"] == nil)
        // P4 was never on the page — still absent.
        #expect(loaded.frontmatter.properties["prop_004"] == nil)

        // In-memory caches updated.
        #expect(manager.pagesByTypeRoot[typeA.id]?.isEmpty == true)
        #expect(manager.pagesByTypeRoot[typeB.id]?.count == 1)
    }

    // MARK: - H.1.3: Cross-Type move clears paired-relation back-refs

    @Test func moveAcrossTypesClearsPairedRelationBackRefs() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // TypeProjects has a property "Tasks" (reverse relation, prop_rev).
        let revProp = PropertyDefinition(
            id: "prop_rev",
            name: "Tasks",
            type: .relation,
            dualProperty: nil  // reverse side — no further dual needed for this test
        )
        let typeProjects = try makePageType(nexus: nexus, title: "Projects", properties: [revProp])

        // TypeA has a "Project" relation pointing to typeProjects, with dualProperty → prop_rev.
        let relProp = PropertyDefinition(
            id: "prop_rel",
            name: "Project",
            type: .relation,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "prop_rev",
                syncedPropertyDefinedOnTypeID: typeProjects.id
            )
        )
        // TypeB does NOT have the "Project" property → it will be stripped.
        let typeA = try makePageType(nexus: nexus, title: "TypeA", properties: [relProp])
        let typeB = try makePageType(nexus: nexus, title: "TypeB", properties: [])

        // Page Y lives in TypeProjects and has page X in its "Tasks" reverse.
        let pageXID = ULID.generate()
        let pageYID = ULID.generate()

        let fmY = PageFrontmatter(
            id: pageYID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_rev": .relation([pageXID])],
            createdAt: Date()
        )
        let yURL = NexusPaths.pageFileURL(
            forTitle: "ProjectY",
            in: NexusPaths.vaultFolderURL(forTitle: "Projects", in: nexus)
        )
        try PageFile(frontmatter: fmY, body: "", title: "ProjectY").save(to: yURL)

        // Page X lives in TypeA and points to Y via "Project" relation.
        let fmX = PageFrontmatter(
            id: pageXID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_rel": .relation([pageYID])],
            createdAt: Date()
        )
        let xURL = NexusPaths.pageFileURL(
            forTitle: "TaskX",
            in: NexusPaths.vaultFolderURL(forTitle: "TypeA", in: nexus)
        )
        try PageFile(frontmatter: fmX, body: "", title: "TaskX").save(to: xURL)

        let pageX = PageMeta(id: pageXID, title: "TaskX", url: xURL, frontmatter: fmX)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.pagesByTypeRoot[typeA.id] = [pageX]
        manager.pagesByTypeRoot[typeB.id] = []

        // Move X from TypeA to TypeB — strips "Project" property and clears back-ref.
        try await manager.movePageAcrossTypes(
            pageX,
            from: typeA, fromCollection: nil,
            to: typeB, toCollection: nil
        )

        // Page Y's "Tasks" back-ref to X should be cleared (set to null).
        let loadedY = try PageFile.load(from: yURL)
        let revVal = loadedY.frontmatter.properties["prop_rev"]
        // The back-ref should either be nil (removed) or .null (cleared).
        let backRefCleared =
            revVal == nil
            || revVal == .null
            || revVal == .relation([])
        #expect(backRefCleared)
    }

    // MARK: - H.1.4: Rollback on transaction failure

    @Test func rollbackRestoresPageAndTargetSideOnFailure() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let p1 = PropertyDefinition(id: "prop_x1", name: "Tag", type: .select)
        let typeA = try makePageType(nexus: nexus, title: "SourceType", properties: [p1])
        // TypeB folder does NOT exist — the destination write will fail, triggering rollback.
        let typeB = PageType(
            id: ULID.generate(), title: "MissingType", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        // We intentionally do NOT create the MissingType folder on disk.

        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_x1": .select("active")],
            createdAt: Date()
        )
        let srcURL = NexusPaths.pageFileURL(
            forTitle: "PageX",
            in: NexusPaths.vaultFolderURL(forTitle: "SourceType", in: nexus)
        )
        try PageFile(frontmatter: fm, body: "original", title: "PageX").save(to: srcURL)

        let page = PageMeta(id: pageID, title: "PageX", url: srcURL, frontmatter: fm)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.pagesByTypeRoot[typeA.id] = [page]

        // The move should throw because the destination folder doesn't exist.
        var threw = false
        do {
            try await manager.movePageAcrossTypes(
                page,
                from: typeA, fromCollection: nil,
                to: typeB, toCollection: nil
            )
        } catch {
            threw = true
        }
        #expect(threw)

        // Source file must still be intact at original location.
        #expect(FileManager.default.fileExists(atPath: srcURL.path))
        let loadedBack = try PageFile.load(from: srcURL)
        #expect(loadedBack.frontmatter.id == pageID)
        #expect(loadedBack.frontmatter.properties["prop_x1"] == .select("active"))
    }

    // MARK: - Private setup helpers

    @discardableResult
    private func makePageType(
        nexus: Nexus,
        title: String,
        properties: [PropertyDefinition]
    ) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        in vault: PageType
    ) throws -> PageCollection {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title,
            inVaultTitled: vault.title,
            in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(),
            typeID: vault.id,
            title: title,
            folderURL: folderURL,
            modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        return coll
    }
}
