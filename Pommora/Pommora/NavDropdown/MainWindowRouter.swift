import Foundation
import Observation

/// Bridge between standalone EntityRef windows and the main Pommora
/// window. Standalone windows can't directly bind the main window's
/// SidebarSelection @State, so they push a pending selection here
/// and tick `bringToFrontTick`. ContentView observes the tick, applies
/// `pendingSelection` to its selection state, raises the main NSWindow,
/// and clears `pendingSelection`.
@MainActor
@Observable
final class MainWindowRouter {
    var pendingSelection: SidebarSelection?
    var bringToFrontTick: Int = 0

    func requestExpand(to selection: SidebarSelection) {
        self.pendingSelection = selection
        self.bringToFrontTick &+= 1
    }
}
