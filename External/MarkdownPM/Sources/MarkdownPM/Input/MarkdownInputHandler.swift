//
//  MarkdownInputHandler.swift
//  MarkdownPM
//
//  Created by Luca Chen on 18.02.26.
//

// Handles Markdown typing shortcuts, like continuing lists and keeping block
// LaTeX on its own line while you type.
import AppKit

@MainActor
enum MarkdownInputHandler {

    static func handleListInsertion(
        textView: NSTextView, affectedCharRange: NSRange, replacementString: String?
    ) -> Bool {
        return MarkdownLists.handleInsertion(
            textView: textView, affectedCharRange: affectedCharRange, replacementString: replacementString)
    }

    // MARK: - Character-Pair Auto-Pair (Pommora addition)
    //
    // Mirrors Bear/Notion/Obsidian behavior: typing `**`/`__`/`[[`/`` `` ``
    // automatically inserts the matching close marker with the caret between.
    // Triggers on the SECOND character of the pair (so the user has already
    // typed the first one and we react to the second). Suppressed inside
    // fenced code blocks / inline code so literal markers aren't molested.
    //
    // v0.2.7 ships the basic insertion behavior. Selection-wrap (typing `*`
    // with text selected wraps the selection in `*text*`) and auto-exit-on-
    // whitespace (typing space at a fresh-pair boundary jumps past the close
    // marker) defer to v0.2.7.1 polish.

    /// Inserts the matching close marker when the user types the second
    /// character of a Markdown pair (`**`, `__`, `[[`, `` `` ``).
    /// Returns true if the insertion was handled — caller should return
    /// false from `shouldChangeTextIn` to suppress the default behavior.
    static func handleCharacterPairAutoPair(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?,
        codeTokens: [MarkdownToken]? = nil
    ) -> Bool {
        guard let typed = replacementString,
            typed.utf16.count == 1,
            affectedCharRange.length == 0,
            affectedCharRange.location > 0
        else { return false }

        // Map typed char → close marker. Empty closeMarker means not a pair char.
        let closeMarker: String
        switch typed {
        case "*": closeMarker = "**"
        case "_": closeMarker = "__"
        case "[": closeMarker = "]]"
        case "(": closeMarker = "))"
        case "`": closeMarker = "``"
        default: return false
        }

        let nsText = textView.string as NSString
        let precedingCharRange = NSRange(location: affectedCharRange.location - 1, length: 1)
        guard precedingCharRange.location + precedingCharRange.length <= nsText.length else { return false }
        let precedingChar = nsText.substring(with: precedingCharRange)

        // Trigger only if preceding char matches the typed char — i.e. user
        // is completing a `**`/`__`/`[[`/`` `` `` sequence.
        guard precedingChar == typed else { return false }

        // Suppress inside code blocks / inline code so literal markers in
        // code samples aren't paired. Lazily compute code tokens if caller
        // didn't pass them in.
        // Phase 3 — prefer caller-supplied tokens; otherwise hit the
        // coordinator's cached parse rather than re-tokenizing the string.
        let inCode: Bool
        if let codeTokens {
            inCode = MarkdownDetection.isInsideCodeBlock(
                range: affectedCharRange, codeTokens: codeTokens)
        } else if let coordinator = textView.delegate as? NativeTextViewCoordinator {
            inCode = coordinator.isInsideCode(range: affectedCharRange, in: textView.string)
        } else {
            inCode = false
        }
        if inCode { return false }

        // Also suppress if the NEXT character is already the close marker —
        // user is typing into an existing pair; double-insert would corrupt.
        let nextCharLocation = affectedCharRange.location
        if nextCharLocation < nsText.length {
            let nextChar = nsText.substring(with: NSRange(location: nextCharLocation, length: 1))
            // For brackets the close char is `]`; otherwise close char is the typed char.
            let closeFirstChar = (typed == "[") ? "]" : typed
            if nextChar == closeFirstChar { return false }
        }

        // Insert: typed char + close marker. Caret lands right after the
        // typed char, before the close marker — `**|**`, `[[|]]`, etc.
        let inserted = typed + closeMarker
        let cursorAfter = affectedCharRange.location + typed.utf16.count
        insertTextProgrammatically(
            textView,
            text: inserted,
            at: affectedCharRange,
            cursorAfter: cursorAfter
        )
        return true
    }

