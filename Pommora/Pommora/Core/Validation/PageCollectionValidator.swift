import Foundation

enum PageCollectionValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existingInType: [PageSet],
        excluding: PageSet? = nil
    ) throws(ValidationError) {
        let trimmed = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existingInType, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)
    }
}
