import Foundation
import Testing

@testable import Pommora

/// Verifies that an intermediate Set with no direct pages still anchors its
/// child sub-sets correctly in structural grouping (collection scope).
///
/// Real case: organizing Sets that only hold sub-Sets, e.g.
///   Type → Collection → SetA (no pages) → SubB (no pages) → page.md
/// Without the anchor fix, SetA is invisible to GroupResolver and SubB floats
/// to the top level.
@MainActor
@Suite("EmptyIntermediateSetTests")
struct EmptyIntermediateSetTests {

    // MARK: - ViewItemSource anchor emission

    @Test("ViewItemSource emits a structural anchor for an empty intermediate Set")
    func viewItemSourceEmitsAnchorForEmptyIntermediateSet() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        // SetA has no direct pages but has SubB as a child.
        let setA = try makePageSet(title: "SetA", in: coll)
        let subB = try makePageSet(title: "SubB", in: setA)

        // Only SubB has a page.
        _ = try writePage(titled: "Page1", in: subB.folderURL)

        let (content, sets) = managers(nexus: nexus)
        await content.loadAll(for: setA)
        await content.loadAll(for: subB)
        await sets.loadAll(types: [vault])

        let items = ViewItemSource.items(
            for: .collection(coll, pageCollection: vault),
            content: content,
            sets: sets,
            collections: { _ in [coll] }
        )

        // Should include the structural anchor for SetA + the real page for SubB.
        let anchors = items.filter { $0.isStructuralAnchor }
        let realItems = items.filter { !$0.isStructuralAnchor }

        #expect(anchors.count == 1)
        if case .set(let s, _, _) = anchors.first?.parent {
            #expect(s.id == setA.id)
        } else {
            #expect(Bool(false), "anchor parent should be .set(setA, ...)")
        }
        #expect(realItems.count == 1)
        #expect(realItems.first?.page.title == "Page1")
    }

    // MARK: - GroupResolver structural grouping with empty intermediate

    @Test("empty intermediate Set anchors child sub-sets instead of floating them to top level")
    func emptyIntermediateSetAnchorsChildrenInGroupResolver() {
        let collA = VPFixture.collection("coll_A", title: "Alpha")

        // SetA has no direct pages; SubB has a page.
        let setA = PageSet(
            id: "set_A", parentID: "coll_A", title: "SetA",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subB = PageSet(
            id: "sub_B", parentID: "set_A", title: "SubB",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))

        // Structural anchor for SetA (no page, isStructuralAnchor: true).
        let anchor = ViewItem(
            page: VPFixture.meta(id: "_anchor_set_A", title: ""),
            parent: .set(setA, collection: collA, pageCollection: VPFixture.vault("vault_1")),
            setLabel: nil,
            isStructuralAnchor: true
        )
        // Real page under SubB.
        let pageItem = VPFixture.item("page_1", title: "Page1", inSubSet: subB, of: collA)

        let groups = GroupResolver.resolve(
            items: [anchor, pageItem],
            config: .structural,
            scope: .collection
        )

        // Top-level group must be SetA (not SubB floating up).
        #expect(groups.count == 1, "SetA should be the only top-level group (no loose pages)")
        let setAGroup = groups[0]
        #expect(setAGroup.id == "set_A")
        #expect(setAGroup.title == "SetA")
        // SetA has no direct pages.
        #expect(setAGroup.items.isEmpty)

        // SubB must be nested under SetA.
        #expect(setAGroup.children?.count == 1)
        let subBGroup = setAGroup.children?.first
        #expect(subBGroup?.id == "sub_B")
        #expect(subBGroup?.items.map(\.id) == ["page_1"])
    }

    @Test("three-level empty chain: SetA(empty) → SubB(empty) → page nests correctly")
    func threeLevelEmptyChainNestsCorrectly() {
        let collA = VPFixture.collection("coll_A", title: "Alpha")

        let setA = PageSet(
            id: "set_A", parentID: "coll_A", title: "SetA",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subB = PageSet(
            id: "sub_B", parentID: "set_A", title: "SubB",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subC = PageSet(
            id: "sub_C", parentID: "sub_B", title: "SubC",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))

        let anchorA = ViewItem(
            page: VPFixture.meta(id: "_anchor_set_A", title: ""),
            parent: .set(setA, collection: collA, pageCollection: VPFixture.vault("vault_1")),
            setLabel: nil,
            isStructuralAnchor: true
        )
        let anchorB = ViewItem(
            page: VPFixture.meta(id: "_anchor_sub_B", title: ""),
            parent: .set(subB, collection: collA, pageCollection: VPFixture.vault("vault_1")),
            setLabel: nil,
            isStructuralAnchor: true
        )
        let pageItem = VPFixture.item("page_1", title: "Page1", inSubSet: subC, of: collA)

        let groups = GroupResolver.resolve(
            items: [anchorA, anchorB, pageItem],
            config: .structural,
            scope: .collection
        )

        #expect(groups.count == 1)
        let setAGroup = groups[0]
        #expect(setAGroup.id == "set_A")
        #expect(setAGroup.items.isEmpty)

        let subBGroup = setAGroup.children?.first
        #expect(subBGroup?.id == "sub_B")
        #expect(subBGroup?.items.isEmpty == true)

        let subCGroup = subBGroup?.children?.first
        #expect(subCGroup?.id == "sub_C")
        #expect(subCGroup?.items.map(\.id) == ["page_1"])
    }

    // MARK: - Helpers

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String, in pageCollection: PageCollection) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return coll
    }

    @discardableResult
    private func makePageSet(title: String, in parent: PageSet) throws -> PageSet {
        let folderURL = parent.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: parent.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return set
    }

    @discardableResult
    private func writePage(titled title: String, in folder: URL) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }

    private func managers(nexus: Nexus) -> (PageContentManager, PageSetManager) {
        let content = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let sets = PageSetManager(nexus: nexus)
        return (content, sets)
    }
}
