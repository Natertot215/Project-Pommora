//
//  ItemChipMetrics.swift
//  MarkdownPM
//
//  Shared layout constants for the inline `{{Item}}` pill so the styler's
//  reserved kern-trick width (MarkdownPMStyler+Links.styleItemLinks) matches
//  exactly what the fragment draws (MarkdownTextLayoutFragment.drawItemChips).
//

import AppKit

enum ItemChipMetrics {
    static let horizontalPadding: CGFloat = 5
    static let iconTitleGap: CGFloat = 3
    static let verticalPadding: CGFloat = 4

    /// SF Symbol icons render ~em-square; reserve a square box at the font size.
    static func iconWidth(font: NSFont) -> CGFloat { font.pointSize }

    /// Total inline pill size for (icon present) + title at `font`.
    static func size(title: String, font: NSFont) -> CGSize {
        let titleW = HeadingHelpers.textWidth(title, font: font)
        let w = horizontalPadding + iconWidth(font: font) + iconTitleGap + titleW + horizontalPadding
        let h = ceil(font.ascender - font.descender) + verticalPadding * 2
        return CGSize(width: w, height: h)
    }
}
