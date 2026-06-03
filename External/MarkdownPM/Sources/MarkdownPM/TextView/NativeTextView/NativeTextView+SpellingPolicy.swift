//
//  NativeTextView+SpellingPolicy.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  Spell-check suppression inside code spans, code blocks, LaTeX, and other
//  coordinator-flagged tokens — anything that should be exempt from the
//  default underline pass.
//

import AppKit

extension NativeTextView {
    override func setSpellingState(_ value: Int, range charRange: NSRange) {
        let coordinator = delegate as? NativeTextViewCoordinator
        if value != 0 {
            if self.string.contains("`") {
                let inCode = coordinator?.isInsideCode(range: charRange, in: self.string) ?? false
                if inCode {
                    return
                }
            }
            if self.string.contains("$") {
                let inLatex = coordinator?.isInsideLatex(location: charRange.location, in: self.string) ?? false
                if inLatex {
                    return
                }
            }
            let inSpellcheckSuppressedToken = coordinator?.isInsideSpellcheckSuppressedToken(range: charRange, in: self.string) ?? false
            if inSpellcheckSuppressedToken {
                return
            }
        }
        super.setSpellingState(value, range: charRange)
    }
}
