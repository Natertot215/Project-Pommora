//
//  NativeTextViewCoordinator+Services.swift
//  MarkdownPM
//
//  Consolidated service-layer extensions on NativeTextViewCoordinator —
//  callback handlers, autocorrect policy, code-block overlay tracking,
//  Writing Tools session bridging, inline-selection geometry, and find
//  highlighting. Each MARK section preserves the original +Topic.swift
//  contents from the upstream engine; access scopes are unchanged because
//  each former file is kept as its own `extension` block.
//
//  The dynamic-syntax pipeline (NativeTextViewCoordinator + +TextDelegate
//  + +Restyling + +HRVisibility) is intentionally NOT consolidated here —
//  those four files are the locked architectural boundary per
//  `.claude/Guidelines/Markdown.md` §3.
//

import AppKit

// MARK: - Find-in-document highlighting
//
// Find-in-document highlighting. The host app posts the bus notifications
// registered in `MarkdownEditorBus.findScrollToRange` / `findClearHighlights`
// to drive the highlight overlay; this extension renders the highlights into
// the underlying NSTextStorage and scrolls the current match into view.

extension NativeTextViewCoordinator {
    @objc func handleFindScrollToRange(_ notification: Notification) {
        guard let tv = textView,
            let info = notification.userInfo,
            let range = info["range"] as? NSRange,
            let currentIndex = info["currentIndex"] as? Int,
            let allRanges = info["allRanges"] as? [NSRange]
        else { return }

        let storage = tv.textStorage
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)

        // Clear previous highlights
        storage?.removeAttribute(.backgroundColor, range: fullRange)

        // Highlight all matches; the focused match gets a stronger color.
        let theme = configuration.theme
        let matchAlpha = configuration.markers.findMatchHighlightAlpha
        let highlightColor = theme.findMatchHighlight.withAlphaComponent(matchAlpha)
        let currentHighlightColor = theme.findCurrentMatchHighlight

        for (i, matchRange) in allRanges.enumerated() {
            guard matchRange.location + matchRange.length <= fullRange.length else { continue }
            let color = (i == currentIndex) ? currentHighlightColor : highlightColor
            storage?.addAttribute(.backgroundColor, value: color, range: matchRange)
        }

        if let tlm = tv.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
        }

        // Scroll to current match
        if range.location + range.length <= fullRange.length {
            tv.scrollRangeToVisible(range)
        }
    }

    @objc func handleFindClearHighlights(_ notification: Notification) {
        guard let tv = textView else { return }
        let scrollView = tv.enclosingScrollView
        let preY = scrollView?.contentView.bounds.origin.y ?? 0
        let insetsTop = scrollView?.contentInsets.top ?? 0
        let visualTopDocY = preY + insetsTop
        var anchorOffsetFromTop: CGFloat = 0
        var anchorTextRange: NSTextRange? = nil
        if let tlm = tv.textLayoutManager {
            tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame
                if frame.maxY < visualTopDocY { return true }
                anchorTextRange = fragment.rangeInElement
                anchorOffsetFromTop = visualTopDocY - frame.minY
                return false
            }
        }

        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
        if let tlm = tv.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
        }

        if let tlm = tv.textLayoutManager, let anchor = anchorTextRange {
            tlm.enumerateTextLayoutFragments(from: anchor.location, options: [.ensuresLayout]) { fragment in
                let newDocY = fragment.layoutFragmentFrame.minY + anchorOffsetFromTop
                let targetScrollY = newDocY - insetsTop
                if let cv = scrollView?.contentView, abs(cv.bounds.origin.y - targetScrollY) > 0.5 {
                    cv.scroll(to: NSPoint(x: cv.bounds.origin.x, y: targetScrollY))
                    scrollView?.reflectScrolledClipView(cv)
                }
                return false
            }
        }
    }
}

// MARK: - Bus notifications
//
// Bus-notification handlers wired up by `subscribeToBusNotifications`. These
// translate embedder-posted requests (apply bold / italic / heading level)
// into the corresponding ContextMenu actions, and refresh styling when the
// syntax highlighter signals an appearance change.

extension NativeTextViewCoordinator {
    @objc func handleBoldNotification(_ notification: Notification) {
        didMarkdownBold(nil)
    }

    @objc func handleItalicNotification(_ notification: Notification) {
        didMarkdownItalic(nil)
    }

    @objc func handleHeadingNotification(_ notification: Notification) {
        guard let level = notification.userInfo?["level"] as? Int else { return }
        let item = NSMenuItem()
        item.tag = level
        didMarkdownHeading(item)
    }

    @objc func handleAppearanceChange(_ notification: Notification) {
        guard let tv = textView else { return }
        // Only react if the notification came from our own text view or from nil (system-wide)
        if let sender = notification.object as? NSTextView, sender !== tv {
            return
        }
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        restyleTextView(tv, paragraphCandidates: [fullRange])
    }
}

