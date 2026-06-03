//
//  PageTextStatsTests.swift
//  PommoraTests
//

import Foundation
import Testing
import MarkdownPM

@testable import Pommora

struct PageTextStatsTests {

    // MARK: - MarkdownPlainText (rendered-prose extraction)

    @Test func plainTextStripsSyntax() {
        let md = "# Title\n\nSome **bold** and `code` and [a link](http://x).\n"
        let plain = MarkdownPlainText.extract(from: md)
        #expect(plain.contains("Title"))
        #expect(plain.contains("bold"))
        #expect(plain.contains("code"))
        #expect(plain.contains("a link"))
        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
        #expect(!plain.contains("http://x"))  // link URL dropped, label kept
    }

    @Test func codeBlockDoesNotFuseAdjacentWords() {
        // The word after a fenced code block must not fuse with the block's
        // last word during counting (regression: visitCodeBlock skipped the
        // block separator).
        let md = "alpha\n\n```\ncode\n```\n\nbravo\n"
        let plain = MarkdownPlainText.extract(from: md)
        #expect(!plain.contains("codebravo"))

        var words = 0
        plain.enumerateSubstrings(in: plain.startIndex..., options: .byWords) { _, _, _, _ in
            words += 1
        }
        #expect(words == 3)  // alpha, code, bravo
    }

    // MARK: - PageTextStats

    @Test func countsFromBody() {
        // "# Heading\n\nOne two three.\n"
        //   raw lines (trailing newline stripped): "# Heading" | "" | "One two three." → 3
        //   prose: "Heading\nOne two three." → 4 words; characters exclude the
        //   structural block-separator newline → "HeadingOne two three." = 21
        let body = "# Heading\n\nOne two three.\n"
        let s = PageTextStats(body: body)
        #expect(s.lines == 3)
        #expect(s.words == 4)
        #expect(s.characters == 21)
    }

    @Test func emptyBodyIsZero() {
        let s = PageTextStats(body: "")
        #expect(s == .empty)
        #expect(s.lines == 0 && s.words == 0 && s.characters == 0)
    }
}
