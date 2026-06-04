//
//  ConstructLineStartsParityTests.swift
//  MarkdownPMTests
//
//  Pins the per-document construct precompute (MarkdownDetection.constructLineStarts)
//  to the canonical per-line detectors (isThematicBreakLine / isBlockquoteLine /
//  isDashBulletLine). If the precompute ever disagrees with calling the detector
//  on a line directly, the draw-path optimization has drifted and this fails.
//

import Foundation
import Testing

@testable import MarkdownPM

@Suite("ConstructLineStartsParity")
struct ConstructLineStartsParityTests {

    // MARK: isBlockquoteLine (Task 1)

    @Test("isBlockquoteLine matches the gate + AST rule")
    func blockquoteDetector() {
        #expect(MarkdownDetection.isBlockquoteLine("> quote", isInsideCodeBlock: false) == true)
        #expect(MarkdownDetection.isBlockquoteLine(">\tquote", isInsideCodeBlock: false) == true)
        #expect(MarkdownDetection.isBlockquoteLine("  > indented quote", isInsideCodeBlock: false) == true)
        #expect(MarkdownDetection.isBlockquoteLine(">no space", isInsideCodeBlock: false) == false)
        #expect(MarkdownDetection.isBlockquoteLine("not a quote", isInsideCodeBlock: false) == false)
        #expect(MarkdownDetection.isBlockquoteLine("> quote", isInsideCodeBlock: true) == false)
        #expect(MarkdownDetection.isBlockquoteLine("", isInsideCodeBlock: false) == false)
    }

    // MARK: constructLineStarts parity (Task 2)

    /// For each line in `text`, the precompute's membership must equal calling
    /// the per-line detector on that line directly (with the same code guard).
    private func assertParity(_ text: String) {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let blockCodeTokens = tokens.filter { $0.kind == .codeBlock }
        let nsText = text as NSString
        let result = MarkdownDetection.constructLineStarts(in: nsText, blockCodeTokens: blockCodeTokens)

        var pos = 0
        while pos < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
            let line = nsText.substring(with: lineRange)
            let insideCode = MarkdownDetection.isInsideCodeBlock(range: lineRange, codeTokens: blockCodeTokens)
            let start = lineRange.location
            #expect(result.thematicBreaks.contains(start)
                == MarkdownDetection.isThematicBreakLine(line, isInsideCodeBlock: insideCode),
                "HR parity at \(start) in \(text.debugDescription)")
            #expect(result.blockquotes.contains(start)
                == MarkdownDetection.isBlockquoteLine(line, isInsideCodeBlock: insideCode),
                "BQ parity at \(start) in \(text.debugDescription)")
            #expect(result.dashBullets.contains(start)
                == MarkdownDetection.isDashBulletLine(line, isInsideCodeBlock: insideCode),
                "Bullet parity at \(start) in \(text.debugDescription)")
            let next = NSMaxRange(lineRange)
            if next <= pos { break }
            pos = next
        }
    }

    @Test("constructLineStarts matches per-line detectors across a mixed corpus")
    func precomputeParity() {
        assertParity("# Heading\n\n> a quote\n> second line\n\n---\n\n- bullet one\n- bullet two\n\nplain text\n")
        assertParity("```\n---\n> not a quote in code\n- not a bullet\n```\n\n---\n")  // code-fenced constructs suppressed
        assertParity("Foo\n---\n")  // setext-adjacent `---` must still be HR (no setext guard)
        assertParity("")            // empty doc
        assertParity("> quote with no trailing newline")
    }
}
