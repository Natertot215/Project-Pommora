import Foundation

enum PageValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case missingCreatedAt
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(name: String)
        case propertyTypeMismatch(name: String)
    }

    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date,
        vault: PageType,
        existingSiblings: [PageMeta],
        context: NexusContext,
        excluding: PageMeta? = nil
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

        let conflict = existingSiblings.contains { p in
            p.id != excluding?.id && p.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }

        for id in tier1 where context.lookupSpace(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 1, id: id)
        }
        for id in tier2 where context.lookupTopic(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 2, id: id)
        }
        for id in tier3 where context.lookupSubtopic(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 3, id: id)
        }

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
        case (.number, .number), (.checkbox, .checkbox),
            (.date, .date), (.datetime, .datetime),
            (.select, .select), (.multiSelect, .multiSelect),
            (.relation, .relation), (.url, .url),
            (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(name: name)
        }
    }
}
