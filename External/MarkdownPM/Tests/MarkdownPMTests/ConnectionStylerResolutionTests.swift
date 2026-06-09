import AppKit
import Foundation
import Testing

@testable import MarkdownPM

/// Pins the resolved-vs-unresolved styling for `[[ ]]` page links and
/// `{{ }}` chip links once a real resolver is wired into
/// `configuration.services`. The regression marker: an UNRESOLVED `[[Ghost]]`
/// must render `secondaryLabelColor` (muted) — NOT the systemBlue
/// incompleteLink color the greedy `styleIncompleteLinkBrackets` pass used to
/// stamp over the title of EVERY completed wikilink (last-writer-wins).
///
/// Chip RENDERING is behind `renderChipLinksAsChips` (default OFF): the
/// chip-on tests flip the gate to keep the dormant chip pipeline covered;
/// the gate-off test pins the default plain-link rendering.
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
        caretAt: Int? = nil,
        renderChipLinksAsChips: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        let services = MarkdownPMServices(
            wikiLinks: StubResolver(knownNames: knownNames),
            chipLinks: StubResolver(knownNames: knownNames)
        )
        var configuration = MarkdownPMConfiguration(services: services)
        configuration.renderChipLinksAsChips = renderChipLinksAsChips

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

    @Test("Gate ON: resolved {{Beta}} renders a chip highlight (.chipLinkTitle + .chipLinkBounds + .chipLinkIcon)")
    func resolvedChipLinkHasChipWhenGateOn() {
        let attrs = finalAttributes(
            body: body, knownNames: known, at: 22, renderChipLinksAsChips: true) // `B`
        #expect(attrs[.chipLinkTitle] as? String == "Beta")
        #expect(attrs[.chipLinkBounds] != nil)
        #expect(attrs[.chipLinkIcon] as? String == "star.fill") // StubResolver returns "star.fill"
        #expect(attrs[.link] != nil) // click routing to onChipLinkClick depends on .link
    }

    @Test("Gate OFF (default): resolved {{Beta}} renders a VISIBLE plain link — .link + .chipLinkTitle + link color + underline, NO chip leakage")
    func resolvedChipLinkIsPlainLinkWhenGateOff() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 22) // `B`
        #expect(attrs[.link] != nil)
        #expect(attrs[.chipLinkTitle] as? String == "Beta")
        #expect(attrs[.chipLinkBounds] == nil)
        #expect(attrs[.chipLinkIcon] == nil)
        // The visible-link contract: linkTextAttributes is cleared on the
        // NSTextView, so the styler must stamp the visuals itself — theme link
        // foreground (NOT clear, NOT nil) + underline, and NO kern (kern is the
        // chip-pipeline's collapse trick; its presence = chip leakage).
        #expect(attrs[.kern] == nil)
        #expect(attrs[.foregroundColor] as? NSColor == MarkdownPMTheme.default.link)
        #expect(attrs[.foregroundColor] as? NSColor != NSColor.clear)
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Unresolved {{Casper}} is muted secondaryLabelColor, no highlight attrs (gate ON)")
    func unresolvedChipLinkIsMutedNoChip() {
        let attrs = finalAttributes(
            body: body, knownNames: known, at: 31, renderChipLinksAsChips: true) // `C`
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(attrs[.chipLinkTitle] == nil)
        #expect(attrs[.chipLinkBounds] == nil)
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
    /// no `.chipLinkBounds` / `.chipLinkTitle`, no clearing kern collapse — so the
    /// raw `{{Beta}}` stays visible + editable (the `!isActive` guard). Gate ON so
    /// the active-state suppression (not the gate) is what's proven.
    @Test("Caret inside a resolved {{Beta}} suppresses the highlight (raw editable, gate ON)")
    func activeResolvedChipLinkHasNoChip() {
        // Caret at 24 = between `t` and `a` inside `{{Beta}}` (content 22..<26).
        let attrs = finalAttributes(
            body: body, knownNames: known, at: 22, caretAt: 24, renderChipLinksAsChips: true)
        #expect(attrs[.chipLinkBounds] == nil)
        #expect(attrs[.chipLinkTitle] == nil)
        #expect(attrs[.link] == nil)
    }
}
