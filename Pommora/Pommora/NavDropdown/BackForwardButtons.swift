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
    // Read directly from AppGlobals so the toolbar (a separate view host in
    // macOS) always sees the live instance. @Observable tracking fires for
    // canStepBack / canStepForward because the accesses happen inside body.
    private var recents: RecentsManager? { AppGlobals.recentsManager }

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(
                systemImage: "chevron.left",
                action: stepBack,
                disabled: !(recents?.canStepBack ?? false),
                help: "Back (⌘[)"
            )
            .keyboardShortcut("[", modifiers: [.command])

            Rectangle()
                .fill(.secondary)
                .frame(width: 1, height: 14)

            segmentButton(
                systemImage: "chevron.right",
                action: stepForward,
                disabled: !(recents?.canStepForward ?? false),
                help: "Forward (⌘])"
            )
            .keyboardShortcut("]", modifiers: [.command])
        }
        .glassEffect()
    }

    @ViewBuilder
    private func segmentButton(
        systemImage: String,
        action: @escaping () -> Void,
        disabled: Bool,
        help: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .help(help)
    }

    private func stepBack() {
        applyStep(recents?.stepBack())
    }

    private func stepForward() {
        applyStep(recents?.stepForward())
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

        guard let sel = SidebarSelection(stateRef: ref) else { return }

        // requestStep sets pendingIntent = .stepHistory so ContentView's
        // onChange handler skips the record() call.
        AppGlobals.mainWindowRouter?.requestStep(to: sel)
    }

    /// O(N) Item lookup across all Vaults + Collections.
    /// Mirrors the pattern in NavDropdownButton.openItemWindow.
    /// SQLite in v0.4.0 will make this instant.
    @MainActor
    private func lookupItem(id: String, contentManager: ContentManager) -> Item? {
        guard let vm = AppGlobals.pageTypeManager else { return nil }
        for vault in vm.types {
            if let item = contentManager.items(in: vault).first(where: { $0.id == id }) {
                return item
            }
            for collection in vm.pageCollections(in: vault) {
                if let item = contentManager.items(in: collection).first(where: { $0.id == id }) {
                    return item
                }
            }
        }
        return nil
    }
}
