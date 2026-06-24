import Foundation

/// Applies on-disk changes reported by `NexusFileWatcher` to the running app —
/// re-reads the affected files into the SQLite index and the in-memory managers
/// so external edits and the app's own out-of-band writes propagate live.
///
/// A real change debounces into a reconcile that is **surgical** for the frequent,
/// provably-safe case — a batch of purely existing-Page edits/creates in known
/// scopes reindexes just those scopes — and falls back to the **coarse** full
/// rebuild (`IndexBuilder.populate` + `reloadAllManagers`) for everything else:
/// gone paths (rename / move / delete), non-Page changes, a dropped-events signal,
/// or a Page in a not-yet-loaded container. The coarse path is the original,
/// correct all-kinds reconcile; the surgical path only ever handles cases that
/// cannot orphan a link or misclassify a move (those all carry a gone path, which
/// forces coarse).
///
/// The open editor's own file is skipped (`deferToEditor`) — its saves are already
/// reconciled by CRUD, and an external edit to an open Page reloads its body in
/// place; renames re-point it by stable id during the reconcile.
@MainActor
final class ExternalChangeReconciler {

    /// Intake classification for a changed path. Internal (not private) so the
    /// reconciler test can pin the routing decision directly.
    enum Disposition {
        case ignore  // app-private / hidden file
        case deferToEditor(PageEditorViewModel)  // an open Page's file — editor authoritative
        case reconcile  // drives the debounced reconcile
    }

    /// A Page scope to reload + reindex surgically, carrying the parent ids
    /// `IndexUpdater.upsertPage` needs. `collectionID` is always the top
    /// PageCollection id (the `pageCollectionID` FK); `parentSetID` is the
    /// immediate container Set for a deeper page.
    enum Scope: Hashable {
        case depthOneSet(id: String, collectionID: String)
        case deeperSet(id: String, parentSetID: String, collectionID: String)
        case collectionRoot(id: String)
    }

    private unowned let env: NexusEnvironment
    /// The Nexus this reconciler belongs to — a debounced reconcile firing after a
    /// Nexus switch is dropped rather than writing one Nexus into another's index.
    private let nexusID: String
    private var reconcileTask: Task<Void, Never>?
    /// Changed paths accumulated across the debounce window, drained by `run()`.
    private var pendingPaths: Set<URL> = []
    /// Serializes reconciles. `run()` is async and `@MainActor`-reentrant, so two
    /// could interleave at an `await` and settle index/memory wrong under bursty
    /// events; a reconcile arriving mid-run sets `rerunRequested` and reschedules.
    private var isRunning = false
    private var rerunRequested = false

    private static let debounce: Duration = .milliseconds(250)

    init(env: NexusEnvironment, nexusID: String) {
        self.env = env
        self.nexusID = nexusID
    }

    // MARK: - Intake

    /// Called on the main actor by the watcher with gated changed paths.
    func handle(_ paths: [URL]) {
        let nexusRoot = env.nexusManager.currentNexus?.rootURL
        var scheduled = false
        for url in paths {
            switch disposition(of: url) {
            case .ignore:
                continue
            case .deferToEditor(let vm):
                if let nexusRoot { vm.reloadFromDisk(nexusRoot: nexusRoot) }
            case .reconcile:
                // Stamp a newly-appeared external Page before it's indexed, so a
                // future rename tracks it by id.
                if let nexusRoot, url.pathExtension == "md" {
                    PageStamper.stampIfNeeded(at: url, nexusRoot: nexusRoot)
                }
                pendingPaths.insert(url)
                scheduled = true
            }
        }
        if scheduled { scheduleReconcile() }
    }

