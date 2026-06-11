import Foundation

enum PageSetValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existingInCollection: [PageSet],
        excluding: PageSet? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existingInCollection, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)
    }
}
