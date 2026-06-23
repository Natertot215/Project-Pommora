//
//  MarkdownPMTheme.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  Visual theme for the Markdown editor engine: the color palette plus the
//  per-feature visual styling structs (markers, code, lists, headings, …).
//
//  Everything the engine puts on screen is routed through this file, so a
//  single override is enough to retheme the editor. Defaults map to system
//  colors so light/dark-mode switching keeps working without extra code.
//  Behavior/layout policy (scrollers, insets, overscroll, drag) lives with
//  the top-level config in `MarkdownPMConfiguration.swift`, NOT here —
//  this file is the visual layer only (decision D5.2-b / LD-24).
//

import AppKit
import Foundation

// MARK: - Colors

/// Color palette consumed by the Markdown editor engine.
///
/// Every color the engine puts on screen is read from this struct, so a
/// single override is enough to retheme the entire editor. The defaults
/// reproduce a system-native macOS look using `NSColor` dynamic system
/// colors, so light/dark-mode switching keeps working without extra code.
public struct MarkdownPMTheme: Sendable {

    // MARK: Text colors

    /// Foreground color for plain body text and the typing caret.
    public var bodyText: NSColor
    /// Foreground color for de-emphasized text and most syntax markers.
    /// Defaults to `secondaryLabelColor` so it tracks the system style.
    public var mutedText: NSColor
    /// Foreground color for content the engine wants to deemphasize further
    /// than `mutedText` — for example, broken wiki-links.
    public var disabledText: NSColor
    /// Foreground color for heading marker glyphs (`#`, `##`, …).
    public var headingMarker: NSColor
    /// Tint used for accented affordances driven by user intent
    /// (e.g. the filled glyph of a checked task checkbox).
    public var accentColor: NSColor
    /// Foreground color for code text — both inline `` `code` `` spans and
    /// fenced code block content not claimed by a syntax highlighter.
    /// Defaults to `systemRed` at 0.85 alpha to match the historical look.
    public var codeText: NSColor

    // MARK: Links

    /// Foreground color for hyperlinks that resolve to an URL.
    public var link: NSColor
    /// Foreground color for incomplete `[text]` patterns (no URL yet).
    public var incompleteLink: NSColor

    // MARK: Find / search highlights

    /// Background color used to highlight all matches when the user is
    /// running an in-document search.
    ///
    /// The default is `.systemYellow` so embedders that don't customize
    /// this still get a sensible result. Apps with their own brand color
    /// (for example, the Nodes app uses its custom yellow) should override
    /// this to match their palette.
    public var findMatchHighlight: NSColor
    /// Background color used to highlight the currently-focused match
    /// during in-document search. Typically a stronger version of
    /// ``findMatchHighlight``.
    public var findCurrentMatchHighlight: NSColor

    // MARK: LaTeX rendering

    /// Foreground color used when rendering LaTeX formulas in light mode.
    public var latexLightModeText: NSColor
    /// Foreground color used when rendering LaTeX formulas in dark mode.
    public var latexDarkModeText: NSColor

    // MARK: Strikethrough / decoration

    /// Stroke color used for strikethrough decorations
    /// (e.g. completed task list items, horizontal rules).
    public var strikethroughColor: NSColor

    // MARK: Init

    public init(
        bodyText: NSColor = .labelColor,
        mutedText: NSColor = .secondaryLabelColor,
        disabledText: NSColor = .tertiaryLabelColor,
        headingMarker: NSColor = .gray,
        accentColor: NSColor = .controlAccentColor,
        codeText: NSColor = NSColor.systemRed.withAlphaComponent(0.85),
        link: NSColor = .linkColor,
        incompleteLink: NSColor = .systemBlue,
        findMatchHighlight: NSColor = .systemYellow,
        findCurrentMatchHighlight: NSColor = .systemYellow,
        latexLightModeText: NSColor = .black,
        latexDarkModeText: NSColor = .white,
        strikethroughColor: NSColor = .labelColor
    ) {
        self.bodyText = bodyText
        self.mutedText = mutedText
        self.disabledText = disabledText
        self.headingMarker = headingMarker
        self.accentColor = accentColor
        self.codeText = codeText
        self.link = link
        self.incompleteLink = incompleteLink
        self.findMatchHighlight = findMatchHighlight
        self.findCurrentMatchHighlight = findCurrentMatchHighlight
        self.latexLightModeText = latexLightModeText
        self.latexDarkModeText = latexDarkModeText
        self.strikethroughColor = strikethroughColor
    }

