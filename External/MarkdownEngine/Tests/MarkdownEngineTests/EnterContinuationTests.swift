import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
private func pressEnter(on source: String, caretAt caret: Int) -> (handled: Bool, result: String) {
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    tv.string = source
    tv.setSelectedRange(NSRange(location: caret, length: 0))
    let handled = !MarkdownLists.handleInsertion(
        textView: tv, affectedCharRange: NSRange(location: caret, length: 0), replacementString: "\n")
    if !handled {
        let ns = tv.string as NSString
        tv.string = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: "\n")
    }
    return (handled, tv.string)
}

@MainActor
struct EnterContinuationTests {
    @Test func bulletStaysBullet() {
        let r = pressEnter(on: "- task", caretAt: 6)
        #expect(r.result == "- task\n- ")
    }
    @Test func emptyBracketContinuesAsCheckbox() {
        // Regression (twice): the empty Pommora shorthand `-[]` — the form
        // auto-pair produces — must continue as a checkbox, not a plain `- `
        // bullet. Depends on BOTH the `[ xX]?` optional inner char in
        // hasCheckbox AND the AST marker-space normalization in
        // detectListContext. Both have been dropped by mistake before.
        let r = pressEnter(on: "-[] task", caretAt: 8)
        #expect(r.result == "-[] task\n- [ ] ")
    }
    @Test func shorthandUncheckedContinuesAsCheckbox() {
        let r = pressEnter(on: "-[ ] task", caretAt: 9)
        #expect(r.result == "-[ ] task\n- [ ] ")
    }
    @Test func shorthandCheckedContinuesAsCheckbox() {
        let r = pressEnter(on: "-[x] task", caretAt: 9)
        #expect(r.result == "-[x] task\n- [ ] ")
    }
    @Test func gfmCheckboxContinuesAsCheckbox() {
        let r = pressEnter(on: "- [ ] task", caretAt: 10)
        #expect(r.result == "- [ ] task\n- [ ] ")
    }
}
