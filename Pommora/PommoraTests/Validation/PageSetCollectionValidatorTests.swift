import Foundation
import Testing

@testable import Pommora

@Suite("CollectionSetValidator")
struct CollectionSetValidatorTests {

    @Test("valid title in empty PageCollection passes")
    func valid() throws {
        try CollectionSetValidator.validate(title: "Tasks", existingInType: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: CollectionSetValidator.ValidationError.emptyTitle) {
            try CollectionSetValidator.validate(title: "", existingInType: [])
        }
        #expect(throws: CollectionSetValidator.ValidationError.invalidTitleCharacters) {
            try CollectionSetValidator.validate(title: "A/B", existingInType: [])
        }
    }

    @Test("duplicate within PageCollection throws")
    func duplicate() {
        let existing = [
            PageSet(
                id: ULID.generate(),
                parentID: "01HV",
                title: "Tasks",
                folderURL: URL(fileURLWithPath: "/tmp/V/Tasks", isDirectory: true),
                modifiedAt: Date()
            )
        ]
        #expect(throws: CollectionSetValidator.ValidationError.duplicateTitle) {
            try CollectionSetValidator.validate(title: "tasks", existingInType: existing)
        }
    }
}