    /// System-native palette built from `NSColor` dynamic system colors.
    ///
    /// Use this if you want the engine to look like a stock macOS
    /// `NSTextView`. It's also the default when no theme is supplied.
    public static let `default` = MarkdownPMTheme()
}

// MARK: - Marker visibility

/// How Markdown syntax markers (e.g. `**`, `*`, `$`) are visualized when
/// the cursor is not inside the corresponding token.
///
/// The engine's default approach is to keep markers in the text storage but
/// shrink them to a near-zero font size (`hiddenMarkerFontSize`). This avoids
/// any range translation between displayed and stored text — cursor movement,
/// find/replace, selection, and copy/paste all stay trivially correct.
/// The trade-off is a sub-pixel residue at extreme zoom levels.
public struct MarkerStyle: Sendable {
    /// Font size used for "hidden" inline markers. Effectively invisible at
    /// normal zoom while keeping displayed-range == stored-range.
    public var hiddenMarkerFontSize: CGFloat
    /// Alpha applied to inline-code's secondary marker color.
    public var inlineCodeMarkerAlpha: CGFloat
    /// Alpha applied to non-focused find matches when in-document search
    /// highlights are visible. The focused match is drawn at full opacity.
    public var findMatchHighlightAlpha: CGFloat

    public init(
        hiddenMarkerFontSize: CGFloat = 0.1,
        inlineCodeMarkerAlpha: CGFloat = 0.5,
        findMatchHighlightAlpha: CGFloat = 0.65
    ) {
        self.hiddenMarkerFontSize = hiddenMarkerFontSize
        self.inlineCodeMarkerAlpha = inlineCodeMarkerAlpha
        self.findMatchHighlightAlpha = findMatchHighlightAlpha
    }

    public static let `default` = MarkerStyle()
}

// MARK: - Code blocks

/// Styling for fenced code blocks (```language ... ```).
public struct CodeBlockStyle: Sendable {
    /// Code-block font size as a fraction of the document base font size.
    public var fontSizeScale: CGFloat
    /// Vertical paragraph spacing applied above and below the code block.
    public var paragraphSpacing: CGFloat
    /// Left/right indent (in points) so code blocks don't run into the gutter.
    public var horizontalIndent: CGFloat

    public init(
        fontSizeScale: CGFloat = 0.85,
        paragraphSpacing: CGFloat = 2.0,
        horizontalIndent: CGFloat = 12.0
    ) {
        self.fontSizeScale = fontSizeScale
        self.paragraphSpacing = paragraphSpacing
        self.horizontalIndent = horizontalIndent
    }

    public static let `default` = CodeBlockStyle()
}

// MARK: - Inline code

/// Styling for inline `` `code` `` spans.
public struct InlineCodeStyle: Sendable {
    /// Inline-code reuses the code block font size scale by default.
    public var fontSizeScale: CGFloat

    public init(fontSizeScale: CGFloat = 0.85) {
        self.fontSizeScale = fontSizeScale
    }

    public static let `default` = InlineCodeStyle()
}

// MARK: - Lists

