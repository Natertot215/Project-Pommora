import Foundation

/// Renamed from `SubtopicValidator` per ParadigmV2.
enum ProjectValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    /// Bare title validation for free-standing tier-3 Projects (Contexts
    /// Decoupling).
    static func validate(
        title: String,
        existing: [Project],
        excluding: Project? = nil
    ) throws {
        let trimmed = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        let conflict = existing.contains { p in
            p.id != excluding?.id && p.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
