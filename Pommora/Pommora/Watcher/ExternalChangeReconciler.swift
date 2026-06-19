import Foundation

/// Applies on-disk changes reported by `NexusFileWatcher` to the running app:
/// re-reads the affected files into the SQLite index and the in-memory managers
/// so external edits (Obsidian, vim, Finder, cloud sync) and the app's own
/// out-of-band writes propagate live.
///
/// **v1 is coarse.** A relevant change debounces into a full reconcile that reuses
/// the launch index build (`IndexBuilder.populate` — atomic, all-kinds, handles
/// deletes) plus a reload of the in-memory managers. This trades per-change
/// efficiency for simplicity and total coverage; per-scope surgical reconcile is
/// the later optimization. The mtime gate in the watcher already drops echoes and
/// duplicate events, so a reconcile only runs on a real change.
///
/// The open editor's own file is skipped: its saves are already reconciled by the
/// CRUD path, and an external edit to an open Page defers to the editor until it
/// closes (protect-live-edits). Live in-place reload of an open Page is a later
/// surgical layer.
@MainActor
final class ExternalChangeReconciler {

    private unowned let env: NexusEnvironment
    private var reconcileTask: Task<Void, Never>?

    /// Debounce window: coalesces a burst of related events (and the temp-file
    /// churn of atomic writes) into one reconcile.
    private static let debounce: Duration = .milliseconds(250)

    init(env: NexusEnvironment) { self.env = env }

    // MARK: - Intake

    /// Called on the main actor by the watcher with gated changed paths.
    func handle(_ paths: [URL]) {
        guard paths.contains(where: warrantsReconcile) else { return }
        scheduleReconcile()
    }

    private func warrantsReconcile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        // App-private / non-entity files never drive a reconcile.
        if name == "nexus.json" || name == "state.json" { return false }
        if name.hasPrefix(".") { return false }
        // The open editor owns its file: its saves are already indexed by CRUD,
        // and external edits to it wait for the editor to close (protect-live-edits).
        if url.pathExtension == "md",
            AppGlobals.openEditor(forPath: url.standardizedFileURL.path) != nil {
            return false
        }
        return true
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    // MARK: - Reconcile

    private func run() async {
        let nexusManager = env.nexusManager
        guard let nexus = nexusManager.currentNexus,
            let index = nexusManager.currentIndex
        else { return }
        let filter = FolderFilter.load(for: nexus)

        // 1. Index — atomic full rebuild (clear + reinsert in one transaction, so
        //    readers never see an empty index; covers every kind and deletes).
        try? await IndexBuilder.populate(index: index, from: nexus, filter: filter)

        // 2. In-memory structure, Contexts, and Agenda — these drive the sidebar.
        await env.vaultManager.loadAll(filter: filter)
        let collections = env.vaultManager.pageCollectionsByType.values.flatMap { $0 }
        await env.pageSetManager.loadAll(collections: collections, filter: filter)
        await env.areaManager.loadAll()
        await env.topicManager.loadAll()
        await env.projectManager.loadAll()
        await env.agendaTaskManager.loadAll()
        await env.agendaEventManager.loadAll()

        // 3. Currently-loaded Page scopes — refresh so open lists pick up external
        //    adds / edits / renames (Pages load lazily; only reload what's live).
        await reloadLoadedPageScopes(collections: collections)
    }

    private func reloadLoadedPageScopes(collections: [PageCollection]) async {
        let content = env.contentManager

        for id in Array(content.pagesByCollection.keys) {
            guard let collection = collections.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: collection)
        }
        for id in Array(content.pagesByTypeRoot.keys) {
            guard let type = env.vaultManager.types.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: type)
        }
        let allSets = env.pageSetManager.pageSetsByCollection.values.flatMap { $0 }
        for id in Array(content.pagesBySet.keys) {
            guard let set = allSets.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: set)
        }
    }
}
