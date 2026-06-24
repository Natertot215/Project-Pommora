// NavigationButton.swift
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case pinned, recents
    var id: String { rawValue }
    var label: String { self == .pinned ? "Pinned" : "Recents" }
}

@MainActor
struct NavigationButton: View {
    /// Managers passed in as explicit params (NOT @Environment) because the
    /// toolbar where this lives is OUTSIDE ContentView's `.detail { ... }`
    /// closure's `.environment(...)` chain. Same pattern as ViewSettingsButton
    /// and BackForwardButtons (quirk #16). Threaded through so
    /// `SidebarSelection(stateRef:lookup:)` in handleOpen() resolves against
    /// live manager instances rather than AppGlobals.
    let lookup: SidebarLookupBundle

    /// Called when a row is double-clicked. ContentView wires this to set
    /// its `sidebarSelection` @State directly — avoids the @Observable hop
    /// through MainWindowRouter, which doesn't propagate reliably from the
    /// popover view host.
    let onOpen: (SidebarSelection) -> Void

    @State private var isPresented = false
    @State private var mode: PanelMode = .pinned
    @State private var selection: EntityStateRef?

    // Snapshots refreshed on popover open. Bypasses an @Observable-
    // through-popover-host edge case where mutations on the source
    // manager don't reliably propagate into the popover's view tree.
    @State private var recentsSnapshot: [EntityStateRef] = []
    @State private var pinnedSnapshot: [EntityStateRef] = []

    var body: some View {
        triggerButton
            .keyboardShortcut("t", modifiers: [.command])
            .help("Navigation (⌘T)")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                panel
                    .frame(width: 320)
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue { refreshSnapshots() }
            }
    }

    private func refreshSnapshots() {
        recentsSnapshot = AppGlobals.recentsManager?.dropdownTop ?? []
        pinnedSnapshot = AppGlobals.pinnedManager?.entries ?? []
    }

    private var triggerButton: some View {
        // Plain segment — the parent pill's `.glassEffect` carries the
        // background; this button adds no chrome of its own.
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "map")
                .toolbarGlyph(width: PUI.Icon.toolbarActionFrame)
        }
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 3) {
            modePicker
                .padding(.horizontal, PUI.Spacing.lg)
                .padding(.top, PUI.Spacing.lg)
                .padding(.bottom, PUI.Spacing.md)

            // Inset list trough — visually recessed inside the glass card
            listContainer
                .padding(.horizontal, PUI.Spacing.sm)
                .padding(.bottom, PUI.Spacing.sm)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: 300, maxHeight: 400)

        .clipShape(.rect(cornerRadius: PUI.Radius.popover))
    }

    /// Custom Liquid Glass segmented pill — hand-rolled HStack of glass
    /// buttons with a selection capsule overlay because the default
    /// `.segmented` chrome doesn't read as glass.
    @ViewBuilder
    private var modePicker: some View {
        HStack(spacing: 1) {
            modeButton(.pinned)
            Rectangle()
                .fill(Color.white.opacity(0.0))
                .frame(width: 1, height: 18)
            modeButton(.recents)
        }

    }

    @ViewBuilder
    private func modeButton(_ m: PanelMode) -> some View {
        Button {
            mode = m
        } label: {
            Text(m.label)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PUI.Spacing.sm)
                .foregroundStyle(mode == m ? Color.primary : Color.secondary)
        }
        .buttonStyle(.borderless)
        .contentShape(.capsule)
    }

    @ViewBuilder
    private var listContainer: some View {
        Group {
            switch mode {
            case .pinned: pinnedList
            case .recents: recentsList
            }
        }
        .background(Color.clear)
        .clipShape(.rect(cornerRadius: PUI.Radius.listTrough))
    }

    @ViewBuilder
    private var pinnedList: some View {
        if pinnedSnapshot.isEmpty {
            Text("Nothing pinned yet. Right-click a row to pin it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(pinnedSnapshot, id: \.self) { ref in
                    EntityRow(
                        ref: ref,
                        lookup: lookup,
                        isPinned: true,
                        pinAction: {
                            AppGlobals.pinnedManager?.toggle(ref)
                            refreshSnapshots()
                        }
                    )
                    .tag(Optional(ref))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { handleOpen(ref) }
                    )
                }
                .onMove { src, dst in
                    AppGlobals.pinnedManager?.move(fromOffsets: src, toOffset: dst)
                    refreshSnapshots()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var recentsList: some View {
        if recentsSnapshot.isEmpty {
            Text("Open a page to populate Recents. Vaults, collections, and sets stay in Back/Forward.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else {
            List(selection: $selection) {
                ForEach(recentsSnapshot, id: \.self) { ref in
                    EntityRow(
                        ref: ref,
                        lookup: lookup,
                        isPinned: pinnedSnapshot.contains(ref),
                        pinAction: {
                            AppGlobals.pinnedManager?.toggle(ref)
                            refreshSnapshots()
                        }
                    )
                    .tag(Optional(ref))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { handleOpen(ref) }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func handleOpen(_ ref: EntityStateRef) {
        isPresented = false
        selection = nil  // reset so the same row can be clicked again

        switch ref.typedKind {
        case .agenda, .none:
            return
        case .page, .collection, .area, .topic, .project, .set:
            if let sel = SidebarSelection(stateRef: ref, lookup: lookup) {
                onOpen(sel)
                return
            }
            // Lazy-load fallback: pages/collections in collections the user hasn't
            // visited this session aren't in ContentManager's dicts yet. Walk
            // every collection + collection until the lookup succeeds. (A future
            // SQLite-backed lookup makes this O(1) and removes the walk entirely.)
            Task { @MainActor in
                guard let cm = AppGlobals.contentManager,
                    let vm = AppGlobals.collectionManager
                else { return }
                for collection in vm.types {
                    await cm.loadAll(for: collection)
                    if let sel = SidebarSelection(stateRef: ref, lookup: lookup) {
                        onOpen(sel)
                        return
                    }
                    for col in vm.pageCollections(in: collection) {
                        await cm.loadAll(forCollection: col)
                        if let sel = SidebarSelection(stateRef: ref, lookup: lookup) {
                            onOpen(sel)
                            return
                        }
                    }
                }
            }
        }
    }

}
