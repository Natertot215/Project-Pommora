import Foundation
import GRDB
import Testing

@testable import Pommora

/// Covers Task D1 — the atomic rename cascade: when a Page is renamed, every
/// OTHER page body that links it by the old title is rewritten on disk
/// (`[[Old]]`→`[[New]]`), atomically, and the connection index re-reconciles.
/// `[[ ]]` is the only connection syntax (PagesV2 decision #3).
///
/// The content manager + cascade share ONE `PommoraIndex` + ONE `IndexUpdater`
/// over one `TempNexus` so the cascade walks the live index.
///
/// Suite/struct name matches the filename so
/// `-only-testing:PommoraTests/ConnectionCascadeTests` resolves a non-zero
/// executed count (quirk #18).
@MainActor
@Suite("ConnectionCascadeTests")
struct ConnectionCascadeTests {

    // MARK: - Required gate: cascade + index re-reconcile

    @Test("renaming a page rewrites [[Old]] in a referencing page source")
    func cascadeOnPageRename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let collection = try makeCollection(in: nexus, index: index)
        let pageManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageManager.indexUpdater = updater

        // Target page, plus a page source A that links [[Target]].
        let target = try await pageManager.createPage(name: "Target", inCollectionRoot: collection)
        let pageA = try await pageManager.createPage(name: "A", inCollectionRoot: collection)
        try await pageManager.updatePage(pageA, body: "see [[Target]] here", inCollectionRoot: collection)

        // Sanity: A → Target resolved before the rename.
        let beforeA = try await IndexQuery(index).outgoingConnections(sourceID: pageA.id)
        #expect(beforeA.first?.resolved == true)
        #expect(beforeA.first?.targetID == target.id)

        // Rename Target → Renamed.
        try await pageManager.renamePage(target, to: "Renamed", inCollectionRoot: collection)

        // (1) Page source A's .md now links [[Renamed]] and not [[Target]].
        let aFolder = NexusPaths.collectionFolderURL(in: nexus.rootURL, collectionFolderName: collection.title)
        let aURL = NexusPaths.pageFileURL(forTitle: "A", in: aFolder)
        let aContent = try String(contentsOf: aURL, encoding: .utf8)
        #expect(aContent.contains("[[Renamed]]"))
        #expect(!aContent.contains("[[Target]]"))

        // (2) A's outgoing edge is still ONE resolved edge → the renamed target.
        let afterA = try await IndexQuery(index).outgoingConnections(sourceID: pageA.id)
        #expect(afterA.count == 1)
        let edge = try #require(afterA.first)
        #expect(edge.resolved == true)
        #expect(edge.targetID == target.id)
        #expect(edge.targetTitle == ConnectionTitle.normalize("Renamed"))

        #expect(pageManager.pendingError == nil)
    }

    // MARK: - Pure-unit rewriter

    @Test("ConnectionRewriter touches only matching [[ ]] links, leaving embeds + {{ }} alone")
    func rewriterScopesToSyntaxAndTitle() {
        let body = "see [[Old]] and [[old]] and ![[Old]] and {{Old}}"
        let out = ConnectionRewriter.rewrite(
            body: body, oldTitle: "Old", newTitle: "New")
        // Both case variants of the [[ ]] page link rewrite (normalized match); the
        // image embed ![[Old]] and the plain-text {{Old}} are untouched.
        // Exact-string assertion since ![[Old]] contains the substring "[[Old]]"
        // (no `contains`).
        #expect(out == "see [[New]] and [[New]] and ![[Old]] and {{Old}}")
    }

    // NOTE: the failure/revert path (txn.commit throws → target file-rename reverted,
    // cascadeFailed surfaced) is covered by code review only. Deterministic injection
    // of an atomic-swap failure on this macOS/temp setup is flaky for the file owner
    // (read-only-dir tricks don't reliably block the owning process), so no flaky test
    // is shipped per the task's revert-test guidance.

    // MARK: - Fixtures (mirror UnlinkTierTests)

    private func makeCollection(in nexus: Nexus, index: PommoraIndex) throws -> PageCollection {
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))
        try IndexUpdater(index).upsertPageCollection(collection)
        return collection
    }
}
