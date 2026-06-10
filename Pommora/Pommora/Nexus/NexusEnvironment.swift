//
//  NexusEnvironment.swift
//  Pommora
//
//  Single-source owner + injector for every per-Nexus manager/resolver.
//
//  Before this type, `ContentView` hand-wired ~16 `@State private var …Manager?`
//  optionals, unwrapped them in nested `if let` pyramids, and injected each one
//  individually via `.environment(...)` in two parallel chains (detail +
//  inspector + sidebar). SwiftUI's `_TaskValueModifier` resolves
//  `@Environment(X.self)` when computing a view's `.task`; if any detail view
//  declared an env that wasn't injected, the app SIGTRAP'd on first selection
//  (active-branch quirk #15) — and adding a manager meant editing two scattered
//  places, with a forgotten inject = crash.
//
//  Now: this object constructs and OWNS every manager (the exact wiring that
//  lived in `ContentView.constructManagers`), and the
//  `.injectNexusEnvironment(_:)` modifier applies the FULL `.environment(...)`
//  chain in ONE place. Adding a manager later = one stored property here + one
//  line in the modifier — co-located and compiler-checked, never a scattered
//  inject that crashes if forgotten.
//

import MarkdownPM
import SwiftUI

/// Owns + wires every per-Nexus manager and the shared relation resolver for
/// the lifetime of one open Nexus. Reconstructed whenever `NexusManager`'s
/// `currentNexus` changes (see `ContentView`).
///
/// All construction + cross-manager wiring (the snapshot-closure validator
/// pattern, IndexUpdater fan-out, cross-side reload hook, AppGlobals publish,
/// and the parallel initial-load `Task`) is performed in `init` and is
/// behavior-identical to the former `ContentView.constructManagers`.
///
/// Deliberately NOT `@Observable`: this container is held in a `@State` and only
/// ever read as a whole optional (rebuilt when `NexusManager.currentNexus`
/// changes). Every stored property is a `let`, so the container's own identity
/// never changes after construction; the one reactive surface in here
/// (`mainWindowRouter.bringToFrontTick`) is observed through `MainWindowRouter`'s
/// OWN `@Observable`, never through this container — so per-member observation
/// would be dead weight.
@MainActor
final class NexusEnvironment {
    /// The app-level Nexus session manager (stable `@Observable`). Injected via
    /// `injectNexusEnvironment` so `@Environment(NexusManager.self)` resolves
    /// without SIGTRAP (quirk #15).
    let nexusManager: NexusManager

    let spaceManager: SpaceManager
    let topicManager: TopicManager
    let vaultManager: PageTypeManager
    let contentManager: PageContentManager
    let agendaTaskManager: AgendaTaskManager
    let agendaEventManager: AgendaEventManager
    let homepageManager: HomepageManager
    let tierConfigManager: TierConfigManager
    let savedConfigManager: SavedConfigManager
    let sidebarSectionsManager: SidebarSectionsManager
    let recentsManager: RecentsManager
    let pinnedManager: PinnedManager
    let mainWindowRouter: MainWindowRouter
    let settingsManager: SettingsManager

    /// Shared context-link/tier display resolver (icon + title from the index).
    /// Its index closure captures `nexusManager` and reads `.currentIndex`
    /// lazily, so it tracks index swaps within this Nexus.
    let contextResolver: ContextDisplayResolver

    /// Stable title-keyed connection resolver for the live editor styler.
    /// Built ONCE here over the current index (NoOp when the index is absent /
    /// degraded), so the `MarkdownPMEditor`'s `NSViewRepresentable` references
    /// the same instance across renders — no per-keystroke re-instantiation.
    /// Drives `[[ ]]` connection styling.
    let connectionResolver: any WikiLinkResolver

    /// Constructs and wires every manager (see the class doc above). The NexusContext
    /// snapshot closures built inline below are **one-shot**: they capture manager arrays
    /// at construction time, so never reuse one from a long-lived background closure
    /// (e.g. a future FSEventStream watcher or SQLite indexer) — rebuild it inline on the
    /// `@MainActor` at the call site.
    init(nexus: Nexus, nexusManager: NexusManager) {
        let spaceMgr = SpaceManager(nexus: nexus)
        let vaultMgr = PageTypeManager(nexus: nexus)

        // TopicManager needs SpaceManager + PageTypeManager for cross-entity lookups.
        // The outer closure runs on MainActor (per TopicManager's signature) and
        // reads live state from the peer managers, then bakes value-type snapshots
        // into the @Sendable NexusContext lookup closures — this is what allows
        // capturing through Swift 6 strict concurrency: managers themselves are
        // @MainActor-isolated and non-Sendable, but `[Space]` / `[Vault]` are.
        let topicMgr = TopicManager(nexus: nexus) { [spaceMgr, vaultMgr] in
            let spaces = spaceMgr.spaces
            let types = vaultMgr.types
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { id in types.first { $0.id == id } }
            )
        }

