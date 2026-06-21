import Foundation
import Observation

/// Bridge between Navigation's popover and the main detail pane.
/// The popover lives in the toolbar's view host (separate from ContentView's
/// SidebarSelection @State), so opens push a pending selection here and tick
/// `bringToFrontTick`. ContentView observes the tick, applies `pendingSelection`,
/// and clears it.
///
/// `pendingIntent` disambiguates two routing paths:
/// - `.directNavigation` — user double-clicked a dropdown row; ContentView
///   records the new selection in RecentsManager.
/// - `.stepHistory` — user pressed Back/Forward; ContentView applies the
///   selection WITHOUT recording so cursor movement doesn't reset LRU order.
@MainActor
@Observable
final class MainWindowRouter {
    enum Intent { case directNavigation, stepHistory }

    var pendingSelection: SidebarSelection?
    var pendingIntent: Intent = .directNavigation
    var bringToFrontTick: Int = 0

    /// Route a direct user navigation (e.g., dropdown double-click) into the
    /// main detail pane. Records the resulting selection in RecentsManager.
    func requestOpen(to selection: SidebarSelection) {
        self.pendingSelection = selection
        self.pendingIntent = .directNavigation
        self.bringToFrontTick &+= 1
    }

    /// Route from a Back/Forward cursor step into the main detail pane.
    /// Does NOT record the resulting selection so LRU order is preserved.
    func requestStep(to selection: SidebarSelection) {
        self.pendingSelection = selection
        self.pendingIntent = .stepHistory
        self.bringToFrontTick &+= 1
    }
}
