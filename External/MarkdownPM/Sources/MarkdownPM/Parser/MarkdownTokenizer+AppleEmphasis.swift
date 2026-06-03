//
//  MarkdownTokenizer+AppleEmphasis.swift
//  MarkdownPM
//
//  Derives emphasis tokens (.italic / .bold / .boldItalic) from Apple
//  swift-markdown's Document AST instead of the legacy `*`-stack parser.
//
//  Phase 4.2 — WIRED. `MarkdownTokenizer.parseTokens` emits emphasis through
//  this helper as the first appended token group; the legacy asterisk-only
//  `parseEmphasisTokens` is retired. `AppleEmphasisTokensTests` +
//  `TokenizerCorpusTests` pin the output.
//
//  Why reconstruct from CONTENT, not node boundaries: Apple emits
//  Emphasis/Strong nodes whose `.range` is delimiter-INCLUSIVE (e.g. `*a*`
//  → (0,3), `**b**` → (0,5)). The downstream consumer `styleEmphasis` reads
//  ONLY `token.kind` and `token.contentRange`, OR-merging a per-char trait
//  map; `shrinkInactiveMarkers` hides chars covered by `markerRanges`.
//
//  Reconstructing markers by subtracting `width` from each END of the node's
//  absolute range is WRONG when an inner Strong/Emphasis ABUTS the outer
//  emphasis's delimiter run: Apple reports the inner node's `.range` STARTING
//  ON a delimiter char that belongs to the OUTER node. E.g.
//  `***bold** then italic*` → inner Strong range is (0,9) — it begins at index
//  0, the OUTER italic's `*`. Width-2 subtraction would put a literal `*` in
//  the bold contentRange and mislocate the marker, leaving a stray styled `*`
//  visible mid-text.
//
//  Robust approach: derive CONTENT boundaries from the node's child spans
//  (the union of its children's ranges, descending through identical-range
//  collapse chains), then place exactly `width` delimiter chars IMMEDIATELY
//  ADJACENT to that content — open = [content.start - width, content.start),
//  close = [content.end, content.end + width). The delimiters thus anchor on
//  the real `*`/`_` chars wherever the run actually sits, not on the node's
//  absolute edges. Matches the retired stack parser byte-for-byte on asterisk
//  input.
//

import Foundation
import Markdown

extension MarkdownTokenizer {

    /// Walk Apple's AST and emit emphasis tokens in document order.
    ///
    /// - Emphasis  → `.italic`     (delimiter width 1)
    /// - Strong    → `.bold`       (delimiter width 2)
    /// - `***x***` → `.boldItalic` (delimiter width 3) when an Emphasis's
    ///   SOLE child is a Strong (or symmetric) sharing an IDENTICAL range —
    ///   the collapse. Genuine sub-span nesting (`**a *b* c**`) is NOT
    ///   collapsed: both a `.bold` and a `.italic` are emitted.
    ///
    /// Emphasis inside inline code / code blocks never appears here because
    /// Apple doesn't emit Emphasis/Strong nodes there — code-suppression is
    /// free.
    static func appleEmphasisTokens(
        in document: Markdown.Document,
        nsText: NSString,
        lineIndex: LineOffsetIndex
    ) -> [MarkdownToken] {
        var walker = EmphasisWalker(nsText: nsText, lineIndex: lineIndex)
        walker.visit(document)
        return walker.tokens
    }

    private struct EmphasisWalker: MarkupWalker {
        let nsText: NSString
        let lineIndex: LineOffsetIndex
        var tokens: [MarkdownToken] = []

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            // Identical-range collapse: Emphasis whose sole child is a Strong
            // spanning the exact same range → one `.boldItalic` (width 3).
            if let strong = soleNestedEmphasis(emphasis, as: Strong.self),
                sameRange(emphasis, strong)
            {
                appendToken(.boldItalic, node: emphasis, width: 3, contentSource: strong)
                return  // do NOT descend — the inner Strong is collapsed.
            }
            appendToken(.italic, node: emphasis, width: 1, contentSource: emphasis)
            descendInto(emphasis)
        }