// MARK: - Autocorrect / spell-check / quote substitution policy
//
// Toggles AppKit's auto-correct, spell-check, grammar-check and quote
// substitution off when the caret enters tokens where those features are
// unwanted (code blocks, LaTeX, links). The previous decision is held so
// the setters only fire when the state actually changes.

extension NativeTextViewCoordinator {
    func updateAutocorrectSettings(
        _ textView: NSTextView,
        caretLocation: Int,
        codeTokens: [MarkdownToken]? = nil,
        latexTokens: [MarkdownToken]? = nil,
        allTokens: [MarkdownToken]? = nil
    ) {
        // Prefer precomputed tokens to avoid the expensive textView.string bridge on long docs.
        let inCode: Bool
        if let codeTokens = codeTokens {
            inCode = MarkdownDetection.isInsideCodeBlock(location: caretLocation, codeTokens: codeTokens)
        } else {
            inCode = MarkdownDetection.isInsideCodeBlock(location: caretLocation, in: textView.string)
        }
        let inLatex: Bool
        if let latexTokens = latexTokens {
            inLatex = MarkdownDetection.isInsideLatex(location: caretLocation, latexTokens: latexTokens)
        } else {
            inLatex = MarkdownDetection.isInsideLatex(location: caretLocation, in: textView.string)
        }
        let inSpellcheckSuppressedToken: Bool
        if let allTokens = allTokens {
            inSpellcheckSuppressedToken = allTokens.contains { token in
                (token.kind == .wikiLink || token.kind == .link || token.kind == .imageEmbed)
                    && NSLocationInRange(caretLocation, token.range)
            }
        } else {
            inSpellcheckSuppressedToken = isInsideSpellcheckSuppressedToken(
                location: caretLocation, in: textView.string)
        }
        let shouldDisableSpelling = inCode || inLatex || inSpellcheckSuppressedToken

        if previousSpellingDisabled == shouldDisableSpelling {
            return
        }
        previousSpellingDisabled = shouldDisableSpelling

        textView.isAutomaticSpellingCorrectionEnabled = !shouldDisableSpelling
        textView.isContinuousSpellCheckingEnabled = !shouldDisableSpelling
        textView.isGrammarCheckingEnabled = !shouldDisableSpelling
        textView.isAutomaticQuoteSubstitutionEnabled = !shouldDisableSpelling
        textView.isAutomaticDashSubstitutionEnabled = false
    }

    func isInsideCode(range: NSRange, in text: String) -> Bool {
        let parsed = parsedDocument(for: text)
        return MarkdownDetection.isInsideCodeBlock(range: range, codeTokens: parsed.codeTokens)
    }

    func isInsideLatex(location: Int, in text: String) -> Bool {
        let parsed = parsedDocument(for: text)
        if MarkdownDetection.isInsideLatex(location: location, latexTokens: parsed.latexTokens) {
            return true
        }
        return MarkdownDetection.isInsideLatex(location: location, latexTokens: parsed.blockLatexTokens)
    }

    func isInsideSpellcheckSuppressedToken(location: Int, in text: String) -> Bool {
        let parsed = parsedDocument(for: text)
        return parsed.tokens.contains { token in
            guard token.kind == .wikiLink || token.kind == .link || token.kind == .imageEmbed else {
                return false
            }
            return NSLocationInRange(location, token.range)
        }
    }

    func isInsideSpellcheckSuppressedToken(range: NSRange, in text: String) -> Bool {
        let parsed = parsedDocument(for: text)
        return parsed.tokens.contains { token in
            guard token.kind == .wikiLink || token.kind == .link || token.kind == .imageEmbed else {
                return false
            }
            return NSIntersectionRange(token.range, range).length > 0
        }
    }
}

// MARK: - Code-block overlay tracking
//
// Tracks code-block selections in the document so the host can render the
// small "copy code" button overlay on top of every fenced code block. Skips
// blocks the caret is currently inside (`activeTokenIndices`) to avoid the
// button overlapping the cursor while editing.

extension NativeTextViewCoordinator {
    func updateCodeBlockSelection(textView: NSTextView, tokens: [MarkdownToken]? = nil) {
        guard let textContainer = textView.textContainer else {
            onCodeBlockSelectionChange?([])
            return
        }

        if let tokens = tokens {
            cachedCodeBlockTokens = tokens.enumerated()
                .filter { $0.element.kind == .codeBlock }
                .map { (index: $0.offset, token: $0.element) }
        } else if cachedCodeBlockTokens.isEmpty {
            onCodeBlockSelectionChange?([])
            return
        }

        let nsText = textView.string as NSString
        let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero

        // One-shot full-document layout per document; fixes stale Y from TextKit 2's lazy layout without per-update cost.
        if !didEnsureLayoutForCurrentDocument, let tlm = textView.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
            didEnsureLayoutForCurrentDocument = true
        }

