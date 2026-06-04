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
    static func pommora(verticalInset: CGFloat) -> MarkdownPMConfiguration {
        var config = MarkdownPMConfiguration.default
        config.textInsets = TextInsets(horizontal: horizontalInset, vertical: verticalInset)
        return config
    }
}
