//
//  MarkdownDetection.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Helper checks for questions like "is the cursor inside code or LaTeX?"
// and "which Markdown part is currently active?".
import Foundation
import Markdown

enum MarkdownDetection {

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

    /// Slow: parses tokens each call
    static func isInsideCodeBlock(range: NSRange, in text: String) -> Bool {
        let codeTokens = MarkdownTokenizer.parseTokens(in: text).filter {
            $0.kind == .codeBlock || $0.kind == .inlineCode
        }
        return isInsideCodeBlock(range: range, codeTokens: codeTokens)
    }

    static func isInsideCodeBlock(location: Int, in text: String) -> Bool {
        isInsideCodeBlock(range: NSRange(location: location, length: 0), in: text)
    }

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

    // MARK: - LaTeX Detection

    static func isInsideLatex(location: Int, in text: String) -> Bool {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let latexTokens = tokens.filter { $0.kind == .inlineLatex || $0.kind == .blockLatex }
        return isInsideLatex(location: location, latexTokens: latexTokens)
    }

    static func isInsideLatex(location: Int, latexTokens: [MarkdownToken]) -> Bool {
        guard !latexTokens.isEmpty else { return false }
        for token in latexTokens {
            let start = token.range.location
            let end = start + token.range.length
            if location >= start && location <= end { return true }
        }
        return false
    }

    static func isInsideInlineLatex(range: NSRange, in text: String) -> Bool {
        let latexTokens = MarkdownTokenizer.parseTokens(in: text).filter { $0.kind == .inlineLatex }
        return isInsideInlineLatex(range: range, latexTokens: latexTokens)
    }

    static func isInsideInlineLatex(location: Int, in text: String) -> Bool {
        isInsideInlineLatex(range: NSRange(location: location, length: 0), in: text)
    }

    static func isInsideInlineLatex(range: NSRange, latexTokens: [MarkdownToken]) -> Bool {
        guard !latexTokens.isEmpty else { return false }
        for token in latexTokens {
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

    static func isInsideInlineLatex(location: Int, latexTokens: [MarkdownToken]) -> Bool {
        isInsideInlineLatex(range: NSRange(location: location, length: 0), latexTokens: latexTokens)
    }
}
