//
//  ChipLinkMetrics.swift
//  MarkdownPM
//
//  Shared layout constants for the inline `{{Title}}` highlight so the styler's
//  kern-trick width (MarkdownPMStyler+Links.styleChipLinks) matches exactly
//  what the fragment draws (MarkdownTextLayoutFragment.drawChipLinks).
//

import AppKit

enum ChipLinkMetrics {
    /// Horizontal padding on each side of the chip content.
    static let horizontalPadding: CGFloat = 4
    /// Gap between the SF Symbol icon and the title text.
    static let iconTitleGap: CGFloat = 3

    /// Reserved square for the SF Symbol icon — approximately one em.
    static func iconWidth(font: NSFont) -> CGFloat { font.pointSize }

    /// Total inline highlight size for `title` at `font` with icon. Height
    /// matches the typographic character height (ascender − descender) so the
    /// highlight sits within the text line without altering line spacing.
    static func size(title: String, font: NSFont) -> CGSize {
        let titleW = HeadingHelpers.textWidth(title, font: font)
        let w = horizontalPadding + iconWidth(font: font) + iconTitleGap + titleW + horizontalPadding
        let h = ceil(font.ascender - font.descender)
        return CGSize(width: w, height: h)
    }
}
