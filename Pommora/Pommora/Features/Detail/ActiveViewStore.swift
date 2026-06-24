import Foundation
import Observation

/// Tracks the last-active SavedView per container as session state. Reads the
/// `active_views` map from `.nexus/state.json` synchronously at init (the
/// SavedConfigManager-style synchronous JSON read) and writes back through
/// `OrderPersister` on every `setActive` so a tab-click never churns a sidecar.
@MainActor
@Observable
final class ActiveViewStore {
    private let nexus: Nexus
    private(set) var activeViews: [String: String] = [:]  // containerID → viewID

    init(nexus: Nexus) {
        self.nexus = nexus
        let url = NexusPaths.nexusStateURL(in: nexus)
        activeViews = ((try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()).activeViews
    }

    func activeViewID(for containerID: String) -> String? { activeViews[containerID] }

    func setActive(_ viewID: String, for containerID: String) {
        activeViews[containerID] = viewID
        try? OrderPersister.setActiveView(viewID, forContainer: containerID, in: nexus)
    }

    /// The container's active `SavedView`: the stored active id matched against
    /// the container's live views (via `manager.views(in:)`), falling back to the
    /// first view when the store has no record yet. The single source for the
    /// `activeViewID → first(where:) ?? first` resolution the panes + Views
    /// dropdown all repeat.
    func resolvedActiveView(in containerID: String, manager: PageCollectionManager) -> SavedView? {
        let views = manager.views(in: containerID)
        let activeID = activeViewID(for: containerID)
        return views.first(where: { $0.id == activeID }) ?? views.first
    }

    /// The active `SavedView` for a View Settings scope — resolves the scope's
    /// `containerID`, then defers to `resolvedActiveView(in:manager:)`. `nil` for
    /// non-container scopes. Single source for the panes' `currentView()`.
    func resolvedActiveView(for scope: ViewSettingsScope, manager: PageCollectionManager) -> SavedView? {
        guard let containerID = scope.containerID else { return nil }
        return resolvedActiveView(in: containerID, manager: manager)
    }
}
