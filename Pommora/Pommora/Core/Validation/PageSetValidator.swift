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
    ) throws(ValidationError) {
        let trimmed = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existingInCollection, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)
    }
}
