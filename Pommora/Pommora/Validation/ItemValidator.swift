import Foundation

enum ItemValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case descriptionTooLong(cap: Int)
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(id: String)
        case propertyTypeMismatch(id: String)
    }

    /// Default cap on an Item's description/body, counted in Markdown **source**
    /// characters (Shape A: description == body). One source of truth — the
    /// Item Window's counter + over-limit colorization reference this constant
    /// rather than a hardcoded literal. A Type may override per-template via
    /// `ItemTemplateConfig.descriptionCap`; resolve with `effectiveCap(for:)`.
    static let maxDescriptionLength = 250

    /// Effective per-Item cap: the Type template override, else the 250 default (LD-7).
    static func effectiveCap(for itemType: ItemType) -> Int {
        itemType.templateConfig?.descriptionCap ?? maxDescriptionLength
    }

    /// Effective per-Item cap from an ALREADY-RESOLVED template (Collection→Type,
    /// LD-10). The live Item Window resolves the template via `TemplateResolver`,
    /// so a Set overriding `descriptionCap` must color its counter against ITS
    /// cap — not the Type's. Same default fallback as `effectiveCap(for:)`.
    static func effectiveCap(template: ItemTemplateConfig) -> Int {
        template.descriptionCap ?? maxDescriptionLength
    }

    /// Pure decision for the Item Window's description counter: is the current
    /// character count over the effective cap? Drives the non-blocking WARN
    /// colorization only — over-cap NEVER blocks load or save (LD-7: a raw
    /// Obsidian file that overflows must still open).
    static func descriptionCounterIsOverCap(count: Int, cap: Int) -> Bool {
        count > cap
    }

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

        let cap = effectiveCap(for: itemType)
        guard description.count <= cap else {
            throw ValidationError.descriptionTooLong(cap: cap)
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
            // Unified Date type: a date-only (`.date`) value and a with-time
            // (`.datetime`) value are interchangeable under either schema type.
            (.date, .datetime),
            (.datetime, .date),
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

    /// User-facing message for each `ValidationError` case. Static + internal so
    /// the save path AND the test suite reach the real mapping (no
    /// re-implementation). Exhaustive switch — no `default`, so a new
    /// `ValidationError` case fails to compile until it's mapped here.
    static func friendly(_ error: ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Title can't be empty."
        case .invalidTitleCharacters: return "Title can't contain / \\ :"
        case .descriptionTooLong(let cap):
            return "Description over \(cap) source/markdown characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let id): return "Unknown property '\(id)' for this Item Type."
        case .propertyTypeMismatch(let id): return "Property '\(id)' has wrong type."
        }
    }
}
