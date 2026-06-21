import Foundation

enum PageTypeValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existing: [PageType],
        excluding: PageType? = nil
    ) throws {
        let trimmed = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existing, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)
    }
}
