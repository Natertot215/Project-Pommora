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
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existing.contains { p in
            p.id != excluding?.id && p.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
