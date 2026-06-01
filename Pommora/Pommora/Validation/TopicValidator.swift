import Foundation

enum TopicValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case parentNotFound(String)
    }

    static func validate(
        title: String,
        parents: [String],
        existing: [Topic],
        context: NexusContext,
        excluding: Topic? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: existing, excludingID: excluding?.id,
            else: ValidationError.duplicateTitle)

        for parentID in parents {
            if context.lookupSpace(parentID) == nil {
                throw ValidationError.parentNotFound(parentID)
            }
        }
    }
}
