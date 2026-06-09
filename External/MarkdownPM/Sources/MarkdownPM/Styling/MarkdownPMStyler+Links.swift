//
//  MarkdownPMStyler+Links.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  Auto-detected URLs, [text](url) Markdown links, and [[Name]] wiki links.
//

import AppKit
import Foundation

extension MarkdownPMStyler {

    // MARK: Auto-detected plain URLs

    static func styleAutoLinks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        guard let detector = MarkdownPMStyler.linkDataDetector else { return attrs }

        // Scope to edited paragraphs when provided; avoids full-doc URL scan per keystroke.
        let rangesToScan: [NSRange]
        if let scoped = ctx.scopedRanges, !scoped.isEmpty {
            rangesToScan = scoped.compactMap { range in
                let clipped = NSIntersectionRange(range, ctx.fullRange)
                return clipped.length > 0 ? clipped : nil
            }
        } else {
            rangesToScan = [ctx.fullRange]
        }

        for range in rangesToScan {
            detector.enumerateMatches(in: ctx.text, options: [], range: range) { match, _, _ in
                guard let match = match, let url = match.url else { return }
                if MarkdownDetection.isInsideCodeBlock(range: match.range, codeTokens: ctx.codeTokens) { return }
                // Explicit visual styling — linkTextAttributes is cleared on NSTextView.
                attrs.append((match.range, [
                    .link: url,
                    .foregroundColor: ctx.configuration.theme.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]))
            }
        }
        return attrs
    }

    // MARK: Wiki Links [[Name]]

    static func styleWikiLinks(_ ctx: StylingContext, wikiLinkIDProvider: (NSRange) -> String?) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (index, token) in ctx.tokens.enumerated() where token.kind == .wikiLink {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))
            let nodeName = ctx.nsText.substring(with: token.contentRange)
            let linkID = wikiLinkIDProvider(token.range)
            var contentAttributes: [NSAttributedString.Key: Any] = [:]
            if let linkID {
                contentAttributes[.wikiLinkID] = linkID
            }
            let isActive = ctx.isActive(tokenIndex: index)
            // Check if the linked node actually exists, using whichever resolver
            // the embedder supplied via configuration.services.
            let nodeExists: Bool = {
                if let resolution = ctx.services.wikiLinks.resolve(displayName: nodeName, range: token.contentRange) {
                    return resolution.exists
                }
                return false
            }()
            if !isActive {
                if nodeExists {
                    contentAttributes[.link] = linkID ?? nodeName
                    // Explicit visual styling — linkTextAttributes is cleared on the
                    // NSTextView so these attributes must be set directly here.
                    contentAttributes[.foregroundColor] = ctx.configuration.theme.link
                    contentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    contentAttributes[.foregroundColor] = NSColor.secondaryLabelColor
                }
            }
            if !contentAttributes.isEmpty {
                attrs.append((token.contentRange, contentAttributes))
            }
            for markerRange in token.markerRanges {
                attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
            }
        }
        return attrs
    }

    // MARK: Chip Links {{Title}}

    /// Title-only parallel of `styleWikiLinks` for `{{Title}}` chip links. No
    /// stored id (no `wikiLinkIDProvider`) — resolution is by title via
    /// `ctx.services.chipLinks`.
    ///
    /// RESOLVED + INACTIVE + `renderChipLinksAsChips` ON → renders as an inline
    /// highlight via the kern-trick (mirrors `styleInlineLatex`): the source
    /// `{{Title}}` text is collapsed to zero visible width and the first content
    /// char reserves the highlight's width, carrying
    /// `.chipLinkBounds`/`.chipLinkTitle` so the fragment's `drawChipLinks`
    /// draws the fill+outline+title over it. `.link` stays set so the click
    /// handler still routes to `onChipLinkClick`.
    /// RESOLVED + INACTIVE + gate OFF (the default) → plain styled link:
    /// `.link` + `.chipLinkTitle` + theme link foreground + underline
    /// (mirrors a resolved wikilink), no chip drawing.
    /// ACTIVE (caret in token) → raw `{{Title}}` stays visible/editable: markers
    /// muted, content plain (no highlight, no kern).
    /// UNRESOLVED → muted secondary label.
    static func styleChipLinks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (index, token) in ctx.tokens.enumerated() where token.kind == .chipLink {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))
            let nodeName = ctx.nsText.substring(with: token.contentRange)
            let isActive = ctx.isActive(tokenIndex: index)
            // Resolve the chip-link title via the embedder-supplied resolver —
            // ONCE; the result carries both `exists` and `icon`.
            let resolution = ctx.services.chipLinks.resolve(displayName: nodeName, range: token.contentRange)
            let nodeExists = resolution?.exists ?? false

            // RESOLVED + INACTIVE (chip rendering gated ON): hide the raw source
            // and reserve the pill's width via the kern-trick. Guard a non-empty
            // title (empty `{{}}` → skip the chip, leave the source as-is).
            if ctx.configuration.renderChipLinksAsChips, !isActive, nodeExists, token.contentRange.length > 0 {
                let title = nodeName
                let icon = resolution?.icon ?? "square.dashed"
                let chipSize = ChipLinkMetrics.size(title: title, font: ctx.baseFont)
                let contentLength = token.contentRange.length

                // FIRST content char: reserve the full highlight width via kern.
                let firstCharRange = NSRange(location: token.contentRange.location, length: 1)
                let firstChar = ctx.nsText.substring(with: firstCharRange)
                attrs.append((firstCharRange, [
                    .chipLinkBounds: NSValue(rect: CGRect(origin: .zero, size: chipSize)),
                    .chipLinkTitle: title,
                    .chipLinkIcon: icon,
                    .link: title,
                    .foregroundColor: NSColor.clear,
                    .kern: chipSize.width - HeadingHelpers.textWidth(firstChar, font: ctx.baseFont)
                ]))

                // REST of content: collapse to zero width.
                if contentLength > 1 {
                    let restRange = NSRange(location: token.contentRange.location + 1, length: contentLength - 1)
                    let restText = ctx.nsText.substring(with: restRange)
                    attrs.append((restRange, [
                        .foregroundColor: NSColor.clear,
                        .kern: -HeadingHelpers.textWidth(restText, font: ctx.baseFont)
                    ]))
                }

                // Markers `{{` / `}}`: collapse to zero width.
                let openMarker = token.markerRanges[0]
                attrs.append((openMarker, [
                    .foregroundColor: NSColor.clear,
                    .kern: -HeadingHelpers.textWidth("{{", font: ctx.baseFont)
                ]))
                let closeMarker = token.markerRanges[1]
                attrs.append((closeMarker, [
                    .foregroundColor: NSColor.clear,
                    .kern: -HeadingHelpers.textWidth("}}", font: ctx.baseFont)
                ]))
                continue
            }

            // GATE-OFF / ACTIVE / UNRESOLVED / empty-title fallback: raw text,
            // no chip — markers muted, resolved content linked, unresolved
            // content muted.
            var contentAttributes: [NSAttributedString.Key: Any] = [:]
            if !isActive {
                if nodeExists {
                    contentAttributes[.link] = nodeName
                    contentAttributes[.chipLinkTitle] = nodeName
                    // Explicit visual styling — linkTextAttributes is cleared on the
                    // NSTextView so these attributes must be set directly here.
                    contentAttributes[.foregroundColor] = ctx.configuration.theme.link
                    contentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    contentAttributes[.foregroundColor] = NSColor.secondaryLabelColor
                }
            }
            if !contentAttributes.isEmpty {
                attrs.append((token.contentRange, contentAttributes))
            }
            for markerRange in token.markerRanges {
                attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
            }
        }
        return attrs
    }

    // MARK: Markdown Links [Text](URL)

    static func styleMarkdownLinks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .link {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))
            let fullMatch = ctx.nsText.substring(with: token.range)
            if let urlStart = fullMatch.firstIndex(of: "("), let urlEnd = fullMatch.lastIndex(of: ")") {
                let rawUrl = String(fullMatch[fullMatch.index(after: urlStart)..<urlEnd])
                var urlCandidate = rawUrl
                if !urlCandidate.contains("://") {
                    urlCandidate = "https://\(urlCandidate)"
                }
                let isActive = ctx.isActive(tokenIndex: idx)
                if let url = URL(string: urlCandidate) {
                    if isActive {
                        attrs.append((token.contentRange, [
                            .foregroundColor: ctx.configuration.theme.link.withAlphaComponent(ctx.configuration.link.activeLinkAlpha)
                        ]))
                    } else {
                        attrs.append((token.contentRange, [
                            .link: url,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: ctx.configuration.theme.link
                        ]))
                    }
                }
                for m in token.markerRanges {
                    attrs.append((m, [.foregroundColor: ctx.configuration.theme.mutedText]))
                }
            }
        }
        return attrs
    }
}
