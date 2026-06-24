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
    // Managers passed in as explicit params (NOT @Environment) because the
    // toolbar where this lives is OUTSIDE ContentView's `.detail { ... }`
    // closure's `.environment(...)` chain. Same pattern as ViewSettingsButton
    // (quirk #16). The lookup bundle is constructed by ContentView and threaded
    // through so SidebarSelection(stateRef:lookup:) resolves against live
    // manager instances rather than AppGlobals.
    let lookup: SidebarLookupBundle

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
                .toolbarGlyph(width: PUI.Icon.toolbarActionFrame)
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
        // Agenda can't appear in the main detail pane. Support is not yet built.
        switch ref.typedKind {
        case .agenda, .none:
            return  // skip — nothing to route
        case .page, .collection, .area, .topic, .project, .set:
            break
        }

        guard let sel = SidebarSelection(stateRef: ref, lookup: lookup) else { return }

        // requestStep sets pendingIntent = .stepHistory so ContentView's
        // onChange handler skips the record() call.
        AppGlobals.mainWindowRouter?.requestStep(to: sel)
    }

}
