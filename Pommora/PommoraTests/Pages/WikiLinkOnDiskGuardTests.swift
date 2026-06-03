import AppKit
import Foundation
import MarkdownPM
import Testing

/// DEC-1 honest anchor: wikilinks MUST be PLAIN `[[Title]]` on disk (target
/// identity is the page's frontmatter ULID, never embedded in the link). The
/// shared producer for BOTH save sinks is WikiLinkService.makeStorageState:
///   - normal typing:        NativeTextViewCoordinator+TextDelegate.swift:70
///   - Writing-Tools commit: NativeTextViewCoordinator+Services.swift:325
///
/// Verified current behavior: makeStorageState has NO id-strip — when a
/// resolver stamps `.wikiLinkID`, it embeds `[[Name|id]]` (WikiLinkService
/// .swift:148). The structural strip is LD-28 and ships in the Wiki-Link session. This
/// suite pins today's behavior honestly and carries the DEC-1 target as a
/// known-gap anchor that flips when the real guard lands.
@Suite("WikiLinkOnDiskGuard")
struct WikiLinkOnDiskGuardTests {

    @Test("CURRENT: a resolver-stamped id is embedded as [[Name|id]] (no strip yet — shared sink producer)")
    func currentlyEmbedsResolverId() {
        // Simulate the resolver having stamped an id onto the live storage's
        // .wikiLinkID attribute — exactly what makeStorageState reads at :138.
        let attributed = NSTextStorage(string: "see [[Note]] end")
        let nameRange = ("see [[Note]] end" as NSString).range(of: "Note")
        attributed.addAttribute(.wikiLinkID, value: "01HZX9ABCDEFGHJKMNPQRSTVWX", range: nameRange)

        let (storage, _) = WikiLinkService.makeStorageState(
            from: "see [[Note]] end",
            existingMetadata: [:],
            textStorage: attributed
        )
        // Honest pin of today's behavior: the id IS embedded. Both save sinks
        // (+TextDelegate:70, +Services:325) feed this same producer.
        #expect(storage == "see [[Note]] end".replacingOccurrences(
            of: "[[Note]]", with: "[[Note|01HZX9ABCDEFGHJKMNPQRSTVWX]]"))
    }

    /// DEC-1 TARGET — known gap. When the Wiki-Link session's structural strip lands in
    /// the consolidated save path (LD-28), the persisted string must stay
    /// id-free even with a resolver-stamped id. This anchor is expected to
    /// FAIL today and flip green when the guard ships; mark it accordingly
    /// (Swift Testing: enable once the strip lands, or carry as a documented
    /// known-failure). It asserts the POLICY, not a test-local helper.
    @Test("DEC-1 TARGET (the Wiki-Link session): persisted string stays plain [[Name]] even with a resolved id",
          .disabled("DEC-1 structural strip ships in the Wiki-Link session (LD-28); flips green then"))
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