/// Behavior toggles and metrics for ordered / unordered list editing.
public struct ListStyle: Sendable {
    /// Master switch for list-related editing helpers (auto-continue,
    /// auto-indent, marker conversion). When `false`, lists are still
    /// rendered, but typing-time conveniences are skipped.
    public var helpersEnabled: Bool
    /// Master switch for auto-closing pairs `()`, `{}`, `[]` while typing.
    public var autoClosePairsEnabled: Bool
    /// Indent (in points) that one nesting level adds to the list item.
    public var indentPerLevel: CGFloat
    /// Maximum nesting level reachable by pressing Tab inside a list.
    public var maximumNestingLevel: Int
    /// Extra line height added on top of the default to give list items room.
    public var extraLineHeight: CGFloat
    /// Extra horizontal padding (in points) between a rendered bullet `•` glyph
    /// and the item text, on top of the source marker's natural width. Applies
    /// to plain `-` bullets only (ordered lists + task checkboxes unaffected).
    public var bulletTextGap: CGFloat

    public init(
        helpersEnabled: Bool = true,
        autoClosePairsEnabled: Bool = true,
        indentPerLevel: CGFloat = 24,
        maximumNestingLevel: Int = 3,
        extraLineHeight: CGFloat = 4,
        bulletTextGap: CGFloat = 3
    ) {
        self.helpersEnabled = helpersEnabled
        self.autoClosePairsEnabled = autoClosePairsEnabled
        self.indentPerLevel = indentPerLevel
        self.maximumNestingLevel = maximumNestingLevel
        self.extraLineHeight = extraLineHeight
        self.bulletTextGap = bulletTextGap
    }

    public static let `default` = ListStyle()
}

// MARK: - Headings

/// Per-level heading metrics. Defaults are the Phase-5 Pommora scale where
/// H6 equals body size (no heading renders below body).
public struct HeadingStyle: Sendable {
    /// Font-size multiplier per heading level (1...6).
    public var fontMultipliers: [CGFloat]
    /// Top spacing in `em` units per heading level (1...6).
    public var topSpacingEm: [CGFloat]

    public init(
        fontMultipliers: [CGFloat] = [2.0, 1.75, 1.5, 1.25, 1.15, 1.0],
        topSpacingEm: [CGFloat] = [0.35, 0.35, 0.32, 0.25, 0.21, 0.15]
    ) {
        self.fontMultipliers = fontMultipliers
        self.topSpacingEm = topSpacingEm
    }

    public func fontMultiplier(for level: Int) -> CGFloat {
        let index = max(1, min(level, fontMultipliers.count)) - 1
        return fontMultipliers[index]
    }

    public func topSpacingEm(for level: Int) -> CGFloat {
        let index = max(1, min(level, topSpacingEm.count)) - 1
        return topSpacingEm[index]
    }

    public static let `default` = HeadingStyle()
}

// MARK: - Image embeds (![[...]])

/// Sizing and spacing rules for `![[Name]]` image embeds.
public struct ImageEmbedStyle: Sendable {
    /// Minimum allowed display width (points) for an embedded image.
    public var minimumWidth: CGFloat
    /// Fallback maximum width if no usable text container width is available.
    public var fallbackMaxWidth: CGFloat
    /// Sanity bound — container widths above this are treated as invalid.
    public var unreasonableMaxWidth: CGFloat
    /// Vertical paragraph spacing above/below the image paragraph.
    public var paragraphSpacing: CGFloat
    /// Gap between the source line and the rendered image (visibleSource mode).
    public var imageGap: CGFloat

    public init(
        minimumWidth: CGFloat = 50,
        fallbackMaxWidth: CGFloat = 650,
        unreasonableMaxWidth: CGFloat = 1_000_000,
        paragraphSpacing: CGFloat = 8,
        imageGap: CGFloat = 8
    ) {
        self.minimumWidth = minimumWidth
        self.fallbackMaxWidth = fallbackMaxWidth
        self.unreasonableMaxWidth = unreasonableMaxWidth
        self.paragraphSpacing = paragraphSpacing
        self.imageGap = imageGap
    }

    public static let `default` = ImageEmbedStyle()
}

// MARK: - LaTeX