        // PageContentManager needs Space + Topic + Project + Page Type for tier validation.
        // Same snapshot pattern as TopicManager: outer closure reads live state on
        // MainActor; inner @Sendable closures use value-type snapshots.
        let contentMgr: PageContentManager = PageContentManager(nexus: nexus) { [spaceMgr, vaultMgr] in
            let spaces = spaceMgr.spaces
            let types = vaultMgr.types
            let topics = topicMgr.topics
            let projectsByParent = topicMgr.projectsByParent
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { id in topics.first { $0.id == id } },
                lookupProject: { id in
                    for arr in projectsByParent.values {
                        if let p = arr.first(where: { $0.id == id }) { return p }
                    }
                    return nil
                },
                lookupVault: { id in types.first { $0.id == id } }
            )
        }

        let agendaTaskMgr = AgendaTaskManager(nexus: nexus)
        let agendaEventMgr = AgendaEventManager(nexus: nexus)
        let homepageMgr = HomepageManager(nexus: nexus)
        let tierMgr = TierConfigManager(nexus: nexus)
        let savedMgr = SavedConfigManager(nexus: nexus)
        let sidebarSectionsMgr = SidebarSectionsManager(nexus: nexus)
        let recentsMgr = RecentsManager(nexus: nexus)
        let pinnedMgr = PinnedManager(nexus: nexus)
        let settingsMgr = SettingsManager(nexus: nexus)
        let router = MainWindowRouter()

        // Shared relation/tier display resolver. Captures `nexusManager` (the
        // stable @Observable instance) and reads `.currentIndex` lazily so it
        // tracks index swaps within this Nexus.
        let contextRes = ContextDisplayResolver(index: { [nexusManager] in nexusManager.currentIndex })

        // Stable title-keyed connection resolver over THIS Nexus's index. Built
        // once (NoOp when the index is absent / degraded) so the editor's
        // NSViewRepresentable references a stable instance across renders.
        let connRes: any WikiLinkResolver =
            nexusManager.currentIndex.map { PommoraConnectionResolver(index: $0) }
            ?? NoOpWikiLinkResolver()

        // Phase E.7.5: wire IndexUpdater into all CRUD managers before publishing
        // (Space + Topic added so Contexts sync to the `contexts` index table).
        // IndexUpdater is Sendable — a single value can be shared across all of them.
        // If currentIndex is nil (degraded mode), updater stays nil and every
        // manager's `if let updater = indexUpdater` guard skips index writes.
        let updater = nexusManager.currentIndex.map { IndexUpdater($0) }
        spaceMgr.indexUpdater = updater
        topicMgr.indexUpdater = updater
        vaultMgr.indexUpdater = updater
        contentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater = updater
        agendaEventMgr.indexUpdater = updater

        // Connections D2: rename refreshes the denormalized title cached in the
        // Pinned + Recents stores so pins/recents don't show a stale name.
        contentMgr.pinnedManager = pinnedMgr
        contentMgr.recentsManager = recentsMgr

        self.nexusManager = nexusManager
        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.contentManager = contentMgr
        self.agendaTaskManager = agendaTaskMgr
        self.agendaEventManager = agendaEventMgr
        self.homepageManager = homepageMgr
        self.tierConfigManager = tierMgr
        self.savedConfigManager = savedMgr
        self.sidebarSectionsManager = sidebarSectionsMgr
        self.recentsManager = recentsMgr
        self.pinnedManager = pinnedMgr
        self.settingsManager = settingsMgr
        self.mainWindowRouter = router
        self.contextResolver = contextRes
        self.connectionResolver = connRes

        // Publish manager refs so standalone WindowGroup scenes can reach
        // them without restructuring the ContentView dependency graph.
        AppGlobals.publish(
            contentManager: contentMgr,
            pageTypeManager: vaultMgr,
            spaceManager: spaceMgr,
            topicManager: topicMgr,
            recentsManager: recentsMgr,
            pinnedManager: pinnedMgr,
            mainWindowRouter: router)
        AppGlobals.current = self

        // Build the folder exclusion filter once — reads .nexus/settings.json
        // synchronously (no SettingsManager dependency) so it is ready before
        // the parallel load task fires.
        let folderFilter = FolderFilter.load(for: nexus)

        // Initial load — fire all in parallel.
        // PageContentManager loads per-collection lazily on detail-view appear.
        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll(filter: folderFilter)
            async let _ = agendaTaskMgr.loadAll()
            async let _ = agendaEventMgr.loadAll()
            async let _ = homepageMgr.load()
            async let _ = tierMgr.load()
            async let _ = savedMgr.load()
            async let _ = sidebarSectionsMgr.load()
            async let _ = settingsMgr.loadOrSeed()
            await recentsMgr.load()
            await pinnedMgr.load()
        }
    }
}

extension View {
    /// Injects every manager owned by `env` into the environment in ONE place.
    ///
    /// This is the single source of manager injection. Every `@Environment(X.self)`
    /// declared on any descendant (sidebar, detail, inspector) is satisfied here,
    /// so a missing inject can no longer SIGTRAP a `.task`-bearing view on first
    /// selection (quirk #15). Adding a manager = add a stored property to
    /// `NexusEnvironment` + one `.environment(...)` line below.
    func injectNexusEnvironment(_ env: NexusEnvironment) -> some View {
        self
            .environment(env.nexusManager)
            .environment(env.spaceManager)
            .environment(env.topicManager)
            .environment(env.vaultManager)
            .environment(env.contentManager)
            .environment(env.agendaTaskManager)
            .environment(env.agendaEventManager)
            .environment(env.homepageManager)
            .environment(env.tierConfigManager)
            .environment(env.savedConfigManager)
            .environment(env.sidebarSectionsManager)
            .environment(env.recentsManager)
            .environment(env.pinnedManager)
            .environment(env.mainWindowRouter)
            .environment(env.settingsManager)
            .environment(env.contextResolver)
            // Protocol existentials ride through keyPath-based environment values
            // (the `@Entry` entry in ConnectionResolver.swift), not `.environment(object)`.
            .environment(\.connectionResolver, env.connectionResolver)
    }
}
