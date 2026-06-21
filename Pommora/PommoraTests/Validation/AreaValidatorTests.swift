import Foundation
import Testing

@testable import Pommora

@Suite("AreaValidator")
struct AreaValidatorTests {

    @Test("non-empty title passes")
    func nonEmptyPasses() throws {
        try AreaValidator.validate(title: "Personal", existing: [])
    }

    @Test("empty title throws emptyTitle")
    func emptyFails() {
        #expect(throws: AreaValidator.ValidationError.emptyTitle) {
            try AreaValidator.validate(title: "", existing: [])
        }
    }

    @Test("whitespace-only title throws emptyTitle")
    func whitespaceFails() {
        #expect(throws: AreaValidator.ValidationError.emptyTitle) {
            try AreaValidator.validate(title: "   \t  ", existing: [])
        }
    }

    @Test("forward slash throws invalidTitleCharacters")
    func slashFails() {
        #expect(throws: AreaValidator.ValidationError.invalidTitleCharacters) {
            try AreaValidator.validate(title: "Foo/Bar", existing: [])
        }
    }

    @Test("backslash throws invalidTitleCharacters")
    func backslashFails() {
        #expect(throws: AreaValidator.ValidationError.invalidTitleCharacters) {
            try AreaValidator.validate(title: "Foo\\Bar", existing: [])
        }
    }

    @Test("colon throws invalidTitleCharacters")
    func colonFails() {
        #expect(throws: AreaValidator.ValidationError.invalidTitleCharacters) {
            try AreaValidator.validate(title: "Foo:Bar", existing: [])
        }
    }

    @Test("case-insensitive duplicate throws duplicateTitle")
    func duplicateFails() {
        let existing = [makeArea(title: "Personal")]
        #expect(throws: AreaValidator.ValidationError.duplicateTitle) {
            try AreaValidator.validate(title: "PERSONAL", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameToSelfPasses() throws {
        let s = makeArea(title: "Personal")
        try AreaValidator.validate(title: "Personal", existing: [s], excluding: s)
    }

    private func makeArea(title: String) -> Area {
        Area(
            id: ULID.generate(),
            title: title,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
    }
}
