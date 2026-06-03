import AppKit
import Testing
@testable import MarkdownPM

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
private func pressSpace(on source: String, caretAt caret: Int) -> (handled: Bool, result: String, caret: Int) {
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    tv.string = source
    tv.setSelectedRange(NSRange(location: caret, length: 0))
    let handled = !MarkdownLists.handleInsertion(
        textView: tv, affectedCharRange: NSRange(location: caret, length: 0), replacementString: " ")
    if !handled {
        let ns = tv.string as NSString
        tv.string = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: " ")
        tv.setSelectedRange(NSRange(location: caret + 1, length: 0))
    }
    return (handled, tv.string, tv.selectedRange().location)
}

// MARK: - Enter continuation

@MainActor
struct EnterContinuationTests {
    @Test func bulletStaysBullet() {
        let r = pressEnter(on: "- task", caretAt: 6)
        #expect(r.result == "- task\n- ")
    }
    @Test func emptyBracketRawContinuesAsBullet() {
        // A RAW empty `-[]` (not canonicalized — e.g. pasted/external) is NOT a
        // checkbox, so Enter continues it as a plain bullet. Typed `-[]` never
        // reaches this: the space-canonicalization rewrites it to `- [ ]` first.
        let r = pressEnter(on: "-[] task", caretAt: 8)
        #expect(r.result == "-[] task\n- ")
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

// MARK: - Shorthand → GFM canonicalization (on the space that starts content)

@MainActor
struct CheckboxCanonicalizationTests {
    @Test func emptyShorthandCanonicalizes() {
        // `-[]` + space → GFM `- [ ] `; caret lands AFTER the trailing space.
        let r = pressSpace(on: "-[]", caretAt: 3)
        #expect(r.handled)
        #expect(r.result == "- [ ] ")
        #expect(r.caret == 6)
    }
    @Test func spacedShorthandCanonicalizes() {
        let r = pressSpace(on: "-[ ]", caretAt: 4)
        #expect(r.result == "- [ ] ")
        #expect(r.caret == 6)
    }
    @Test func checkedShorthandCanonicalizes() {
        let r = pressSpace(on: "-[x]", caretAt: 4)
        #expect(r.result == "- [x] ")
        #expect(r.caret == 6)
    }
    @Test func uppercaseCheckedCanonicalizesToLowercase() {
        let r = pressSpace(on: "-[X]", caretAt: 4)
        #expect(r.result == "- [x] ")
    }
    @Test func nestedShorthandPreservesIndent() {
        let r = pressSpace(on: "\t-[]", caretAt: 4)
        #expect(r.result == "\t- [ ] ")
        #expect(r.caret == 7)
    }
    @Test func gfmCheckboxSpaceNotRetransformed() {
        // Already GFM: a space after `- [ ]` is a plain space, not re-transformed.
        let r = pressSpace(on: "- [ ]", caretAt: 5)
        #expect(!r.handled)
        #expect(r.result == "- [ ] ")
    }
    @Test func plainTextWithBracketsUntouched() {
        // Not a line-leading marker → no transform.
        let r = pressSpace(on: "see -[] here", caretAt: 7)
        #expect(!r.handled)
        #expect(r.result == "see -[]  here")
    }
}
