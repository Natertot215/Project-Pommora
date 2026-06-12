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
}
