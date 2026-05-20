// NavDropdownButton.swift
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case favorites, recents
    var id: String { rawValue }
    var label: String { self == .favorites ? "Favorites" : "Recents" }
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

    @Environment(\.openWindow) private var openWindow

    @State private var isPresented = false
    @State private var mode: PanelMode = .favorites
    @State private var selection: EntityStateRef?

    // Snapshots refreshed on popover open. Bypasses an @Observable-
    // through-popover-host edge case where mutations on the source
    // manager don't reliably propagate into the popover's view tree.
    @State private var recentsSnapshot: [EntityStateRef] = []
    @State private var favoritesSnapshot: [EntityStateRef] = []

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
        favoritesSnapshot = AppGlobals.favoritesManager?.entries ?? []
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
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Inset list trough — visually recessed inside the glass card
            listContainer
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .frame(maxHeight: 420)
        .clipShape(.rect(cornerRadius: 24))
    }

    /// Custom Liquid Glass segmented pill — hand-rolled HStack of glass
    /// buttons with a selection capsule overlay because the default
    /// `.segmented` chrome doesn't read as glass.
    @ViewBuilder
    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.favorites)
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
        .buttonStyle(.plain)
        .contentShape(.capsule)
    }

    @ViewBuilder
    private var listContainer: some View {
        Group {
            switch mode {
            case .favorites: favoritesList
            case .recents: recentsList
            }
        }
        .background(Color.black.opacity(0.18))  // recessed-trough tint
        .clipShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var favoritesList: some View {
        if favoritesSnapshot.isEmpty {
            Text("No favorites yet. Hover a Recents row and click the heart to favorite.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        } else {
            List(selection: $selection) {
                ForEach(favoritesSnapshot, id: \.self) { ref in
                    EntityRow(
                        ref: ref,
                        isFavorite: true,
                        favoriteAction: {
                            AppGlobals.favoritesManager?.toggle(ref)
                            refreshSnapshots()
                        }
                    )
                    .tag(Optional(ref))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
                .onMove { src, dst in
                    AppGlobals.favoritesManager?.move(fromOffsets: src, toOffset: dst)
                    refreshSnapshots()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selection) { _, new in
                guard let ref = new else { return }
                handleOpen(ref)
            }
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
        } else {
            List(selection: $selection) {
                ForEach(recentsSnapshot, id: \.self) { ref in
                    EntityRow(
                        ref: ref,
                        isFavorite: favoritesSnapshot.contains(ref),
                        favoriteAction: {
                            AppGlobals.favoritesManager?.toggle(ref)
                            refreshSnapshots()
                        }
                    )
                    .tag(Optional(ref))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selection) { _, new in
                guard let ref = new else { return }
                handleOpen(ref)
            }
        }
    }

    private func handleOpen(_ ref: EntityStateRef) {
        isPresented = false
        selection = nil  // reset so the same row can be clicked again

        switch ref.typedKind {
        case .item:
            openItemWindow(ref)
        case .agenda:
            return  // v0.6.0+
        case .none:
            return  // unknown kind — skip
        case .page, .vault, .space, .topic, .subtopic, .collection:
            openStandaloneWindow(for: ref)
        }
    }

    private func openStandaloneWindow(for stateRef: EntityStateRef) {
        guard let entityRef = EntityRef(stateRef: stateRef) else { return }
        openWindow(id: "entity", value: entityRef)
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
