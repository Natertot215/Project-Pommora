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
/// HARNESS NOTE (Phase 3 / Task 3.5 landed): `MarkdownListHandler.handleInsertion`
/// now routes the dash transforms' code carve-out through the coordinator
/// delegate's CACHED parse (`coordinator?.isInsideCode(...) ?? false`) instead of
/// re-reading `textView.string`. This suite keeps the delegate-less bare host —
/// wiring a live `NativeTextViewCoordinator` as `tv.delegate` fires its full
/// restyle/selection pipeline on every `performEdit` (`didChangeText()` +
/// `setSelectedRange`), which force-unwraps layout infrastructure a bare
/// programmatic NSTextView lacks → SIGTRAP (Suite E). The already-landed, passing
/// input-transform suites (EnterContinuationTests, CheckboxCanonicalizationTests)
/// use the same bare host. CONSEQUENCE: with no delegate, the carve-out coalesces
/// to `false`, so the transform-level code-carve-out goldens can no longer pass
/// honestly here — they were removed and the carve-out's DETECTION is re-pinned
/// read-only in `ParseSpineTests.cacheRoutedCodeBlockCarveOutDetection` (see the
/// "code carve-out" MARK below). Every other transform here is
/// delegate-independent and is unaffected by the rewire.
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
    // HARNESS LIMITATION (Phase 3 / Task 3.5): the dash transforms' code carve-out
    // no longer reads `textView.string` directly — `MarkdownListHandler.swift`
    // now routes code-block detection through the coordinator delegate's CACHED
    // parse (`coordinator?.isInsideCode(...) ?? false`). This bare host has no
    // delegate (wiring a live coordinator fires its restyle/selection pipeline on
    // every `performEdit` → SIGTRAP on a windowless NSTextView — Suite E), so the
    // carve-out coalesces to `false` here and the transform-level
    // `dashSkipsInsideClosedCode` golden could no longer pass HONESTLY. It and its
    // companion `dashFiresInsideOpenFence` were therefore REMOVED.
    //
    // The carve-out's DETECTION — exactly what 3.5 changed — is now pinned in
    // `ParseSpineTests.cacheRoutedCodeBlockCarveOutDetection`, which drives the
    // read-only `coordinator.isInsideCode(range:in:)` cache path (safe per Tasks
    // 3.1/3.3): CLOSED fence → code, OPEN fence → not code. That is the honest
    // guard for the rewired behavior. All other transforms above (em-/en-dash,
    // arrows, bracket-skip, `enDashSkipsWikilink`) are delegate-independent and
    // stay pinned here unchanged.
}
