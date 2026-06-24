//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager
    @State private var sidebarSelection: SidebarSelection = .none
    @State private var presentedSheet: SidebarSheet?

    // Inline-rename + stub-and-edit CRUD state. Lifted to ContentView so
    // detail-view footer "+" triggers can flip the matching sidebar row into
    // rename mode after a stub-create.
    // `justCreatedID` signals RenameableRow to select-all-on-focus so the user's
    // first keystroke replaces the default title.
    @State private var editingID: String? = nil
    @State private var justCreatedID: String? = nil
    /// Inspector toggle. Per-Page persistence: loaded from AppState on
    /// selection change, persisted on every toggle. Lives at this level
    /// (not inside PageEditorView) so the inspector renders at the window's
    /// trailing edge via the NavigationSplitView, not as a nested side panel
    /// inside the detail sub-view.
    @State private var inspectorPresented = false

    /// Single owner + injector for every per-Nexus manager/resolver. Reconstructed
    /// when `currentNexus` changes; nil while no Nexus is open. Satisfies all
    /// descendant `@Environment` values in ONE place via `.injectNexusEnvironment(env)`
    /// (eliminates the forgotten-inject SIGTRAP, quirk #11).
    @State private var nexusEnvironment: NexusEnvironment?

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
        case .area:
            return .area
        case .topic:
            return .topic
        case .project:
            return .project
        case .pageCollection(let t):
            return .pageCollection(t)
        case .collection(let c):
            return .pageSet(c)
        case .page:
            return .page
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

    /// Shared sidebar lookup bundle — built from the live Nexus environment and
    /// reused by the toolbar controls that resolve selection (Back/Forward,
    /// Navigation). Nil until the environment is ready.
    private var sidebarLookup: SidebarLookupBundle? {
        guard let env = nexusEnvironment else { return nil }
        return SidebarLookupBundle(
            content: env.contentManager,
            pageCollection: env.collectionManager,
            area: env.areaManager,
            topic: env.topicManager,
            project: env.projectManager
        )
    }

    /// Inspector show/hide toggle — the trailing member of the settings segment.
    private var inspectorToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                inspectorPresented.toggle()
            }
        } label: {
            Image(systemName: "sidebar.trailing")
                .toolbarGlyph(width: PUI.Icon.toolbarActionFrame)
        }
        .keyboardShortcut("0", modifiers: [.option, .command])
        .help("Toggle Inspector (⌥⌘0)")
    }

    /// The **Views** pill — standalone so the trio's width stays decoupled from
    /// whether Views is visible (welding them condensed the trio on container views).
    @ViewBuilder
    private var viewsButtonCapsule: some View {
        if let env = nexusEnvironment {
            ViewsDropdownButton(
                scope: currentViewSettingsScope,
                collectionManager: env.collectionManager,
                activeViewStore: env.activeViewStore
            )
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    /// The settings·nav·inspector **trio** — the `.primaryAction` item the inspector folds.
    /// Width is stable independent of the Views pill (welding them condensed it).
    @ViewBuilder
    private var trioCapsule: some View {
        if let env = nexusEnvironment {
            HStack(spacing: 0) {
                ViewSettingsButton(
                    scope: currentViewSettingsScope,
                    collectionManager: env.collectionManager,
                    tierConfigManager: env.tierConfigManager,
                    pageContentManager: env.contentManager
                )
                if let lookup = sidebarLookup {
                    NavigationButton(lookup: lookup) { sel in
                        sidebarSelection = sel
                    }
                }
                inspectorToggleButton
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    /// Whether the views button surfaces — only for the two container detail
    /// views that own SavedViews.
    private var showsViewControls: Bool {
        switch currentViewSettingsScope {
        case .pageCollection, .pageSet: return true
        default: return false
        }
    }

    /// Window toolbar. Views pill and trio are TWO separate items — welding them condensed
    /// the trio on container views. KNOWN QUIRK: both live in the trailing region the inspector
    /// adopts, so toggling the inspector folds the Views pill in too. macOS exposes no
    /// content-trailing slot to avoid this; accepted tradeoff. See `// Guidelines //Design.md`.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if let lookup = sidebarLookup {
                BackForwardButtons(lookup: lookup)
            }
        }
        ToolbarSpacer(.flexible)
        if showsViewControls {
            ToolbarItem {
                viewsButtonCapsule
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem(placement: .primaryAction) {
            trioCapsule
        }
        .sharedBackgroundVisibility(.hidden)
    }

    var body: some View {
        @Bindable var bindableNexusManager = nexusManager

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 330)
        } detail: {
            detail
                    // Hosted on the DETAIL column — on the split-view root, `.primaryAction`
                // anchors to the sidebar and folds into overflow; on the inspector it leaks.
                .toolbar { mainToolbar }
        }
        .tint(currentAccent)
        .environment(\.nexusAccent, currentAccent)
        .toolbarBackground(.hidden, for: .windowToolbar)
        // Suppress the native NSToolbar right-click display-mode menu
        // ("Icon Only / Icon and Text") — see WindowToolbarConfigurator.
        .background(WindowToolbarConfigurator())
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
        .task {
            LaunchTrace.mark("ContentView.task: fired")
            await nexusManager.loadOnLaunch()
        }
        .onChange(of: nexusManager.currentNexus, initial: true) { _, nexus in
            rebuildEnvironment(for: nexus)
        }
        .onChange(of: nexusEnvironment?.mainWindowRouter.bringToFrontTick) { _, _ in
            guard let router = nexusEnvironment?.mainWindowRouter, let sel = router.pendingSelection else { return }
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
            AppGlobals.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if let env = nexusEnvironment {
            SidebarView(
                selection: $sidebarSelection,
                editingID: $editingID,
                justCreatedID: $justCreatedID
            )
            .injectNexusEnvironment(env)
            .overlay(alignment: .bottom) {
                if nexusManager.isIndexing {
                    IndexingHUD()
                        .transition(.opacity)
                        .padding(PUI.Spacing.lg)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: nexusManager.isIndexing)
        } else {
            VStack(spacing: PUI.Spacing.md) {
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
        // Non-Page selections fall through to Color.clear so the inspector
        // pane stays in the scene tree (avoids layout jumps when toggling).
        if case .page(let p) = sidebarSelection,
            let env = nexusEnvironment,
            let resolved = env.contentManager.resolveParent(
                for: p, collectionManager: env.collectionManager, pageSetManager: env.pageSetManager)
        {
            FrontmatterInspector(
                page: p,
                pageCollection: resolved.pageCollection,
                index: nexusManager.currentIndex,
                relationDisplay: env.contextResolver,
                onSave: { updated in
                    Task {
                        try? await env.contentManager.updatePageFrontmatter(
                            p, frontmatter: updated, pageCollection: resolved.pageCollection,
                            collection: resolved.collection, set: resolved.set)
                    }
                }
            )
            .injectNexusEnvironment(env)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let env = nexusEnvironment {
            SidebarDetailView(
                selection: $sidebarSelection,
                presentedSheet: $presentedSheet,
                editingID: $editingID,
                justCreatedID: $justCreatedID
            )
            .injectNexusEnvironment(env)
        } else {
            Color.clear
        }
    }

    /// Per-Nexus accent color resolved from SettingsManager. Returns the
    /// SwiftUI `Color` mapped from the stored `SettingsAccentColor` enum, or
    /// the system accent (`.accentColor`) when no override is set or the
    /// manager hasn't loaded yet. Wired here (not in PommoraApp) because
    /// SettingsManager is per-Nexus and constructed inside `NexusEnvironment`.
    private var currentAccent: Color {
        nexusEnvironment?.settingsManager.settings.accentColor?.color ?? .accentColor
    }

    private func rebuildEnvironment(for nexus: Nexus?) {
        // Stop the outgoing Nexus's file watcher deterministically (on the main
        // actor) before the env is dropped. The switch path also re-overwrites
        // AppGlobals.current via the new env's init, but the close path below
        // would otherwise leave the old env strongly pinned there — running its
        // watcher against a closed Nexus forever.
        nexusEnvironment?.stopWatching()
        // Preview windows are per-Nexus state (their PageRefs resolve against
        // the outgoing managers) — close the whole group when switching away
        // from a live environment. MUST stay guarded to non-initial runs and
        // deferred out of the current view update: this runs from
        // `onChange(initial: true)` during the FIRST render, and tearing the
        // panel down mid-update can disturb the update cycle.
        if nexusEnvironment != nil {
            Task { @MainActor in PreviewTarget.shared.close() }
        }
        guard let nexus else {
            AppGlobals.current = nil
            nexusEnvironment = nil
            return
        }
        nexusEnvironment = NexusEnvironment(nexus: nexus, nexusManager: nexusManager)
        #if DEBUG
        // Test hook: `-openPreviewSample` auto-opens the first resolvable
        // page as a preview once managers load (screenshot-driven UI
        // verification without scripted clicks). Never set by XCTest.
        if ProcessInfo.processInfo.arguments.contains("-openPreviewSample"),
            let env = nexusEnvironment
        {
            PreviewSampleLauncher.run(env: env) { ref in
                openPagePreview(ref)
            }
        }
        #endif
    }
}

/// Transient HUD shown over the sidebar while `NexusManager.isIndexing` is true.
private struct IndexingHUD: View {
    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PUI.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: PUI.Radius.medium)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

#Preview {
    ContentView()
        .environment(NexusManager())
        .frame(width: 1200, height: 800)
}
