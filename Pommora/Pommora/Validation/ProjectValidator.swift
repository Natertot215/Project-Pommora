import Foundation

enum SubtopicValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case missingParent
        case tooManyParents
        case parentNotFound(String)
        case fileLocationMismatch
    }

    struct FileLocation: Equatable, Sendable {
        var parentFolderTitle: String
    }

    static func validate(
        title: String,
        parents: [String],
        fileLocation: FileLocation,
        existing: [Subtopic],
        context: NexusContext,
        excluding: Subtopic? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        guard !parents.isEmpty else { throw ValidationError.missingParent }
        guard parents.count == 1 else { throw ValidationError.tooManyParents }

        let parentID = parents[0]
        guard let parentTopic = context.lookupTopic(parentID) else {
            throw ValidationError.parentNotFound(parentID)
        }

        // File location must equal parent Topic's folder name
        guard fileLocation.parentFolderTitle == parentTopic.title else {
            throw ValidationError.fileLocationMismatch
        }

        // Duplicate title within same parent
        let conflict = existing.contains { st in
            st.id != excluding?.id && st.parents == parents && st.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