        let selections: [CodeBlockSelection] = cachedCodeBlockTokens.compactMap { originalIndex, token in
            guard !activeTokenIndices.contains(originalIndex) else { return nil }
            guard var boundingRect = textView.viewRect(forCharacterRange: token.range, using: layoutBridge) else {
                return nil
            }

            boundingRect.origin.x = textView.textContainerOrigin.x - scrollOffset.x
            boundingRect.size.width = textContainer.containerSize.width

            return CodeBlockSelection(
                id: originalIndex,
                rect: boundingRect,
                language: MarkdownTokenizer.extractLanguage(from: token, in: textView.string),
                code: nsText.substring(with: token.contentRange)
            )
        }

        onCodeBlockSelectionChange?(selections)
    }
}

// MARK: - Writing Tools (macOS 15+) session bridging
//
// macOS 15+ Writing Tools integration: pauses styling during the session,
// re-syncs results on end, fixes child window position, and recovers from
// Apple's stale-accept-action bug after mid-session Cmd+Z.

extension NativeTextViewCoordinator {
    @available(macOS 15.0, *)
    public func textViewWritingToolsWillBegin(_ textView: NSTextView) {
        let sel = textView.selectedRange()
        isWritingToolsActive = true
        wtStartDocumentId = documentId
        wtChildWindow = nil
        wtInitialChildOrigin = nil
        wtInitialSelectionRange = sel.length > 0 ? sel : nil
        wtDetectedMode = .unknown
        wtUndoneDuringSession = false
        wtPostUndoSnapshot = nil
        observeUndoNotifications(for: textView.undoManager)
        scheduleChildWindowFix(textView: textView, attemptsRemaining: 20)
    }

    @available(macOS 15.0, *)
    public func textViewWritingToolsDidEnd(_ textView: NSTextView) {
        guard isWritingToolsActive else { return }
        isWritingToolsActive = false
        wtChildWindow = nil
        wtInitialChildOrigin = nil
        stopObservingUndoNotifications()

        // Doc switched mid-session — discard WT results, the new node already loaded.
        if wtStartDocumentId != nil && wtStartDocumentId != documentId {
            wtStartDocumentId = nil
            return
        }
        wtStartDocumentId = nil

        // Cmd+Z mid-session: Apple's stale accept-action corrupts text + contaminates attrs with 0.1pt marker font; the post-undo snapshot is the authoritative state.
        let sourceText: String
        let undoDuringSession: Bool
        if wtUndoneDuringSession, let snapshot = wtPostUndoSnapshot {
            sourceText = snapshot
            undoDuringSession = true
        } else {
            sourceText = textView.string
            undoDuringSession = false
        }
        wtUndoneDuringSession = false
        wtPostUndoSnapshot = nil

        let storageState = WikiLinkService.makeStorageState(
            from: sourceText,
            existingMetadata: wikiLinkMetadata,
            textStorage: textView.textStorage
        )
        wikiLinkMetadata = storageState.metadata
        let storage = storageState.storage

        // Binding is already equal to `storage` after undo so SwiftUI won't re-render — rebuild the textView directly.
        if undoDuringSession {
            rebuildTextStorageAndStyle(textView, from: storage)
        }
        DispatchQueue.main.async { [self] in
            lastSyncedText = storage
            text = storage
        }
    }

    // MARK: Child window (Done/Original panel) position fix

