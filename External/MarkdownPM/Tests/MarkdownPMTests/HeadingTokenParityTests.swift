//
//  HeadingTokenParityTests.swift
//  MarkdownPMTests
//
//  Pins the token-based heading detector (`MarkdownDetection.headingTokenCovers`)
//  to the canonical AST-based `MarkdownDetection.isHeadingLine`. If the two ever
//  disagree on any corpus line, the draw-path optimization has drifted from the
//  source of truth and this test fails. Mirrors the D-HEAD-1 corpus.
//
//  Loop-based (not `@Test(arguments:)`): the package's existing suites
//  (TokenizerCorpus, HeadingSizeCorpus) use plain `@Test` with in-body
//  assertions — this file follows that established idiom rather than
//  introducing a parametrized-test syntax the package doesn't use elsewhere.
//

import Foundation
import Testing

@testable import MarkdownPM

@Suite("HeadingTokenParity")
struct HeadingTokenParityTests {

    /// Tokenize `text`, then ask the token-based detector whether the line
    /// containing `lineLocation` is a heading — applying the same code-block
    /// guard the renderer applies.
    private func tokenSaysHeading(_ text: String, lineLocation: Int = 0) -> Bool {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let headingTokens = tokens.filter { $0.kind == .heading }
        let blockCodeTokens = tokens.filter { $0.kind == .codeBlock }
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
        return MarkdownDetection.headingTokenCovers(
            range: lineRange,
            headingTokens: headingTokens,
            blockCodeTokens: blockCodeTokens
        )
    }

    /// The canonical answer for a single-line input.
    private func astSaysHeading(_ line: String, isInsideCodeBlock: Bool = false) -> Bool {
        MarkdownDetection.isHeadingLine(line, isInsideCodeBlock: isInsideCodeBlock)
    }

    @Test("Single-line heading corpus: token detector matches isHeadingLine")
    func tokenMatchesAST() {
        let corpus = [
            "## Foo",          // space → heading
            "##\tFoo",         // tab separator → heading
            "###",             // bare hashes at EOL → heading
            "#Foo",            // no separator → NOT a heading
            "####### x",       // 7 hashes → NOT a heading (max 6)
            "   ## Foo",       // 3 leading spaces → heading
            "    ## Foo",      // 4 leading spaces → indented code, NOT a heading
            "\t## Foo",        // leading tab → indented code, NOT a heading
            "Just prose",      // plain text → NOT a heading
            "",                // empty → NOT a heading
        ]
        for line in corpus {
            #expect(
                tokenSaysHeading(line) == astSaysHeading(line),
                "Parity mismatch for line: \(line.debugDescription)"
            )
        }
    }

    @Test("`# Foo` inside a fenced code block is NOT a heading (code guard)")
    func headingInsideCodeBlockSuppressed() {
        let text = "```\n# Foo\n```"
        let nsText = text as NSString
        let fooLocation = nsText.range(of: "# Foo").location
        #expect(tokenSaysHeading(text, lineLocation: fooLocation) == false)
    }

    @Test("Heading after a code block IS a heading")
    func headingAfterCodeBlock() {
        let text = "```\ncode\n```\n## Real"
        let nsText = text as NSString
        let realLocation = nsText.range(of: "## Real").location
        #expect(tokenSaysHeading(text, lineLocation: realLocation) == true)
    }
}
