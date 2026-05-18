import Foundation
import Testing

@testable import Pommora

@Suite("CollectionValidator")
struct CollectionValidatorTests {

    @Test("valid title in empty vault passes")
    func valid() throws {
        try CollectionValidator.validate(title: "Tasks", existingInVault: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: CollectionValidator.ValidationError.emptyTitle) {
            try CollectionValidator.validate(title: "", existingInVault: [])
        }
        #expect(throws: CollectionValidator.ValidationError.invalidTitleCharacters) {
            try CollectionValidator.validate(title: "A/B", existingInVault: [])
        }
    }

    @Test("duplicate within vault throws")
    func duplicate() {
        let existing = [
            Collection(
                id: ULID.generate(),
                vaultID: "01HV",
                title: "Tasks",
                folderURL: URL(fileURLWithPath: "/tmp/V/Tasks", isDirectory: true),
                modifiedAt: Date()
            )
        ]
        #expect(throws: CollectionValidator.ValidationError.duplicateTitle) {
            try CollectionValidator.validate(title: "tasks", existingInVault: existing)
        }
    }
}
