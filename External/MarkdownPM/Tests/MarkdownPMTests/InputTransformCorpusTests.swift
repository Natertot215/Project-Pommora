import AppKit
import Testing

@testable import MarkdownPM

/// Byte-level golden for the input transforms in MarkdownLists.handleInsertion.
///
/// Pins the two byte-changing dash transforms + arrows + bracket-skip verbatim
/// before any Phase-6 tidy. Smart-quotes is delegated to macOS (NOT an engine
/// transform) and auto-dash is forced OFF — both documented, neither tested as
/// engine behavior here.
///
/// HARNESS NOTE (plan-vs-reality adaptation — see report): the plan called for a
/// delegate-backed host (a real `NativeTextViewCoordinator` set as `tv.delegate`)
/// "mirroring the Phase-3 makeCoordinator harness" so the transforms would run
/// against the production *cached* code-block query. That harness does not exist
/// yet: (a) no `ParseSpineTests.makeCoordinator` has landed, and (b) the Phase-3
/// rewire of `MarkdownListHandler.swift:381/:416` to a cached query has NOT
/// happened — both call sites still read `textView.string` directly via
/// `MarkdownDetection.isInsideCodeBlock(location:in:)`. So the delegate has zero
/// effect on what these goldens characterize today; `handleInsertion` (358–898)
/// references neither the coordinator nor any cache. Wiring a live coordinator as
/// delegate instead fires its full restyle/selection pipeline on every
/// `performEdit` (`didChangeText()` + `setSelectedRange`), which force-unwraps
/// layout infrastructure a bare programmatic NSTextView lacks → SIGTRAP. The
/// already-landed, passing input-transform suites (EnterContinuationTests,
/// CheckboxCanonicalizationTests) use the same delegate-less bare host this one
/// does. WHEN PHASE 3 LANDS the cached code-block path, re-wire `makeHost` to a
/// delegate-backed coordinator and re-pin `dashSkipsInsideCode` against it — that
/// re-pin is the guard the plan intended, deferred until the path it guards
/// exists.
@MainActor
struct InputTransformCorpusTests {

