import Foundation
import Testing

@testable import Pommora

@Suite("PageTypeValidator")
struct PageTypeValidatorTests {

    @Test("valid title passes")
    func valid() throws {
        try PageTypeValidator.validate(title: "Planner", existing: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: PageTypeValidator.ValidationError.emptyTitle) {
            try PageTypeValidator.validate(title: "  ", existing: [])
        }
        #expect(throws: PageTypeValidator.ValidationError.invalidTitleCharacters) {
            try PageTypeValidator.validate(title: "A:B", existing: [])
        }
    }

    @Test("duplicate PageType title throws")
    func duplicate() {
        let existing = [makePageType(title: "Planner")]
        #expect(throws: PageTypeValidator.ValidationError.duplicateTitle) {
            try PageTypeValidator.validate(title: "PLANNER", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameSelf() throws {
        let v = makePageType(title: "Planner")
        try PageTypeValidator.validate(title: "Planner", existing: [v], excluding: v)
    }

    private func makePageType(title: String) -> PageType {
        PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date())
    }
}
