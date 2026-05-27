import Foundation
import Testing

@testable import Pommora

@Suite("DefaultTitleResolver")
struct DefaultTitleResolverTests {

    @Test("empty siblings yields bare default")
    func bareDefault() {
        let title = DefaultTitleResolver.resolve(label: "Folder", existingTitles: [])
        #expect(title == "New Folder")
    }

    @Test("default already taken yields '2' disambiguator")
    func firstDisambiguator() {
        let title = DefaultTitleResolver.resolve(
            label: "Folder", existingTitles: ["New Folder"]
        )
        #expect(title == "New Folder 2")
    }

    @Test("'New Folder' + 'New Folder 2' yields 'New Folder 3'")
    func skipsToFreeInteger() {
        let title = DefaultTitleResolver.resolve(
            label: "Folder", existingTitles: ["New Folder", "New Folder 2"]
        )
        #expect(title == "New Folder 3")
    }

    @Test("gap in disambiguator sequence picks lowest free integer")
    func gapPickedFirst() {
        // "New Folder 2" exists but bare "New Folder" doesn't — bare wins because
        // the lowest free slot is the bare default itself.
        let title = DefaultTitleResolver.resolve(
            label: "Folder", existingTitles: ["New Folder 2"]
        )
        #expect(title == "New Folder")
    }

    @Test("gap in continuous suffix sequence picks the gap")
    func gapInContinuousSequence() {
        // bare + 2 + 4 taken → 3 is the next free slot.
        let title = DefaultTitleResolver.resolve(
            label: "Folder",
            existingTitles: ["New Folder", "New Folder 2", "New Folder 4"]
        )
        #expect(title == "New Folder 3")
    }

    @Test("unrelated sibling titles don't interfere")
    func unrelatedTitlesIgnored() {
        let title = DefaultTitleResolver.resolve(
            label: "Folder",
            existingTitles: ["Research", "Cooking", "Garden"]
        )
        #expect(title == "New Folder")
    }

    @Test("comparison is case-sensitive")
    func caseSensitive() {
        // "new folder" (lowercase) is a different string than "New Folder";
        // the resolver only collides on exact matches, matching the validator's
        // exact-title uniqueness check.
        let title = DefaultTitleResolver.resolve(
            label: "Folder", existingTitles: ["new folder"]
        )
        #expect(title == "New Folder")
    }

    @Test("multi-word label substitutes verbatim")
    func multiWordLabel() {
        let title = DefaultTitleResolver.resolve(
            label: "Page Collection", existingTitles: []
        )
        #expect(title == "New Page Collection")
    }

    @Test("disambiguator format is space-separated integer")
    func disambiguatorFormat() {
        // Plan locked: "New <Label> 2" / "New <Label> 3" — no parentheses, no
        // dash, just a space and the integer. Verifies the format is stable.
        let title = DefaultTitleResolver.resolve(
            label: "Item", existingTitles: ["New Item"]
        )
        #expect(title == "New Item 2")
    }
}
