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

        for id in tier1 where context.lookupArea(id) == nil {
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
        // Exhaustive over the VALUE side (values arrive from disk) with no
        // `default:` arm — a new PropertyValue case fails compilation here
        // until its valid pairing is declared. (A tuple-switch `default:`
        // previously hid the missing status/file pairs, bricking every save
        // of a page that carried a status value.)
        let matches: Bool
        switch value {
        case .number: matches = type == .number
        case .checkbox: matches = type == .checkbox
        // Unified Date type: date-only + with-time values interchangeable.
        case .date, .datetime: matches = type == .date || type == .datetime
        case .select: matches = type == .select
        case .multiSelect: matches = type == .multiSelect
        case .status: matches = type == .status
        case .relation: matches = type == .relation
        case .url: matches = type == .url
        case .file: matches = type == .file
        // Virtual — never persisted, so never valid as a stored value.
        case .lastEditedTime: matches = false
        case .null: matches = true
        }
        guard matches else { throw ValidationError.propertyTypeMismatch(id: id) }
    }
}
