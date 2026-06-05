import AppKit
import Foundation
import MarkdownPM
import Testing

/// DEC-1 guard: wikilinks MUST be PLAIN `[[Title]]` on disk (target identity is
/// the page's frontmatter ULID, never embedded in the link). The shared producer
/// for BOTH save sinks is WikiLinkService.makeStorageState:
///   - normal typing:        NativeTextViewCoordinator+TextDelegate.swift:70
///   - Writing-Tools commit: NativeTextViewCoordinator+Services.swift:325
///
/// LD-28 (shipped) makes makeStorageState ALWAYS write `[[Name]]` — even when a
/// resolver has stamped a `.wikiLinkID` onto the live storage, the id never
/// reaches disk. This suite is the active guard for that invariant.
@Suite("WikiLinkOnDiskGuard")
struct WikiLinkOnDiskGuardTests {

    /// DEC-1 guard (active since LD-28): the persisted string stays id-free even
    /// when a resolver has stamped a `.wikiLinkID`. Asserts the POLICY (no
    /// `[[Name|id]]` may reach disk), not a test-local helper.
    @Test("DEC-1: persisted string stays plain [[Name]] even with a resolved id")
    func dec1TargetNoIdOnDisk() {
        let attributed = NSTextStorage(string: "a [[X]] b")
        let r = ("a [[X]] b" as NSString).range(of: "X")
        attributed.addAttribute(.wikiLinkID, value: "01HZX9ABCDEFGHJKMNPQRSTVWX", range: r)
        let (storage, _) = WikiLinkService.makeStorageState(
            from: "a [[X]] b", existingMetadata: [:], textStorage: attributed)
        // No id-bearing [[Name|id]] may reach disk once the strip lands.
        let pipeInLink = try! NSRegularExpression(
            pattern: #"(?<!!)\[\[[^\]\r\n]*\|[^\]\r\n]+\]\]"#)
        let ns = storage as NSString
        let hits = pipeInLink.numberOfMatches(
            in: storage, range: NSRange(location: 0, length: ns.length))
        #expect(hits == 0, "an id-bearing [[Name|id]] reached disk: \(storage)")
    }
}
