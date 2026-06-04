//
//  MarkdownDetection.swift
//  MarkdownPM
//
//  Created by Luca Chen on 18.02.26.
//

// Helper checks for questions like "is the cursor inside code or LaTeX?"
// and "which Markdown part is currently active?".
import Foundation
import Markdown

/// A top-level Markdown heading paired with the source range of the content
/// that falls under it. Returned from `MarkdownDetection.foldableHeadings` so
/// the editor can collapse / expand sections by NSRange without re-walking
/// the AST at every render.
public struct FoldedHeading: Equatable, Sendable {
    /// Exact heading source line, stripped of trailing newline — e.g.
    /// `"## Implementation notes"`. Used as the stable identity key in
    /// `Set<String>`-shaped fold state on disk and in memory.
    public let key: String
    /// 1...6 — ATX heading depth.
    public let level: Int
    /// Source range of the heading line itself, INCLUDING the trailing
    /// newline (the line range). The chevron + draw logic positions itself
    /// against this range.
    public let headingRange: NSRange
    /// Source range of the content under this heading — from the first
    /// character after the heading's newline to (exclusive) the start of the
    /// next heading at level ≤ `level`, or document end if no such heading
    /// follows. Zero-length when the heading has no content under it.
    public let contentRange: NSRange

    public init(key: String, level: Int, headingRange: NSRange, contentRange: NSRange) {
        self.key = key
        self.level = level
        self.headingRange = headingRange
        self.contentRange = contentRange
    }
}

public enum MarkdownDetection {

    // MARK: - Thematic Break (HR) detection

    /// Three-stage detection for whether a single-paragraph string is a
    /// Markdown ThematicBreak (`---`, `***`, `___`). Used by both the
    /// renderer (per-fragment) and the HRVisibility service (per-paragraph).
    /// Both callers MUST share this logic — drift produces "dashes hidden
    /// but no line drawn" or "line drawn over visible text" half-applied
    /// states (`.claude/Guidelines/Markdown.md` L2).
    ///
    /// No setext-underline guard. Per Pommora's locked design, `---` ALWAYS
    /// renders as HR regardless of what's on the line above; the AST already
    /// gives the desired answer for `---\n` in isolation.
    ///
    /// - Parameters:
    ///   - paragraphString: The line(s) to test, including any trailing newline.
    ///   - isInsideCodeBlock: Stage 0 result from the caller's context — the
    ///     renderer reads its fragment's `.backgroundColor`; the service reads
    ///     the same attribute from storage. Either way the answer flows in here.
    static func isThematicBreakLine(
        _ paragraphString: String,
        isInsideCodeBlock: Bool
    ) -> Bool {
        // Stage 0 — code-block guard.
        if isInsideCodeBlock { return false }

        // Stage 1 — cheap prefilter. ~99% of paragraphs early-exit here.
        let trimmed = paragraphString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3,
            let first = trimmed.first,
            first == "-" || first == "*" || first == "_"
        else { return false }

        // Stage 2 — AST parse confirms.
        let document = Markdown.Document(parsing: paragraphString)
        return document.children.contains { $0 is ThematicBreak }
    }

    // MARK: - Dash bullet detection