    func disposition(of url: URL) -> Disposition {
        let name = url.lastPathComponent
        if name == "nexus.json" || name == "state.json" || name.hasPrefix(".") {
            return .ignore
        }
        // An open Page's in-place external edit defers to the editor — it reloads
        // its own body. But a file GONE at the editor's path (an external move or
        // delete out from under it) can't be reloaded; route it to reconcile so the
        // gone path forces the coarse rebuild, which re-points the editor by stable
        // id. Without this guard a moved open Page re-saves at its old path.
        if url.pathExtension == "md",
            FileManager.default.fileExists(atPath: url.path),
            let vm = AppGlobals.openEditor(forPath: url.standardizedFileURL.path) {
            return .deferToEditor(vm)
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

    // MARK: - Reconcile

    private func run() async {
        // Serialize: a reconcile arriving while one is in flight defers to a rerun.
        if isRunning {
            rerunRequested = true
            return
        }
        isRunning = true
        defer {
            isRunning = false
            if rerunRequested {
                rerunRequested = false
                scheduleReconcile()
            }
        }

        let nexusManager = env.nexusManager
        let paths = pendingPaths
        pendingPaths.removeAll()
        guard nexusManager.currentNexus?.id == nexusID,
            let nexus = nexusManager.currentNexus,
            let index = nexusManager.currentIndex
        else { return }

        if let scopes = surgicalScopes(for: paths, nexus: nexus),
            let updater = env.contentManager.indexUpdater {
            for scope in scopes { await reloadAndIndex(scope, updater: updater) }
            // Re-sync wiki-connection edges for the changed Page bodies (an external
            // edit may have added/removed a `[[ ]]`), matching the in-app edit path
            // so a later rename cascade doesn't miss them.
            for url in paths where url.pathExtension == "md" {
                guard let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)
                else { continue }
                try? updater.reconcileConnections(
                    sourceID: pf.frontmatter.id, sourceKind: "page",
                    sourceTitle: pf.title, body: pf.body)
            }
            // External create/edit may activate or phantom a `[[ ]]` target — nudge
            // open editors to restyle, matching the in-app edit path. (Open Pages'
            // own files route to the editor at intake, never into a surgical batch,
            // so they need no reload here.)
            ConnectionsBus.postChanged(from: env.contentManager)
            return
        }

        await runCoarse(nexus: nexus, index: index)
    }

    /// Distinct Page scopes to reindex when every changed path is an existing `.md`
    /// in a known scope; `nil` (→ coarse) otherwise. See the type doc for why a
    /// gone path must force coarse.
    func surgicalScopes(for paths: Set<URL>, nexus: Nexus) -> Set<Scope>? {
        guard !paths.isEmpty else { return nil }
        var scopes: Set<Scope> = []
        for url in paths {
            guard url.pathExtension == "md",
                FileManager.default.fileExists(atPath: url.path),
                let scope = resolveScope(for: url, nexus: nexus)
            else { return nil }
            scopes.insert(scope)
        }
        return scopes
    }

    /// Reloads one scope's Pages and syncs the index to match it via `syncScope`
    /// (set-sync: upsert present, delete vanished).
    private func reloadAndIndex(_ scope: Scope, updater: IndexUpdater) async {
        let content = env.contentManager
        switch scope {
        case .depthOneSet(let id, let collectionID):
            guard let set = depthOneSet(id: id, collectionID: collectionID) else { return }
            await content.loadAll(forCollection: set)
            syncScope(
                content.pagesByCollection[id] ?? [],
                pageCollectionID: collectionID, pageSetID: id, updater: updater)
        case .deeperSet(let id, let parentSetID, let collectionID):
            guard let set = childSet(id: id, parentSetID: parentSetID) else { return }
            await content.loadAll(for: set)
            syncScope(
                content.pagesBySet[id] ?? [],
                pageCollectionID: collectionID, pageSetID: id, updater: updater)
        case .collectionRoot(let id):
            guard let type = env.collectionManager.types.first(where: { $0.id == id }) else { return }
            await content.loadAll(for: type)
            syncScope(
                content.pagesByCollectionRoot[id] ?? [],
                pageCollectionID: id, pageSetID: nil, updater: updater)
        }
    }

    /// Upserts a scope's on-disk Pages, then deletes any index row whose file is no
    /// longer present in that scope (set-sync).
    private func syncScope(
        _ metas: [PageMeta], pageCollectionID: String, pageSetID: String?,
        updater: IndexUpdater
    ) {
        for meta in metas {
            try? updater.upsertPage(meta, pageCollectionID: pageCollectionID, pageSetID: pageSetID)
        }
        let diskIDs = Set(metas.map(\.id))
        guard
            let indexed = try? updater.pageIDs(pageCollectionID: pageCollectionID, pageSetID: pageSetID)
        else { return }
        for staleID in indexed where !diskIDs.contains(staleID) {
            try? updater.deletePage(id: staleID)
        }
    }

    /// Coarse reconcile: rebuild the index atomically (clear + reinsert in one
    /// transaction, covers every kind + deletes) then refresh the managers + loaded
    /// scopes.
    private func runCoarse(nexus: Nexus, index: PommoraIndex) async {
        let filter = FolderFilter.load(for: nexus)
        try? await IndexBuilder.populate(index: index, from: nexus, filter: filter)
        await env.reloadAllManagers(filter: filter)
        await reloadLoadedPageScopes()
        refreshOpenEditors(nexusRoot: nexus.rootURL)
        ConnectionsBus.postChanged(from: env.contentManager)
    }

    // MARK: - Scope resolution

    /// Resolves the most-specific known container (Set → Collection → Type root)
    /// whose folder contains `url`; `nil` if no loaded container matches (a Page in
    /// a not-yet-loaded container → coarse).
    private func resolveScope(for url: URL, nexus: Nexus) -> Scope? {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        for (parentSetID, sets) in env.pageSetManager.childSetsByParentSet {
            for set in sets where isUnder(parent, set.folderURL) {
                guard let collectionID = collectionID(ofDepthOneSet: parentSetID) else { return nil }
                return .deeperSet(id: set.id, parentSetID: parentSetID, collectionID: collectionID)
            }
        }
        for (collectionID, sets) in env.collectionManager.depthOneSetsByCollection {
            for set in sets where isUnder(parent, set.folderURL) {
                return .depthOneSet(id: set.id, collectionID: collectionID)
            }
        }
        for type in env.collectionManager.types
        where isUnder(parent, NexusPaths.collectionFolderURL(forTitle: type.title, in: nexus)) {
            return .collectionRoot(id: type.id)
        }
        return nil
    }

    /// Path containment with a separator boundary so `/a/bc` is not under `/a/b`.
    private func isUnder(_ path: String, _ folder: URL) -> Bool {
        let f = folder.standardizedFileURL.path
        return path == f || path.hasPrefix(f + "/")
    }

    private func collectionID(ofDepthOneSet depthOneSetID: String) -> String? {
        for (collectionID, sets) in env.collectionManager.depthOneSetsByCollection
        where sets.contains(where: { $0.id == depthOneSetID }) {
            return collectionID
        }
        return nil
    }

    private func depthOneSet(id: String, collectionID: String) -> PageSet? {
        (env.collectionManager.depthOneSetsByCollection[collectionID] ?? []).first { $0.id == id }
    }

    private func childSet(id: String, parentSetID: String) -> PageSet? {
        (env.pageSetManager.childSetsByParentSet[parentSetID] ?? []).first { $0.id == id }
    }

    // MARK: - Editors + loaded scopes

    /// After a reconcile, re-point each open editor whose file was renamed/moved
    /// externally (matched by stable id) and reload its body. Pages with unflushed
    /// edits are left untouched (protect live edits).
    private func refreshOpenEditors(nexusRoot: URL) {
        for vm in AppGlobals.openEditorVMs() {
            if let fresh = env.contentManager.meta(forID: vm.page.id), fresh.url != vm.page.url {
                vm.refreshMeta(fresh)
            }
            vm.reloadFromDisk(nexusRoot: nexusRoot)
        }
    }

    /// Refreshes the currently-loaded Page scopes (Pages load lazily) so any open
    /// list picks up external changes after a coarse rebuild.
    private func reloadLoadedPageScopes() async {
        let content = env.contentManager
        let collections = env.collectionManager.depthOneSetsByCollection.values.flatMap { $0 }
        for id in Array(content.pagesByCollection.keys) {
            guard let collection = collections.first(where: { $0.id == id }) else { continue }
            await content.loadAll(forCollection: collection)
        }
        for id in Array(content.pagesByCollectionRoot.keys) {
            guard let type = env.collectionManager.types.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: type)
        }
        let sets = env.pageSetManager.childSetsByParentSet.values.flatMap { $0 }
        for id in Array(content.pagesBySet.keys) {
            guard let set = sets.first(where: { $0.id == id }) else { continue }
            await content.loadAll(for: set)
        }
    }
}
