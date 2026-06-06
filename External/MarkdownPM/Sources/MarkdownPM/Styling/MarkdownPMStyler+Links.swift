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
                attrs.append((match.range, [.link: url]))
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
                } else {
                    contentAttributes[.foregroundColor] = ctx.configuration.theme.disabledText
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

    // MARK: Item Links {{Title}}

    /// Title-only parallel of `styleWikiLinks` for `{{Title}}` item links. No
    /// stored id (no `wikiLinkIDProvider`) — resolution is by title via
    /// `ctx.services.itemLinks`. Resolved → renders as a colored `.link` (a
    /// placeholder for a future item-pill) and is stamped with `.itemLinkTitle`
    /// so E4's click handler can route to the Item Window instead of page-nav.
    /// UNRESOLVED → muted `disabledText` (SAME as `[[ ]]` — intentionally NOT
    /// plain body color).
    static func styleItemLinks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (index, token) in ctx.tokens.enumerated() where token.kind == .itemLink {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))
            let nodeName = ctx.nsText.substring(with: token.contentRange)
            var contentAttributes: [NSAttributedString.Key: Any] = [:]
            let isActive = ctx.isActive(tokenIndex: index)
            // Resolve the item title via the embedder-supplied item resolver.
            let nodeExists: Bool = {
                if let resolution = ctx.services.itemLinks.resolve(displayName: nodeName, range: token.contentRange) {
                    return resolution.exists
                }
                return false
            }()
            if !isActive {
                if nodeExists {
                    contentAttributes[.link] = nodeName
                    contentAttributes[.itemLinkTitle] = nodeName
                } else {
                    contentAttributes[.foregroundColor] = ctx.configuration.theme.disabledText
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