    private func scheduleChildWindowFix(textView: NSTextView, attemptsRemaining: Int) {
        guard attemptsRemaining > 0, isWritingToolsActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isWritingToolsActive else { return }
            self.captureChildWindowIfNeeded(textView: textView)
            if self.wtChildWindow == nil {
                self.scheduleChildWindowFix(textView: textView, attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    private func captureChildWindowIfNeeded(textView: NSTextView) {
        guard wtChildWindow == nil,
            let mainWindow = textView.window,
            let childWin = mainWindow.childWindows?.first(where: { $0.isVisible })
        else { return }
        wtChildWindow = childWin
        wtInitialChildOrigin = childWin.frame.origin
    }

    // MARK: Undo observer (captures post-undo snapshot for recovery)

    private func observeUndoNotifications(for undoManager: UndoManager?) {
        stopObservingUndoNotifications()
        guard let um = undoManager else { return }
        let center = NotificationCenter.default
        wtUndoObserverTokens = [
            center.addObserver(forName: .NSUndoManagerDidUndoChange, object: um, queue: .main) { [weak self] _ in
                guard let self, let tv = self.textView, self.isWritingToolsActive else { return }
                self.wtUndoneDuringSession = true
                self.wtPostUndoSnapshot = tv.string
            }
        ]
    }

    private func stopObservingUndoNotifications() {
        wtUndoObserverTokens.forEach(NotificationCenter.default.removeObserver(_:))
        wtUndoObserverTokens.removeAll()
    }

    func fixWritingToolsChildWindowIfNeeded(textView: NSTextView) {
        guard let childWin = wtChildWindow,
            let correctOrigin = wtInitialChildOrigin
        else { return }

        let frame = childWin.frame
        let needsFix = abs(frame.origin.x - correctOrigin.x) > 0.5 || abs(frame.origin.y - correctOrigin.y) > 0.5
        if needsFix {
            var fixed = frame
            fixed.origin = correctOrigin
            childWin.setFrame(fixed, display: false)
        }
    }
}

// MARK: - Inline selection geometry (wiki-links + image embeds)
//
// Inline selection geometry: figure out which inline token (wiki-link `[[…]]`
// or image-embed `![[…]]`) the caret is currently in, compute its on-screen
// rect for the host's preview popover, and keep image-embed activation in
// sync with the active-token-index set.

extension NativeTextViewCoordinator {

    /// Recompute the preview anchor for the active inline token (used when scrolling).
    func refreshActiveLinkCaretRect() {
        guard isWikiLinkActive || isImageEmbedActive, let tv = textView else { return }
        guard let rect = inlinePreviewRect(in: tv) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCaretRectChange?(rect)
        }
    }

    func inlinePreviewRect(in tv: NSTextView) -> CGRect? {
        let nsText = tv.string as NSString
        let parsed = parsedDocument(for: tv.string)
        let selectionLocation = tv.selectedRange().location
        guard
            let inlineContext = inlineTokenContext(
                at: selectionLocation,
                parsed: parsed,
                codeTokens: parsed.codeTokens,
                text: nsText
            )
        else {
            return tv.viewRect(forCharacterRange: tv.selectedRange(), using: layoutBridge)
        }

        let openingMarkerLength = inlineContext.selectionKind == .imageEmbed ? 3 : 2
        let displayRange = selectionDisplayRange(for: inlineContext.token, openingMarkerLength: openingMarkerLength)
        return tv.viewRect(forCharacterRange: displayRange, using: layoutBridge)
            ?? tv.viewRect(forCharacterRange: tv.selectedRange(), using: layoutBridge)
    }

    func selectionDisplayRange(for token: MarkdownToken, openingMarkerLength: Int) -> NSRange {
        let leftRange =
            token.markerRanges.first
            ?? NSRange(location: token.range.location, length: min(openingMarkerLength, token.range.length))
        let rightRange =
            token.markerRanges.last
            ?? NSRange(
                location: max(token.range.location, NSMaxRange(token.range) - min(2, token.range.length)),
                length: min(2, token.range.length)
            )
        return NSRange(
            location: leftRange.location, length: rightRange.location + rightRange.length - leftRange.location)
    }

    func imageEmbedToken(
        at selectionLocation: Int,
        parsed: ParsedDocument,
        in text: NSString
    ) -> (token: MarkdownToken, index: Int)? {
        for token in parsed.imageEmbedTokens {
            guard token.containsSelectionOrStandaloneParagraph(selectionLocation, in: text) else {
                continue
            }
            let index =
                parsed.tokens.firstIndex(where: {
                    $0.range.location == token.range.location && $0.kind == .imageEmbed
                }) ?? 0
            return (token, index)
        }
        return nil
    }

    func inlineTokenContext(
        at selectionLocation: Int,
        parsed: ParsedDocument,
        codeTokens: [MarkdownToken],
        text: NSString
    ) -> InlineTokenContext? {
        if let (token, _) = imageEmbedToken(at: selectionLocation, parsed: parsed, in: text),
            !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens)
        {
            return .imageEmbed(token: token)
        }

        for token in parsed.wikiLinkTokens {
            // Only match when the caret sits between the inner edges of `[[…]]` —
            let start = token.range.location + 2
            let end = NSMaxRange(token.range) - 2
            guard selectionLocation >= start && selectionLocation <= end else { continue }
            guard !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens) else { break }
            return .wikiLink(token: token)
        }

        return nil
    }

    // MARK: Image Embed Activation

    func filterImageEmbedActiveTokens(parsed: ParsedDocument, text: NSString, selectionLocation: Int) {
        let activeImageEmbedIndex = imageEmbedToken(
            at: selectionLocation,
            parsed: parsed,
            in: text
        )?.index

        for (idx, token) in parsed.tokens.enumerated() where token.kind == .imageEmbed {
            if idx != activeImageEmbedIndex {
                activeTokenIndices.remove(idx)
            } else {
                activeTokenIndices.insert(idx)
            }
        }
    }

    func resetImageEmbedState() {
        isImageEmbedActive = false
    }
}
