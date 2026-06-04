import Testing

@testable import Pommora

/// T5.2 — the archetype picker's pure parts: human labels (a view concern, kept
/// out of the schema enum) and the mute decision (single-sourced from
/// `ItemWindowLayouts.hasRecipe`). The SwiftUI wiring (selection + persist) is
/// build-verified, not unit-tested.
@Suite("Archetype picker")
struct ArchetypePickerTests {

    @Test("label(for:) is non-empty for every selectable archetype")
    func labelsAreNonEmpty() {
        for archetype in LayoutArchetype.selectable {
            #expect(!ItemTemplatePane.label(for: archetype).isEmpty)
        }
    }

    @Test("label(for:) gives the expected human names")
    func labelsMatchRoster() {
        #expect(ItemTemplatePane.label(for: .compact) == "Compact Stack")
        #expect(ItemTemplatePane.label(for: .standard) == "Standard Panel")
        #expect(ItemTemplatePane.label(for: .bannerTwoColumn) == "Banner / Two-Column")
        #expect(ItemTemplatePane.label(for: .gallery) == "Gallery")
        #expect(ItemTemplatePane.label(for: .wide) == "Wide")
        #expect(ItemTemplatePane.label(for: .reserved) == "Reserved")
    }

    @Test("only .standard is enabled — mute decision tracks hasRecipe single source")
    func muteDecisionTracksHasRecipe() {
        for archetype in LayoutArchetype.selectable {
            let enabled = ItemWindowLayouts.hasRecipe(for: archetype)
            #expect(enabled == (archetype == .standard))
        }
    }
}
