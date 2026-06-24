import Foundation
import GRDB
import MarkdownPM
import Testing

@testable import Pommora

/// E1 Step 4 — the cross-surface LIVE REFRESH bus. A phantom `[[X]]` in an
/// open editor must light up when X is created / renamed / deleted in ANOTHER
/// surface, without the user typing in the doc holding the link.
///
/// The conduit mirrors the proven `appearanceDidChangeNotification` path: a host-
/// owned `Notification.Name` lives on `MarkdownPMBus.connectionsChanged`, the
/// editor coordinator observes it via `subscribeToBusNotifications` and restyles
/// the whole document on receipt (`handleConnectionsChanged` → `restyleTextView`,
/// the SAME full-document restyle `handleAppearanceChange` runs). The CRUD
/// managers post `ConnectionsBus.changed` after their connection-index work.
///
/// What's testable here: (1) the bus exposes the field, and (2) each CRUD op that
/// changes which titles exist actually POSTS the signal. The visual restyle-on-
/// receipt is NOT unit-tested — it needs a live coordinator + NSTextView — but it
/// runs the identical code path as the shipped, proven `appearanceDidChange`
/// restyle, so the post (asserted here) + that shared path is the whole feature.
@MainActor
@Suite("ConnectionLiveRefreshTests")
struct ConnectionLiveRefreshTests {

    // MARK: - Bus surface

    /// The new bus slot exists and round-trips a name — the production config
    /// (`MarkdownEditorConfig.pommora`) sets it to `ConnectionsBus.changed`.
    @Test("MarkdownPMBus exposes a settable connectionsChanged slot")
    func busExposesConnectionsChanged() {
        var bus = MarkdownPMBus()
        #expect(bus.connectionsChanged == nil)
        bus.connectionsChanged = ConnectionsBus.changed
        #expect(bus.connectionsChanged == ConnectionsBus.changed)

        // The production config wires the slot so open editors actually observe it.
        let cfg = MarkdownEditorConfig.pommora(verticalInset: 0)
        #expect(cfg.services.bus.connectionsChanged == ConnectionsBus.changed)
    }

    // MARK: - Page CRUD posts the signal

    @Test("createPage / renamePage / deletePage each post ConnectionsBus.changed")
    func pageCRUDPostsChanged() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makeVault(in: nexus, index: index, title: "V")
        let coll = try makePageCollection(in: nexus, vault: vault, index: index, title: "C")
        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        // Observe ONLY this manager's posts (object filter) so concurrent CRUD in
        // other parallel suites — which also post the global signal — can't inflate
        // the count. Each op must bump it by exactly one.
        let counter = PostCounter(observing: manager)
        defer { counter.stop() }

        let before = counter.count
        let page = try await manager.createPage(name: "Alpha", in: coll, vault: vault)
        #expect(counter.count == before + 1)

        let afterCreate = counter.count
        try await manager.renamePage(page, to: "Beta", in: coll, vault: vault)
        #expect(counter.count == afterCreate + 1)

        // delete — the renamed page now lives at title "Beta".
        var renamed = page
        renamed.title = "Beta"
        renamed.url = NexusPaths.pageFileURL(forTitle: "Beta", in: coll.folderURL)
        let afterRename = counter.count
        try await manager.deletePage(renamed, inCollection: coll)
        #expect(counter.count == afterRename + 1)
    }

    // MARK: - Fixtures (mirror NexusWideUniquenessTests)

    private func makeVault(in nexus: Nexus, index: PommoraIndex, title: String) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        try IndexUpdater(index).upsertPageType(vault)
        return vault
    }

    private func makePageCollection(
        in nexus: Nexus, vault: PageType, index: PommoraIndex, title: String
    ) throws -> PageCollection {
        let folder = NexusPaths.collectionFolderURL(forTitle: title, inVaultTitled: vault.title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: title, folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        try IndexUpdater(index).upsertPageCollection(coll)
        return coll
    }

}

// MARK: - Observer helper

/// Counts `ConnectionsBus.changed` posts from a specific source (`observing`), so
/// concurrent CRUD in other parallel test suites can't inflate the count. Explicitly
/// `nonisolated` because this target builds with `-default-isolation=MainActor`,
/// which would otherwise infer the class `@MainActor` — and then the `@Sendable`
/// observer block couldn't synchronously bump the count when the post fires (the
/// bump would be silently dropped / deferred). `@unchecked Sendable` + an internal
/// `NSLock` make the state genuinely thread-safe; the test reads `count` after each
/// awaited CRUD call, by which point the synchronous post (`queue: nil` → inline on
/// the posting thread) has fired. Call `stop()` (in a `defer`) to unregister —
/// cleanup is explicit rather than in a `deinit`, which can't touch the non-Sendable
/// observer token under Swift 6.
private nonisolated final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var token: (any NSObjectProtocol)?

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    init(observing object: AnyObject?) {
        token = NotificationCenter.default.addObserver(
            forName: ConnectionsBus.changed, object: object, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self._count += 1
            self.lock.unlock()
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}
