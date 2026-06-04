import Testing

@testable import Pommora

/// T3.4 — per-property `display` resolution: a promoted property's explicit
/// `PromotedProperty.display` override wins; when it's nil, the archetype's
/// default treatment for that property's type applies (LD-4). Tests the
/// RESOLUTION (which display wins), not the pixels.
@Suite struct ItemWindowDisplayResolutionTests {
    /// Explicit per-property override always wins, regardless of type or archetype.
    @Test func explicitOverrideWins() {
        let promoted = PromotedProperty(id: "p", display: .thumbnail)
        let resolved = ItemWindowRenderer.resolvedDisplay(
            for: promoted,
            propertyType: .number,
            archetype: .standard
        )
        #expect(resolved == .thumbnail)
    }

    /// Override wins even when the archetype default would differ for the type.
    @Test func explicitOverrideWinsOverArchetypeDefault() {
        let promoted = PromotedProperty(id: "p", display: .inline)
        let resolved = ItemWindowRenderer.resolvedDisplay(
            for: promoted,
            propertyType: .file,
            archetype: .gallery
        )
        #expect(resolved == .inline)
    }

    /// Nil override falls through to the archetype default — asserted against the
    /// pure default map for the same inputs, so the test stays honest without
    /// hard-coding a pixel choice.
    @Test func nilOverrideFallsToArchetypeDefault() {
        let promoted = PromotedProperty(id: "p", display: nil)
        let resolved = ItemWindowRenderer.resolvedDisplay(
            for: promoted,
            propertyType: .number,
            archetype: .standard
        )
        #expect(resolved == ItemWindowRenderer.archetypeDefaultDisplay(for: .number, archetype: .standard))
    }

    /// A gallery archetype gives a `.file` image property a non-`.inline` default.
    @Test func galleryFileDefaultsToThumbnail() {
        let resolved = ItemWindowRenderer.archetypeDefaultDisplay(for: .file, archetype: .gallery)
        #expect(resolved == .thumbnail)
    }

    /// A banner-two-column archetype gives a `.file` image property a banner default.
    @Test func bannerFileDefaultsToBanner() {
        let resolved = ItemWindowRenderer.archetypeDefaultDisplay(for: .file, archetype: .bannerTwoColumn)
        #expect(resolved == .banner)
    }

    /// Relations default to `.chips` across archetypes (no override).
    @Test func relationDefaultsToChips() {
        let resolved = ItemWindowRenderer.archetypeDefaultDisplay(for: .relation, archetype: .standard)
        #expect(resolved == .chips)
    }

    /// Everything else defaults to `.inline`.
    @Test func plainTypeDefaultsToInline() {
        #expect(ItemWindowRenderer.archetypeDefaultDisplay(for: .number, archetype: .standard) == .inline)
        #expect(ItemWindowRenderer.archetypeDefaultDisplay(for: .date, archetype: .gallery) == .inline)
        #expect(ItemWindowRenderer.archetypeDefaultDisplay(for: .file, archetype: .standard) == .inline)
    }
}
