import AppKit
import Foundation
import Testing
@testable import MarkdownPM

/// Pins the LIVE WikiLinkService display↔storage transform. This is the seam
/// the post-rebuild Wiki-Link session builds on; Phase 2 freezes its current
/// behavior. The transform runs on every load/restyle/save — do NOT
/// "simplify away" the live adapter (CodeMap F4).
@Suite("WikiLinkRoundTrip")
struct WikiLinkRoundTripTests {

    @Test("Storage [[Name|id]] → display [[Name]] strips the id, keeps metadata")
    func storageToDisplayStripsId() {
        let (display, meta) = WikiLinkService.makeDisplayState(from: "see [[Note|01ABC]] end")
        #expect(display == "see [[Note]] end")
        // Metadata recovers the id for the display occurrence.
        #expect(meta.values.contains { $0.id == "01ABC" })
    }

    @Test("Display [[Name]] with NO resolver id round-trips to plain [[Name]]")
    func displayToStoragePlainNoId() {
        let (storage, _) = WikiLinkService.makeStorageState(
            from: "see [[Note]] end",
            existingMetadata: [:],
            textStorage: nil
        )
        // No id anywhere → storage stays plain. This is the DEC-1 default.
        #expect(storage == "see [[Note]] end")
    }

    @Test("Image embed ![[Img]] is EXCLUDED from the wikilink transform")
    func imageEmbedExcluded() {
        // (?<!!) lookbehind routes ![[…]] away from the rewrite.
        let (display, meta) = WikiLinkService.makeDisplayState(from: "![[Img|x]]")
        #expect(display == "![[Img|x]]")   // unchanged
        #expect(meta.isEmpty)
    }

    @Test("Multibyte name round-trips with correct UTF-16 ranges")
    func multibyteRoundTrip() {
        let src = "x [[日本語|01ABC]] y"
        let (display, _) = WikiLinkService.makeDisplayState(from: src)
        #expect(display == "x [[日本語]] y")
    }

    @Test("Round-trip is stable: display→storage→display with no id is identity")
    func stableRoundTrip() {
        let display0 = "a [[One]] b [[Two]] c"
        let (storage, _) = WikiLinkService.makeStorageState(
            from: display0, existingMetadata: [:], textStorage: nil)
        let (display1, _) = WikiLinkService.makeDisplayState(from: storage)
        #expect(display1 == display0)
    }
}