    /// Build a bare NSTextView host with the source loaded and caret set.
    /// `handleInsertion` reads `textView.string` (+ `.configuration` defaults)
    /// directly, so no delegate is needed to exercise the transforms today.
    private func makeHost(_ source: String, caret: Int) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = source
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        return tv
    }

    /// Type `replacement` at `caret` into `source`; return the resulting
    /// string + caret. Mirrors EnterContinuationTests.pressSpace/pressEnter but
    /// over the delegate-backed host.
    private func type(
        _ replacement: String, on source: String, caretAt caret: Int
    ) -> (handled: Bool, result: String, caret: Int) {
        let tv = makeHost(source, caret: caret)
        let handled = !MarkdownLists.handleInsertion(
            textView: tv,
            affectedCharRange: NSRange(location: caret, length: 0),
            replacementString: replacement)
        if !handled {
            let ns = tv.string as NSString
            tv.string = ns.replacingCharacters(
                in: NSRange(location: caret, length: 0), with: replacement)
            tv.setSelectedRange(
                NSRange(location: caret + (replacement as NSString).length, length: 0))
        }
        return (handled, tv.string, tv.selectedRange().location)
    }

    // MARK: - (3) `--` → em-dash (fires on the NEXT non-dash char)

    @Test("Typing a letter after `--` converts to em-dash")
    func emDash() {
        // "a--" then type "b" → "a—b"
        let r = type("b", on: "a--", caretAt: 3)
        #expect(r.result == "a—b")
    }

    @Test("`---` (HR) is preserved: 3rd dash does not em-dash")
    func emDashPreservesHR() {
        // "a--" then type "-" → the em-dash collision guard checks text[N-3];
        // a third dash keeps `---` intact (HR), no em-dash.
        let r = type("-", on: "a--", caretAt: 3)
        #expect(r.result == "a---")
    }

    // MARK: - (4) spaced ` - ` → en-dash (fires on the 2nd space)

    @Test("Spaced ` - ` then a space converts to en-dash")
    func enDash() {
        // "9 -" then type " " → "9 – " (en-dash + trailing space)
        let r = type(" ", on: "9 -", caretAt: 3)
        #expect(r.result == "9 – ")
    }

    @Test("En-dash carve-out: ` - ` inside a [[wikilink]] is NOT rewritten")
    func enDashSkipsWikilink() {
        // Inside `[[Mon - Fri` the en-dash transform must not fire — filenames
        // with ` - ` separators stay literal (isInsideWikilink guard).
        let r = type(" ", on: "[[Mon -", caretAt: 7)
        #expect(r.result == "[[Mon - ")  // literal hyphen preserved
    }

    // MARK: - (5) en→em promotion

    @Test("Typing `-` adjacent to an en-dash promotes it to em-dash")
    func enToEmPromotion() {
        // "a–" (en-dash at index 1) then type "-" → "a—"
        let r = type("-", on: "a\u{2013}", caretAt: 2)
        #expect(r.result == "a—")
    }

    // MARK: - (6) arrows
    //
    // RECONCILIATION (plan-vs-actual): the plan typed a trailing char AFTER a
    // pre-existing `->` / `<-` and expected the arrow to form. It does NOT — the
    // arrow transforms fire only on the keystroke that COMPLETES the sequence:
    // `->`→`→` fires when `>` is typed after `-` (Case C, MarkdownListHandler
    // :445), and `<-`→`←` fires when `-` is typed after `<` (:455). Typing any
    // other char after an already-complete arrow hits the single-char fast-path
    // filter (:395-401) and is left literal. Both behaviors pinned below.

    @Test("`->` completes to → on the typed `>`")
    func rightArrow() {
        // "a-" then type ">" → the `>` completes the arrow: `a→` (caret after).
        let r = type(">", on: "a-", caretAt: 2)
        #expect(r.result == "a→")
        #expect(r.caret == 2)
    }

    @Test("Typing a char after a complete `->` leaves it literal (fast-path)")
    func rightArrowLiteralAfterComplete() {
        // `->` already in buffer; typing `x` hits the fast-path → no transform.
        let r = type("x", on: "a->", caretAt: 3)
        #expect(r.result == "a->x")
    }

    @Test("`<-` completes to ← on the typed `-`")
    func leftArrow() {
        // "a<" then type "-" → the `-` after `<` swaps to `←` (caret after).
        let r = type("-", on: "a<", caretAt: 2)
        #expect(r.result == "a←")
        #expect(r.caret == 2)
    }

    @Test("Typing a char after a complete `<-` leaves it literal (fast-path)")
    func leftArrowLiteralAfterComplete() {
        // `<-` already in buffer; typing `x` hits the fast-path → no transform.
        let r = type("x", on: "a<-", caretAt: 3)
        #expect(r.result == "a<-x")
    }

    // MARK: - (7) bracket-skip on Enter

    @Test("Enter between a matched [ ] pair jumps past the closer (no newline)")
    func bracketSkipEnter() {
        // caret between `[` and `]` in "x[]" at index 2; Enter jumps to index 3.
        let tv = makeHost("x[]", caret: 2)
        let handled = !MarkdownLists.handleInsertion(
            textView: tv,
            affectedCharRange: NSRange(location: 2, length: 0),
            replacementString: "\n")
        #expect(handled)
        #expect(tv.string == "x[]")  // no newline inserted
        #expect(tv.selectedRange().location == 3)  // caret past `]`
    }

    // MARK: - code carve-out (shared by dash transforms)
    //
    // RECONCILIATION (plan-vs-actual): the plan used an UNTERMINATED fence
    // ("```\na--") and expected the dash transform to be carved out. It is NOT —
    // the carve-out keys on `MarkdownDetection.isInsideCodeBlock`, which returns
    // false for an open/incomplete fence (the tokenizer emits no `.codeBlock`
    // token spanning the caret), so the em-dash fires. The carve-out only
    // engages when the caret sits inside a CLOSED fenced block. Both pinned.

    @Test("Dash transform skips inside a CLOSED fenced code block")
    func dashSkipsInsideClosedCode() {
        // Caret inside a complete ```...``` block, right after `a--`. The
        // isInsideCodeBlock guard fires → em-dash suppressed, dashes stay literal.
        let source = "```\na--\n```"
        let r = type("b", on: source, caretAt: 7)  // just after the second `-`
        #expect(r.result == "```\na--b\n```")  // literal, no em-dash
    }

    @Test("Dash transform is NOT carved out inside an UNTERMINATED fence")
    func dashFiresInsideOpenFence() {
        // Open fence → isInsideCodeBlock returns false → em-dash DOES fire.
        // Current behavior; would flip if open fences ever counted as code.
        let source = "```\na--"
        let r = type("b", on: source, caretAt: (source as NSString).length)
        #expect(r.result == "```\na—b")  // em-dash applied
    }
}
