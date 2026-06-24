import Foundation
import Testing

@testable import Pommora

/// Cross-Type and between-Collection move tests for PageContentManager (Phase H.1).
///
/// Tests cover:
/// - Same-Type moves (no strip, just file relocation between Collections).
/// - Cross-Type moves (strip non-shared properties by name, retain shared ones).
/// - Rollback on mid-transaction failure.
@MainActor
@Suite("Move Page")
struct MovePageTests {

    // MARK: - H.1.1: Same-Type move preserves all properties

    @Test func moveBetweenCollectionsPreservesAllProperties() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let propA = PropertyDefinition(id: "prop_aaa", name: "Priority", type: .select)
        let propB = PropertyDefinition(id: "prop_bbb", name: "Status", type: .status)
        let propC = PropertyDefinition(id: "prop_ccc", name: "Due", type: .date)
        let vault = try makePageCollection(
            nexus: nexus, title: "Tasks",
            properties: [propA, propB, propC]
        )

        let collA = try makePageSet(
            nexus: nexus, title: "CollA", in: vault
        )
        let collB = try makePageSet(
            nexus: nexus, title: "CollB", in: vault
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })

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

        try await manager.movePageBetweenCollections(page, from: collA, to: collB, in: vault)

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

        let typeA = try makePageCollection(nexus: nexus, title: "TypeA", properties: [p1, p2, p3])
        let typeB = try makePageCollection(nexus: nexus, title: "TypeB", properties: [p1, p4])

        // No collections — pages live at the Type root.
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [
                "prop_001": .select("high"),  // P1 — shared: KEEP
                "prop_002": .status("done"),  // P2 — TypeA only: STRIP
                "prop_003": .date(Date()),  // P3 — TypeA only: STRIP
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

    // MARK: - H.1.4: Rollback on transaction failure

    @Test func rollbackRestoresPageAndTargetSideOnFailure() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let p1 = PropertyDefinition(id: "prop_x1", name: "Tag", type: .select)
        let typeA = try makePageCollection(nexus: nexus, title: "SourceType", properties: [p1])
        // TypeB folder does NOT exist — the destination write will fail, triggering rollback.
        let typeB = PageCollection(
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

    // MARK: - H.1.5: Move onto a same-title sibling is rejected (no clobber)

    /// Moving a Page into a Collection that already holds a same-title Page must
    /// throw `duplicateTitle` and leave the destination Page's body intact — the
    /// move path stages via `SchemaTransaction` (which would back up + drop the
    /// existing file), so a pre-check is the only thing standing between the user
    /// and silent data loss.
    @Test func moveBetweenCollectionsOntoSameTitleRejectedNoClobber() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Tasks", properties: [])
        let collA = try makePageSet(nexus: nexus, title: "CollA", in: vault)
        let collB = try makePageSet(nexus: nexus, title: "CollB", in: vault)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })

        // Same title "Notes" in BOTH collections, distinct ids + bodies.
        let srcID = ULID.generate()
        let dstID = ULID.generate()
        let srcFM = PageFrontmatter(
            id: srcID, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        let dstFM = PageFrontmatter(
            id: dstID, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        let srcURL = NexusPaths.pageFileURL(forTitle: "Notes", in: collA.folderURL)
        let dstURL = NexusPaths.pageFileURL(forTitle: "Notes", in: collB.folderURL)
        try PageFile(frontmatter: srcFM, body: "SOURCE BODY", title: "Notes").save(to: srcURL)
        try PageFile(frontmatter: dstFM, body: "DEST BODY", title: "Notes").save(to: dstURL)

        let srcPage = PageMeta(id: srcID, title: "Notes", url: srcURL, frontmatter: srcFM)
        manager.pagesByCollection[collA.id] = [srcPage]
        manager.pagesByCollection[collB.id] = [
            PageMeta(id: dstID, title: "Notes", url: dstURL, frontmatter: dstFM)
        ]

        await #expect(throws: PageCRUDError.duplicateTitle) {
            try await manager.movePageBetweenCollections(srcPage, from: collA, to: collB, in: vault)
        }

        // Neither file was clobbered: both bodies + both files survive.
        #expect(try PageFile.load(from: srcURL).body == "SOURCE BODY")
        #expect(try PageFile.load(from: dstURL).body == "DEST BODY")
        #expect(try PageFile.load(from: dstURL).frontmatter.id == dstID)
        #expect(manager.pagesByCollection[collA.id]?.count == 1)
        #expect(manager.pagesByCollection[collB.id]?.count == 1)
    }

    // MARK: - Cross-Type move strips schema, keeps foreign keys (Task 7 / PagesV2)

    /// A Page→Page move across Page Types must strip the Type-scoped schema
    /// property the destination Type does not share, and carry any foreign
    /// frontmatter key through.
    ///
    /// PagesV2: `Class` is RETIRED as a modeled key — an on-disk `Class` entry
    /// is now plain foreign frontmatter, preserved BY VALUE like any other
    /// non-modeled key. The raw-text assert below pins that carry-through.
    @Test func moveAcrossTypesCarriesClassStampStripsSchemaKeepsForeign() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // TypeA owns "Priority" (prop_a, schema-scoped → STRIP on move to TypeB).
        let propA = PropertyDefinition(id: "prop_a", name: "Priority", type: .select)
        let typeA = try makePageCollection(nexus: nexus, title: "TypeA", properties: [propA])
        let typeB = try makePageCollection(nexus: nexus, title: "TypeB", properties: [])

        // Hand-author a `.md` Page with `Class: page`, the TypeA schema property,
        // AND a foreign (non-Pommora) frontmatter key.
        let pageID = ULID.generate()
        let srcURL = NexusPaths.pageFileURL(
            forTitle: "Doc",
            in: NexusPaths.vaultFolderURL(forTitle: "TypeA", in: nexus)
        )
        let raw = """
            ---
            id: \(pageID)
            Class: page
            plugin_color: "#abcdef"
            tier1: []
            tier2: []
            tier3: []
            properties:
              prop_a: high
            created_at: 2026-01-01T00:00:00Z
            ---

            the carried body
            """
        try raw.data(using: .utf8)!.write(to: srcURL, options: [.atomic])

        let loadedSrc = try PageFile.load(from: srcURL)
        #expect(loadedSrc.frontmatter.properties["prop_a"] == .select("high"))

        let page = PageMeta(id: pageID, title: "Doc", url: srcURL, frontmatter: loadedSrc.frontmatter)
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.pagesByTypeRoot[typeA.id] = [page]
        manager.pagesByTypeRoot[typeB.id] = []

        try await manager.movePageAcrossTypes(
            page,
            from: typeA, fromCollection: nil,
            to: typeB, toCollection: nil
        )

        let dstURL = NexusPaths.pageFileURL(
            forTitle: "Doc",
            in: NexusPaths.vaultFolderURL(forTitle: "TypeB", in: nexus)
        )
        #expect(FileManager.default.fileExists(atPath: dstURL.path))

        let loadedDst = try PageFile.load(from: dstURL)
        // Schema property dropped, foreign keys + body preserved.
        #expect(loadedDst.frontmatter.properties["prop_a"] == nil)
        #expect(loadedDst.body == "the carried body")
        let after = try String(contentsOf: dstURL, encoding: .utf8)
        // The legacy on-disk `Class` key is foreign frontmatter now (PagesV2) —
        // it must survive the move BY VALUE, exactly like `plugin_color`.
        #expect(after.contains("Class: page"))
        #expect(after.contains("plugin_color"))
    }

    // MARK: - Private setup helpers

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        properties: [PropertyDefinition]
    ) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageSet(
        nexus: Nexus,
        title: String,
        in pageCollection: PageCollection
    ) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title,
            inVaultTitled: pageCollection.title,
            in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: pageCollection.id,
            title: title,
            folderURL: folderURL,
            modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return coll
    }
}
