import Foundation

/// Single source for "create a default property of type X on a Vault schema"
/// — shared by the View Settings type-picker pane and the inspector's
/// Add Property affordance, so both surfaces mint and seed identically.
@MainActor
enum PropertyCreation {
    /// Build a minimal-defaults PropertyDefinition for each user-creatable
    /// type. The ID is left empty; `commitDefault` (or the caller) mints it.
    static func makeDefaultDefinition(for type: PropertyType) -> PropertyDefinition {
        let name = "New \(type.displayName)"
        switch type {
        case .number:
            return PropertyDefinition(id: "", name: name, type: .number, numberFormat: .decimal)
        case .checkbox:
            return PropertyDefinition(id: "", name: name, type: .checkbox)
        case .date:
            return PropertyDefinition(id: "", name: name, type: .date)
        case .datetime:
            return PropertyDefinition(id: "", name: name, type: .datetime)
        case .select:
            // Seed one default option so PropertyDefinitionValidator passes on
            // create (it throws .selectMissingOptions for an empty options
            // array). User customizes / removes the placeholder in
            // EditPropertyPane.
            return PropertyDefinition(
                id: "", name: name, type: .select,
                selectOptions: [
                    PropertyDefinition.SelectOption(value: "option_1", label: "Option 1", color: nil)
                ]
            )
        case .multiSelect:
            return PropertyDefinition(
                id: "", name: name, type: .multiSelect,
                selectOptions: [
                    PropertyDefinition.SelectOption(value: "option_1", label: "Option 1", color: nil)
                ]
            )
        case .status:
            return PropertyDefinition(
                id: "", name: name, type: .status,
                statusGroups: PropertyDefinition.StatusGroup.defaultSeed()
            )
        case .url:
            return PropertyDefinition(id: "", name: name, type: .url)
        case .file:
            return PropertyDefinition(id: "", name: name, type: .file)
        case .relation:
            // Kept only to satisfy the exhaustive switch over PropertyType
            // (KEEP-substrate: .relation case must not be removed).
            return PropertyDefinition(id: "", name: name, type: .relation)
        case .lastEditedTime:
            // Excluded from PropertyType.userCreatable — unreachable, but
            // the exhaustive switch requires a case.
            return PropertyDefinition(id: "", name: name, type: type)
        }
    }

    /// Mint + commit a default property of `type` onto the Type schema that
    /// owns `collectionID`. Returns the committed definition (with its real ULID)
    /// so callers can route to post-create configuration.
    @discardableResult
    static func commitDefault(
        _ type: PropertyType, toCollectionID collectionID: String, manager: PageCollectionManager
    ) async throws -> PropertyDefinition {
        var definition = makeDefaultDefinition(for: type)
        // Mint up-front so the caller's route argument carries a real ULID —
        // the manager would otherwise mint internally and the value would be
        // lost at the struct-by-value boundary.
        definition.id = ReservedPropertyID.mintUserPropertyID()
        try await manager.addProperty(definition, to: collectionID)
        return definition
    }
}
