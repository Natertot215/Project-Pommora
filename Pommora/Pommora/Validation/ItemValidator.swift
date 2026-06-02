import Foundation

enum ItemValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case descriptionTooLong
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(id: String)
        case propertyTypeMismatch(id: String)
    }

    /// Cap on an Item's description/body, counted in Markdown **source**
    /// characters (Shape A: description == body). One source of truth — the
    /// Item Window's counter + over-limit colorization reference this constant
    /// rather than a hardcoded literal.
    static let maxDescriptionLength = 1000

    /// Save-time validation for an Item. Schema is sourced from the **Item
    /// Type** (`itemType.properties`) — the stored user-defined schema (tier
    /// relation properties live at the frontmatter root and are validated by
    /// the dedicated tier loop, not the property-schema loop).
    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        description: String = "",
        properties: [String: PropertyValue],
        itemType: ItemType,
        context: NexusContext
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        guard description.count <= maxDescriptionLength else {
            throw ValidationError.descriptionTooLong
        }

        // tier rules
        for id in tier1 {
            if context.lookupSpace(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 1, id: id)
            }
        }
        for id in tier2 {
            if context.lookupTopic(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 2, id: id)
            }
        }
        for id in tier3 {
            if context.lookupProject(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 3, id: id)
            }
        }

        // properties must be in schema + type match (keyed by property ID)
        let schemaByID = Dictionary(uniqueKeysWithValues: itemType.properties.map { ($0.id, $0) })
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
        case (.number, .number),
            (.checkbox, .checkbox),
            (.date, .date),
            (.datetime, .datetime),
            (.select, .select),
            (.multiSelect, .multiSelect),
            (.status, .status),
            (.relation, .relation),
            (.url, .url),
            (.file, .file),
            (.lastEditedTime, .lastEditedTime),
            (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(id: id)
        }
    }
}