        mutating func visitStrong(_ strong: Strong) {
            // Symmetric collapse: Strong whose sole child is an identical-range
            // Emphasis → one `.boldItalic`.
            if let emphasis = soleNestedEmphasis(strong, as: Emphasis.self),
                sameRange(strong, emphasis)
            {
                appendToken(.boldItalic, node: strong, width: 3, contentSource: emphasis)
                return
            }
            // Same-type identical-range nesting (`****d****` → Strong(Strong)).
            // Descend without emitting; the inner Strong emits the single
            // `.bold`. Emitting here too would double-count (idempotent under
            // the OR-merge, but sloppy) — one bold token is the clean result.
            if let inner = soleNestedEmphasis(strong, as: Strong.self),
                sameRange(strong, inner)
            {
                descendInto(strong)
                return
            }
            appendToken(.bold, node: strong, width: 2, contentSource: strong)
            descendInto(strong)
        }

        // MARK: Helpers

        private func soleNestedEmphasis<T: Markup>(_ node: any Markup, as type: T.Type) -> T? {
            let children = Array(node.children)
            guard children.count == 1, let only = children.first as? T else { return nil }
            return only
        }

        private func sameRange(_ a: any Markup, _ b: any Markup) -> Bool {
            guard
                let ra = SourceRangeConverter.nsRange(from: a.range, in: nsText, lineIndex: lineIndex),
                let rb = SourceRangeConverter.nsRange(from: b.range, in: nsText, lineIndex: lineIndex)
            else { return false }
            return NSEqualRanges(ra, rb)
        }

        /// Union of `node`'s direct child ranges. Returns nil if there are no
        /// convertible children.
        private func childSpan(of node: any Markup) -> NSRange? {
            var lower = Int.max
            var upper = Int.min
            for child in node.children {
                guard let r = SourceRangeConverter.nsRange(from: child.range, in: nsText, lineIndex: lineIndex)
                else { continue }
                lower = min(lower, r.location)
                upper = max(upper, NSMaxRange(r))
            }
            guard lower != Int.max, upper > lower else { return nil }
            return NSRange(location: lower, length: upper - lower)
        }

        /// Emit an emphasis token. The delimiter geometry is reconstructed from
        /// TWO clamped signals so each side anchors on a real `*`/`_` char:
        ///
        /// - The node's OWN `.range` (`delimNode`) reliably marks ITS delimiters
        ///   when nothing absorbed them — content sits `width` chars inside each
        ///   end (`full.start + width` … `full.end - width`).
        /// - The CHILD span (`contentSource`'s children) reliably marks content
        ///   when an inner abutting node absorbed a delimiter — Apple's child
        ///   Text/Emphasis spans start AFTER this node's open delimiter and end
        ///   BEFORE its close delimiter.
        ///
        /// Taking the TIGHTER bound on each side — `max(childLower, full.start +
        /// width)` for the open, `min(childUpper, full.end - width)` for the
        /// close — yields the true content for both the outer node (whose child
        /// absorbed ITS open `*`, pushing childLower too low) and the inner node
        /// (whose own `.range` bled onto the parent's `*`, pushing full.start too
        /// low). Markers are then exactly `width` chars adjacent to that content.
        ///
        /// `contentSource` differs from `delimNode` only for the collapse, where
        /// the INNER identical-range node carries the child text.
        private mutating func appendToken(
            _ kind: MarkdownTokenKind,
            node delimNode: any Markup,
            width: Int,
            contentSource: any Markup
        ) {
            guard
                let full = SourceRangeConverter.nsRange(from: delimNode.range, in: nsText, lineIndex: lineIndex),
                let children = childSpan(of: contentSource),
                full.length >= width * 2
            else { return }
            let contentStart = max(children.location, full.location + width)
            let contentEnd = min(NSMaxRange(children), NSMaxRange(full) - width)
            guard contentEnd > contentStart else { return }
            let openStart = contentStart - width
            let closeStart = contentEnd
            guard openStart >= 0, closeStart + width <= nsText.length else { return }
            let open = NSRange(location: openStart, length: width)
            let close = NSRange(location: closeStart, length: width)
            let content = NSRange(location: contentStart, length: contentEnd - contentStart)
            let fullToken = NSRange(location: openStart, length: (closeStart + width) - openStart)
            tokens.append(
                MarkdownToken(
                    kind: kind,
                    range: fullToken,
                    contentRange: content,
                    markerRanges: [open, close]
                ))
        }
    }
}
