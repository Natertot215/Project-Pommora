import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionValidator")
struct PageCollectionValidatorTests {

    @Test("valid title passes")
    func valid() throws {
        try PageCollectionValidator.validate(title: "Planner", existing: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: PageCollectionValidator.ValidationError.emptyTitle) {
            try PageCollectionValidator.validate(title: "  ", existing: [])
        }
        #expect(throws: PageCollectionValidator.ValidationError.invalidTitleCharacters) {
            try PageCollectionValidator.validate(title: "A:B", existing: [])
        }
    }

    @Test("duplicate PageCollection title throws")
    func duplicate() {
        let existing = [makePageCollection(title: "Planner")]
        #expect(throws: PageCollectionValidator.ValidationError.duplicateTitle) {
            try PageCollectionValidator.validate(title: "PLANNER", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameSelf() throws {
        let v = makePageCollection(title: "Planner")
        try PageCollectionValidator.validate(title: "Planner", existing: [v], excluding: v)
    }

    private func makePageCollection(title: String) -> PageCollection {
        PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date())
    }
}
