//
//  NativeTextViewCoordinator.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Keeps the editor in sync while you type, updating formatting, selections,
// links, and other editing behavior in one place.
import AppKit
import SwiftUI

/// `NSTextViewDelegate` that bridges ``NativeTextViewWrapper`` and the
/// underlying `NSTextView`.
///
/// The coordinator is created automatically by SwiftUI; embedders never
/// construct one directly. Behaviors that don't fit in the main file live
/// in extensions (Autocorrect, CodeBlocks, Find, InlineSelection,
/// Notifications, Restyling, TextDelegate, WritingTools).
///
/// Pommora vendoring: marked `@MainActor` for Swift 6 strict concurrency.
/// NSTextViewDelegate callbacks are always invoked on the main thread, and
/// the coordinator's notification observers all dispatch to `.main` queue —
/// `@MainActor` makes that contract explicit to the compiler.
@MainActor
public final class NativeTextViewCoordinator: NSObject, NSTextViewDelegate {
    var documentId: String?
    @Binding var text: String
    @Binding var isWikiLinkActive: Bool
    /// UI-only fold state for the editor surface. Keys are exact heading
    /// source lines (e.g. `"## Foo"`); each present key means the content
    /// under that heading is collapsed. The HeadingFolding service is the
    /// sole consumer; it derives the runtime `foldedRanges` from this set
    /// + the current document AST. Defaults to `.constant([])` when the
    /// embedder doesn't supply a binding.
    @Binding var foldedHeadings: Set<String>
    var fontName: String
    var fontSize: CGFloat
    var configuration: MarkdownEditorConfiguration = .default {
        didSet {
            subscribeToBusNotifications(replacing: oldValue.services.bus)
            subscribeToAppearanceNotification()
        }
    }
    private var registeredAppearanceObserverName: Notification.Name?
    weak var textView: NSTextView?
    var layoutBridge: LayoutBridge?
    var layoutDelegate: MarkdownLayoutManagerDelegate?
    var onLinkClick: ((String) -> Void)?
    var onCaretRectChange: ((CGRect) -> Void)?
    var onInlineSelectionChange: ((InlineSelectionState?) -> Void)?
    var onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)?
    var didInitialFormatting: Bool = false
    /// One-shot guard so `updateCodeBlockSelection` only forces a full-document layout once per document.
    var didEnsureLayoutForCurrentDocument: Bool = false
    var lastSyncedText: String
    var isProgrammaticEdit: Bool = false
    var isWritingToolsActive: Bool = false
    var wtStartDocumentId: String?
    weak var wtChildWindow: NSWindow?
    var wtInitialChildOrigin: CGPoint?
    var wtInitialSelectionRange: NSRange?
    enum WTMode { case unknown, proofread, rewrite }
    var wtDetectedMode: WTMode = .unknown
    var wtUndoObserverTokens: [NSObjectProtocol] = []
    var wtUndoneDuringSession: Bool = false
    var wtPostUndoSnapshot: String?
    var lastAppliedInlineReplacementID: UUID?
    var activeTokenIndices: Set<Int> = []
    var previousActiveTokenIndices: Set<Int> = []
    var wikiLinkMetadata: [WikiLinkService.RangeKey: WikiLinkService.LinkMetadata] = [:]
    // Previous count of fenced/inline code tokens — used to detect code-block
    // structure changes and trigger a full-document restyle. The earlier
    // "count `` ``` `` substrings in the raw string" heuristic tripped on
    // edge cases (spaces inside triple-backticks, escaped backticks); the
    // token-count comparison is robust for any case the tokenizer can parse.
    var previousCodeBlockTokenCount: Int = 0

    var pendingEditedRange: NSRange? = nil
    var pendingPreEditActiveTokenIndices: Set<Int>? = nil
    var previousCaretLocation: Int? = nil
    /// Reentry guard for `syncHRVisibility`. The service writes attributes
    /// inside beginEditing/endEditing; if those writes trigger restyle (which
    /// our post-restyle hook would re-enter), we'd recurse. Set on entry,
    /// cleared in defer, early-return if already set.
    var isSyncingHRVisibility: Bool = false

    // MARK: - Foldable headings

    /// NSRanges of content currently hidden by a folded heading. Refilled by
    /// `syncHeadingFolding` from the AST + `foldedHeadings` binding; the
    /// renderer queries it at `layoutFragmentFrame` / `draw(at:in:)` time to
    /// skip folded fragments.
    var foldedRanges: [NSRange] = []
    /// Heading key (exact source line, e.g. `"## Foo"`) currently under the
    /// mouse cursor — drives chevron visibility. nil means no heading hovered.
    var hoveredHeadingKey: String? = nil
    /// In-flight chevron rotation animations, keyed by heading source line.
    /// Single-glyph rotation per Nathan's preference: `chevron.right`
    /// rotated 0° (folded) ↔ 90° (expanded) — geometrically identical to
    /// `chevron.down` at the 90° endpoint, matching SwiftUI DisclosureGroup's
    /// pattern. The interpolator reads from this dict at draw time; absent
    /// key means no in-flight animation so the renderer snaps to the static
    /// target angle for the current fold state.
    var chevronAnimations: [String: ChevronAnimation] = [:]
    /// Timer that ticks `chevronAnimations` toward completion at ~60Hz.
    /// Lives only while at least one animation is in flight; nil otherwise.
    var chevronAnimationTimer: Timer?

    /// A single chevron's rotation animation. Captures the heading's line
    /// range at start time so the 60Hz tick can nudge it without re-walking
    /// the document per frame.
    struct ChevronAnimation: Sendable {
        let startAngle: CGFloat
        let targetAngle: CGFloat
        let startTime: TimeInterval
        let duration: TimeInterval
        let headingRange: NSRange?
    }
    /// Snapshot of `foldedHeadings` at the last successful sync — the
    /// fold-toggle path compares the live binding against this to decide
    /// whether to re-sync. `syncHeadingFolding` keeps it in lockstep.
    var lastSyncedFoldedHeadings: Set<String> = []
    /// Reentry guard for the caret-skip path. `NSTextView.setSelectedRange`
    /// synchronously re-fires `textViewDidChangeSelection`, and the skip
    /// handler lives at the top of that delegate method — without this
    /// flag the push would recurse.
    var isPushingCaretOutOfFold: Bool = false

    var cachedCodeBlockTokens: [(index: Int, token: MarkdownToken)] = []
    var cachedParsedText: String?
    var cachedParsedDocument: ParsedDocument?
    // Skip spellcheck property setters when the state wouldn't change. Not a
    // cache — there is no invalidation; this is "previous value, re-checked
    // on every textDidChange + textViewDidChangeSelection."
    var previousSpellingDisabled: Bool?

    struct ParsedDocument {
        let tokens: [MarkdownToken]
        let codeTokens: [MarkdownToken]
        let latexTokens: [MarkdownToken]
        let blockLatexTokens: [MarkdownToken]
        let wikiLinkTokens: [MarkdownToken]
        let imageEmbedTokens: [MarkdownToken]
    }

    enum InlineTokenContext {
        case wikiLink(token: MarkdownToken)
        case imageEmbed(token: MarkdownToken)

        var token: MarkdownToken {
            switch self {
            case .wikiLink(let token), .imageEmbed(let token):
                return token
            }
        }

        var selectionKind: InlineSelectionKind {
            switch self {
            case .wikiLink:
                return .wikiLink
            case .imageEmbed:
                return .imageEmbed
            }
        }
    }

    var isImageEmbedActive: Bool = false

    // Inline selection geometry, image-embed activation, and inline-token
    // detection live in `NativeTextViewCoordinator+InlineSelection.swift`.

    init(
        text: Binding<String>,
        fontName: String,
        fontSize: CGFloat,
        isWikiLinkActive: Binding<Bool>,
        onLinkClick: ((String) -> Void)?,
        onInlineSelectionChange: ((InlineSelectionState?) -> Void)?,
        foldedHeadings: Binding<Set<String>> = .constant([])
    ) {
        _text = text
        self.fontName = fontName
        self.fontSize = fontSize
        _isWikiLinkActive = isWikiLinkActive
        _foldedHeadings = foldedHeadings
        self.onLinkClick = onLinkClick
        self.onCaretRectChange = nil
        self.onInlineSelectionChange = onInlineSelectionChange
        self.lastSyncedText = text.wrappedValue
        super.init()
        // Init + didSet share this helper so the observer tracks whichever service is current.
        subscribeToAppearanceNotification()
    }

    /// (Re)register the syntax-highlighter appearance observer; idempotent and unsubscribes on nil.
    private func subscribeToAppearanceNotification() {
        let target = configuration.services.syntaxHighlighter.appearanceDidChangeNotification
        if registeredAppearanceObserverName == target { return }
        if let current = registeredAppearanceObserverName {
            NotificationCenter.default.removeObserver(self, name: current, object: nil)
        }
        registeredAppearanceObserverName = nil
        guard let name = target else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange(_:)),
            name: name,
            object: nil
        )
        registeredAppearanceObserverName = name
    }

    /// Subscribe to whichever bus notification names the current configuration
    /// supplies. Removes any previous subscriptions first so that swapping
    /// configurations at runtime doesn't double-fire handlers.
    private func subscribeToBusNotifications(replacing previous: MarkdownEditorBus) {
        let center = NotificationCenter.default

        // Remove any prior subscriptions by their explicit name+selector pairs
        // so that swapping configurations at runtime doesn't double-fire.
        if let name = previous.applyBoldRequest {
            center.removeObserver(self, name: name, object: nil)
        }
        if let name = previous.applyItalicRequest {
            center.removeObserver(self, name: name, object: nil)
        }
        if let name = previous.applyHeadingRequest {
            center.removeObserver(self, name: name, object: nil)
        }
        if let name = previous.findScrollToRange {
            center.removeObserver(self, name: name, object: nil)
        }
        if let name = previous.findClearHighlights {
            center.removeObserver(self, name: name, object: nil)
        }

        let bus = configuration.services.bus

        // Use selector-based observation (@objc dispatch) rather than the
        // block-based addObserver(forName:object:queue:using:) — block form's
        // closure is task-isolated `@Sendable (Notification) -> Void`, which
        // trips Swift 6 strict concurrency's "sending non-Sendable Notification
        // across actor boundary" check. The @objc selector form bypasses the
        // sending check entirely (dispatched through Obj-C runtime; thread-safe
        // by Apple contract on NotificationCenter posting). All 5 @objc
        // handlers live on this same class in +Notifications/+Find extensions.
        //
        // The tradeoff: we no longer pass `queue: .main`, so handlers run on
        // whatever thread the notification is posted on. All 5 of these
        // notifications are posted from main-thread UI flows (toolbar buttons,
        // find-in-document), so this is fine in practice. Engine consumers
        // posting from background threads would need to dispatch to main
        // themselves — same contract as any @objc NotificationCenter observer.
        if let name = bus.applyBoldRequest {
            center.addObserver(self, selector: #selector(handleBoldNotification(_:)), name: name, object: nil)
        }
        if let name = bus.applyItalicRequest {
            center.addObserver(self, selector: #selector(handleItalicNotification(_:)), name: name, object: nil)
        }
        if let name = bus.applyHeadingRequest {
            center.addObserver(self, selector: #selector(handleHeadingNotification(_:)), name: name, object: nil)
        }
        if let name = bus.findScrollToRange {
            center.addObserver(self, selector: #selector(handleFindScrollToRange(_:)), name: name, object: nil)
        }
        if let name = bus.findClearHighlights {
            center.addObserver(self, selector: #selector(handleFindClearHighlights(_:)), name: name, object: nil)
        }
    }

    // Find-in-document highlight handlers live in
    // `NativeTextViewCoordinator+Find.swift`.

    func wikiLinkID(for range: NSRange) -> String? {
        wikiLinkMetadata[WikiLinkService.RangeKey(range)]?.id
    }

    func storageRange(forDisplayRange range: NSRange) -> NSRange? {
        wikiLinkMetadata[WikiLinkService.RangeKey(range)]?.storageRange
    }

    func storageRange(containingDisplayLocation location: Int) -> NSRange? {
        for (key, value) in wikiLinkMetadata {
            let displayRange = NSRange(location: key.location, length: key.length)
            if NSLocationInRange(location, displayRange) {
                return value.storageRange
            }
        }
        return nil
    }

    // Methods are split across the following extensions:
    //   - +TextDelegate    — NSTextViewDelegate hot path
    //   - +Restyling       — restyle pipeline + parsedDocument cache
    //   - +InlineSelection — inline-token detection + image-embed activation
    //   - +CodeBlocks      — copy-button overlay
    //   - +Find            — find-in-document highlights
    //   - +Notifications   — bus + appearance bridge
    //   - +Autocorrect     — spell/grammar/quote toggles
    //   - +WritingTools    — macOS 15+ Writing Tools session

    deinit {
        // removeObserver(self) is documented thread-safe and removes all
        // observers added with `self` as the observer — covers the selector-
        // based bus + appearance subscriptions. No @MainActor-isolated state
        // is touched.
        NotificationCenter.default.removeObserver(self)
        // `Timer.scheduledTimer(target:)` retains its target until
        // invalidate, so without this the chevron animation timer would
        // hold a strong ref to a dead coordinator on page switch.
        chevronAnimationTimer?.invalidate()
    }
}

extension NSTextView {
    func viewRect(forCharacterRange range: NSRange, using bridge: LayoutBridge?) -> CGRect? {
        guard range.location != NSNotFound,
            let bridge = bridge,
            let textContainer = textContainer
        else { return nil }
        var boundingRect = bridge.boundingRect(forCharacterRange: range, in: textContainer)
        let containerOrigin = textContainerOrigin
        boundingRect.origin.x += containerOrigin.x
        boundingRect.origin.y += containerOrigin.y
        if let scrollView = enclosingScrollView {
            let contentOffset = scrollView.contentView.bounds.origin
            boundingRect.origin.x -= contentOffset.x
            boundingRect.origin.y -= contentOffset.y
        }
        return boundingRect
    }
}
