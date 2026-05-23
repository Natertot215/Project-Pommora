import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionValidator")
struct PageCollectionValidatorTests {

    @Test("valid title in empty PageType passes")
    func valid() throws {
        try PageCollectionValidator.validate(title: "Tasks", existingInType: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: PageCollectionValidator.ValidationError.emptyTitle) {
            try PageCollectionValidator.validate(title: "", existingInType: [])
        }
        #expect(throws: PageCollectionValidator.ValidationError.invalidTitleCharacters) {
            try PageCollectionValidator.validate(title: "A/B", existingInType: [])
        }
    }

    @Test("duplicate within PageType throws")
    func duplicate() {
        let existing = [
            PageCollection(
                id: ULID.generate(),
                typeID: "01HV",
                title: "Tasks",
                folderURL: URL(fileURLWithPath: "/tmp/V/Tasks", isDirectory: true),
                modifiedAt: Date()
            )
        ]
        #expect(throws: PageCollectionValidator.ValidationError.duplicateTitle) {
            try PageCollectionValidator.validate(title: "tasks", existingInType: existing)
        }
    }
}
