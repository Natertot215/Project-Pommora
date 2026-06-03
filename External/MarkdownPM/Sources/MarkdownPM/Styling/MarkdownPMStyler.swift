//
//  MarkdownPMStyler.swift
//  MarkdownPM
//
//  The owned compose-seam for styled ranges. Both styler-composition
//  sites (per-edit `TextStylingService.restyle` and full-rebuild
//  `rebuildTextStorageAndStyle`) route their styling COMPOSE step through
//  this single entry point so the primary-then-supplemental ordering and
//  the concatenation live in exactly one place.
//
//  Phase 5 Stage A — verbatim delegation. This type does NOT own or move
//  any styling logic: it calls `MarkdownStyler.styleAttributes` (the caret-
//  aware primary pass) and `AppleASTSupplementalStyler.styleAttributes`
//  (the caret-unaware AST pass for BlockQuote / Strikethrough / Table /
//  ThematicBreak) exactly as the two sites did inline, then concatenates
//  primary-then-supplemental. Supplemental runs LAST so its attributes win
//  per key (last-writer-wins). The apply loops stay at each call site.
//
//  `scopedRanges` is threaded straight to the primary call: nil drives the
//  whole-document full-rebuild path; a paragraph array drives the per-edit
//  scoped path. The supplemental pass is whole-document on both sites and
//  takes no scope.
//

import AppKit
import Markdown

@MainActor
enum MarkdownPMStyler {

    /// Compose the primary + supplemental styled ranges for one styling
    /// pass. Pure delegation — primary first, supplemental last; the caller
    /// owns applying the returned `[StyledRange]` to its text storage.
    static func styledRanges(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        baseFont: NSFont,
        layoutBridge: LayoutBridge?,
        caretLocation: Int,
        activeTokenIndices: Set<Int>,
        wikiLinkIDProvider: (NSRange) -> String? = { _ in nil },
        precomputedTokens: [MarkdownToken]?,
        scopedRanges: [NSRange]?,
        document: Document,
        lineIndex: LineOffsetIndex,
        configuration: MarkdownPMConfiguration
    ) -> [StyledRange] {
        let primary = MarkdownStyler.styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            layoutBridge: layoutBridge,
            caretLocation: caretLocation,
            activeTokenIndices: activeTokenIndices,
            wikiLinkIDProvider: wikiLinkIDProvider,
            precomputedTokens: precomputedTokens,
            scopedRanges: scopedRanges,
            configuration: configuration
        )

        // Supplemental pass: walk Apple swift-markdown's AST for GFM-and-
        // extended block types the regex tokenizer doesn't cover (BlockQuote,
        // Strikethrough, Table, ThematicBreak). Composes additively on top
        // of the primary styler — primary handles emphasis/links/code/lists/
        // headings; this fills the gaps. Runs LAST so it wins per attribute
        // key (last-writer-wins).
        let supplemental = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: document,
            lineIndex: lineIndex,
            baseFont: baseFont,
            theme: configuration.theme
        )

        return primary + supplemental
    }
}
