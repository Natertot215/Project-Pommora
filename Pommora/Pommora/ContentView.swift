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
        // Inspector now lives per-Page inside PageEditorView (v0.2.7 onward).
        // Non-Page detail views have no inspector content in v0.2.7; Properties
        // v0.3.0 will re-introduce inspectors for Vault/Collection/Space if needed.
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .task {
            await nexusManager.loadOnLaunch()
        }
        .onChange(of: nexusManager.currentNexus, initial: true) { _, nexus in
            constructManagers(for: nexus)
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

        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.contentManager = contentMgr
        self.agendaManager = agendaMgr
        self.homepageManager = homepageMgr
        self.tierConfigManager = tierMgr
        self.savedConfigManager = savedMgr

        // Publish ContentManager + VaultManager refs so the standalone
        // WindowGroup(for: PageRef.self) scene can resolve PageRefs to live
        // PageMeta + Vault + Collection. See AppGlobals doc-comment for the
        // rationale on this lightweight shared-state approach.
        AppGlobals.contentManager = contentMgr
        AppGlobals.vaultManager = vaultMgr

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
