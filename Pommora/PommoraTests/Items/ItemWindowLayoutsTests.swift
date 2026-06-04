import SwiftUI
import Testing

@testable import Pommora

/// T3.1 — the testable core of the renderer: the archetype → layout recipe map.
/// `AnyLayout` isn't `Equatable`, so we can only assert each call SUCCEEDS
/// (returns a value, no crash) for every selectable archetype plus `.unknown`,
/// and assert the `hasRecipe` booleans that the settings pane mutes from.
@MainActor
struct ItemWindowLayoutsTests {
    @Test("layout(for:) returns a value for every selectable archetype")
    func layoutCallableForEverySelectableCase() {
        for archetype in LayoutArchetype.selectable {
            // Assigning the result proves the call returned a valid AnyLayout;
            // AnyLayout has no Equatable conformance to assert against.
            let layout = ItemWindowLayouts.layout(for: archetype)
            _ = layout
        }
    }

    @Test("layout(for:) tolerates an unknown archetype (falls back, no crash)")
    func layoutFallsBackForUnknown() {
        let layout = ItemWindowLayouts.layout(for: .unknown("x"))
        _ = layout
    }

    @Test("hasRecipe is true only for the standard archetype")
    func hasRecipeOnlyStandard() {
        #expect(ItemWindowLayouts.hasRecipe(for: .standard) == true)
        #expect(ItemWindowLayouts.hasRecipe(for: .reserved) == false)
        #expect(ItemWindowLayouts.hasRecipe(for: .compact) == false)
        #expect(ItemWindowLayouts.hasRecipe(for: .bannerTwoColumn) == false)
        #expect(ItemWindowLayouts.hasRecipe(for: .gallery) == false)
        #expect(ItemWindowLayouts.hasRecipe(for: .wide) == false)
        #expect(ItemWindowLayouts.hasRecipe(for: .unknown("x")) == false)
    }
}
