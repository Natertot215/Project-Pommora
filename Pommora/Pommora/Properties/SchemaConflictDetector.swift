import Foundation

/// Pure logic helper for detecting schema drift between a user's in-progress
/// Item edits and the freshly-loaded on-disk ItemType schema.
///
/// No SwiftUI or UI dependency — deliberately separate so unit tests can
/// target this type without pulling in the app's view layer.
///
/// Used by `ItemWindow.save()` (EC4 — revalidate-on-save guard) and by
/// `SchemaConflictTests` directly.
enum SchemaConflictDetector {

    // MARK: - Drift detection

    /// Compares the editor's in-progress property values against the freshly-
    /// loaded schema. Returns two name arrays: property IDs whose definitions
    /// were removed from the schema, and property IDs whose types changed.
    ///
    /// - Parameters:
    ///   - editingProperties: The `[propertyID: PropertyValue]` dict the editor
    ///     currently holds (unsaved).
    ///   - freshSchema: The `[PropertyDefinition]` just loaded from disk.
    ///   - originalSchema: The schema the editor opened against — used to look
    ///     up display names for properties that have since been deleted.
    /// - Returns: A tuple of `(removed: [String], typeChanged: [String])` where
    ///   each element is a user-visible property name.
    static func detectDrift(
        editingProperties: [String: PropertyValue],
        freshSchema: [PropertyDefinition],
        originalSchema: [PropertyDefinition]
    ) -> (removed: [String], typeChanged: [String]) {
        let freshByID = Dictionary(uniqueKeysWithValues: freshSchema.map { ($0.id, $0) })
        let originalByID = Dictionary(uniqueKeysWithValues: originalSchema.map { ($0.id, $0) })

        var removed: [String] = []
        var typeChanged: [String] = []

        for (propertyID, value) in editingProperties {
            if let freshDef = freshByID[propertyID] {
                // Property still exists — check for type mismatch.
                if isIncompatible(value, with: freshDef.type) {
                    typeChanged.append(freshDef.name)
                }
            } else {
                // Property was removed from the schema. Fall back to the
                // original schema's name for the user-facing message.
                let displayName = originalByID[propertyID]?.name ?? propertyID
                removed.append(displayName)
            }
        }

        // Sort for deterministic output (test assertions + UI ordering).
        return (removed: removed.sorted(), typeChanged: typeChanged.sorted())
    }

    // MARK: - Valid-subset filter

    /// Returns a copy of `editingProperties` with only the entries that are
    /// present in `freshSchema` and whose value type is compatible with the
    /// fresh definition's type. Stale or type-mismatched keys are silently
    /// dropped.
    ///
    /// Used by the "Save valid subset" action in `SchemaConflictDialog`.
    static func filterToValidSubset(
        editingProperties: [String: PropertyValue],
        freshSchema: [PropertyDefinition]
    ) -> [String: PropertyValue] {
        let freshByID = Dictionary(uniqueKeysWithValues: freshSchema.map { ($0.id, $0) })
        var result: [String: PropertyValue] = [:]

        for (propertyID, value) in editingProperties {
            guard let freshDef = freshByID[propertyID] else { continue }
            guard !isIncompatible(value, with: freshDef.type) else { continue }
            result[propertyID] = value
        }

        return result
    }

    // MARK: - Compatibility check

    /// Returns `true` when `value` cannot be stored under a property whose
    /// schema type is `type`. `.null` is always compatible (represents "no
    /// value set"). Any non-null value that doesn't correspond to `type` is
    /// incompatible.
    static func isIncompatible(_ value: PropertyValue, with type: PropertyType) -> Bool {
        switch value {
        case .null: return false  // null is always compatible — no value set
        case .number: return type != .number
        case .checkbox: return type != .checkbox
        // Unified Date type: date-only + with-time values are interchangeable
        // under either schema type.
        case .date, .datetime: return type != .date && type != .datetime
        case .select: return type != .select
        case .multiSelect: return type != .multiSelect
        case .status: return type != .status
        case .relation: return type != .relation
        case .url: return type != .url
        case .file: return type != .file
        case .lastEditedTime: return type != .lastEditedTime
        }
    }
}
