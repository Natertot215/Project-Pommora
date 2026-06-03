//
//  NSTextLayoutFragment+NSRange.swift
//  MarkdownEngine
//
//  Shared helper for converting a fragment's `rangeInElement` into a
//  document-relative `NSRange`. Both the renderer
//  (`MarkdownTextLayoutFragment`) and the hover handler
//  (`NativeTextView+HeadingFoldHover`) need this; previously each shipped
//  its own implementation (L2 violation). The extension reads via the
//  standard `textContentManager → NSTextContentStorage` chain.
//

import AppKit

extension NSTextLayoutFragment {
    /// Document-relative NSRange for this fragment's content, or `nil` if the
    /// content manager isn't an `NSTextContentStorage` (atypical) or the range
    /// doesn't resolve.
    var nsRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage
        else { return nil }
        let docStart = tcs.documentRange.location
        let start = tcs.offset(from: docStart, to: rangeInElement.location)
        let end = tcs.offset(from: docStart, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
