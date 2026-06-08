import Testing

@testable import Pommora

/// T5.2 — the archetype picker's mute decision (single-sourced from
/// `ItemWindowLayouts.hasRecipe`). The SwiftUI wiring (selection + persist) is
/// build-verified, not unit-tested.
@Suite("Archetype picker")
struct ArchetypePickerTests {

    @Test("only .standard is enabled — mute decision tracks hasRecipe single source")
    func muteDecisionTracksHasRecipe() {
        for archetype in LayoutArchetype.selectable {
            let enabled = ItemWindowLayouts.hasRecipe(for: archetype)
            #expect(enabled == (archetype == .standard))
        }
    }
}
