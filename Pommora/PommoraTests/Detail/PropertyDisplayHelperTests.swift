import Foundation
import Testing

@testable import Pommora

/// Resolution tests for `PropertyDisplay.treatment(for:)` — the pure branching
/// decision that drives `PropertyCellDisplay`'s per-property `display` modes
/// (Task 2.2). These assert *which treatment* a (display, type) pair yields, not
/// any rendered pixels (the SwiftUI body is never evaluated). The renderer in
/// `PropertyCellDisplay` consumes the same helper, so testing the decision here
/// covers the read-side branching without a snapshot.
@Suite("PropertyDisplayHelperTests")
struct PropertyDisplayHelperTests {

    // MARK: - File / image treatments

    @Test("thumbnail on a file type yields the image treatment")
    func thumbnailFileIsImage() {
        #expect(PropertyDisplay.thumbnail.treatment(for: .file) == .image)
    }

    @Test("banner on a file type yields the image treatment")
    func bannerFileIsImage() {
        #expect(PropertyDisplay.banner.treatment(for: .file) == .image)
    }

    @Test("thumbnail on a non-file type falls back to default")
    func thumbnailNonFileIsDefault() {
        #expect(PropertyDisplay.thumbnail.treatment(for: .url) == .default)
        #expect(PropertyDisplay.banner.treatment(for: .relation) == .default)
    }

    // MARK: - Relation / list treatment

    @Test("list on a relation type yields the vertical treatment")
    func listRelationIsVertical() {
        #expect(PropertyDisplay.list.treatment(for: .relation) == .verticalList)
    }

    @Test("list on a non-relation type falls back to default")
    func listNonRelationIsDefault() {
        #expect(PropertyDisplay.list.treatment(for: .file) == .default)
        #expect(PropertyDisplay.list.treatment(for: .select) == .default)
    }

    // MARK: - Inline / fall-through defaults

    @Test("inline always yields the default treatment")
    func inlineIsDefault() {
        for type in PropertyType.allCases {
            #expect(PropertyDisplay.inline.treatment(for: type) == .default)
        }
    }

    @Test("chips and unknown yield the default treatment")
    func chipsAndUnknownAreDefault() {
        #expect(PropertyDisplay.chips.treatment(for: .relation) == .default)
        #expect(PropertyDisplay.unknown("future").treatment(for: .file) == .default)
    }
}
