//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var searchQuery = ""
    @State private var sidebarSelection: SidebarSelection = .none
    @State private var presentedSheet: SidebarSheet?

    // Inline-rename + stub-and-edit CRUD state. Lifted to ContentView (was
    // SidebarView-local pre-F.0) so detail-view footer "+" triggers can flip
    // the matching sidebar row into rename mode after a stub-create. Both
    // bindings cascade into SidebarView (and its sections/rows) AND into
    // SidebarDetailView (and its detail views).
    //
    // `editingID` is set non-nil when a single row is in inline-rename mode.
    // `justCreatedID` is set non-nil when the row in rename mode was just
    // freshly stub-created; RenameableRow reads it to select-all-on-focus so
    // the user's first keystroke replaces the default title.
    @State private var editingID: String? = nil
    @State private var justCreatedID: String? = nil
    /// Inspector toggle. Per-Page persistence: loaded from AppState on
    /// selection change, persisted on every toggle. Lives at this level
    /// (not inside PageEditorView) so the inspector renders at the window's
    /// trailing edge via the NavigationSplitView, not as a nested side panel
    /// inside the detail sub-view.
    @State private var inspectorPresented = false

    /// Single owner + injector for every per-Nexus manager/resolver. Replaces
    /// the former ~16 individual `@State …Manager?` optionals + their scattered
    /// `.environment(...)` injects. Reconstructed whenever `currentNexus`
    /// changes (see `.onChange` → `rebuildEnvironment`); nil while no Nexus is
    /// open. Every manager is reached via `nexusEnvironment?.someManager`, and
    /// every descendant's `@Environment(X.self)` is satisfied in ONE place by
    /// `.injectNexusEnvironment(env)` (eliminates the forgotten-inject SIGTRAP,
    /// quirk #15). See `NexusEnvironment.swift`.
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

    /// Toolbar primary-action capsule (ViewSettings + NavDropdown + Inspector
    /// toggle). Extracted to a separate ViewBuilder so the compound nil-guards
    /// don't blow up SwiftUI's @ViewBuilder type-checker inside the toolbar
    /// closure. Renders nothing until the managers it needs are non-nil.
    @ViewBuilder
    private var primaryActionCapsule: some View {
        if let env = nexusEnvironment {
            let vaultMgr = env.vaultManager
            let tierConfigMgr = env.tierConfigManager
            let contentMgr = env.contentManager
            let lookup = SidebarLookupBundle(
                content: contentMgr,
                pageType: vaultMgr,
                space: env.spaceManager,
                topic: env.topicManager
            )
            HStack(spacing: 0) {
                ViewSettingsButton(
                    scope: currentViewSettingsScope,
                    pageTypeManager: vaultMgr,
                    tierConfigManager: tierConfigMgr,
                    pageContentManager: contentMgr
                )
                NavDropdownButton(asSegment: true, lookup: lookup) { sel in
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
        .environment(\.nexusAccent, currentAccent)
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
                        if let env = nexusEnvironment {
                            BackForwardButtons(
                                lookup: SidebarLookupBundle(
                                    content: env.contentManager,
                                    pageType: env.vaultManager,
                                    space: env.spaceManager,
                                    topic: env.topicManager
                                ))
                        }
                    }
                    // Segmented pair: NavDropdown (left) + Inspector toggle
                    // (right). One .glassEffect on the outer HStack — the
                    // segment buttons inside are plain so the background
                    // glass isn't doubled by per-button glass.
                    ToolbarItem(placement: .primaryAction) {
                        primaryActionCapsule
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
            // Raise the main NSWindow.
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
            let env = nexusEnvironment,
            let resolved = env.contentManager.resolveParent(for: p, pageTypeManager: env.vaultManager)
        {
            FrontmatterInspector(
                page: p,
                vault: resolved.vault,
                index: nexusManager.currentIndex,
                relationDisplay: env.contextResolver,
                onSave: { updated in
                    Task {
                        try? await env.contentManager.updatePageFrontmatter(
                            p, frontmatter: updated, vault: resolved.vault, collection: resolved.collection)
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

    /// (Re)build the per-Nexus manager container when `currentNexus` changes.
    /// nil clears the environment (no Nexus open); a value constructs a fresh
    /// `NexusEnvironment`, which performs all manager construction, cross-manager
    /// wiring, AppGlobals publish, and the parallel initial-load `Task` in its
    /// initializer (formerly `constructManagers`). See `NexusEnvironment.swift`.
    private func rebuildEnvironment(for nexus: Nexus?) {
        // Preview windows are per-Nexus state (their PageRefs resolve against
        // the outgoing managers) — close the whole group when switching away
        // from a live environment. MUST stay guarded to non-initial runs and
        // deferred out of the current view update: this runs from
        // `onChange(initial: true)` during the FIRST render, and mutating
        // scene state (dismissWindow) mid-update breaks the update cycle.
        if nexusEnvironment != nil {
            let dismissWindow = dismissWindow
            Task { @MainActor in
                PreviewTarget.shared.ref = nil
                dismissWindow(id: "page-preview")
            }
        }
        guard let nexus else {
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
                openPagePreview(ref, using: openWindow)
            }
        }
        #endif
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
