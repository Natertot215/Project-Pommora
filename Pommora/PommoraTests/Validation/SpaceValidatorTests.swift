import Foundation
import Testing
@testable import Pommora

@Suite("SpaceValidator")
struct SpaceValidatorTests {

    @Test("non-empty title passes")
    func nonEmptyPasses() throws {
        try SpaceValidator.validate(title: "Personal", existing: [])
    }

    @Test("empty title throws emptyTitle")
    func emptyFails() {
        #expect(throws: SpaceValidator.ValidationError.emptyTitle) {
            try SpaceValidator.validate(title: "", existing: [])
        }
    }

    @Test("whitespace-only title throws emptyTitle")
    func whitespaceFails() {
        #expect(throws: SpaceValidator.ValidationError.emptyTitle) {
            try SpaceValidator.validate(title: "   \t  ", existing: [])
        }
    }

    @Test("forward slash throws invalidTitleCharacters")
    func slashFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo/Bar", existing: [])
        }
    }

    @Test("backslash throws invalidTitleCharacters")
    func backslashFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo\\Bar", existing: [])
        }
    }

    @Test("colon throws invalidTitleCharacters")
    func colonFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo:Bar", existing: [])
        }
    }

    @Test("case-insensitive duplicate throws duplicateTitle")
    func duplicateFails() {
        let existing = [makeSpace(title: "Personal")]
        #expect(throws: SpaceValidator.ValidationError.duplicateTitle) {
            try SpaceValidator.validate(title: "PERSONAL", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameToSelfPasses() throws {
        let s = makeSpace(title: "Personal")
        try SpaceValidator.validate(title: "Personal", existing: [s], excluding: s)
    }

    private func makeSpace(title: String) -> Space {
        Space(
            id: ULID.generate(),
            title: title,
            color: .blue,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
    }
}
