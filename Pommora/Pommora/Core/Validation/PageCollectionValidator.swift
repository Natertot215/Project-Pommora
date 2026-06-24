import Foundation

enum PageCollectionValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existing: [PageCollection],
        excluding: PageCollection? = nil
    ) throws(ValidationError) {
        let trimmed = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existing, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)
    }
}
