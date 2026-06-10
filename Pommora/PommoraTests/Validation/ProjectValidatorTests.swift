import Foundation
import Testing

@testable import Pommora

@Suite("ProjectValidator")
struct ProjectValidatorTests {

    @Test("non-empty title passes")
    func nonEmptyPasses() throws {
        try ProjectValidator.validate(title: "GTD method", existing: [])
    }

    @Test("empty title throws emptyTitle")
    func emptyFails() {
        #expect(throws: ProjectValidator.ValidationError.emptyTitle) {
            try ProjectValidator.validate(title: "", existing: [])
        }
    }

    @Test("whitespace-only title throws emptyTitle")
    func whitespaceFails() {
        #expect(throws: ProjectValidator.ValidationError.emptyTitle) {
            try ProjectValidator.validate(title: "   \t  ", existing: [])
        }
    }

    @Test("forward slash throws invalidTitleCharacters")
    func slashFails() {
        #expect(throws: ProjectValidator.ValidationError.invalidTitleCharacters) {
            try ProjectValidator.validate(title: "Foo/Bar", existing: [])
        }
    }

    @Test("backslash throws invalidTitleCharacters")
    func backslashFails() {
        #expect(throws: ProjectValidator.ValidationError.invalidTitleCharacters) {
            try ProjectValidator.validate(title: "Foo\\Bar", existing: [])
        }
    }

    @Test("colon throws invalidTitleCharacters")
    func colonFails() {
        #expect(throws: ProjectValidator.ValidationError.invalidTitleCharacters) {
            try ProjectValidator.validate(title: "Foo:Bar", existing: [])
        }
    }

    @Test("case-insensitive duplicate throws duplicateTitle")
    func duplicateFails() {
        let existing = [makeProject(title: "GTD")]
        #expect(throws: ProjectValidator.ValidationError.duplicateTitle) {
            try ProjectValidator.validate(title: "gtd", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameToSelfPasses() throws {
        let p = makeProject(title: "GTD")
        try ProjectValidator.validate(title: "GTD", existing: [p], excluding: p)
    }

    private func makeProject(title: String) -> Project {
        Project(
            id: ULID.generate(), title: title,
            icon: nil, blocks: [], modifiedAt: Date())
    }
}