/// Vertical spacing for block-LaTeX `$$...$$` paragraphs.
public struct BlockLatexStyle: Sendable {
    /// Top spacing for $$...$$ block paragraphs.
    public var paragraphSpacingBefore: CGFloat
    /// Bottom spacing for $$...$$ block paragraphs.
    public var paragraphSpacing: CGFloat
    /// Extra bottom padding added to single-letter formulas to avoid clipping.
    public var singleLetterPaddingBottom: CGFloat

    public init(
        paragraphSpacingBefore: CGFloat = 16,
        paragraphSpacing: CGFloat = 20,
        singleLetterPaddingBottom: CGFloat = 1.0
    ) {
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.paragraphSpacing = paragraphSpacing
        self.singleLetterPaddingBottom = singleLetterPaddingBottom
    }

    public static let `default` = BlockLatexStyle()
}

/// Reserved for future inline-LaTeX (`$...$`) tuning. Currently has no
/// effect; inline LaTeX inherits font size from the surrounding context.
public struct InlineLatexStyle: Sendable {
    /// Reserved for future inline-LaTeX tuning — currently the engine inherits
    /// font size from the surrounding heading context.
    public var placeholder: Void

    public init() { self.placeholder = () }

    public static let `default` = InlineLatexStyle()
}

// MARK: - Task checkboxes

/// Glyph sizing and spacing for `- [ ]` / `- [x]` task checkboxes.
public struct CheckboxStyle: Sendable {
    /// Minimum extra spacing (points) inserted after an unchecked checkbox to
    /// optically center the rendered glyph.
    public var minimumExtraSpacing: CGFloat
    /// Additional spacing as a fraction of the surrounding font's point size.
    public var extraSpacingPerFontPointFraction: CGFloat
    /// Checkbox glyph size as a fraction of the line's font height.
    public var sizeFromFontHeightFactor: CGFloat
    /// Checkbox glyph size as a fraction of the `[ ]` marker width.
    public var sizeFromMarkerWidthFactor: CGFloat
    /// Inset applied inside the checkbox bounding box before drawing the icon.
    public var iconInsetFraction: CGFloat

    public init(
        minimumExtraSpacing: CGFloat = 2.0,
        extraSpacingPerFontPointFraction: CGFloat = 0.18,
        sizeFromFontHeightFactor: CGFloat = 1.2,
        sizeFromMarkerWidthFactor: CGFloat = 1.2,
        iconInsetFraction: CGFloat = 0.01
    ) {
        self.minimumExtraSpacing = minimumExtraSpacing
        self.extraSpacingPerFontPointFraction = extraSpacingPerFontPointFraction
        self.sizeFromFontHeightFactor = sizeFromFontHeightFactor
        self.sizeFromMarkerWidthFactor = sizeFromMarkerWidthFactor
        self.iconInsetFraction = iconInsetFraction
    }

    public static let `default` = CheckboxStyle()
}

// MARK: - Links

/// Foreground alpha values applied to link content in different states.
public struct LinkStyle: Sendable {
    /// Foreground alpha for the visible label of an active markdown link.
    public var activeLinkAlpha: CGFloat
    /// Foreground alpha applied to "incomplete" link content (e.g. `[text]`
    /// without a target).
    public var incompleteLinkAlpha: CGFloat

    public init(activeLinkAlpha: CGFloat = 0.55, incompleteLinkAlpha: CGFloat = 0.7) {
        self.activeLinkAlpha = activeLinkAlpha
        self.incompleteLinkAlpha = incompleteLinkAlpha
    }

    public static let `default` = LinkStyle()
}

// MARK: - Paragraphs

/// Default paragraph spacing and line height applied to body text.
public struct ParagraphStyle: Sendable {
    /// Extra paragraph spacing as a fraction of the document's default line height.
    public var spacingFactor: CGFloat
    /// Extra height (points) added to the default paragraph line height.
    public var lineHeightExtraSpacing: CGFloat

    public init(spacingFactor: CGFloat = 0.3, lineHeightExtraSpacing: CGFloat = 2) {
        self.spacingFactor = spacingFactor
        self.lineHeightExtraSpacing = lineHeightExtraSpacing
    }

    public static let `default` = ParagraphStyle()
}
