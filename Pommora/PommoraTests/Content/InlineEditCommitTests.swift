import Foundation
import Testing
import Yams

@testable import Pommora

/// Baseline + regression coverage for inline-edit COMMIT behavior across the
/// surfaces that persist a Page edit through `PageContentManager`:
///   - table / gallery cells → `updatePageProperty`
///   - page sidebar inspector + Page-preview window → `updatePageFrontmatter`
///
/// Two contracts are pinned:
///   1. PERSISTENCE (happy path): the edit lands in BOTH the in-memory cache
///      (what the cells render) AND on disk, preserving the body and foreign
///      (plugin) frontmatter. The refactor that removes the commit lag must not
///      regress any of this — these stay green before and after.
///   2. DECOUPLING (the lag fix): the in-memory cache reflects the edit WITHOUT
///      depending on a successful disk round-trip. Encoded as — even when the
///      on-disk file is gone (so persistence throws), the cache still shows the
///      new value, and the failure is surfaced via `pendingError` rather than
///      swallowed. Pre-fix the cache update ran AFTER the disk load+write, so a
///      load failure left the cache stale; these go red until the fix lands.
///
/// Quirk #18: struct name matches the filename so `-only-testing` filters hit.
@MainActor
@Suite("InlineEditCommitTests")
struct InlineEditCommitTests {

    // MARK: - updatePageProperty (table / gallery)

    @Test("updatePageProperty: edit lands in cache + disk, preserving body + foreign frontmatter")
    func propertyPersistsAndPreserves() async throws {
        let (nexus, collection, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        try seedBodyAndForeign(at: page.url, id: page.frontmatter.id)

        let propID = ReservedPropertyID.mintUserPropertyID()
        try await manager.updatePageProperty(
            page, propertyID: propID, newValue: .number(42),
            pageCollection: collection, collection: nil)

        // Cache (what the cells render) reflects the edit.
        let cached = manager.pages(in: collection).first { $0.id == page.id }
        #expect(cached?.frontmatter.properties[propID] == .number(42))

        // Disk reflects it too; body + foreign frontmatter survive.
        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.properties[propID] == .number(42))
        #expect(reloaded.body.contains("Body marker"))
        #expect(foreignTags(at: page.url) == ["alpha", "beta"])
    }

    @Test("updatePageProperty: cache reflects the edit even when the disk write fails (optimistic, decoupled)")
    func propertyCacheDecoupledFromDisk() async throws {
        let (nexus, collection, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        // Remove the file so any disk round-trip throws.
        try FileManager.default.removeItem(at: page.url)

        let propID = ReservedPropertyID.mintUserPropertyID()
        try? await manager.updatePageProperty(
            page, propertyID: propID, newValue: .number(7),
            pageCollection: collection, collection: nil)

        let cached = manager.pages(in: collection).first { $0.id == page.id }
        #expect(
            cached?.frontmatter.properties[propID] == .number(7),
            "the in-memory cache must reflect the edit without depending on a disk round-trip")
        #expect(manager.pendingError != nil, "a failed persist must surface, not be swallowed")
    }

    // MARK: - updatePageFrontmatter (inspector + preview)

    @Test("updatePageFrontmatter: edit lands in cache + disk, preserving body + foreign frontmatter")
    func frontmatterPersistsAndPreserves() async throws {
        let (nexus, collection, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        try seedBodyAndForeign(at: page.url, id: page.frontmatter.id)

        let propID = ReservedPropertyID.mintUserPropertyID()
        var fm = page.frontmatter
        fm.properties[propID] = .number(99)
        try await manager.updatePageFrontmatter(
            page, frontmatter: fm, pageCollection: collection, collection: nil)

        let cached = manager.pages(in: collection).first { $0.id == page.id }
        #expect(cached?.frontmatter.properties[propID] == .number(99))

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.properties[propID] == .number(99))
        #expect(reloaded.body.contains("Body marker"))
        #expect(foreignTags(at: page.url) == ["alpha", "beta"])
    }

    @Test("updatePageFrontmatter: cache reflects the edit even when the disk write fails (optimistic, decoupled)")
    func frontmatterCacheDecoupledFromDisk() async throws {
        let (nexus, collection, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        try FileManager.default.removeItem(at: page.url)

        let propID = ReservedPropertyID.mintUserPropertyID()
        var fm = page.frontmatter
        fm.properties[propID] = .number(13)
        try? await manager.updatePageFrontmatter(
            page, frontmatter: fm, pageCollection: collection, collection: nil)

        let cached = manager.pages(in: collection).first { $0.id == page.id }
        #expect(cached?.frontmatter.properties[propID] == .number(13))
        #expect(manager.pendingError != nil)
    }

    // MARK: - Harness

    private func setup() async throws -> (Nexus, PageCollection, PageContentManager) {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, manager)
    }

    /// Overwrites the page file with a real body + a foreign (plugin) `tags` key
    /// so the persistence path's body- and foreign-preservation are assertable.
    private func seedBodyAndForeign(at url: URL, id: String) throws {
        let raw = """
            ---
            id: \(id)
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            tags:
              - alpha
              - beta
            ---
            # Body marker
            """
        try FixtureFiles.write(raw, to: url)
    }

    private func foreignTags(at url: URL) -> [String]? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
            let split = try? AtomicYAMLMarkdown.split(raw),
            case .mapping(let m)? = try? Yams.compose(yaml: split.0),
            case .sequence(let seq)? = m[Node("tags")]
        else { return nil }
        return seq.compactMap { $0.string }
    }
}
