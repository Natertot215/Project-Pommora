//
//  NativeTextViewCoordinator+TextDelegate.swift
//  MarkdownPM
//
//  Created by Luca Chen on 16.03.26.
//
//  The hot NSTextViewDelegate path: keystroke handling, selection-change
//  reaction, link-click forwarding, and the typing-attributes shim that
//  prevents AppKit from leaking heading paragraphStyle into the trailing
//  extra-line fragment. Restyle scoping (which paragraphs to re-tokenize on
//  each event) lives here too — it sets up the inputs that
//  `+Restyling.swift` then consumes.
//

import AppKit

extension NativeTextViewCoordinator {

    /// Force base typingAttributes on every change so AppKit's auto-inheritance
    /// can't bleed a heading paragraphStyle into the trailing extra-line
    /// fragment's metrics.
    public func textView(
        _ textView: NSTextView,
        shouldChangeTypingAttributes oldTypingAttributes: [String: Any],
        toAttributes newTypingAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let (baseFont, baseParagraphStyle) = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName,
            fontSize: fontSize,
            layoutBridge: layoutBridge,
            configuration: configuration
        )
        var result = newTypingAttributes
        result[.paragraphStyle] = baseParagraphStyle
        result[.font] = baseFont
        result[.foregroundColor] = configuration.theme.bodyText
        return result
    }

    public func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        let wtActive = isWritingToolsActive
        if wtActive, wtDetectedMode == .unknown {
            let firstEditLen = tv.textStorage?.editedRange.length ?? 0
            if let sel = wtInitialSelectionRange, sel.length > 0 {
                let threshold = max(10, Int(Double(sel.length) * 0.6))
                wtDetectedMode = firstEditLen >= threshold ? .rewrite : .proofread
            } else {
                wtDetectedMode = .rewrite
            }
        }
        if wtActive && wtDetectedMode == .proofread { return }

        let rawSelRange = tv.selectedRange()
        let fullLength = (tv.string as NSString).length
        guard !tv.hasMarkedText() else { return }
        let safeLocation = min(rawSelRange.location, fullLength)
        let safeSelRange = NSRange(location: safeLocation, length: 0)
        previousCaretLocation = safeSelRange.location
        if !wtActive {
            let storageState = WikiLinkService.makeStorageState(
                from: tv.string,
                existingMetadata: self.wikiLinkMetadata,
                textStorage: tv.textStorage
            )
            self.wikiLinkMetadata = storageState.metadata
            if storageState.storage != self.lastSyncedText {
                DispatchQueue.main.async {
                    self.lastSyncedText = storageState.storage
                    self.text = storageState.storage
                }
            }
        }

        let fullText = tv.string as NSString
        let paragraphRange = fullText.paragraphRange(for: safeSelRange)
        let documentLength = fullText.length
        let nextLocation = min(documentLength, NSMaxRange(paragraphRange))
        let previousParagraph =
            paragraphRange.location > 0
            ? fullText.paragraphRange(for: NSRange(location: max(0, paragraphRange.location - 1), length: 0))
            : NSRange(location: NSNotFound, length: 0)
        let nextParagraph =
            nextLocation < documentLength
            ? fullText.paragraphRange(for: NSRange(location: nextLocation, length: 0))
            : NSRange(location: NSNotFound, length: 0)
        let editedRange = pendingEditedRange ?? tv.textStorage?.editedRange ?? safeSelRange
        pendingEditedRange = nil
        let wtEditedFallback: NSRange? = {
            guard wtActive, let sel = wtInitialSelectionRange else { return nil }
            let docLength = fullText.length
            let loc = min(sel.location, docLength)
            let len = min(sel.length, docLength - loc)
            return NSRange(location: loc, length: len)
        }()
        let safeEditedRange: NSRange = {
            if let wtRange = wtEditedFallback { return wtRange }
            return editedRange.location == NSNotFound ? safeSelRange : editedRange
        }()
        let editedParagraphs = paragraphRanges(in: fullText, intersecting: safeEditedRange)
        let paragraphCandidates: [NSRange] =
            [
                previousParagraph,
                paragraphRange,
                nextParagraph,
            ] + editedParagraphs

        let parsed = parsedDocument(for: tv.string)
        let tokens = parsed.tokens
        let codeTokens = parsed.codeTokens
        let latexTokens = parsed.latexTokens
        let blockLatexTokens = parsed.blockLatexTokens

        let codeBlockStructureChanged = codeTokens.count != previousCodeBlockTokenCount
        previousCodeBlockTokenCount = codeTokens.count
        let preEditActiveTokenIndices = pendingPreEditActiveTokenIndices ?? previousActiveTokenIndices
        pendingPreEditActiveTokenIndices = nil

        activeTokenIndices = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: safeSelRange,
            tokens: tokens,
            in: fullText
        )
        filterImageEmbedActiveTokens(parsed: parsed, text: fullText, selectionLocation: safeSelRange.location)
        updateAutocorrectSettings(
            tv,
            caretLocation: safeSelRange.location,
            codeTokens: codeTokens,
            latexTokens: latexTokens,
            allTokens: tokens
        )

        var effectiveParagraphCandidates = paragraphCandidates
        if codeBlockStructureChanged {
            effectiveParagraphCandidates = [NSRange(location: 0, length: fullText.length)]
        }
        // Always restyle paragraphs containing latex/imageEmbed tokens to avoid stale raw text.
        let latexParagraphs = (latexTokens + blockLatexTokens + parsed.imageEmbedTokens).map {
            fullText.paragraphRange(for: $0.range)
        }
        effectiveParagraphCandidates.append(contentsOf: latexParagraphs)
        effectiveParagraphCandidates.append(
            contentsOf: tokenRestyleParagraphs(
                in: fullText,
                tokens: tokens,
                currentActiveTokenIndices: activeTokenIndices,
                previousActiveTokenIndices: preEditActiveTokenIndices
            ))

        restyleTextView(tv, paragraphCandidates: effectiveParagraphCandidates, tokens: tokens)
        updateCodeBlockSelection(textView: tv, tokens: tokens)
        if wtActive {
            previousActiveTokenIndices = activeTokenIndices
            return
        }
        if let bottomTextView = tv as? NativeTextView,
            let scrollView = tv.enclosingScrollView
        {
            bottomTextView.recalcOverscroll(for: scrollView, debugTag: "textDidChange")
            (scrollView as? ClampedScrollView)?.clampToInsets()
        }
        previousActiveTokenIndices = activeTokenIndices
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if isWritingToolsActive { return }

        let selRange = tv.selectedRange()
        let currentEventType = NSApp.currentEvent?.type
        // Mouse-/Wake-Fokus auf Link: kein Preview, erst Navigation. Gilt für alle Nicht-Key-Events.
        if currentEventType != .keyDown,
            selRange.location < (tv.string as NSString).length,
            tv.textStorage?.attribute(.link, at: selRange.location, effectiveRange: nil) != nil
        {
            isImageEmbedActive = false
            isWikiLinkActive = false
            isChipLinkActive = false
            onInlineSelectionChange?(nil)
            return
        }
        updateSelectionStates(tv)
        let selLoc = selRange.location

        let parsed = parsedDocument(for: tv.string)
        let tokens = parsed.tokens
        let codeTokens = parsed.codeTokens
        let latexTokens = parsed.latexTokens
        let blockLatexTokens = parsed.blockLatexTokens
        let nsText = tv.string as NSString

        let prevActive = activeTokenIndices
        activeTokenIndices = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: selRange, tokens: tokens, in: nsText)
        filterImageEmbedActiveTokens(parsed: parsed, text: nsText, selectionLocation: selRange.location)
        updateAutocorrectSettings(
            tv,
            caretLocation: selLoc,
            codeTokens: codeTokens,
            latexTokens: latexTokens,
            allTokens: tokens
        )
        let caretLoc = selRange.location
        let paragraphRange = nsText.paragraphRange(for: NSRange(location: caretLoc, length: 0))

        // Capture the prior caret location BEFORE `previousCaretLocation` is
        // overwritten at the bottom of this function — the scoped HR sync
        // needs the genuine previous location to know which paragraph the
        // caret just left.
        let priorCaretLocation = previousCaretLocation

        var paragraphCandidates: [NSRange] = [paragraphRange]
        if paragraphRange.length == 0 && caretLoc > 0 {
            paragraphCandidates.append(nsText.paragraphRange(for: NSRange(location: max(0, caretLoc - 1), length: 0)))
        }
        if let prevLoc = priorCaretLocation, prevLoc != caretLoc {
            let safePrev = min(prevLoc, nsText.length)
            let prevPara = nsText.paragraphRange(for: NSRange(location: safePrev, length: 0))
            paragraphCandidates.append(prevPara)
        }
        // Also restyle paragraphs containing latex/imageEmbed tokens to refresh rendering.
        let latexParagraphs = (latexTokens + blockLatexTokens + parsed.imageEmbedTokens).map {
            nsText.paragraphRange(for: $0.range)
        }
        paragraphCandidates.append(contentsOf: latexParagraphs)
        paragraphCandidates.append(
            contentsOf: tokenRestyleParagraphs(
                in: nsText,
                tokens: tokens,
                currentActiveTokenIndices: activeTokenIndices,
                previousActiveTokenIndices: previousActiveTokenIndices
            ))

        let shouldSkipSelectionRestyle = pendingEditedRange != nil
        let tokensChanged = activeTokenIndices != prevActive
        if shouldSkipSelectionRestyle {
            // textDidChange performs the pending restyle for this edit cycle.
        } else if tokensChanged {
            restyleTextView(tv, paragraphCandidates: paragraphCandidates, tokens: tokens)
            // When a wiki/chip-link token transitions active→inactive the `{{`/`[[`
            // and `}}`/`]]` markers collapse to 0 visual width via the kern trick.
            // A caret that landed on a marker character appears visually inside the
            // chip/link. Nudge it to the nearest token boundary so the cursor sits
            // clearly outside the rendered chip.
            nudgeCaretOutOfCollapsedMarkers(tv, tokens: tokens, caretLoc: selRange.location)
        }

        // Auto-select content when clicking (mouse) into a rendered (previously inactive) latex or image embed
        if selRange.length == 0,
            let eventType = currentEventType,
            eventType == .leftMouseUp || eventType == .leftMouseDown
        {
            let newlyActive = activeTokenIndices.subtracting(previousActiveTokenIndices)
            for idx in newlyActive {
                let token = tokens[idx]
                guard
                    token.kind == .inlineLatex
                        || token.kind == .blockLatex
                        || token.kind == .imageEmbed
                else {
                    continue
                }
                let selectRange = token.contentRange
                if selectRange.length > 0 {
                    tv.setSelectedRange(selectRange)
                    break
                }
            }
        }

        let nsString = tv.string as NSString
        let selLocation = tv.selectedRange().location
        let inlineContext = inlineTokenContext(
            at: selLocation,
            parsed: parsed,
            codeTokens: codeTokens,
            text: nsText
        )
        let isInsideImageEmbed = {
            guard case .imageEmbed = inlineContext else { return false }
            return true
        }()
        // Preview must only trigger inside the `![[…]]` content area
        let isInsideImageEmbedContent: Bool = {
            guard case .imageEmbed(let token) = inlineContext else { return false }
            let start = token.range.location + 3
            let end = NSMaxRange(token.range) - 2
            return selLocation >= start && selLocation <= end
        }()

        let isTyping = currentEventType == .keyDown
        let imageEmbedShowsInlinePreview = isInsideImageEmbedContent && isTyping
        var inlineSelectionState: InlineSelectionState? = nil
        if let inlineContext {
            let openingMarkerLength = inlineContext.selectionKind == .imageEmbed ? 3 : 2
            let displayRange = selectionDisplayRange(for: inlineContext.token, openingMarkerLength: openingMarkerLength)
            // Placeholder is the token INTERIOR (`Beta`), not the marker-wrapped
            // span (`{{Beta}}`): the embedder seeds autocomplete / rename from the
            // bare title. `displayRange` stays the caret-anchor + storage range.
            let placeholder = inlinePlaceholder(for: inlineContext.token, in: nsString)
            let storageRange =
                inlineContext.selectionKind == .wikiLink
                ? storageRange(containingDisplayLocation: selLocation) ?? storageRange(forDisplayRange: displayRange)
                : nil
            let previewRect =
                tv.viewRect(forCharacterRange: displayRange, using: layoutBridge)
                ?? tv.viewRect(forCharacterRange: tv.selectedRange(), using: layoutBridge)

            let shouldShowInlinePreview: Bool
            switch inlineContext.selectionKind {
            case .wikiLink, .chipLink:
                // `{{ }}` fires the selection-change + caret-rect the same way
                // `[[ ]]` does — a later task hooks this to show the `{{`
                // autocomplete window. `.chipLink` is title-only (no storage id).
                shouldShowInlinePreview = true
            case .imageEmbed:
                shouldShowInlinePreview = imageEmbedShowsInlinePreview
            }
            if shouldShowInlinePreview, let previewRect {
                let selection = WikiLinkSelection(
                    displayRange: displayRange,
                    storageRange: storageRange,
                    placeholder: placeholder
                )
                inlineSelectionState = InlineSelectionState(kind: inlineContext.selectionKind, selection: selection)
                DispatchQueue.main.async {
                    self.onCaretRectChange?(previewRect)
                }
            }
        }

        DispatchQueue.main.async {
            self.isWikiLinkActive = inlineSelectionState?.kind == .wikiLink
            self.isChipLinkActive = inlineSelectionState?.kind == .chipLink
            self.isImageEmbedActive = isInsideImageEmbed
            self.onInlineSelectionChange?(inlineSelectionState)
        }

        self.previousActiveTokenIndices = self.activeTokenIndices
        self.previousCaretLocation = caretLoc

        // Skip during a pending edit — viewRect is stale until textDidChange's restyle runs; otherwise the overlay flashes to the old Y before settling.
        if !shouldSkipSelectionRestyle {
            updateCodeBlockSelection(textView: tv, tokens: tokens)
        }

        // Pommora: re-sync HR dynamic-syntax visibility on caret move.
        // SCOPED variant — only the paragraph the caret just left and the
        // one it just entered can transition HR state on a caret-only event;
        // every other HR in the document is already correctly hidden/revealed
        // from the last full walk (initial load + each edit cycle). The full
        // walk in `restyleTextView` / `rebuildTextStorageAndStyle` still
        // catches HRs created or destroyed by edits, so this scoped path is
        // safe. Replaces an O(N) per-caret-tick document scan that caused
        // visible jitter on large files. Reentry-guarded to prevent
        // recursion via restyle.
        if !tokensChanged, let ts = tv.textStorage {
            var scope: [NSRange] = [paragraphRange]
            if let prev = priorCaretLocation, prev != caretLoc {
                let safePrev = min(prev, nsText.length)
                scope.append(nsText.paragraphRange(for: NSRange(location: safePrev, length: 0)))
            }
            syncHRVisibility(in: ts, textView: tv, scopedTo: scope)
        }
    }

    public func textView(
        _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
    ) -> Bool {
        if isProgrammaticEdit { return true }
        if isWritingToolsActive { return true }
        pendingEditedRange = NSRange(location: affectedCharRange.location, length: replacementString?.utf16.count ?? 0)
        let currentLen = (textView.string as NSString).length
        let maxR = affectedCharRange.location + affectedCharRange.length
        if affectedCharRange.location > currentLen || maxR > currentLen {
            pendingPreEditActiveTokenIndices = nil
            return false
        }
        if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true {
            pendingPreEditActiveTokenIndices = nil
            return true
        }
        let parsed = parsedDocument(for: textView.string)
        pendingPreEditActiveTokenIndices = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: textView.selectedRange(),
            tokens: parsed.tokens,
            in: textView.string as NSString
        )

        // Block LaTeX auto-wrap: insert newlines to keep $$ on its own line
        if MarkdownInputHandler.handleBlockLatexAutoWrap(
            textView: textView,
            affectedCharRange: affectedCharRange,
            replacementString: replacementString,
            blockLatexTokens: parsed.blockLatexTokens
        ) {
            return false
        }

        if MarkdownInputHandler.handleImageEmbedAutoWrap(
            textView: textView,
            affectedCharRange: affectedCharRange,
            replacementString: replacementString,
            imageEmbedTokens: parsed.imageEmbedTokens
        ) {
            return false
        }

        // Character-pair auto-pair (Pommora addition): `**` / `__` / `[[` / `` `` ``
        // → insert close marker with caret between.
        if MarkdownInputHandler.handleCharacterPairAutoPair(
            textView: textView,
            affectedCharRange: affectedCharRange,
            replacementString: replacementString,
            codeTokens: parsed.codeTokens
        ) {
            return false
        }

        // Character-pair auto-delete: backspace inside `*|*` / `**|**` /
        // `[[|]]` / `` `|` `` removes both halves.
        if MarkdownInputHandler.handleCharacterPairAutoDelete(
            textView: textView,
            affectedCharRange: affectedCharRange,
            replacementString: replacementString
        ) {
            return false
        }

        return MarkdownInputHandler.handleListInsertion(
            textView: textView, affectedCharRange: affectedCharRange, replacementString: replacementString)
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return handleBacktab(textView)
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return handleEnterInInlineLink(textView)
        }
        return false
    }

    /// Enter pressed while caret is inside `[[ ]]` or `{{ }}`: move the caret
    /// to just after the closing marker and consume the event (no newline). If
    /// the caret is NOT inside an inline link, returns false so NSTextView
    /// inserts a normal newline.
    private func handleEnterInInlineLink(_ textView: NSTextView) -> Bool {
        let selLoc = textView.selectedRange().location
        let parsed = parsedDocument(for: textView.string)
        let nsText = textView.string as NSString
        guard let context = inlineTokenContext(
            at: selLoc, parsed: parsed, codeTokens: parsed.codeTokens, text: nsText)
        else { return false }
        let afterToken = min(NSMaxRange(context.token.range), nsText.length)
        textView.setSelectedRange(NSRange(location: afterToken, length: 0))
        return true
    }

    /// After active→inactive token transition: if the caret landed on an opening
    /// or closing marker (`{{`/`}}`/`[[`/`]]`), those chars have 0 visual width
    /// and the cursor appears inside the chip. Nudge to the nearest token edge.
    private func nudgeCaretOutOfCollapsedMarkers(
        _ textView: NSTextView, tokens: [MarkdownToken], caretLoc: Int
    ) {
        let docLen = (textView.string as NSString).length
        for token in tokens where token.kind == .wikiLink || token.kind == .chipLink {
            guard caretLoc > token.range.location,
                  caretLoc < NSMaxRange(token.range) else { continue }
            let innerStart = token.range.location + 2
            let innerEnd = NSMaxRange(token.range) - 2
            // Caret is in the token range but NOT in the inner-active content range.
            guard caretLoc < innerStart || caretLoc > innerEnd else { continue }
            let target = caretLoc < innerStart
                ? token.range.location             // before opening marker
                : min(NSMaxRange(token.range), docLen)  // after closing marker
            DispatchQueue.main.async { [weak textView] in
                textView?.setSelectedRange(NSRange(location: target, length: 0))
            }
            return
        }
    }

    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        // A resolved `{{Title}}` carries `.chipLinkTitle` on its content range —
        // route those to the chip-link click handler. `[[ ]]` links carry no such
        // attribute and fall through to the page-navigation path below.
        if let storage = textView.textStorage, charIndex < storage.length,
            let chipTitle = storage.attribute(.chipLinkTitle, at: charIndex, effectiveRange: nil) as? String {
            self.isWikiLinkActive = false
            self.isChipLinkActive = false
            DispatchQueue.main.async {
                self.onChipLinkClick?(chipTitle)
            }
            return true
        }
        guard let target = WikiLinkService.resolveIdentifier(link: link, textView: textView, at: charIndex) else {
            return false
        }
        // Direkt deaktivieren, bevor der Navigation-Callback läuft.
        self.isWikiLinkActive = false
        self.isChipLinkActive = false
        DispatchQueue.main.async {
            self.onLinkClick?(target)
        }
        return true
    }

    func updateSelectionStates(_ tv: NSTextView) {
        let nsText = tv.string as NSString
        let selRange = tv.selectedRange()
        let bus = configuration.services.bus
        let center = NotificationCenter.default
        if let name = bus.selectionBoldDidChange {
            center.post(
                name: name, object: nil,
                userInfo: ["isBold": isSelectionBold(in: nsText, range: selRange)]
            )
        }
        if let name = bus.selectionItalicDidChange {
            center.post(
                name: name, object: nil,
                userInfo: ["isItalic": isSelectionItalic(in: nsText, range: selRange)]
            )
        }
    }

    func handleBacktab(_ textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let caretLoc = textView.selectedRange().location
        let lineRange = nsText.lineRange(for: NSRange(location: caretLoc, length: 0))
        let line = nsText.substring(with: lineRange)

        let pattern = #"^([\t ]*)((\d+)\.|-|•)\s"#
        let regex = try? NSRegularExpression(pattern: pattern)
        if let regex = regex,
            let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
        {
            let wsRangeLocal = match.range(at: 1)
            let wsString = (line as NSString).substring(with: wsRangeLocal)
            let wsDocStart = lineRange.location + wsRangeLocal.location
            let depth = MarkdownLists.indentLevel(from: wsString)
            if depth <= 1 {
                return true
            }

            if wsRangeLocal.length > 0 {
                if wsString.hasPrefix("\t") {
                    MarkdownLists.performEdit(textView, replace: NSRange(location: wsDocStart, length: 1), with: "")
                    textView.setSelectedRange(NSRange(location: max(0, caretLoc - 1), length: 0))
                    return true
                } else {
                    var removeCount = 0
                    for ch in wsString {
                        if ch == " " && removeCount < 2 { removeCount += 1 } else { break }
                    }
                    if removeCount == 0 { removeCount = min(2, wsRangeLocal.length) }
                    MarkdownLists.performEdit(
                        textView, replace: NSRange(location: wsDocStart, length: removeCount), with: "")
                    textView.setSelectedRange(NSRange(location: max(0, caretLoc - removeCount), length: 0))
                    return true
                }
            } else {
                return true
            }
        }

        if line.hasPrefix("\t") {
            MarkdownLists.performEdit(textView, replace: NSRange(location: lineRange.location, length: 1), with: "")
            textView.setSelectedRange(NSRange(location: max(0, caretLoc - 1), length: 0))
            return true
        }
        return false
    }

}
