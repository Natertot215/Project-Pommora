import Foundation
import Testing

@testable import Pommora

@Suite("FolderValidator")
struct FolderValidatorTests {

    private func makeFolder(title: String) -> Folder {
        Folder(
            id: ULID.generate(),
            typeID: "01HVAULT",
            collectionID: "01HCOLL",
            title: title,
            folderURL: URL(fileURLWithPath: "/tmp/V/C/\(title)", isDirectory: true),
            modifiedAt: Date()
        )
    }

    @Test("valid title in empty Collection passes")
    func valid() throws {
        try FolderValidator.validate(title: "Topic A", existingInCollection: [])
    }

    @Test("empty title throws")
    func emptyTitle() {
        #expect(throws: FolderValidator.ValidationError.emptyTitle) {
            try FolderValidator.validate(title: "", existingInCollection: [])
        }
        #expect(throws: FolderValidator.ValidationError.emptyTitle) {
            try FolderValidator.validate(title: "   ", existingInCollection: [])
        }
    }

    @Test("invalid characters throw")
    func invalidChars() {
        #expect(throws: FolderValidator.ValidationError.invalidTitleCharacters) {
            try FolderValidator.validate(title: "A/B", existingInCollection: [])
        }
        #expect(throws: FolderValidator.ValidationError.invalidTitleCharacters) {
            try FolderValidator.validate(title: #"A\B"#, existingInCollection: [])
        }
        #expect(throws: FolderValidator.ValidationError.invalidTitleCharacters) {
            try FolderValidator.validate(title: "A:B", existingInCollection: [])
        }
    }

    @Test("duplicate within Collection throws (case-insensitive)")
    func duplicate() {
        let existing = [makeFolder(title: "Topic A")]
        #expect(throws: FolderValidator.ValidationError.duplicateTitle) {
            try FolderValidator.validate(title: "topic a", existingInCollection: existing)
        }
    }

    @Test("rename to same title passes via `excluding`")
    func excludingSelf() throws {
        let existing = makeFolder(title: "Topic A")
        try FolderValidator.validate(
            title: "Topic A",
            existingInCollection: [existing],
            excluding: existing
        )
    }

    @Test("siblings in different Collections do not collide")
    func crossCollectionSameNameAllowed() throws {
        // The validator only knows about the in-Collection list. Cross-Collection
        // duplicates are allowed by design — caller picks the right list.
        let existing: [Folder] = []
        try FolderValidator.validate(title: "Topic A", existingInCollection: existing)
    }
}
