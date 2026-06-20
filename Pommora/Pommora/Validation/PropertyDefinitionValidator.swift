import Foundation

enum PropertyDefinitionValidator {
    enum ValidationError: Error, Equatable {
        case emptyName
        case reservedID
        case duplicateID
        case duplicateName
        case selectMissingOptions
        case duplicateSelectOptionValue
    }

    static func validate(
        _ def: PropertyDefinition, in existing: [PropertyDefinition], nexus: NexusContext
    ) throws {
        let trimmedName = def.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }

        if ReservedPropertyID.isReserved(def.id) { throw ValidationError.reservedID }

        if existing.contains(where: { $0.id == def.id }) { throw ValidationError.duplicateID }

        // Name uniqueness is case-insensitive + whitespace-trimmed.
        let lowerName = trimmedName.lowercased()
        if existing.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == lowerName }) {
            throw ValidationError.duplicateName
        }

        if def.type == .select || def.type == .multiSelect {
            let options = def.selectOptions ?? []
            guard !options.isEmpty else { throw ValidationError.selectMissingOptions }

            let values = options.map { $0.value }
            if Set(values).count < values.count { throw ValidationError.duplicateSelectOptionValue }
        }
    }
}