    /// Companion to `handleCharacterPairAutoPair`: when the user presses
    /// backspace inside an empty pair (`*|*`, `**|**`, `[[|]]`, `` `|` ``,
    /// `` ``|`` ``), delete BOTH halves so backing out of a freshly-paired
    /// region behaves symmetrically with typing into it. Standard Notion/
    /// Obsidian/Bear behavior.
    ///
    /// Triggers when:
    /// - deletion of a single character (replacementString empty, length 1)
    /// - char being deleted is one of `* _ [ ``
    /// - char immediately after the deletion point is the matching close
    ///   (same char for `* _ ` ``; `]` for `[`)
    ///
    /// Returns true if the unpair was handled — caller should return false
    /// from `shouldChangeTextIn` to suppress the default behavior.
    static func handleCharacterPairAutoDelete(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Only backspace-style deletions: empty replacement on a single-char
        // range. Larger selections / multi-char deletes / inserts skip this.
        guard let replacement = replacementString, replacement.isEmpty,
            affectedCharRange.length == 1
        else { return false }

        let nsText = textView.string as NSString
        let deleteStart = affectedCharRange.location
        let deleteEnd = deleteStart + 1
        guard deleteEnd < nsText.length else { return false }

        let deletedChar = nsText.substring(with: NSRange(location: deleteStart, length: 1))
        let nextChar = nsText.substring(with: NSRange(location: deleteEnd, length: 1))

        // Match deleted-char → expected matching-close-char.
        let expectedCloseChar: String
        switch deletedChar {
        case "*": expectedCloseChar = "*"
        case "_": expectedCloseChar = "_"
        case "[": expectedCloseChar = "]"
        case "(": expectedCloseChar = ")"
        case "`": expectedCloseChar = "`"
        default: return false
        }
        guard nextChar == expectedCloseChar else { return false }

        // Extend deletion to swallow the close char too. Both standard
        // delete (deleteStart) AND the matching close (deleteEnd) go away
        // in a single edit so undo treats it as one step.
        let combinedRange = NSRange(location: deleteStart, length: 2)
        insertTextProgrammatically(
            textView,
            text: "",
            at: combinedRange,
            cursorAfter: deleteStart
        )
        return true
    }

    // MARK: - Block LaTeX Auto-Wrap

    private static func insertTextProgrammatically(
        _ textView: NSTextView, text: String, at range: NSRange, cursorAfter: Int
    ) {
        if let coord = textView.delegate as? MarkdownPMEditor.Coordinator {
            coord.isProgrammaticEdit = true
        }
        textView.insertText(text, replacementRange: range)
        if let coord = textView.delegate as? MarkdownPMEditor.Coordinator {
            coord.isProgrammaticEdit = false
        }
        textView.setSelectedRange(NSRange(location: cursorAfter, length: 0))
    }

    /// Ensures block LaTeX ($$...$$) stays on its own line by automatically inserting newlines
    /// when typing directly before or after a block LaTeX token.
    /// Returns true if the insertion was handled (caller should return false from shouldChangeTextIn).
    static func handleBlockLatexAutoWrap(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?,
        blockLatexTokens: [MarkdownToken]
    ) -> Bool {
        return handleBlockAutoWrap(
            textView: textView, affectedCharRange: affectedCharRange,
            replacementString: replacementString, tokens: blockLatexTokens)
    }

    /// Ensures image embeds (![[...]]) stay on their own line by automatically inserting newlines.
    static func handleImageEmbedAutoWrap(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?,
        imageEmbedTokens: [MarkdownToken]
    ) -> Bool {
        return handleBlockAutoWrap(
            textView: textView, affectedCharRange: affectedCharRange,
            replacementString: replacementString, tokens: imageEmbedTokens)
    }

    /// Shared auto-wrap logic: ensures a block-level token stays on its own line.
    private static func handleBlockAutoWrap(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?,
        tokens: [MarkdownToken]
    ) -> Bool {
        guard let replacement = replacementString,
            !replacement.isEmpty,
            replacement != "\n"
        else { return false }

        let text = textView.string as NSString
        let newlineChar = UInt16(("\n" as Character).asciiValue!)

        for token in tokens {
            let tokenEnd = NSMaxRange(token.range)

            // Typing right after closing marker
            if affectedCharRange.location == tokenEnd {
                if tokenEnd < text.length && text.character(at: tokenEnd) == newlineChar {
                    insertTextProgrammatically(
                        textView, text: replacement,
                        at: NSRange(location: tokenEnd + 1, length: 0),
                        cursorAfter: tokenEnd + 1 + replacement.utf16.count)
                } else {
                    insertTextProgrammatically(
                        textView, text: "\n" + replacement,
                        at: affectedCharRange,
                        cursorAfter: affectedCharRange.location + 1 + replacement.utf16.count)
                }
                return true
            }

            // Typing right before opening marker
            if affectedCharRange.location == token.range.location {
                if token.range.location > 0 && text.character(at: token.range.location - 1) == newlineChar {
                    insertTextProgrammatically(
                        textView, text: replacement,
                        at: NSRange(location: token.range.location - 1, length: 0),
                        cursorAfter: token.range.location - 1 + replacement.utf16.count)
                } else {
                    insertTextProgrammatically(
                        textView, text: replacement + "\n",
                        at: affectedCharRange,
                        cursorAfter: affectedCharRange.location + replacement.utf16.count)
                }
                return true
            }
        }

        return false
    }
}
