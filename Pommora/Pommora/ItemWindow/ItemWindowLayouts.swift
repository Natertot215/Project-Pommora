import SwiftUI

/// T3.1 — archetype → layout recipe for the Item Window main region. The single
/// place that maps a `LayoutArchetype` to the `AnyLayout` the renderer wraps its
/// (constant) child set in. Every selectable case returns a valid, non-nil layout;
/// `.unknown` and the not-yet-bespoke archetypes fall back to the standard VStack.
///
/// The bespoke region recipes (banner/two-column geometry, gallery grid) are
/// deferred to their own Figma sessions (T3.6+); for now they reuse stock stacks
/// so the renderer composes correctly without a real design behind them.
enum ItemWindowLayouts {
    /// Archetype → layout recipe. Each archetype gets a DISTINCT but stock recipe
    /// (no custom `Layout`): the bespoke region recipe for banner/two-column (and a
    /// real gallery grid) is deferred to its own Figma session. `.standard` is the
    /// v1 baseline; `.reserved`/`.unknown` fall back to it.
    static func layout(for archetype: LayoutArchetype) -> AnyLayout {
        switch archetype {
        case .standard, .reserved, .unknown:
            // v1 baseline — comfortable leading VStack.
            return AnyLayout(VStackLayout(alignment: .leading, spacing: PUI.Spacing.xl))
        case .compact:
            // Tight vertical rhythm.
            return AnyLayout(VStackLayout(alignment: .leading, spacing: PUI.Spacing.sm))
        case .wide:
            // Full-width intent — stretch children edge-to-edge, generous gaps.
            return AnyLayout(VStackLayout(alignment: .leading, spacing: PUI.Spacing.xxl))
        case .gallery:
            // Stock grid (SwiftUI `GridLayout`, not a custom Layout) — generous gaps.
            return AnyLayout(GridLayout(alignment: .topLeading, horizontalSpacing: PUI.Spacing.xl, verticalSpacing: PUI.Spacing.xl))
        case .bannerTwoColumn:
            // Top-aligned two-column — bespoke region geometry deferred to Figma.
            return AnyLayout(HStackLayout(alignment: .top, spacing: PUI.Spacing.xl + PUI.Spacing.xs))
        }
    }

    /// True once an archetype has a real, non-fallback recipe (single source the
    /// settings pane mutes from). Only `standard` is "real" initially; the rest
    /// reuse the fallback stack until their bespoke recipe ships (T3.6+).
    static func hasRecipe(for archetype: LayoutArchetype) -> Bool {
        switch archetype {
        case .standard: return true
        default: return false
        }
    }
}
