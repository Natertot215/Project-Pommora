// NavDropdownButton.swift
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case pinned, recents
    var id: String { rawValue }
    var label: String { self == .pinned ? "Pinned" : "Recents" }
}

@MainActor
struct NavDropdownButton: View {
    /// When `true`, the trigger button renders as a plain segment (no outer
    /// glass chrome) for embedding inside a shared Liquid Glass pill.
    /// When `false` (default), renders as a standalone Liquid Glass capsule.
    let asSegment: Bool

    init(asSegment: Bool = false) {
        self.asSegment = asSegment
    }

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

    @ViewBuilder
    private var triggerButton: some View {
        if asSegment {
            // Segment style — no .buttonStyle here; the parent pill's
            // .glassEffect carries the background. Avoids doubling.
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "square.on.square")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 16)
                    .contentShape(Rectangle())
            }
        } else {
            // Standalone style — Liquid Glass capsule.
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "square.on.square")
            }

        }
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 3) {
            modePicker
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Inset list trough — visually recessed inside the glass card
            listContainer
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: 300, maxHeight: 400)

        .clipShape(.rect(cornerRadius: 24))
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
                .padding(.vertical, 6)
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
        .clipShape(.rect(cornerRadius: 18))
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
            Text("Click pages, vaults, or other entities in the sidebar to populate Recents.")
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
        case .item:
            openItemWindow(ref)
        case .agenda, .none:
            return
        case .page, .vault, .space, .topic, .subtopic, .collection:
            if let sel = SidebarSelection(stateRef: ref) {
                AppGlobals.mainWindowRouter?.requestOpen(to: sel)
                return
            }
            // Lazy-load fallback: pages in collections the user hasn't visited
            // this session aren't in ContentManager's dicts yet. Walk every
            // vault + collection until the lookup succeeds. (SQLite in v0.4.0
            // makes this O(1) and removes the need for the walk entirely.)
            Task { @MainActor in
                guard let cm = AppGlobals.contentManager,
                    let vm = AppGlobals.vaultManager
                else { return }
                for vault in vm.vaults {
                    await cm.loadAll(for: vault)
                    if let sel = SidebarSelection(stateRef: ref) {
                        AppGlobals.mainWindowRouter?.requestOpen(to: sel)
                        return
                    }
                    for col in vm.collections(in: vault) {
                        await cm.loadAll(for: col)
                        if let sel = SidebarSelection(stateRef: ref) {
                            AppGlobals.mainWindowRouter?.requestOpen(to: sel)
                            return
                        }
                    }
                }
            }
        }
    }

    private func openItemWindow(_ ref: EntityStateRef) {
        guard let cm = AppGlobals.contentManager,
            let vm = AppGlobals.vaultManager
        else { return }
        // Brute-force O(N) search across all vaults + collections (SQLite in v0.4.0).
        for vault in vm.vaults {
            if let item = cm.items(in: vault).first(where: { $0.id == ref.id }) {
                AppGlobals.presentItemAction?(item)
                return
            }
            for collection in vm.collections(in: vault) {
                if let item = cm.items(in: collection).first(where: { $0.id == ref.id }) {
                    AppGlobals.presentItemAction?(item)
                    return
                }
            }
        }
    }
}
