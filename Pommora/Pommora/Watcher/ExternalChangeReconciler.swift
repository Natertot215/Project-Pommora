import Foundation

/// Applies on-disk changes reported by `NexusFileWatcher` to the running app —
/// re-reads the affected files into the SQLite index and the in-memory managers
/// so external edits and the app's own out-of-band writes propagate live.
///
/// v1 reconcile is coarse: a real change debounces into a full reconcile that
/// reuses the launch index build (`IndexBuilder.populate` — atomic, all-kinds,
/// handles deletes) plus `NexusEnvironment.reloadAllManagers`. Per-scope surgical
/// reconcile is a later optimization. The open editor's own file is skipped — its
/// saves are already reconciled by CRUD, and an external edit to an open Page
/// defers to the editor until it closes (protect-live-edits).
@MainActor
final class ExternalChangeReconciler {

    /// How a changed path is routed. The editor-reload + stamping layers extend
    /// this switch rather than reshaping a boolean chain.
    private enum Disposition {
        case ignore  // app-private / hidden file
        case deferToEditor  // an open Page's own file — the editor is authoritative
        case reconcile  // everything else — drives the coarse reconcile
    }

    private unowned let env: NexusEnvironment
    /// The Nexus this reconciler belongs to. A debounced reconcile that fires
    /// after a Nexus switch is dropped rather than writing one Nexus's content
    /// into another's index.
    private let nexusID: String
    private var reconcileTask: Task<Void, Never>?

    /// Coalesces a burst of related events (and atomic-write temp churn) into one
    /// reconcile.
    private static let debounce: Duration = .milliseconds(250)

    init(env: NexusEnvironment, nexusID: String) {
        self.env = env
        self.nexusID = nexusID
    }

    /// Called on the main actor by the watcher with gated changed paths.
    func handle(_ paths: [URL]) {
        let needsReconcile = paths.contains {
            if case .reconcile = disposition(of: $0) { return true }
            return false
        }
        guard needsReconcile else { return }
        scheduleReconcile()
    }

    private func disposition(of url: URL) -> Disposition {
        let name = url.lastPathComponent
        if name == "nexus.json" || name == "state.json" || name.hasPrefix(".") {
            return .ignore
        }
        if url.pathExtension == "md",
            AppGlobals.openEditor(forPath: url.standardizedFileURL.path) != nil {
            return .deferToEditor
        }
        return .reconcile
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    /// Coarse reconcile: rebuild the index atomically (clear + reinsert in one
    /// transaction, so readers never see it empty; covers every kind and deletes),
    /// then refresh the in-memory managers.
    private func run() async {
        let nexusManager = env.nexusManager
        guard nexusManager.currentNexus?.id == nexusID,
            let nexus = nexusManager.currentNexus,
            let index = nexusManager.currentIndex
        else { return }
        let filter = FolderFilter.load(for: nexus)

        try? await IndexBuilder.populate(index: index, from: nexus, filter: filter)
        await env.reloadAllManagers(filter: filter)
        await reloadLoadedPageScopes()
    }

    /// Refreshes only the currently-loaded Page scopes (Pages load lazily) so any
    /// open list picks up external adds / edits / renames.
    private func reloadLoadedPageScopes() async {
        let content = env.contentManager
        let collections = env.vaultManager.pageCollectionsByType.values.flatMap { $0 }

        for id in Array(content.pagesByCollection.keys) {
            guard let collection = collections.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: collection)
        }
        for id in Array(content.pagesByTypeRoot.keys) {
            guard let type = env.vaultManager.types.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: type)
        }
        let sets = env.pageSetManager.pageSetsByCollection.values.flatMap { $0 }
        for id in Array(content.pagesBySet.keys) {
            guard let set = sets.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: set)
        }
    }
}
