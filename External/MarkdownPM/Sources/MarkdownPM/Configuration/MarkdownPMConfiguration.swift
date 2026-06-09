//
//  MarkdownPMConfiguration.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  Centralized configuration for the Markdown editor engine.
//
//  This struct exposes every spacing, sizing, and behavior knob that is
//  shared across the engine. The defaults reproduce the historical
//  Nodes-app behavior, so passing `.default` keeps existing rendering
//  pixel-identical. Embedders that want a different look-and-feel can
//  override individual fields without forking the engine.
//
//  Visual styling (the color palette + per-feature style structs:
//  MarkerStyle, CodeBlockStyle, HeadingStyle, …) lives in
//  `MarkdownPMTheme.swift`. This file owns only the top-level config and
//  the behavior/layout POLICY structs (scrollers, insets, overscroll,
//  drag) — the non-visual seam (LD-24 / decision D5.2-b).
//

import AppKit
import Foundation

// MARK: - Top-level Configuration

/// All tunable values for the Markdown editor engine grouped by concern.
///
/// The struct is deliberately flat-with-nested-groups: top level holds
/// orthogonal feature areas (markers, code blocks, lists, …), each group
/// owns the values that belong together. Default values are the production
/// defaults used by the Nodes app and have been chosen empirically.
public struct MarkdownPMConfiguration: Sendable {

    public var theme: MarkdownPMTheme
    public var services: MarkdownPMServices
    public var markers: MarkerStyle
    public var codeBlock: CodeBlockStyle
    public var inlineCode: InlineCodeStyle
    public var lists: ListStyle
    public var headings: HeadingStyle
    public var imageEmbed: ImageEmbedStyle
    public var blockLatex: BlockLatexStyle
    public var inlineLatex: InlineLatexStyle
    public var checkbox: CheckboxStyle
    public var link: LinkStyle
    public var paragraph: ParagraphStyle
    public var overscroll: OverscrollPolicy
    public var dragSelection: DragSelectionPolicy
    public var safeAreaInsets: SafeAreaInsets
    public var scrollers: ScrollersPolicy
    public var textInsets: TextInsets
    /// Render a resolved `{{Title}}` chip-link as a drawn inline chip
    /// (kern-collapsed source + fill/outline/icon/title overlay). When `false`
    /// (the default) a resolved chip-link renders as a plain styled link —
    /// the chip pipeline stays dormant.
    public var renderChipLinksAsChips: Bool

    public init(
        theme: MarkdownPMTheme = .default,
        services: MarkdownPMServices = .default,
        markers: MarkerStyle = .default,
        codeBlock: CodeBlockStyle = .default,
        inlineCode: InlineCodeStyle = .default,
        lists: ListStyle = .default,
        headings: HeadingStyle = .default,
        imageEmbed: ImageEmbedStyle = .default,
        blockLatex: BlockLatexStyle = .default,
        inlineLatex: InlineLatexStyle = .default,
        checkbox: CheckboxStyle = .default,
        link: LinkStyle = .default,
        paragraph: ParagraphStyle = .default,
        overscroll: OverscrollPolicy = .default,
        dragSelection: DragSelectionPolicy = .default,
        safeAreaInsets: SafeAreaInsets = .default,
        scrollers: ScrollersPolicy = .default,
        textInsets: TextInsets = .default,
        renderChipLinksAsChips: Bool = false
    ) {
        self.theme = theme
        self.services = services
        self.markers = markers
        self.codeBlock = codeBlock
        self.inlineCode = inlineCode
        self.lists = lists
        self.headings = headings
        self.imageEmbed = imageEmbed
        self.blockLatex = blockLatex
        self.inlineLatex = inlineLatex
        self.checkbox = checkbox
        self.link = link
        self.paragraph = paragraph
        self.overscroll = overscroll
        self.dragSelection = dragSelection
        self.safeAreaInsets = safeAreaInsets
        self.scrollers = scrollers
        self.textInsets = textInsets
        self.renderChipLinksAsChips = renderChipLinksAsChips
    }

    public static let `default` = MarkdownPMConfiguration()
}

// MARK: - Scroll bars

/// Scroll bar visibility. Default: vertical only, autohide on.
public struct ScrollersPolicy: Sendable {
    public var hasVerticalScroller: Bool
    public var hasHorizontalScroller: Bool
    public var autohidesScrollers: Bool

