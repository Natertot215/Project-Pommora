import Foundation
import MarkdownPM

/// Single source of truth for Pommora's `MarkdownPMEditor` configuration.
///
/// Both long-form surfaces — the Page editor body and the Item Window
/// description — share the same themed base (`MarkdownPMConfiguration.default`
/// theme + services + style toggles). The ONLY per-surface divergence is the
/// vertical text inset:
///   • Page editor reserves `titleAreaHeight` (90pt) so the scrolling title
///     overlay can sit atop the body's reserved zone.
///   • Item Window has no in-editor title overlay, so it uses `0`.
///
/// Hoisted here (DRY) so neither call site duplicates the config body; each
/// passes only its vertical inset.
enum MarkdownEditorConfig {
    /// Horizontal text inset shared by every Pommora editor surface — matches
    /// the 24pt horizontal content padding so body text aligns under the title.
    static let horizontalInset: CGFloat = 24

    /// Build the Pommora editor configuration with a surface-specific vertical
    /// text inset. `verticalInset` reserves the top (and symmetrically the
    /// bottom) of the text container; pass `0` for surfaces without a scrolling
    /// title overlay.
    ///
    /// `pageResolver` / `itemResolver` drive live `[[ ]]` / `{{ }}` connection
    /// styling. They default to NoOp so display-only surfaces (the Item Window)
    /// compile unchanged and stay inert; the Page editor passes the stable
    /// title-keyed resolvers injected by `NexusEnvironment`.
    static func pommora(
        verticalInset: CGFloat,
        pageResolver: any WikiLinkResolver = NoOpWikiLinkResolver(),
        itemResolver: any WikiLinkResolver = NoOpWikiLinkResolver(),
        renderChipLinksAsChips: Bool = false
    ) -> MarkdownPMConfiguration {
        var config = MarkdownPMConfiguration.default
        config.textInsets = TextInsets(horizontal: horizontalInset, vertical: verticalInset)
        config.services.wikiLinks = pageResolver
        config.services.chipLinks = itemResolver
        config.renderChipLinksAsChips = renderChipLinksAsChips
        // Live cross-surface refresh: when an entity is created / renamed / deleted
        // in another window, the CRUD managers post `ConnectionsBus.changed`; the
        // editor coordinator observes this bus slot and restyles, so a phantom
        // `[[ ]]`/`{{ }}` lights up without the user editing this document.
        config.services.bus.connectionsChanged = ConnectionsBus.changed
        return config
    }
}
