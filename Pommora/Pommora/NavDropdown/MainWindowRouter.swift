import Foundation
import Observation

/// Bridge between standalone EntityRef windows and the main Pommora
/// window. Standalone windows can't directly bind the main window's
/// SidebarSelection @State, so they push a pending selection here
/// and tick `bringToFrontTick`. ContentView observes the tick, applies
/// `pendingSelection` to its selection state, raises the main NSWindow,
/// and clears `pendingSelection`.
///
/// `pendingIntent` disambiguates two routing paths:
/// - `.expandFromWindow` — user opens an entity from a standalone window;
///   ContentView records the new selection in RecentsManager.
/// - `.stepHistory` — user pressed Back/Forward; ContentView applies the
///   selection WITHOUT recording so cursor movement doesn't reset LRU order.
@MainActor
@Observable
final class MainWindowRouter {
    enum Intent { case expandFromWindow, stepHistory }

    var pendingSelection: SidebarSelection?
    var pendingIntent: Intent = .expandFromWindow
    var bringToFrontTick: Int = 0

    /// Route from a standalone entity window into the main detail pane.
    /// Records the resulting selection in RecentsManager.
    func requestExpand(to selection: SidebarSelection) {
        self.pendingSelection = selection
        self.pendingIntent = .expandFromWindow
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
