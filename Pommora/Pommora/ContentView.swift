//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager
    @State private var searchQuery = ""
    @State private var sidebarSelection: SidebarSelection = .none
    @State private var presentedSheet: SidebarSheet?
    /// Inspector toggle. Per-Page persistence: loaded from AppState on
    /// selection change, persisted on every toggle. Lives at this level
    /// (not inside PageEditorView) so the inspector renders at the window's
    /// trailing edge via the NavigationSplitView, not as a nested side panel
    /// inside the detail sub-view.
    @State private var inspectorPresented = false

    // Task 64: full 8-manager environment. TopicManager + PageContentManager receive
    // real contextProvider closures with live cross-manager lookups (replacing
    // Task 48's NexusContext.empty placeholder).
    //
    // ParadigmV2 (Task 5.5): ContentManager split into PageContentManager (Pages)
    // and ItemContentManager (Items). ItemTypeManager wires in Phase 6.
    @State private var spaceManager: SpaceManager?
    @State private var topicManager: TopicManager?
    @State private var vaultManager: PageTypeManager?
    @State private var itemTypeManager: ItemTypeManager?
    @State private var contentManager: PageContentManager?
    @State private var itemContentManager: ItemContentManager?
    @State private var agendaTaskManager: AgendaTaskManager?
    @State private var agendaEventManager: AgendaEventManager?
    @State private var homepageManager: HomepageManager?
    @State private var tierConfigManager: TierConfigManager?
    @State private var savedConfigManager: SavedConfigManager?
    @State private var recentsManager: RecentsManager?
    @State private var pinnedManager: PinnedManager?
    @State private var mainWindowRouter: MainWindowRouter?
    @State private var settingsManager: SettingsManager?

    /// Maps a `SidebarSelection` to a `ViewSettingsScope`. Static + pure so the
    /// scope-mapping logic is unit-testable without bootstrapping a full
    /// `ContentView` instance + its env values.
    ///
    /// `.savedKey("calendar")` collapses to `.calendar`; other saved keys
    /// (`homepage`, `recents`, unknown) collapse to `.none` — they aren't
    /// view-settings surfaces.
    static func viewSettingsScope(for selection: SidebarSelection) -> ViewSettingsScope {
        switch selection {
        case .none:
            return .none
        case .savedKey(let key):
            return key == "calendar" ? .calendar : .none
        case .space:
            return .space
        case .topic:
            return .topic
        case .project:
            return .project
        case .pageType(let t):
            return .pageType(t)
        case .collection(let c):
            return .pageCollection(c)
        case .page:
            return .page
        case .itemType(let t):
            return .itemType(t)
        case .itemCollection(let c):
            return .itemCollection(c)
        }
    }

    /// Reactive scope derived from the current sidebar selection. Re-evaluates
    /// every time `sidebarSelection` mutates. Read by `ViewSettingsButton` to
    /// drive the popover body's per-scope content. Statically positioning the
    /// button + dynamically passing this scope is the architectural principle
    /// of the View Settings surface.
    private var currentViewSettingsScope: ViewSettingsScope {
        Self.viewSettingsScope(for: sidebarSelection)
    }

    var body: some View {
        @Bindable var bindableNexusManager = nexusManager

        NavigationSplitView {
            sidebar
                .safeAreaInset(edge: .top, spacing: 8) {
                    SidebarSearchField(text: $searchQuery)
                        .padding(.horizontal, 10)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 330)
        } detail: {
            detail
        }
        .tint(currentAccent)
        .sheet(
            item: $bindableNexusManager.pendingAdoption,
            onDismiss: {
                // Catches Esc / click-outside dismissal — without this the
                // continuation in `runAdoptionIfNeeded` would never resume
                // and the app would hang on the loading placeholder.
                // resolveAdoption is idempotent: a no-op if a button already
                // resumed it.
                nexusManager.resolveAdoption(false)
            }
        ) { plan in
            AdoptionPreviewView(
                plan: plan,
                migrationPlan: nexusManager.pendingMigrationPlan
            ) { confirmed in
                nexusManager.resolveAdoption(confirmed)
            }
        }
        .inspector(isPresented: $inspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 320, max: 480)

                .toolbarBackground(.hidden, for: .windowToolbar)
                .toolbar {
                    // Back/Forward navigation arrows in the leading toolbar area.
                    ToolbarItemGroup(placement: .navigation) {
                        if recentsManager != nil {
                            BackForwardButtons()
                        }
                    }
                    // Segmented pair: NavDropdown (left) + Inspector toggle
                    // (right). One .glassEffect on the outer HStack — the
                    // segment buttons inside are plain so the background
                    // glass isn't doubled by per-button glass.
                    ToolbarItem(placement: .primaryAction) {
                        if recentsManager != nil, pinnedManager != nil {
                            HStack(spacing: 0) {
                                ViewSettingsButton(scope: currentViewSettingsScope)
                                NavDropdownButton(asSegment: true) { sel in
                                    sidebarSelection = sel
                                }

                                Button {
                                    withAnimation(.smooth(duration: 0.25)) {
                                        inspectorPresented.toggle()
                                    }
                                } label: {
                                    Image(systemName: "sidebar.trailing")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 22, height: 16)
                                        .contentShape(Rectangle())
                                }
                                .keyboardShortcut("0", modifiers: [.option, .command])
                                .help("Toggle Inspector (⌥⌘0)")
                            }
                            .glassEffect()
                        }
                    }
                }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            // Per-Page inspector state: when a Page becomes selected, restore
            // its last open/closed flag; otherwise close.
            if case .page(let p) = newValue {
                inspectorPresented = AppState.pageInspectorOpen(pageID: p.id)
            } else {
                inspectorPresented = false

            }

        }
        .onChange(of: sidebarSelection) { _, newSelection in
            guard let recents = AppGlobals.recentsManager else { return }
            guard !recents.isNavigatingHistory else { return }
            guard let ref = EntityStateRef(sidebarSelection: newSelection) else { return }
            recents.record(ref)
        }
        .onChange(of: inspectorPresented) { _, newValue in
            // Persist whenever the user toggles, keyed by the currently
            // selected Page (if any — non-Page toggles don't persist).
            if case .page(let p) = sidebarSelection {
                AppState.setPageInspectorOpen(newValue, pageID: p.id)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .environment(recentsManager)
        .environment(pinnedManager)
        .environment(mainWindowRouter)
        .task {
            await nexusManager.loadOnLaunch()
        }
        .onChange(of: nexusManager.currentNexus, initial: true) { _, nexus in
            constructManagers(for: nexus)
        }
        .onChange(of: mainWindowRouter?.bringToFrontTick) { _, _ in
            guard let router = mainWindowRouter, let sel = router.pendingSelection else { return }
            // Suppress double-recording in the sidebar-selection observer
            // while the programmatic selection mutation propagates.
            AppGlobals.recentsManager?.isNavigatingHistory = true
            sidebarSelection = sel
            DispatchQueue.main.async {
                AppGlobals.recentsManager?.isNavigatingHistory = false
                // Only record for directNavigation — stepHistory moves the
                // cursor without resetting LRU order.
                if router.pendingIntent == .directNavigation {
                    if let ref = EntityStateRef(sidebarSelection: sel) {
                        AppGlobals.recentsManager?.record(ref)
                    }
                }
                router.pendingSelection = nil
            }
            // Raise the main NSWindow.
            NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if let spaceMgr = spaceManager,
            let topicMgr = topicManager,
            let vaultMgr = vaultManager,
            let itemTypeMgr = itemTypeManager,
            let contentMgr = contentManager,
            let itemContentMgr = itemContentManager,
            let savedMgr = savedConfigManager,
            let settingsMgr = settingsManager,
            let agendaTaskMgr = agendaTaskManager,
            let agendaEventMgr = agendaEventManager
        {
            SidebarView(selection: $sidebarSelection)
                .environment(spaceMgr)
                .environment(topicMgr)
                .environment(vaultMgr)
                .environment(itemTypeMgr)
                .environment(contentMgr)
                .environment(itemContentMgr)
                .environment(savedMgr)
                .environment(settingsMgr)
                .environment(agendaTaskMgr)
                .environment(agendaEventMgr)
                .overlay(alignment: .bottom) {
                    if nexusManager.isIndexing {
                        IndexingHUD()
                            .transition(.opacity)
                            .padding(10)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: nexusManager.isIndexing)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading nexus…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        // FrontmatterInspector is the only inspector content in v0.2.7.
        // Resolves vault for the selected Page via ContentManager's walker.
        // Non-Page selections fall through to an empty view (inspector pane
        // stays in the scene tree to avoid layout jumps when toggling).
        if case .page(let p) = sidebarSelection,
            let spaceMgr = spaceManager,
            let vaultMgr = vaultManager,
            let contentMgr = contentManager,
            let resolved = contentMgr.resolveParent(for: p, pageTypeManager: vaultMgr)
        {
            FrontmatterInspector(page: p, vault: resolved.vault)
                .environment(spaceMgr)
                .environment(vaultMgr)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let spaceMgr = spaceManager,
            let vaultMgr = vaultManager,
            let itemTypeMgr = itemTypeManager,
            let contentMgr = contentManager,
            let itemContentMgr = itemContentManager,
            let settingsMgr = settingsManager
        {
            SidebarDetailView(
                selection: $sidebarSelection,
                presentedSheet: $presentedSheet
            )
            .environment(spaceMgr)
            .environment(vaultMgr)
            .environment(itemTypeMgr)
            .environment(contentMgr)
            .environment(itemContentMgr)
            .environment(settingsMgr)
        } else {
            Color.clear
        }
    }

    /// Per-Nexus accent color resolved from SettingsManager. Returns the
    /// SwiftUI `Color` mapped from the stored `SettingsAccentColor` enum, or
    /// the system accent (`.accentColor`) when no override is set or the
    /// manager hasn't loaded yet. Wired here (not in PommoraApp) because
    /// SettingsManager is per-Nexus and constructed inside `constructManagers`.
    private var currentAccent: Color {
        guard let manager = settingsManager,
            let color = manager.settings.accentColor
        else {
            return .accentColor
        }
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    /// Build NexusContext provider closures for TopicManager and ContentManager validators.
    ///
    /// **Important — this snapshot-closure pattern is one-shot.** The returned NexusContext
    /// captures manager arrays at construction time. Suitable for synchronous validator
    /// runs invoked from within `@MainActor` contexts. **Do NOT store the returned
    /// NexusContext or reuse it from a long-lived background closure** (e.g. a future
    /// FSEventStream watcher or SQLite indexer) — by the time such a closure fires, the
    /// captured snapshots are stale. Always rebuild the context inline at the call site,
    /// on the @MainActor.
    private func constructManagers(for nexus: Nexus?) {
        guard let nexus else {
            spaceManager = nil
            topicManager = nil
            vaultManager = nil
            itemTypeManager = nil
            contentManager = nil
            itemContentManager = nil
            agendaTaskManager = nil
            agendaEventManager = nil
            homepageManager = nil
            tierConfigManager = nil
            savedConfigManager = nil
            settingsManager = nil
            return
        }

        let spaceMgr = SpaceManager(nexus: nexus)
        let vaultMgr = PageTypeManager(nexus: nexus)
        let itemTypeMgr = ItemTypeManager(nexus: nexus)

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

        // ItemContentManager mirrors PageContentManager's NexusContext snapshot
        // pattern. Item Type Manager wires in Phase 6 — until then ItemContentManager
        // exists but has no on-disk data to load (`<nexus>/Items/` is materialized
        // by NexusAdopter in Phase 6).
        let itemContentMgr: ItemContentManager = ItemContentManager(nexus: nexus) { [spaceMgr, vaultMgr] in
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
        let recentsMgr = RecentsManager(nexus: nexus)
        let pinnedMgr = PinnedManager(nexus: nexus)
        let settingsMgr = SettingsManager(nexus: nexus)
        let router = MainWindowRouter()

        // Phase E.7.5: wire IndexUpdater into all 6 CRUD managers before publishing.
        // IndexUpdater is Sendable — a single value can be shared across all 6.
        // If currentIndex is nil (degraded mode), updater stays nil and every
        // manager's `if let updater = indexUpdater` guard skips index writes.
        let updater = nexusManager.currentIndex.map { IndexUpdater($0) }
        vaultMgr.indexUpdater = updater
        itemTypeMgr.indexUpdater = updater
        contentMgr.indexUpdater = updater
        itemContentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater = updater
        agendaEventMgr.indexUpdater = updater

        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.itemTypeManager = itemTypeMgr
        self.contentManager = contentMgr
        self.itemContentManager = itemContentMgr
        self.agendaTaskManager = agendaTaskMgr
        self.agendaEventManager = agendaEventMgr
        self.homepageManager = homepageMgr
        self.tierConfigManager = tierMgr
        self.savedConfigManager = savedMgr
        self.recentsManager = recentsMgr
        self.pinnedManager = pinnedMgr
        self.settingsManager = settingsMgr
        self.mainWindowRouter = router

        // Publish manager refs so standalone WindowGroup scenes can reach
        // them without restructuring the ContentView dependency graph.
        AppGlobals.contentManager = contentMgr
        AppGlobals.itemContentManager = itemContentMgr
        AppGlobals.pageTypeManager = vaultMgr
        AppGlobals.itemTypeManager = itemTypeMgr
        AppGlobals.spaceManager = spaceMgr
        AppGlobals.topicManager = topicMgr
        AppGlobals.recentsManager = recentsMgr
        AppGlobals.pinnedManager = pinnedMgr
        AppGlobals.mainWindowRouter = router

        // Initial load — fire all in parallel.
        // PageContentManager + ItemContentManager load per-collection lazily on
        // detail-view appear.
        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll()
            async let _ = itemTypeMgr.loadAll()
            async let _ = agendaTaskMgr.loadAll()
            async let _ = agendaEventMgr.loadAll()
            async let _ = homepageMgr.load()
            async let _ = tierMgr.load()
            async let _ = savedMgr.load()
            async let _ = settingsMgr.loadOrSeed()
            await recentsMgr.load()
            await pinnedMgr.load()
        }
    }
}

/// Transient HUD shown over the sidebar while `NexusManager.isIndexing`
/// is true. Mirrors the Obsidian-style "indexing…" feedback the user expects
/// on Nexus open. Auto-fades in/out via the caller's `.animation` modifier.
private struct IndexingHUD: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

private struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

#Preview {
    ContentView()
        .environment(NexusManager())
        .frame(width: 1200, height: 800)
}
