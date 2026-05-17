//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager
    @State private var inspectorPresented = false
    @State private var searchQuery = ""
    @State private var sidebarSelection: SidebarSelection = .none

    // Interim manager wiring — Task 64 will lift this into a richer
    // constructManagers(for:) that also builds Content/Agenda/Homepage/Tier
    // managers and triggers parallel loadAll. For now, Task 48's sidebar only
    // needs Space/Topic/Vault/SavedConfig; ProgressView until nexus settles.
    @State private var spaceManager: SpaceManager?
    @State private var topicManager: TopicManager?
    @State private var vaultManager: VaultManager?
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
            Color.clear
        }
        .inspector(isPresented: $inspectorPresented) {
            Color.clear
                .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.smooth(duration: 0.30)) {
                                inspectorPresented.toggle()
                            }
                        } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.trailing")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .task {
            await nexusManager.loadOnLaunch()
        }
        .onChange(of: nexusManager.currentNexus) { _, nexus in
            constructManagers(for: nexus)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if let spaceMgr = spaceManager,
           let topicMgr = topicManager,
           let vaultMgr = vaultManager,
           let savedMgr = savedConfigManager
        {
            SidebarView(selection: $sidebarSelection)
                .environment(spaceMgr)
                .environment(topicMgr)
                .environment(vaultMgr)
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

    private func constructManagers(for nexus: Nexus?) {
        guard let nexus else {
            spaceManager = nil
            topicManager = nil
            vaultManager = nil
            savedConfigManager = nil
            return
        }

        let spaceMgr = SpaceManager(nexus: nexus)
        let vaultMgr = VaultManager(nexus: nexus)
        // TopicValidator lookup closures are @Sendable; capturing the MainActor
        // managers directly is rejected by Swift 6 strict concurrency. Task 48's
        // sidebar UI never triggers validator-driven lookups (Topic CRUD UI is
        // stubbed); supply .empty for now. Task 64 will rebuild this with the
        // correct lookup wiring once the UI actually creates/edits Topics.
        let topicMgr = TopicManager(nexus: nexus) { NexusContext.empty }
        let savedMgr = SavedConfigManager(nexus: nexus)

        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.savedConfigManager = savedMgr

        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll()
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
