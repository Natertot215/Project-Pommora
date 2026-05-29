import Foundation

enum PropertyDefinitionValidator {
    enum ValidationError: Error, Equatable {
        case emptyName
        case reservedID
        case duplicateID
        case duplicateName
        case selectMissingOptions
        case duplicateSelectOptionValue
        /// A `.relation` property carries no `relationTarget`.
        case relationMissingTarget
        /// A `.relation` property's target Type ID doesn't resolve in the nexus,
        /// or it targets a legacy Collection kind (rejected at save time).
        case relationTargetNotResolvable(typeID: String)
    }

    static func validate(
        _ def: PropertyDefinition, in existing: [PropertyDefinition], nexus: NexusContext
    ) throws {
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

        // Relation-target rules (apply only to .relation properties). Relations now
        // treat context_tier as a normal internal target — the former dual-on-context-tier
        // rejection (Rule 6) is retired.
        if def.type == .relation {
            // Relation must carry a target.
            guard let target = def.relationTarget else { throw ValidationError.relationMissingTarget }

            // Target must resolve. Type targets require a live catalog entry; singleton /
            // system targets accept without lookup; legacy Collection targets are rejected
            // at save time (read-tolerance for existing ones is handled by migration).
            switch target {
            case .pageType(let id):
                guard nexus.lookupVault(id) != nil else {
                    throw ValidationError.relationTargetNotResolvable(typeID: id)
                }
            case .itemType(let id):
                guard nexus.lookupItemType(id) != nil else {
                    throw ValidationError.relationTargetNotResolvable(typeID: id)
                }
            case .agendaTasks, .agendaEvents, .contextTier:
                // Singletons / system targets — no catalog lookup, accept.
                break
            case .pageCollection(let id), .itemCollection(let id):
                // Legacy targets — reject creating NEW relations against them.
                throw ValidationError.relationTargetNotResolvable(typeID: id)
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
