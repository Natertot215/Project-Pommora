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

    // Task 64: full 8-manager environment. TopicManager + ContentManager receive
    // real contextProvider closures with live cross-manager lookups (replacing
    // Task 48's NexusContext.empty placeholder).
    @State private var spaceManager: SpaceManager?
    @State private var topicManager: TopicManager?
    @State private var vaultManager: VaultManager?
    @State private var contentManager: ContentManager?
    @State private var agendaManager: AgendaManager?
    @State private var homepageManager: HomepageManager?
    @State private var tierConfigManager: TierConfigManager?
    @State private var savedConfigManager: SavedConfigManager?
    @State private var recentsManager: RecentsManager?
    @State private var favoritesManager: FavoritesManager?
    @State private var mainWindowRouter: MainWindowRouter?

    var body: some View {
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
        .inspector(isPresented: $inspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 320, max: 480)

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
                        if recentsManager != nil, favoritesManager != nil {
                            HStack(spacing: 0) {
                                NavDropdownButton(asSegment: true)

                                Rectangle()
                                    .fill(.secondary)
                                    .frame(width: 1, height: 14)

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
        .environment(favoritesManager)
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
            let contentMgr = contentManager,
            let savedMgr = savedConfigManager
        {
            SidebarView(selection: $sidebarSelection)
                .environment(spaceMgr)
                .environment(topicMgr)
                .environment(vaultMgr)
                .environment(contentMgr)
                .environment(savedMgr)
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
            let resolved = contentMgr.resolveParent(for: p, vaultManager: vaultMgr)
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
            let contentMgr = contentManager
        {
            SidebarDetailView(
                selection: $sidebarSelection,
                presentedSheet: $presentedSheet
            )
            .environment(spaceMgr)
            .environment(vaultMgr)
            .environment(contentMgr)
        } else {
            Color.clear
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
            contentManager = nil
            agendaManager = nil
            homepageManager = nil
            tierConfigManager = nil
            savedConfigManager = nil
            return
        }

        let spaceMgr = SpaceManager(nexus: nexus)
        let vaultMgr = VaultManager(nexus: nexus)

        // TopicManager needs SpaceManager + VaultManager for cross-entity lookups.
        // The outer closure runs on MainActor (per TopicManager's signature) and
        // reads live state from the peer managers, then bakes value-type snapshots
        // into the @Sendable NexusContext lookup closures — this is what allows
        // capturing through Swift 6 strict concurrency: managers themselves are
        // @MainActor-isolated and non-Sendable, but `[Space]` / `[Vault]` are.
        let topicMgr = TopicManager(nexus: nexus) { [spaceMgr, vaultMgr] in
            let spaces = spaceMgr.spaces
            let vaults = vaultMgr.vaults
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { _ in nil },
                lookupSubtopic: { _ in nil },
                lookupVault: { id in vaults.first { $0.id == id } }
            )
        }

        // ContentManager needs Space + Topic + Subtopic + Vault for tier validation.
        // Same snapshot pattern as TopicManager: outer closure reads live state on
        // MainActor; inner @Sendable closures use value-type snapshots.
        let contentMgr: ContentManager = ContentManager(nexus: nexus) { [spaceMgr, vaultMgr] in
            let spaces = spaceMgr.spaces
            let vaults = vaultMgr.vaults
            let topics = topicMgr.topics
            let subsByParent = topicMgr.subtopicsByParent
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { id in topics.first { $0.id == id } },
                lookupSubtopic: { id in
                    for arr in subsByParent.values {
                        if let s = arr.first(where: { $0.id == id }) { return s }
                    }
                    return nil
                },
                lookupVault: { id in vaults.first { $0.id == id } }
            )
        }

        let agendaMgr = AgendaManager(nexus: nexus)
        let homepageMgr = HomepageManager(nexus: nexus)
        let tierMgr = TierConfigManager(nexus: nexus)
        let savedMgr = SavedConfigManager(nexus: nexus)
        let recentsMgr = RecentsManager(nexus: nexus)
        let favoritesMgr = FavoritesManager(nexus: nexus)
        let router = MainWindowRouter()

        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.contentManager = contentMgr
        self.agendaManager = agendaMgr
        self.homepageManager = homepageMgr
        self.tierConfigManager = tierMgr
        self.savedConfigManager = savedMgr
        self.recentsManager = recentsMgr
        self.favoritesManager = favoritesMgr
        self.mainWindowRouter = router

        // Publish manager refs so standalone WindowGroup scenes can reach
        // them without restructuring the ContentView dependency graph.
        AppGlobals.contentManager = contentMgr
        AppGlobals.vaultManager = vaultMgr
        AppGlobals.spaceManager = spaceMgr
        AppGlobals.topicManager = topicMgr
        AppGlobals.recentsManager = recentsMgr
        AppGlobals.favoritesManager = favoritesMgr
        AppGlobals.mainWindowRouter = router

        // Initial load — fire all in parallel.
        // ContentManager loads per-collection lazily on detail-view appear.
        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll()
            async let _ = agendaMgr.loadAll()
            async let _ = homepageMgr.load()
            async let _ = tierMgr.load()
            async let _ = savedMgr.load()
            await recentsMgr.load()
            await favoritesMgr.load()
        }
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
