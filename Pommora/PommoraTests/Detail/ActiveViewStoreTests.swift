import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("ActiveViewStoreTests")
struct ActiveViewStoreTests {

    // (a) Full NexusState round-trip through AtomicJSON to a temp FILE — catches a
    //     missed decodeIfPresent / encode on the new active_views key.
    @Test("NexusState active_views round-trips through AtomicJSON")
    func nexusStateActiveViewsRoundTrips() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        var state = NexusState()
        state.activeViews = ["cont_1": "view_x", "cont_2": "view_y"]

        let url = NexusPaths.nexusStateURL(in: nexus)
        try AtomicJSON.write(state, to: url)
        let decoded = try AtomicJSON.decode(NexusState.self, from: url)

        #expect(decoded == state)
        #expect(decoded.activeViews["cont_1"] == "view_x")
        #expect(decoded.activeViews["cont_2"] == "view_y")
    }

    // (b) setActive persists across instances: write on one store, read on a second
    //     store built over the same nexus (reads back from disk).
    @Test("setActive persists and a fresh store reads it back from disk")
    func setActivePersistsCrossInstance() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let store = ActiveViewStore(nexus: nexus)
        store.setActive("view_x", for: "cont_1")

        let reloaded = ActiveViewStore(nexus: nexus)
        #expect(reloaded.activeViewID(for: "cont_1") == "view_x")
    }

    // (c) Unset container → nil.
    @Test("activeViewID returns nil for an unset container")
    func unsetContainerReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let store = ActiveViewStore(nexus: nexus)
        #expect(store.activeViewID(for: "nope") == nil)
    }

    // (d) NexusEnvironment construction smoke test — asserts it builds and exposes a
    //     non-nil activeViewStore. Runtime environment injection is exercised from
    //     Task 12 onward; this only verifies construction + wiring presence.
    @Test("NexusEnvironment constructs with a non-nil activeViewStore")
    func nexusEnvironmentExposesActiveViewStore() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let env = NexusEnvironment(nexus: nexus, nexusManager: NexusManager())
        _ = env.activeViewStore
    }
}
