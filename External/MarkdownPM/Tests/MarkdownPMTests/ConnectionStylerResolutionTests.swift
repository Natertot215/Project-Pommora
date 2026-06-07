import AppKit
import Foundation
import Testing

@testable import MarkdownPM

/// Pins the resolved-vs-unresolved styling for `[[ ]]` page links and
/// `{{ }}` item links once a real resolver is wired into
/// `configuration.services`. The regression marker: an UNRESOLVED `[[Ghost]]`
/// must render `secondaryLabelColor` (muted) — NOT the systemBlue
/// incompleteLink color the greedy `styleIncompleteLinkBrackets` pass used to
/// stamp over the title of EVERY completed wikilink (last-writer-wins).
@MainActor
@Suite("ConnectionStylerResolution")
struct ConnectionStylerResolutionTests {

    /// Faithfully mimics `PommoraConnectionResolver`'s contract without the app
    /// module: resolves any display name in `knownNames` (case-insensitively)
    /// to an existing target carrying an icon; everything else is `nil`.
    struct StubResolver: WikiLinkResolver {
        let knownNames: Set<String>
        func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
            guard knownNames.contains(displayName.lowercased()) else { return nil }
            return WikiLinkResolution(id: displayName, exists: true, icon: "star.fill")
        }
    }

    /// Collapse the emitted `[StyledRange]` to the final attributes at a single
    /// location, replaying the renderer's apply loop exactly
    /// (`NativeTextViewCoordinator+Restyling`): `addAttribute(key:value:range:)`
    /// per key in emission order → last-writer-wins per key.
    ///
    /// `caretAt` controls which token is ACTIVE (caret-inside): when `nil` the
    /// caret sits past the last token so every connection renders INACTIVE; when
    /// a location is supplied the token containing it renders in its ACTIVE (raw,
    /// editable) form. Both `inspectLocation` and `caretAt` are caller-supplied so
    /// a single helper covers the caret-outside AND caret-inside matrices.
    private func finalAttributes(
        body: String,
        knownNames: Set<String>,
        at inspectLocation: Int,
        caretAt: Int? = nil
    ) -> [NSAttributedString.Key: Any] {
        let services = MarkdownPMServices(
            wikiLinks: StubResolver(knownNames: knownNames),
            itemLinks: StubResolver(knownNames: knownNames)
        )
        let configuration = MarkdownPMConfiguration(services: services)

        let tokens = MarkdownTokenizer.parseTokens(in: body)
        // Default caret OUTSIDE every token (trailing position past the last
        // token's end) → all connections INACTIVE; an explicit `caretAt` makes
        // the token containing it ACTIVE (raw editable form).
        let caret = caretAt ?? (body as NSString).length
        let active = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: caret, length: 0),
            tokens: tokens,
            in: body as NSString
        )
        let ranges = MarkdownPMStyler.styleAttributes(
            text: body,
            fontName: "SF Pro Text",
            fontSize: 15,
            caretLocation: caret,
            activeTokenIndices: active,
            precomputedTokens: tokens,
            configuration: configuration
        )

        let storage = NSMutableAttributedString(string: body)
        for (range, attrs) in ranges {
            for (key, value) in attrs {
                storage.addAttribute(key, value: value, range: range)
            }
        }
        return storage.attributes(at: inspectLocation, effectiveRange: nil)
    }

    /// Body indices (UTF-16):
    /// `[[Alpha]]` → `A` at 2; `[[Ghost]]` → `G` at 12;
    /// `{{Beta}}` → `B` at 22; `{{Casper}}` → `C` at 31.
    private let body = "[[Alpha]] [[Ghost]] {{Beta}} {{Casper}} "
    private let known: Set<String> = ["alpha", "beta"]

    @Test("Resolved [[Alpha]] keeps a clickable .link (theme link color)")
    func resolvedWikiLinkHasLink() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 2) // `A`
        #expect(attrs[.link] != nil)
    }

    @Test("Unresolved [[Ghost]] is muted secondaryLabelColor, NOT blue, NO .link")
    func unresolvedWikiLinkIsMutedNotBlue() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 12) // `G`
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(attrs[.link] == nil)
    }

    @Test("Resolved {{Beta}} renders an item highlight (.itemLinkTitle + .itemChipBounds + .itemChipIcon)")
    func resolvedItemLinkHasChip() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 22) // `B`
        #expect(attrs[.itemLinkTitle] as? String == "Beta")
        #expect(attrs[.itemChipBounds] != nil)
        #expect(attrs[.itemChipIcon] as? String == "star.fill") // StubResolver returns "star.fill"
    }

    @Test("Unresolved {{Casper}} is muted secondaryLabelColor, no highlight attrs")
    func unresolvedItemLinkIsMutedNoChip() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 31) // `C`
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(attrs[.itemLinkTitle] == nil)
        #expect(attrs[.itemChipBounds] == nil)
    }

    // MARK: - Caret INSIDE a resolved token → raw editable form (E3 behavior)

    /// A resolved `[[Alpha]]` with the caret INSIDE the brackets must NOT emit
    /// `.link` on its title — the link is suppressed while ACTIVE so the source
    /// stays plain/editable (the `isActive` gate in `styleWikiLinks`). The
    /// caret-OUTSIDE companion (`resolvedWikiLinkHasLink`) asserts the inverse.
    @Test("Caret inside a resolved [[Alpha]] suppresses .link (raw editable)")
    func activeResolvedWikiLinkHasNoLink() {
        // Caret at 4 = between `l` and `p` inside `[[Alpha]]` (content 2..<7).
        let attrs = finalAttributes(body: body, knownNames: known, at: 2, caretAt: 4)
        #expect(attrs[.link] == nil)
    }

    /// A resolved `{{Beta}}` with the caret INSIDE must NOT render the highlight —
    /// no `.itemChipBounds` / `.itemLinkTitle`, no clearing kern collapse — so the
    /// raw `{{Beta}}` stays visible + editable (the `!isActive` guard).
    @Test("Caret inside a resolved {{Beta}} suppresses the highlight (raw editable)")
    func activeResolvedItemLinkHasNoChip() {
        // Caret at 24 = between `t` and `a` inside `{{Beta}}` (content 22..<26).
        let attrs = finalAttributes(body: body, knownNames: known, at: 22, caretAt: 24)
        #expect(attrs[.itemChipBounds] == nil)
        #expect(attrs[.itemLinkTitle] == nil)
        #expect(attrs[.link] == nil)
    }
}
