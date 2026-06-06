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
    private func finalAttributes(
        body: String,
        knownNames: Set<String>,
        at location: Int
    ) -> [NSAttributedString.Key: Any] {
        let services = MarkdownPMServices(
            wikiLinks: StubResolver(knownNames: knownNames),
            itemLinks: StubResolver(knownNames: knownNames)
        )
        let configuration = MarkdownPMConfiguration(services: services)

        let tokens = MarkdownTokenizer.parseTokens(in: body)
        // Caret placed OUTSIDE every token (the trailing position past the last
        // token's end) so all four connections render in their INACTIVE form.
        let caret = (body as NSString).length
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
        return storage.attributes(at: location, effectiveRange: nil)
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

    @Test("Resolved {{Beta}} renders an item chip (.itemLinkTitle + .itemChipIcon)")
    func resolvedItemLinkHasChip() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 22) // `B`
        #expect(attrs[.itemLinkTitle] as? String == "Beta")
        #expect(attrs[.itemChipIcon] as? String == "star.fill")
    }

    @Test("Unresolved {{Casper}} is muted secondaryLabelColor, no chip attrs")
    func unresolvedItemLinkIsMutedNoChip() {
        let attrs = finalAttributes(body: body, knownNames: known, at: 31) // `C`
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(attrs[.itemLinkTitle] == nil)
        #expect(attrs[.itemChipIcon] == nil)
    }
}