    /// Three-stage detection for whether a single-paragraph string is a
    /// `-`-marker bullet list item (excluding task lists). Used by the
    /// renderer to decide whether to overlay a `•` glyph on the hidden
    /// source `-`. Mirrors `isThematicBreakLine`'s pattern.
    ///
    /// Only `-` triggers. `*`, `+`, and legacy `•` lines return false here
    /// and render as their literal characters. Task lines (`- [ ]` /
    /// `- [x]`) also return false — the existing checkbox UX is preserved.
    ///
    /// - Parameters:
    ///   - paragraphString: The line(s) to test, including any trailing newline.
    ///   - isInsideCodeBlock: Stage 0 result from the caller's context.
    /// Matches a dash/asterisk/plus/bullet list-item line. Pre-compiled once —
    /// `isDashBulletLine` is called per visible fragment on every redraw, so a
    /// fresh `NSRegularExpression` per call was needless compile churn on the
    /// draw hot path. Mirrors the static-regex pattern in `MarkdownTokenizer`.
    private static let dashBulletRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$"#,
        options: [.anchorsMatchLines]
    )

    static func isDashBulletLine(
        _ paragraphString: String,
        isInsideCodeBlock: Bool
    ) -> Bool {
        // Stage 0 — code-block guard.
        if isInsideCodeBlock { return false }

        // Match the SAME regex the styler uses in `MarkdownLists.applyListMatches`
        // so the renderer's bullet-glyph detection and the styler's hide-attr
        // are guaranteed to agree. No AST parse needed — the regex already
        // encodes CommonMark's space-after-marker requirement.
        let nsLine = paragraphString as NSString
        guard
            let match = dashBulletRegex.firstMatch(
                in: paragraphString,
                options: [],
                range: NSRange(location: 0, length: nsLine.length)
            )
        else { return false }

        // Marker char must be `-`. Task lists (`- [ ]` / `- [x]`) are excluded
        // so the existing checkbox UX is preserved.
        let markerRange = match.range(at: 2)
        guard markerRange.length > 0 else { return false }
        let firstChar = nsLine.substring(with: NSRange(location: markerRange.location, length: 1))
        guard firstChar == "-" else { return false }
        let group2 = nsLine.substring(with: markerRange)
        if group2.contains("[") { return false }

        return true
    }

    // MARK: - Blockquote detection

    /// Per-line blockquote detection — the shared definition behind the
    /// renderer's `hasBlockquoteMarker` and the construct precompute. Mirrors
    /// `isThematicBreakLine`'s shape: a cheap gate then an isolated AST confirm.
    ///
    /// Stage 1 scans the RAW line (not trimmed — a `> ` line's significant
    /// trailing space must survive): skip leading whitespace, require `>`, then
    /// require the next char to be space or tab (bare `>` does not activate,
    /// matching the list `- ` rule). Stage 2 parses the line in isolation and
    /// confirms a top-level `BlockQuote` node.
    ///
    /// - Parameters:
    ///   - paragraphString: the line to test, including any trailing newline.
    ///   - isInsideCodeBlock: Stage-0 result from the caller's context.
    static func isBlockquoteLine(
        _ paragraphString: String,
        isInsideCodeBlock: Bool
    ) -> Bool {
        if isInsideCodeBlock { return false }
        let ns = paragraphString as NSString
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 0x20 || c == 0x09 { i += 1; continue }
            break
        }
        guard i < ns.length, ns.character(at: i) == 0x3E else { return false }   // `>`
        guard i + 1 < ns.length else { return false }
        let next = ns.character(at: i + 1)
        guard next == 0x20 || next == 0x09 else { return false }
        let document = Markdown.Document(parsing: paragraphString)
        return document.children.contains { $0 is BlockQuote }
    }

    // MARK: - Per-document construct precompute (draw-path optimization)

    /// Line-start offsets for the block constructs the renderer draws per
    /// fragment. Computed ONCE per `parsedDocument(for:)` (memoized per text
    /// change) so the draw path does an O(1) Set lookup instead of allocating a
    /// line string + parsing an AST per fragment per frame.
    struct ConstructLineStarts: Sendable {
        let thematicBreaks: Set<Int>
        let blockquotes: Set<Int>
        let dashBullets: Set<Int>
    }

    /// Walk every line once and record which lines are thematic breaks /
    /// blockquote lines / dash-bullets, BY CALLING THE PER-LINE DETECTORS — so
    /// the result is equivalent-by-construction to the renderer's prior
    /// per-fragment checks. Must NOT short-circuit via the whole-document AST:
    /// the per-line detectors parse each line in isolation (e.g. `Foo\n---`
    /// keeps `---` an HR — Pommora has no setext guard), which a whole-doc parse
    /// would not reproduce.
    ///
    /// - Parameters:
    ///   - nsText: the full document text.
    ///   - blockCodeTokens: tokens filtered to `.codeBlock` (the Stage-0 guard).
    static func constructLineStarts(
        in nsText: NSString,
        blockCodeTokens: [MarkdownToken]
    ) -> ConstructLineStarts {
        var hr: Set<Int> = []
        var bq: Set<Int> = []
        var bullet: Set<Int> = []
        var pos = 0
        while pos < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
            let line = nsText.substring(with: lineRange)
            let insideCode = isInsideCodeBlock(range: lineRange, codeTokens: blockCodeTokens)
            if isThematicBreakLine(line, isInsideCodeBlock: insideCode) { hr.insert(lineRange.location) }
            if isBlockquoteLine(line, isInsideCodeBlock: insideCode) { bq.insert(lineRange.location) }
            if isDashBulletLine(line, isInsideCodeBlock: insideCode) { bullet.insert(lineRange.location) }
            let next = NSMaxRange(lineRange)
            if next <= pos { break }
            pos = next
        }
        return ConstructLineStarts(thematicBreaks: hr, blockquotes: bq, dashBullets: bullet)
    }

    // MARK: - Heading detection (foldable headings)

    /// Three-stage detection for whether a paragraph string is an ATX heading
    /// line (e.g. `## Foo`, `###`, `# `). Used by the hover tracker to decide
    /// whether to show a fold chevron over the fragment under the cursor.
    /// Mirrors `isThematicBreakLine`'s three-stage shape so renderer + service
    /// agree at every decision point (`.claude/Guidelines/Markdown.md` L2).
    ///
    /// - Parameters:
    ///   - paragraphString: The line(s) to test, including any trailing newline.
    ///   - isInsideCodeBlock: Stage 0 result from the caller's context — `# X`
    ///     inside a fenced block parses as code, not a heading; must not be
    ///     foldable.
    /// ATX-heading prefix matcher (1-6 `#` then space/tab/EOL). Pre-compiled
    /// once — `isHeadingLine` runs per visible fragment on every redraw via
    /// the renderer's `hasHeadingMarker`. Replaces a per-call
    /// `range(of:options:.regularExpression)` compile.
    private static let headingPrefixRegex = try! NSRegularExpression(
        pattern: #"^#{1,6}([ \t]|$)"#
    )

    static func isHeadingLine(
        _ paragraphString: String,
        isInsideCodeBlock: Bool
    ) -> Bool {
        // Stage 0 — code-block guard.
        if isInsideCodeBlock { return false }

        // Stage 1 — cheap prefilter. CommonMark requires 1-6 `#`s followed by
        // a space, tab, or end-of-line; `#Foo` (no space) is NOT a heading.
        let trimmed = paragraphString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return false }
        let trimmedNS = trimmed as NSString
        guard
            headingPrefixRegex.firstMatch(
                in: trimmed, range: NSRange(location: 0, length: trimmedNS.length)
            ) != nil
        else {
            return false
        }

        // Stage 2 — AST parse confirms.
        let document = Markdown.Document(parsing: paragraphString)
        return document.children.contains { $0 is Markdown.Heading }
    }

    /// Walk a parsed document for top-level headings, pairing each with the
    /// NSRange of source content that falls under it (until the next equal-
    /// or-higher heading, or document end). Used by the engine's
    /// HeadingFolding service to translate the user's set of folded heading
    /// keys into runtime ranges that the renderer can collapse to zero height.
    ///
    /// Top-level only — headings nested inside list items / blockquotes /
    /// custom blocks are NOT foldable in v1. CommonMark places headings at
    /// the top level by default; nested headings are uncommon Pommora content.
    public static func foldableHeadings(
        in document: Markdown.Document,
        nsText: NSString
    ) -> [FoldedHeading] {
        let lineIndex = LineOffsetIndex(text: nsText as String)
        return foldableHeadings(in: document, nsText: nsText, lineIndex: lineIndex)
    }

    /// One-shot convenience: parses `text` and computes folded ranges in a
    /// single call. Used by tests + Pommora-side helpers that don't already
    /// have a parsed document on hand. Production hot paths should prefer
    /// the `(document:, nsText:, lineIndex:)` overload to reuse caches.
    public static func foldableHeadings(in text: String) -> [FoldedHeading] {
        let document = Markdown.Document(parsing: text)
        return foldableHeadings(in: document, nsText: text as NSString)
    }

    /// Returns the subset of `foldedHeadings` whose keys still match an
    /// existing heading in `body` (after ordinal-disambiguation by
    /// `foldableHeadings`). Stale entries — keys whose corresponding
    /// heading was renamed or deleted — are dropped.
    ///
    /// Used by `PageEditorViewModel` before save to keep `folded_headings:`
    /// from accumulating dead entries across rename cycles. The on-disk
    /// frontmatter ends up containing only keys that correspond to a real
    /// heading in the current body, no matter how many edits the user
    /// makes between saves.
    public static func reconcileFoldedHeadings(
        _ foldedHeadings: Set<String>,
        in body: String
    ) -> Set<String> {
        guard !foldedHeadings.isEmpty else { return foldedHeadings }
        let currentKeys = Set(foldableHeadings(in: body).map { $0.key })
        return foldedHeadings.intersection(currentKeys)
    }

    /// Internal overload that accepts a prebuilt `LineOffsetIndex` so the
    /// service can avoid re-walking the document text once per restyle.
    static func foldableHeadings(
        in document: Markdown.Document,
        nsText: NSString,
        lineIndex: LineOffsetIndex
    ) -> [FoldedHeading] {
        // Collect top-level headings in document order with their AST NSRanges.
        struct RawHeading {
            let level: Int
            let astRange: NSRange
        }
        var raws: [RawHeading] = []
        raws.reserveCapacity(8)
        for child in document.children {
            guard let heading = child as? Markdown.Heading else { continue }
            guard
                let astRange = SourceRangeConverter.nsRange(
                    from: heading.range, in: nsText, lineIndex: lineIndex
                )
            else { continue }
            raws.append(RawHeading(level: heading.level, astRange: astRange))
        }

        // Pair each heading with its content range via the level-stack rule:
        // for heading at index i with level N, the content spans from the end
        // of its line to the start of the next heading at level <= N (or to
        // the document end if no such heading follows).
        //
        // Decision 1 (ordinal disambiguation): the first occurrence of a
        // source line keeps the bare key (`"## Foo"`); subsequent occurrences
        // with identical source-line text get an ordinal suffix (`"## Foo [2]"`,
        // `"## Foo [3]"`, ...). Disambiguates duplicate-text headings so each
        // fold target is independent. Level prefix is part of the key already
        // (`"## A"` vs `"### A"`), so different levels with the same body text
        // get separate ordinal counters automatically.
        var result: [FoldedHeading] = []
        result.reserveCapacity(raws.count)
        var occurrenceCounts: [String: Int] = [:]
        for (i, raw) in raws.enumerated() {
            // The heading occupies a full line (`## Foo\n`). The AST range
            // covers only `## Foo` — we widen to the line range so content
            // starts cleanly on the next line.
            let headingLine = nsText.lineRange(
                for: NSRange(location: raw.astRange.location, length: 0)
            )
            let contentStart = headingLine.location + headingLine.length

            var contentEnd = nsText.length
            for j in (i + 1)..<raws.count where raws[j].level <= raw.level {
                contentEnd = raws[j].astRange.location
                break
            }

            // Bare key = exact source line stripped of its trailing newline
            // (so `"## Foo"` matches across LF / CRLF / no-trailing-newline).
            // Swift represents `\r\n` as a single extended grapheme cluster, so
            // `hasSuffix("\n")` returns false on CRLF input — the prior
            // two-step strip silently no-op'd on Windows-saved files.
            // `trimmingCharacters(in: .newlines)` handles LF, CR, CRLF, and the
            // Unicode line/paragraph separators in one pass.
            let bareKey = nsText.substring(with: headingLine)
                .trimmingCharacters(in: .newlines)
            let count = (occurrenceCounts[bareKey] ?? 0) + 1
            occurrenceCounts[bareKey] = count
            let key = count == 1 ? bareKey : "\(bareKey) [\(count)]"

            let contentRange = NSRange(
                location: contentStart,
                length: max(0, contentEnd - contentStart)
            )
            result.append(
                FoldedHeading(
                    key: key,
                    level: raw.level,
                    headingRange: headingLine,
                    contentRange: contentRange
                ))
        }
        return result
    }

    // MARK: - Active Token Indices

    static func computeActiveTokenIndices(
        selectionRange: NSRange,
        tokens: [MarkdownToken],
        in text: NSString
    ) -> Set<Int> {
        var indices: Set<Int> = []
        let caretLocation = selectionRange.location
        for (index, token) in tokens.enumerated() {
            let start = token.range.location
            let end = NSMaxRange(token.range)
            if selectionRange.length > 0 && (token.kind == .inlineLatex || token.kind == .blockLatex)
                && NSIntersectionRange(selectionRange, token.range).length > 0
            {
                indices.insert(index)
                continue
            }
            if caretLocation >= start && caretLocation < end {
                indices.insert(index)
                continue
            }
            if caretLocation == end {
                let lastIndex = end - 1
                if lastIndex >= start && lastIndex < text.length {
                    let lastChar = text.substring(with: NSRange(location: lastIndex, length: 1))
                    if lastChar != "\n" {
                        indices.insert(index)
                    }
                }
            }
        }
        return indices
    }

    // MARK: - Code Block Detection

    /// Fast: uses pre-parsed tokens
    static func isInsideCodeBlock(range: NSRange, codeTokens: [MarkdownToken]) -> Bool {
        guard !codeTokens.isEmpty else { return false }
        for token in codeTokens {
            let start = token.range.location
            let end = start + token.range.length
            if range.length == 0 {
                if range.location >= start && range.location <= end { return true }
            } else {
                if range.location < end && range.location + range.length > start { return true }
            }
        }
        return false
    }

    static func isInsideCodeBlock(location: Int, codeTokens: [MarkdownToken]) -> Bool {
        isInsideCodeBlock(range: NSRange(location: location, length: 0), codeTokens: codeTokens)
    }

    // MARK: - Token-based heading detection (draw-path optimization)

    /// Draw-path-optimized heading check: answers "is the line at `range` a
    /// heading?" from the already-parsed token stream instead of re-parsing the
    /// line's AST per fragment per repaint.
    ///
    /// Defined to be EQUIVALENT to
    /// `isHeadingLine(line, isInsideCodeBlock: isInsideCodeBlock(range:, codeTokens: blockCodeTokens))`.
    /// `HeadingTokenParityTests` pins that equivalence across the D-HEAD-1 corpus.
    ///
    /// Why the code guard is still needed: the tokenizer emits `.heading` tokens
    /// even for `#` lines INSIDE a fenced code block (its heading regex has no
    /// code-block guard — see MarkdownTokenizer.swift). A bare token-presence
    /// check would therefore wrongly fire inside code; this function re-applies
    /// the same block-code guard the renderer's Stage 0 used.
    ///
    /// - Parameters:
    ///   - range: the fragment's line range (document-relative).
    ///   - headingTokens: tokens pre-filtered to `.heading` kind.
    ///   - blockCodeTokens: tokens pre-filtered to `.codeBlock` kind (fenced/
    ///     indented blocks only — never `.inlineCode`, which may legitimately
    ///     sit on a heading line).
    static func headingTokenCovers(
        range: NSRange,
        headingTokens: [MarkdownToken],
        blockCodeTokens: [MarkdownToken]
    ) -> Bool {
        // Stage 0 — block-code guard (identical to the renderer's prior Stage 0).
        if isInsideCodeBlock(range: range, codeTokens: blockCodeTokens) {
            return false
        }
        // A heading is line-scoped and its token starts at the first `#` of the
        // line. The line is a heading iff some `.heading` token's range falls
        // within it. Intersection (not containment) because the token range
        // starts after any leading whitespace and excludes the trailing newline,
        // so it is a strict subrange of the fragment's line range.
        for token in headingTokens where NSIntersectionRange(token.range, range).length > 0 {
            return true
        }
        return false
    }

    // MARK: - Wikilink Detection

    /// Returns true when `location` falls inside an open `[[...]]` wikilink
    /// target on the same line. Scoped to the current line — wikilinks don't
    /// span lines in CommonMark/Obsidian-style usage. Used by typing-time
    /// transforms (em-/en-dash auto-format) to skip substitutions inside
    /// wikilink targets, where users sometimes include literal ` - ` or `--`
    /// as filename separators that must not be rewritten on disk.
    static func isInsideWikilink(location: Int, in text: String) -> Bool {
        let nsText = text as NSString
        guard location > 0 && location <= nsText.length else { return false }
        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let scanStart = lineRange.location
        let scanEnd = min(location, lineRange.location + lineRange.length)
        guard scanStart < scanEnd else { return false }

        var depth = 0
        var i = scanStart
        while i < scanEnd - 1 {
            let pair = nsText.substring(with: NSRange(location: i, length: 2))
            if pair == "[[" {
                depth += 1
                i += 2
            } else if pair == "]]" {
                depth = max(0, depth - 1)
                i += 2
            } else {
                i += 1
            }
        }
        return depth > 0
    }

    // MARK: - LaTeX Detection

    static func isInsideLatex(location: Int, latexTokens: [MarkdownToken]) -> Bool {
        guard !latexTokens.isEmpty else { return false }
        for token in latexTokens {
            let start = token.range.location
            let end = start + token.range.length
            if location >= start && location <= end { return true }
        }
        return false
    }
}
