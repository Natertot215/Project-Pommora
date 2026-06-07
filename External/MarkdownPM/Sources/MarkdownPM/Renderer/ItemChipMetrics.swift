//
//  ItemChipMetrics.swift
//  MarkdownPM
//
//  Shared layout constants for the inline `{{Item}}` highlight so the styler's
//  kern-trick width (MarkdownPMStyler+Links.styleItemLinks) matches exactly
//  what the fragment draws (MarkdownTextLayoutFragment.drawItemChips).
//

import AppKit

enum ItemChipMetrics {
    /// Horizontal padding on each side of the title text inside the highlight.
    static let horizontalPadding: CGFloat = 4

    /// Total inline highlight size for `title` at `font`. Height matches the
    /// typographic character height (ascender − descender) so the highlight
    /// sits within the text line without altering line spacing.
    static func size(title: String, font: NSFont) -> CGSize {
        let titleW = HeadingHelpers.textWidth(title, font: font)
        let w = horizontalPadding + titleW + horizontalPadding
        let h = ceil(font.ascender - font.descender)
        return CGSize(width: w, height: h)
    }
}
