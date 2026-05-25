import Foundation

enum PropertyDefinitionValidator {
    enum ValidationError: Error, Equatable {
        case emptyName
        case reservedID
        case duplicateID
        case duplicateName
        case dualRelationOnContextTier
        case selectMissingOptions
        case duplicateSelectOptionValue
    }

    static func validate(_ def: PropertyDefinition, in existing: [PropertyDefinition]) throws {
        // Rule 1 & 2: name must be non-empty after trimming whitespace
        let trimmedName = def.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }

        // Rule 3: ID must not be reserved
        if ReservedPropertyID.isReserved(def.id) { throw ValidationError.reservedID }

        // Rule 4: ID must be unique in the existing schema
        if existing.contains(where: { $0.id == def.id }) { throw ValidationError.duplicateID }

        // Rule 5: name must be unique (case-insensitive) in the existing schema
        let lowerName = trimmedName.lowercased()
        if existing.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == lowerName }) {
            throw ValidationError.duplicateName
        }

        // Rule 6: context-tier relation may not carry a dual-property config
        if def.type == .relation, def.dualProperty != nil {
            if case .some(.contextTier) = def.relationScope {
                throw ValidationError.dualRelationOnContextTier
            }
        }

        // Rules 7 & 8: select / multiSelect option constraints
        if def.type == .select || def.type == .multiSelect {
            let options = def.selectOptions ?? []

            // Rule 7: must have at least one option
            guard !options.isEmpty else { throw ValidationError.selectMissingOptions }

            // Rule 8: option values must be unique
            let values = options.map { $0.value }
            if Set(values).count < values.count { throw ValidationError.duplicateSelectOptionValue }
        }
    }
}
