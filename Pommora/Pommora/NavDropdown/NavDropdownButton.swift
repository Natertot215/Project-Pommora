// NavDropdownButton.swift
import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case favorites, recents
    var id: String { rawValue }
    var label: String { self == .favorites ? "Favorites" : "Recents" }
}

@MainActor
struct NavDropdownButton: View {
    @Environment(RecentsManager.self) private var recents
    @Environment(FavoritesManager.self) private var favorites
    @Environment(\.openWindow) private var openWindow

    @State private var isPresented = false
    @State private var mode: PanelMode = .favorites
    @State private var selection: EntityStateRef?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "square.on.square")
        }
        .buttonStyle(.glass)
        .keyboardShortcut("t", modifiers: [.command])
        .help("Navigation (⌘T)")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            panel
                .frame(width: 320)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
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
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)
            modeButton(.recents)
        }
        .background(.thinMaterial, in: .capsule)
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
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
        List(selection: $selection) {
            ForEach(favorites.entries, id: \.self) { ref in
                EntityRow(ref: ref, isFavorite: true, favoriteAction: { favorites.toggle(ref) })
                    .tag(Optional(ref))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
            }
            .onMove { src, dst in favorites.move(fromOffsets: src, toOffset: dst) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: selection) { _, new in
            guard let ref = new else { return }
            handleOpen(ref)
        }
    }

    @ViewBuilder
    private var recentsList: some View {
        List(selection: $selection) {
            ForEach(recents.dropdownTop, id: \.self) { ref in
                EntityRow(
                    ref: ref,
                    isFavorite: favorites.contains(ref),
                    favoriteAction: { favorites.toggle(ref) }
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
        // TODO: Task 4.2 — wire via AppGlobals.presentItemAction bridge.
        // Items in the dropdown silently no-op until then.
        _ = ref
    }
}
