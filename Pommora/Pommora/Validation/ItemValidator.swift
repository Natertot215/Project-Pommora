import Foundation

enum ItemValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case descriptionTooLong
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(name: String)
        case propertyTypeMismatch(name: String)
    }

    static let maxDescriptionLength = 250

    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        description: String = "",
        properties: [String: PropertyValue],
        vault: Vault,
        existingSiblings: [Item],
        context: NexusContext,
        excluding: Item? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existingSiblings.contains { i in
            i.id != excluding?.id &&
            i.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }

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
            if context.lookupSubtopic(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 3, id: id)
            }
        }

        // properties must be in schema + type match
        let schemaByName = Dictionary(uniqueKeysWithValues: vault.properties.map { ($0.name, $0) })
        for (name, value) in properties {
            guard let def = schemaByName[name] else {
                throw ValidationError.unknownProperty(name: name)
            }
            try validateType(value, against: def.type, name: name)
        }
    }

    private static func validateType(
        _ value: PropertyValue,
        against type: PropertyType,
        name: String
    ) throws {
        switch (value, type) {
        case (.number, .number),
             (.checkbox, .checkbox),
             (.date, .date),
             (.datetime, .datetime),
             (.select, .select),
             (.multiSelect, .multiSelect),
             (.relation, .relation),
             (.url, .url),
             (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(name: name)
        }
    }
}
