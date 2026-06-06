import Foundation
import GRDB
import Testing

@testable import Pommora

/// Covers Task D1 — the atomic rename cascade: when a Page/Item is renamed,
/// every OTHER body (page OR item) that links it by the old title is rewritten
/// on disk (`[[Old]]`→`[[New]]` for a page target, `{{Old}}`→`{{New}}` for an
/// item target), atomically, and the connection index re-reconciles.
///
/// The required gate is cross-kind: a page rename must rewrite BOTH a page
/// source and an item source. Both content managers share ONE `PommoraIndex` +
/// ONE `IndexUpdater` over one `TempNexus` so the cascade walks the live index.
///
/// Suite/struct name matches the filename so
/// `-only-testing:PommoraTests/ConnectionCascadeTests` resolves a non-zero
/// executed count (quirk #18).
@MainActor
@Suite("ConnectionCascadeTests")
struct ConnectionCascadeTests {

    // MARK: - Required gate: cross-kind cascade + index re-reconcile

    @Test("renaming a page rewrites [[Old]] in both a page source and an item source")
    func crossKindCascadeOnPageRename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        // Page side: one PageType (vault).
        let vault = try makeVault(in: nexus, index: index)
        let pageManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageManager.indexUpdater = updater

        // Item side: one ItemType, sharing the same index/updater.
        let itemType = try makeItemType(in: nexus, index: index)
        let itemManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        itemManager.indexUpdater = updater

        // Target page, plus a page source A and an item source B that both link [[Target]].
        let target = try await pageManager.createPage(name: "Target", inVaultRoot: vault)
        let pageA = try await pageManager.createPage(name: "A", inVaultRoot: vault)
        try await pageManager.updatePage(pageA, body: "see [[Target]] here", inVaultRoot: vault)

        let itemB = try await itemManager.createItem(name: "B", inTypeRoot: itemType)
        var itemBWithBody = itemB
        itemBWithBody.description = "refers to [[Target]] too"
        try await itemManager.updateItem(itemBWithBody, inTypeRoot: itemType)

        // Sanity: A → Target resolved before the rename.
        let beforeA = try await IndexQuery(index).outgoingConnections(sourceID: pageA.id)
        #expect(beforeA.first?.resolved == true)
        #expect(beforeA.first?.targetID == target.id)

        // Rename Target → Renamed.
        try await pageManager.renamePage(target, to: "Renamed", inVaultRoot: vault)

        // (1) Page source A's .md now links [[Renamed]] and not [[Target]].
        let aFolder = NexusPaths.pageTypeFolderURL(in: nexus.rootURL, typeFolderName: vault.title)
        let aURL = NexusPaths.pageFileURL(forTitle: "A", in: aFolder)
        let aContent = try String(contentsOf: aURL, encoding: .utf8)
        #expect(aContent.contains("[[Renamed]]"))
        #expect(!aContent.contains("[[Target]]"))

        // (2) Item source B's .md now links [[Renamed]].
        let bFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        let bURL = NexusPaths.itemFileURL(forTitle: "B", in: bFolder)
        let bContent = try String(contentsOf: bURL, encoding: .utf8)
        #expect(bContent.contains("[[Renamed]]"))
        #expect(!bContent.contains("[[Target]]"))

        // (3) A's outgoing edge is still ONE resolved edge → the renamed target.
        let afterA = try await IndexQuery(index).outgoingConnections(sourceID: pageA.id)
        #expect(afterA.count == 1)
        let edge = try #require(afterA.first)
        #expect(edge.resolved == true)
        #expect(edge.targetID == target.id)
        #expect(edge.targetTitle == ConnectionTitle.normalize("Renamed"))

        #expect(pageManager.pendingError == nil)
        #expect(itemManager.pendingError == nil)
    }

    @Test("renaming an item rewrites {{Old}} in a referencing page source")
    func itemRenameRewritesItemSyntax() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let vault = try makeVault(in: nexus, index: index)
        let pageManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageManager.indexUpdater = updater

        let itemType = try makeItemType(in: nexus, index: index)
        let itemManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        itemManager.indexUpdater = updater

        // Item target, plus a page source that links {{Widget}}.
        let widget = try await itemManager.createItem(name: "Widget", inTypeRoot: itemType)
        let page = try await pageManager.createPage(name: "Doc", inVaultRoot: vault)
        try await pageManager.updatePage(page, body: "uses {{Widget}} here", inVaultRoot: vault)

        try await itemManager.renameItem(widget, to: "Gizmo", inTypeRoot: itemType)

        let folder = NexusPaths.pageTypeFolderURL(in: nexus.rootURL, typeFolderName: vault.title)
        let url = NexusPaths.pageFileURL(forTitle: "Doc", in: folder)
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("{{Gizmo}}"))
        #expect(!content.contains("{{Widget}}"))

        let after = try await IndexQuery(index).outgoingConnections(sourceID: page.id)
        #expect(after.count == 1)
        #expect(after.first?.resolved == true)
        #expect(after.first?.targetID == widget.id)
        #expect(pageManager.pendingError == nil)
        #expect(itemManager.pendingError == nil)
    }

    // MARK: - Pure-unit rewriter

    @Test("ConnectionRewriter touches only matching [[ ]] links, leaving embeds + {{ }} alone")
    func rewriterScopesToSyntaxAndTitle() {
        let body = "see [[Old]] and [[old]] and ![[Old]] and {{Old}}"
        let out = ConnectionRewriter.rewrite(
            body: body, oldTitle: "Old", newTitle: "New", syntax: .page)
        // Both case variants of the [[ ]] page link rewrite (normalized match); the
        // image embed ![[Old]] and the item link {{Old}} are untouched. Exact-string
        // assertion since ![[Old]] contains the substring "[[Old]]" (no `contains`).
        #expect(out == "see [[New]] and [[New]] and ![[Old]] and {{Old}}")
    }

    @Test("ConnectionRewriter rewrites {{ }} item links and leaves [[ ]] alone")
    func rewriterItemSyntax() {
        let body = "{{Old}} and [[Old]]"
        let out = ConnectionRewriter.rewrite(
            body: body, oldTitle: "Old", newTitle: "New", syntax: .item)
        #expect(out.contains("{{New}}"))
        #expect(!out.contains("{{Old}}"))
        #expect(out.contains("[[Old]]"))
    }

    // NOTE: the failure/revert path (txn.commit throws → target file-rename reverted,
    // cascadeFailed surfaced) is covered by code review only. Deterministic injection
    // of an atomic-swap failure on this macOS/temp setup is flaky for the file owner
    // (read-only-dir tricks don't reliably block the owning process), so no flaky test
    // is shipped per the task's revert-test guidance.

    // MARK: - Fixtures (mirror UnlinkTierTests)

    private func makeVault(in nexus: Nexus, index: PommoraIndex) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))
        try IndexUpdater(index).upsertPageType(vault)
        return vault
    }

    private func makeItemType(in nexus: Nexus, index: PommoraIndex) throws -> ItemType {
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))
        try IndexUpdater(index).upsertItemType(itemType)
        return itemType
    }
}
