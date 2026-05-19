// BackForwardButtons.swift
import SwiftUI

/// Toolbar Back (‹) and Forward (›) buttons wired to RecentsManager cursor
/// stepping. ⌘[ / ⌘] keyboard shortcuts.
///
/// The critical gotcha: stepping must NOT re-record the resulting selection
/// in RecentsManager or it would reset cursor to 0 and break LRU order.
/// Protection is layered:
/// 1. `MainWindowRouter.requestStep(to:)` sets `pendingIntent = .stepHistory`.
/// 2. ContentView's `onChange(of: bringToFrontTick)` skips `record()` when
///    intent is `.stepHistory`.
/// 3. `RecentsManager.isNavigatingHistory = true` suppresses the sidebar-
///    selection observer in ContentView while the mutation propagates.
@MainActor
struct BackForwardButtons: View {
    @Environment(RecentsManager.self) private var recents

    var body: some View {
        HStack(spacing: 4) {
            Button {
                stepBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(!recents.canStepBack)
            .help("Back (⌘[)")

            Button {
                stepForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(!recents.canStepForward)
            .help("Forward (⌘])")
        }
    }

    private func stepBack() {
        applyStep(recents.stepBack())
    }

    private func stepForward() {
        applyStep(recents.stepForward())
    }

    private func applyStep(_ ref: EntityStateRef?) {
        guard let ref else { return }
        // Items + Agenda can't appear in the main detail pane — open via
        // ItemWindow instead. Agenda support arrives at v0.6.0+.
        switch ref.typedKind {
        case .item:
            guard let cm = AppGlobals.contentManager,
                let item = lookupItem(id: ref.id, contentManager: cm)
            else { return }
            AppGlobals.presentItemAction?(item)
            return
        case .agenda, .none:
            return  // skip — nothing to route
        case .page, .vault, .space, .topic, .subtopic, .collection:
            break
        }

        guard let entityRef = EntityRef(stateRef: ref),
            let sel = SidebarSelection(entityRef: entityRef)
        else { return }

        // requestStep sets pendingIntent = .stepHistory so ContentView's
        // onChange handler skips the record() call.
        AppGlobals.mainWindowRouter?.requestStep(to: sel)
    }

    /// O(N) Item lookup across all Vaults + Collections.
    /// Mirrors the pattern in NavDropdownButton.openItemWindow.
    /// SQLite in v0.4.0 will make this instant.
    @MainActor
    private func lookupItem(id: String, contentManager: ContentManager) -> Item? {
        guard let vm = AppGlobals.vaultManager else { return nil }
        for vault in vm.vaults {
            if let item = contentManager.items(in: vault).first(where: { $0.id == id }) {
                return item
            }
            for collection in vm.collections(in: vault) {
                if let item = contentManager.items(in: collection).first(where: { $0.id == id }) {
                    return item
                }
            }
        }
        return nil
    }
}
