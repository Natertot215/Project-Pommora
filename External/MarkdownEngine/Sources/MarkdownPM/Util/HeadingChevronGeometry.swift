//
//  HeadingChevronGeometry.swift
//  MarkdownEngine
//
//  Shared rect computation for the foldable-headings chevron. Renderer
//  (`MarkdownTextLayoutFragment.drawHeadingChevron`) and hover handler
//  (`NativeTextView+HeadingFoldHover`) consume the SAME math so the visible
//  glyph and the click hit-test agree by construction (Markdown.md L2).
//

import AppKit

enum HeadingChevronGeometry {
    /// Visual constants. Must match the prior local implementations exactly
    /// so hover/click hit-tests continue landing on the drawn glyph.
    static let glyphSize: CGFloat = 12
    static let textGap: CGFloat = 6

    /// Chevron rect for a fragment whose origin is `fragmentOrigin` and whose
    /// first line fragment has typographic bounds `firstLineBounds`.
    /// `fragmentOrigin` is in the coordinate space the caller wants the rect
    /// expressed in: view coords for hover; fragment-local coords for the
    /// renderer's `draw(at:in:)` call. `containerLeading` is the text
    /// container's leading edge in the SAME coordinate space.
    static func rect(
        fragmentOrigin: CGPoint,
        containerLeading: CGFloat,
        firstLineBounds: CGRect
    ) -> CGRect {
        let gutterX = containerLeading - glyphSize - textGap
        let midY = fragmentOrigin.y + firstLineBounds.midY
        return CGRect(
            x: gutterX,
            y: midY - glyphSize / 2,
            width: glyphSize,
            height: glyphSize
        )
    }
}
