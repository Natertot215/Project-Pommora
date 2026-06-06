import Foundation
import MarkdownPM
import Testing

@testable import Pommora

/// Pins the PURE wiring logic that drives the `[[` / `{{` autocomplete (E5-D):
/// the trigger gate, the storage-fragment builder, the query-kind mapping, and
/// the `EntityRef → AutoCompleteCandidate` mapping.
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

    @Test func showsForItemLinkWithTypedPlaceholder() {
        #expect(AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .itemLink, placeholder: "Tas")))
    }

    @Test func suppressedForEmptyWikiLinkPlaceholder() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .wikiLink, placeholder: "")))
    }

    @Test func suppressedForEmptyItemLinkPlaceholder() {
        #expect(!AutoCompleteWiring.shouldShowAutocomplete(for: state(kind: .itemLink, placeholder: "")))
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

    @Test func itemLinkFragmentIsDoubleCurlyBraces() {
        #expect(AutoCompleteWiring.fragment(kind: .itemLink, title: "Buy milk") == "{{Buy milk}}")
    }

    // MARK: - Query kind

    @Test func wikiLinkQueriesPages() {
        #expect(AutoCompleteWiring.queryKind(for: .wikiLink) == .page)
    }

    @Test func itemLinkQueriesItems() {
        #expect(AutoCompleteWiring.queryKind(for: .itemLink) == .item)
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
        let itemRef = EntityRef(id: "i1", kind: .item, title: "I", icon: nil)
        #expect(AutoCompleteWiring.candidate(from: pageRef).icon == ContextDisplayResolver.defaultIcon(for: .page))
        #expect(AutoCompleteWiring.candidate(from: itemRef).icon == ContextDisplayResolver.defaultIcon(for: .item))
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