    public init(
        hasVerticalScroller: Bool = true,
        hasHorizontalScroller: Bool = false,
        autohidesScrollers: Bool = true
    ) {
        self.hasVerticalScroller = hasVerticalScroller
        self.hasHorizontalScroller = hasHorizontalScroller
        self.autohidesScrollers = autohidesScrollers
    }

    public static let `default` = ScrollersPolicy()
    /// No scrollers (use with a custom scroll overlay).
    public static let hidden = ScrollersPolicy(hasVerticalScroller: false, hasHorizontalScroller: false)
    /// Vertical only — same as `.default`.
    public static let vertical = ScrollersPolicy(hasVerticalScroller: true, hasHorizontalScroller: false)
    /// Both axes (code-heavy / wide content).
    public static let both = ScrollersPolicy(hasVerticalScroller: true, hasHorizontalScroller: true)
    /// Vertical, no auto-hide.
    public static let alwaysVisible = ScrollersPolicy(hasVerticalScroller: true, autohidesScrollers: false)
}

// MARK: - Text insets

/// Margins inside the text view (`NSTextView.textContainerInset`). Scroll bar stays at the outer edge.
public struct TextInsets: Sendable {
    public var horizontal: CGFloat
    public var vertical: CGFloat

    public init(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let `default` = TextInsets()
}

// MARK: - Bottom overscroll

/// Controls the empty space below the last line so that typing at the bottom
/// of a long document remains comfortable instead of pinning to the viewport
/// bottom edge.
public struct OverscrollPolicy: Sendable {
    /// Desired overscroll as a fraction of the visible viewport height.
    public var percent: CGFloat
    /// Hard upper bound for the overscroll in points.
    public var maxPoints: CGFloat
    /// Hard lower bound for the overscroll in points.
    public var minPoints: CGFloat
    /// Fraction of the viewport above which overscroll starts ramping up.
    public var activationStartFraction: CGFloat
    /// Fraction of the viewport over which overscroll fully ramps in.
    public var activationRangeFraction: CGFloat

    public init(
        percent: CGFloat = 0.5,
        maxPoints: CGFloat = 450,
        minPoints: CGFloat = 40,
        activationStartFraction: CGFloat = 0.15,
        activationRangeFraction: CGFloat = 0.85
    ) {
        self.percent = percent
        self.maxPoints = maxPoints
        self.minPoints = minPoints
        self.activationStartFraction = activationStartFraction
        self.activationRangeFraction = activationRangeFraction
    }

    public static let `default` = OverscrollPolicy()
}

// MARK: - Drag selection

/// Tuning for the auto-scroll boost that engages while the user drags a
/// selection past the visible viewport edges.
public struct DragSelectionPolicy: Sendable {
    /// Movement threshold (points) before the auto-scroll boost engages.
    public var movementThreshold: CGFloat
    /// Distance from the window edge that triggers the boost.
    public var edgeTriggerDistance: CGFloat
    /// Pixels per tick scrolled while the boost is active.
    public var scrollStepPerTick: CGFloat
    /// Boost timer frequency (ticks per second).
    public var ticksPerSecond: Double

    public init(
        movementThreshold: CGFloat = 5.0,
        edgeTriggerDistance: CGFloat = 5.0,
        scrollStepPerTick: CGFloat = 12.0,
        ticksPerSecond: Double = 60.0
    ) {
        self.movementThreshold = movementThreshold
        self.edgeTriggerDistance = edgeTriggerDistance
        self.scrollStepPerTick = scrollStepPerTick
        self.ticksPerSecond = ticksPerSecond
    }

    public static let `default` = DragSelectionPolicy()
}

// MARK: - Safe-area insets

/// Reserves space on the scroll view for system overlays (e.g. a translucent toolbar to scroll underneath). Maps to `NSScrollView.contentInsets`; scroll bar follows the inset.
public struct SafeAreaInsets: Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var trailing: CGFloat
    public var bottom: CGFloat

    public init(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        trailing: CGFloat = 0,
        bottom: CGFloat = 0
    ) {
        self.top = top
        self.leading = leading
        self.trailing = trailing
        self.bottom = bottom
    }

    public static let `default` = SafeAreaInsets()
}
