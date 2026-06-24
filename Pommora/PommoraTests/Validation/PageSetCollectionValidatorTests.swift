import Foundation
import Testing

@testable import Pommora

@Suite("PageSetCollectionValidator")
struct PageSetCollectionValidatorTests {

    @Test("valid title in empty PageCollection passes")
    func valid() throws {
        try PageSetCollectionValidator.validate(title: "Tasks", existingInType: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: PageSetCollectionValidator.ValidationError.emptyTitle) {
            try PageSetCollectionValidator.validate(title: "", existingInType: [])
        }
        #expect(throws: PageSetCollectionValidator.ValidationError.invalidTitleCharacters) {
            try PageSetCollectionValidator.validate(title: "A/B", existingInType: [])
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
        #expect(throws: PageSetCollectionValidator.ValidationError.duplicateTitle) {
            try PageSetCollectionValidator.validate(title: "tasks", existingInType: existing)
        }
    }
}
