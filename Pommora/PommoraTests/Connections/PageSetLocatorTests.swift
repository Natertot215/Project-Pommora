import Foundation
import Testing

@testable import Pommora

/// ConnectionFileLocator resolves a Page's `.md` URL through the Set layer:
/// a Set page's folder folds Type/Collection/Set via `NexusPaths.pageSetFolderURL`,
/// while Collection-root and Vault-root pages keep their existing derivations.
/// Fixture mirrors `PageSetIndexTests` — Set folder + sidecar laid down directly
/// on disk (no manager CRUD surface for Sets), then indexed via IndexBuilder.
@Suite("PageSetLocator")
@MainActor
struct PageSetLocatorTests {

    // MARK: - Fixture

    /// Builds a nexus with Vault "Notes" + Collection "Inbox" + Set "Drafts",
    /// holding one Page at each level: in the Set, at the Collection root,
    /// and at the Vault root.
    private func setup() async throws -> (
        nexus: Nexus, idx: PommoraIndex,
        setPage: (id: String, url: URL),
        collectionPage: (id: String, url: URL),
        vaultPage: (id: String, url: URL)
    ) {
        let nexus = try TempNexus.make()

        let pageTypeManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak pageTypeManager] in pageTypeManager?.types ?? [] }
        pageTypeManager.pageSetManager = setManager
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!
        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

        let setFolder = coll.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: setFolder, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "Drafts",
            folderURL: setFolder, modifiedAt: Date()
        )
        try set.save(to: setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        func writePage(titled title: String, in folder: URL) throws -> (id: String, url: URL) {
            let now = Date()
            let fm = PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.pageFileURL(forTitle: title, in: folder)
            try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: url)
            return (fm.id, url)
        }
        let setPage = try writePage(titled: "Set Page", in: setFolder)
        let collectionPage = try writePage(titled: "Coll Page", in: coll.folderURL)
        let vaultPage = try writePage(
            titled: "Root Page", in: NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus))

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)
        return (nexus, idx, setPage, collectionPage, vaultPage)
    }

    private func locate(id: String, idx: PommoraIndex, nexus: Nexus) async throws -> URL? {
        let resolved = try await IndexQuery(idx).entityContainer(id: id, kind: .page)
        let container = try #require(resolved)
        return ConnectionFileLocator.locate(id: id, kind: .page, container: container, nexusRoot: nexus.rootURL)
    }

    // MARK: - Test 1: a page inside a Set locates to its on-disk file

    @Test func locatesSetPage() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        let located = try await locate(id: fx.setPage.id, idx: fx.idx, nexus: fx.nexus)
        #expect(located?.standardizedFileURL.path == fx.setPage.url.standardizedFileURL.path)
    }

    // MARK: - Test 2: regression — a Collection-root page still locates

    @Test func locatesCollectionRootPage() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        let located = try await locate(id: fx.collectionPage.id, idx: fx.idx, nexus: fx.nexus)
        #expect(located?.standardizedFileURL.path == fx.collectionPage.url.standardizedFileURL.path)
    }

    // MARK: - Test 3: regression — a Vault-root page still locates

    @Test func locatesVaultRootPage() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        let located = try await locate(id: fx.vaultPage.id, idx: fx.idx, nexus: fx.nexus)
        #expect(located?.standardizedFileURL.path == fx.vaultPage.url.standardizedFileURL.path)
    }

    // MARK: - Test 4: end-to-end — a wikilink to a Set page opens it

    @Test func wikiLinkOpensSetPage() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        let selection = await WikiLinkPageOpener.pageSelection(
            forTitle: "Set Page", index: fx.idx, nexusRootURL: fx.nexus.rootURL)

        guard case .page(let meta) = selection else {
            Issue.record("expected .page selection, got \(String(describing: selection))")
            return
        }
        #expect(meta.id == fx.setPage.id)
        #expect(meta.url.standardizedFileURL.path == fx.setPage.url.standardizedFileURL.path)
    }
}
