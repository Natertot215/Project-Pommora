import Foundation
import MarkdownPM
import Testing

@testable import Pommora

/// Pins the PURE wiring logic that drives the `[[` autocomplete (E5-D):
/// the trigger gate, the storage-fragment builder, and
/// the `EntityRef → AutoCompleteCandidate` mapping. `[[ ]]` is the only
/// connection syntax (PagesV2 decision #3) — the dormant `.chipLink` kind
/// must never trigger, and every fragment/query resolves page-side.
///
/// The popup presentation, caret anchoring, and the live NSTextView insertion
/// are runtime concerns (SwiftUI overlay placement + AppKit text replacement);
/// they are NOT unit-testable here and are verified by manual run. These tests
/// cover everything BELOW that runtime boundary.
@Suite("AutoCompleteWiringTests")
struct AutoCompleteWiringTests {

    private func state(kind: InlineSelectionKind, placeholder: String) -> InlineSelectionState {
        InlineSelectionState(
            kind: kind,
            selection: WikiLinkSelection(
                displayRange: NSRange(location: 0, length: placeholder.count),
                storageRange: nil,
                placeholder: placeholder
            )
        )
    }

    // MARK: - Trigger gate

    @Test func showsForWikiLinkWithTypedPlaceholder() {
        #expect(AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .wikiLink, placeholder: "Atl")))
    }

    @Test func suppressedForChipLinkWithTypedPlaceholder() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .chipLink, placeholder: "Tas")))
    }

    @Test func suppressedForEmptyWikiLinkPlaceholder() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .wikiLink, placeholder: "")))
    }

    @Test func suppressedForEmptyChipLinkPlaceholder() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .chipLink, placeholder: "")))
    }

    @Test func suppressedForImageEmbed() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .imageEmbed, placeholder: "pic")))
    }

    @Test func suppressedForNilState() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: nil))
    }

    // MARK: - Fragment builder

    @Test func wikiLinkFragmentIsDoubleSquareBrackets() {
        #expect(AutoCompleteWiring.fragment(kind: .wikiLink, title: "Project Atlas") == "[[Project Atlas]]")
    }

    @Test func fragmentIsWikiLinkRegardlessOfKind() {
        #expect(AutoCompleteWiring.fragment(kind: .chipLink, title: "Buy milk") == "[[Buy milk]]")
    }

    // MARK: - EntityRef → AutoCompleteCandidate mapping

    @Test func mappingCarriesIdIconTitle() {
        let ref = EntityRef(id: "01ABC", kind: .page, title: "Atlas", icon: "star.fill")
        let candidate = AutoCompleteWiring.candidate(from: ref)
        #expect(candidate.id == "01ABC")
        #expect(candidate.icon == "star.fill")
        #expect(candidate.title == "Atlas")
    }

    @Test func mappingFallsBackToKindDefaultIconWhenNil() {
        let pageRef = EntityRef(id: "p1", kind: .page, title: "P", icon: nil)
        #expect(AutoCompleteWiring.candidate(from: pageRef).icon == ContextDisplayResolver.defaultIcon(for: .page))
    }

    @Test func mapsArrayPreservingOrderAndCount() {
        let refs = [
            EntityRef(id: "1", kind: .page, title: "One", icon: "1.circle"),
            EntityRef(id: "2", kind: .page, title: "Two", icon: nil),
        ]
        let candidates = AutoCompleteWiring.candidates(from: refs)
        #expect(candidates.count == 2)
        #expect(candidates.map(\.id) == ["1", "2"])
        #expect(candidates[1].icon == ContextDisplayResolver.defaultIcon(for: .page))
    }
}
