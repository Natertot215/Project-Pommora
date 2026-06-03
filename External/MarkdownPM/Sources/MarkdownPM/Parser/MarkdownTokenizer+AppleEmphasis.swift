//
//  MarkdownTokenizer+AppleEmphasis.swift
//  MarkdownPM
//
//  Derives emphasis tokens (.italic / .bold / .boldItalic) from Apple
//  swift-markdown's Document AST instead of the legacy `*`-stack parser.
//
//  Phase 4.1 — ADDITIVE + UNWIRED. This helper is called by NOTHING in the
//  live token stream yet; `MarkdownTokenizer.parseEmphasisTokens` keeps
//  running. Only `AppleEmphasisTokensTests` exercises this.
//
//  Why reconstruct by width-subtraction: Apple emits Emphasis/Strong nodes
//  whose `.range` is delimiter-INCLUSIVE (e.g. `*a*` → (0,3), `**b**` →
//  (0,5)). The downstream consumer `styleEmphasis` reads ONLY `token.kind`
//  and `token.contentRange`, OR-merging a per-char trait map. So we derive
//  contentRange = full-span minus the known delimiter widths (1 for
//  Emphasis, 2 for Strong, 3 for the boldItalic collapse) and let the
//  consumer compose nested spans for free.
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
               sameRange(emphasis, strong) {
                appendToken(.boldItalic, node: emphasis, width: 3)
                return  // do NOT descend — the inner Strong is collapsed.
            }
            appendToken(.italic, node: emphasis, width: 1)
            descendInto(emphasis)
        }

        mutating func visitStrong(_ strong: Strong) {
            // Symmetric collapse: Strong whose sole child is an identical-range
            // Emphasis → one `.boldItalic`.
            if let emphasis = soleNestedEmphasis(strong, as: Emphasis.self),
               sameRange(strong, emphasis) {
                appendToken(.boldItalic, node: strong, width: 3)
                return
            }
            appendToken(.bold, node: strong, width: 2)
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

        private mutating func appendToken(_ kind: MarkdownTokenKind, node: any Markup, width: Int) {
            guard let full = SourceRangeConverter.nsRange(from: node.range, in: nsText, lineIndex: lineIndex),
                  full.length >= width * 2
            else { return }
            let open = NSRange(location: full.location, length: width)
            let close = NSRange(location: NSMaxRange(full) - width, length: width)
            let content = NSRange(location: full.location + width, length: full.length - width * 2)
            tokens.append(MarkdownToken(
                kind: kind,
                range: full,
                contentRange: content,
                markerRanges: [open, close]
            ))
        }
    }
}
