import Foundation

enum PageValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case missingCreatedAt
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(id: String)
        case propertyTypeMismatch(id: String)
    }

    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date,
        vault: PageType,
        context: NexusContext
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // created_at must be present (epoch-zero sentinels for "missing"); allow values > 0
        guard createdAt.timeIntervalSince1970 > 0 else {
            throw ValidationError.missingCreatedAt
        }

        for id in tier1 where context.lookupSpace(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 1, id: id)
        }
        for id in tier2 where context.lookupTopic(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 2, id: id)
        }
        for id in tier3 where context.lookupProject(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 3, id: id)
        }

        let schemaByID = Dictionary(uniqueKeysWithValues: vault.properties.map { ($0.id, $0) })
        for (propertyID, value) in properties {
            guard let def = schemaByID[propertyID] else {
                throw ValidationError.unknownProperty(id: propertyID)
            }
            try validateType(value, against: def.type, id: propertyID)
        }
    }

    private static func validateType(
        _ value: PropertyValue,
        against type: PropertyType,
        id: String
    ) throws {
        switch (value, type) {
        case (.number, .number), (.checkbox, .checkbox),
            (.date, .date), (.datetime, .datetime),
            (.select, .select), (.multiSelect, .multiSelect),
            (.relation, .relation), (.url, .url),
            (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(id: id)
        }
    }
}
