import Foundation

/// Validates Folder (third-tier on Pages side, F.1) titles. Mirrors
/// `PageCollectionValidator` exactly — Folders share the same naming
/// constraints since both ultimately become filesystem folder names.
///
/// Sibling-uniqueness is checked within the parent PageCollection
/// (`existingInCollection`), not globally — two different Collections can
/// each have a Folder named "Topic A".
enum FolderValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existingInCollection: [Folder],
        excluding: Folder? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existingInCollection.contains { f in
            f.id != excluding?.id && f.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
