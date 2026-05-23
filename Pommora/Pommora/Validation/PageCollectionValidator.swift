import Foundation

enum PageCollectionValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existingInType: [PageCollection],
        excluding: PageCollection? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existingInType.contains { c in
            c.id != excluding?.id && c.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
