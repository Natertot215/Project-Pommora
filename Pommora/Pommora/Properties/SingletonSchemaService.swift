import Foundation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProperty

// MARK: - Adapter

/// Per-side dependencies the singleton-schema property-mutation methods need.
///
/// The Agenda Tasks and Agenda Events managers are singleton schema managers
/// (one `schema`, no per-type lookup). Their five property-mutation methods are
/// byte-identical modulo a handful of mechanical token swaps (error enum, schema
/// type, `NexusPaths` helpers, file extension, decode type, the two index
/// `owningType*` discriminators). `SingletonSchemaService` lifts those bodies
/// verbatim and routes every per-side bit through this adapter so each manager
/// keeps a thin delegator.
///
/// Implementations own the in-memory `schema` and its on-disk sidecar; the
/// service never touches either directly.
@MainActor
protocol SingletonSchemaAdapter: AnyObject {

    // MARK: Schema read

    /// The current schema's property definitions (replaces `schema.properties`).
    var schemaProperties: [PropertyDefinition] { get }

    // MARK: Schema persist

    /// Build the updated schema (with `properties` substituted in and
    /// `modifiedAt` bumped), write the sidecar atomically (`AtomicJSON.write`),
    /// and assign the in-memory `schema`. Used by the schema-only paths
    /// (`addProperty`, `renameProperty`, `reorderProperty`, lossless `changeType`).
    func writeSchema(properties: [PropertyDefinition]) throws

    /// Build the updated schema (with `properties` substituted in and
    /// `modifiedAt` bumped) and **stage** its sidecar write into `tx` (rather
    /// than writing it immediately). Used by the transactional paths
    /// (`deleteProperty`, lossy `changeType`) so the sidecar and member-file
    /// rewrites commit atomically together.
    func stageSchema(properties: [PropertyDefinition], into tx: SchemaTransaction) throws

    /// Assign the in-memory `schema` to the value previously staged via
    /// `stageSchema` once `tx.commit()` has succeeded. Carries the same
    /// `properties` + bumped `modifiedAt` as the staged sidecar.
    func commitStagedSchema(properties: [PropertyDefinition])

    // MARK: Member files

    /// All member files (`.task.json` / `.event.json`) in the singleton folder.
    func memberFiles() throws -> [URL]

    /// Decode the member file at `url`, remove `propertyID` from its `properties`
    /// dictionary, and (only if the value was present) stage the re-encoded
    /// member back to `url` in `tx`. A no-op when the member lacks the property.
    func stripMember(at url: URL, removing propertyID: String, into tx: SchemaTransaction) throws

    // MARK: Guards / validation

    /// Whether `propertyID` may be deleted (false for built-in reserved
    /// properties such as `_type` / `_status`).
    func canDelete(propertyID: String) -> Bool

    /// The validation context for `PropertyDefinitionValidator.validate`
    /// (replaces `NexusContext.forTypeResolution(in: nexus)`).
    var validationContext: NexusContext { get }

    // MARK: Index

    var indexOwningTypeID: String { get }
    var indexOwningTypeKind: String { get }
    var indexUpdater: IndexUpdater? { get }

    // MARK: Errors (per-side enum, surfaced as `any Error`)

    var errPropertyNotFound: any Error { get }
    var errCannotDeleteBuiltin: any Error { get }
    var errLossyChangeRequiresConfirmation: any Error { get }
    var errIndexOutOfBounds: any Error { get }

    // MARK: pendingError sink

    /// Best-effort sink for non-fatal index-write failures (the filesystem is
    /// canonical). Mirrors the `self.pendingError = error` assignments inside the
    /// original `if let updater` blocks.
    func recordIndexError(_ error: any Error)
}

// MARK: - Service

/// Shared implementation of the five singleton-schema property-mutation methods,
/// lifted verbatim from `AgendaTaskManager` and parameterized over a
/// `SingletonSchemaAdapter`. Methods **throw** on error; they do NOT set
/// `pendingError` for the thrown error — the manager's delegator keeps the
/// `catch { pendingError = error; throw }` wrapper. (Non-fatal index-write
/// failures are still routed to `adapter.recordIndexError`, matching the
/// original `if let updater { ... } catch { self.pendingError = error }` shape.)
enum SingletonSchemaService {

    // MARK: - Add property

    /// Adds a property definition to the singleton schema. If `definition.id` is
    /// empty, a new user-property ID (`prop_<ulid>`) is minted. Validates against
    /// existing properties via `PropertyDefinitionValidator`. Schema-only write
    /// (member files are not touched — identity is stored by ID).
    @MainActor
    static func addProperty(
        _ definition: PropertyDefinition,
        on adapter: any SingletonSchemaAdapter
    ) throws {
        var def = definition
        if def.id.isEmpty {
            def.id = ReservedPropertyID.mintUserPropertyID()
        }

        try PropertyDefinitionValidator.validate(
            def, in: adapter.schemaProperties, nexus: adapter.validationContext)

        var properties = adapter.schemaProperties
        properties.append(def)

        try adapter.writeSchema(properties: properties)

        if let updater = adapter.indexUpdater {
            let position = properties.count - 1
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: adapter.indexOwningTypeID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: position)
            } catch { adapter.recordIndexError(error) }
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed
    /// by name are not touched (rename-safe by design per the domain model).
    @MainActor
    static func renameProperty(
        id propertyID: String,
        to newName: String,
        on adapter: any SingletonSchemaAdapter
    ) throws {
        guard let propIndex = adapter.schemaProperties.firstIndex(where: { $0.id == propertyID })
        else {
            throw adapter.errPropertyNotFound
        }

        var renamedDef = adapter.schemaProperties[propIndex]
        renamedDef.name = newName

        // Build the schema with the renamed definition substituted in, so validation
        // can check name-uniqueness against the rest of the schema (excluding itself).
        var otherProps = adapter.schemaProperties
        otherProps.remove(at: propIndex)
        // Validate name only — supply a fresh temp-unique ID so the duplicate-ID
        // rule doesn't fire. We only care about the name-uniqueness check here.
        var validationDef = renamedDef
        validationDef.id = ReservedPropertyID.mintUserPropertyID()
        try PropertyDefinitionValidator.validate(
            validationDef, in: otherProps, nexus: adapter.validationContext)

        var properties = adapter.schemaProperties
        properties[propIndex] = renamedDef

        try adapter.writeSchema(properties: properties)

        if let updater = adapter.indexUpdater {
            do {
                try updater.upsertPropertyDefinition(
                    renamedDef,
                    owningTypeID: adapter.indexOwningTypeID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the singleton schema. Built-in properties
    /// (`_type`, `_status`) cannot be deleted — throws `cannotDeleteBuiltinProperty`.
    /// Atomically removes the schema entry and strips the corresponding key from
    /// every member file via `SchemaTransaction`.
    @MainActor
    static func deleteProperty(
        id propertyID: String,
        on adapter: any SingletonSchemaAdapter
    ) throws {
        // Block deletion of built-in reserved properties.
        // _status non-deletable per plan; _type non-deletable as core select.
        guard adapter.canDelete(propertyID: propertyID) else {
            throw adapter.errCannotDeleteBuiltin
        }

        guard let propIndex = adapter.schemaProperties.firstIndex(where: { $0.id == propertyID })
        else {
            throw adapter.errPropertyNotFound
        }

        var properties = adapter.schemaProperties
        properties.remove(at: propIndex)

        let tx = SchemaTransaction()

        // Stage updated schema sidecar.
        try adapter.stageSchema(properties: properties, into: tx)

        // Stage member-file rewrites: strip the property key from every member file.
        let memberFiles = try adapter.memberFiles()
        for memberURL in memberFiles {
            try adapter.stripMember(at: memberURL, removing: propertyID, into: tx)
        }

        try tx.commit()

        if let updater = adapter.indexUpdater {
            do { try updater.deletePropertyDefinition(id: propertyID) } catch { adapter.recordIndexError(error) }
        }

        adapter.commitStagedSchema(properties: properties)
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    @MainActor
    static func reorderProperty(
        id propertyID: String,
        toIndex newIndex: Int,
        on adapter: any SingletonSchemaAdapter
    ) throws {
        guard let propIndex = adapter.schemaProperties.firstIndex(where: { $0.id == propertyID })
        else {
            throw adapter.errPropertyNotFound
        }

        var props = adapter.schemaProperties
        let clampedIndex = min(max(newIndex, 0), props.count - 1)
        guard clampedIndex != propIndex else { return }

        guard clampedIndex >= 0 && clampedIndex < props.count else {
            throw adapter.errIndexOutOfBounds
        }

        props.move(
            fromOffsets: IndexSet(integer: propIndex),
            toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex
        )

        try adapter.writeSchema(properties: props)

        if let updater = adapter.indexUpdater {
            for (pos, def) in props.enumerated() {
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: adapter.indexOwningTypeID,
                        owningTypeKind: adapter.indexOwningTypeKind,
                        position: pos)
                } catch { adapter.recordIndexError(error) }
            }
        }
    }

    // MARK: - Change property type

    /// Changes the type of an existing property.
    ///
    /// **Lossless path** (`oldType == newType`): updates the schema sidecar only.
    ///
    /// **Lossy path** (`oldType != newType`):
    /// - `dropConflictingValues == false` → throws `.lossyChangeRequiresConfirmation`
    ///   so the caller can surface a confirmation dialog.
    /// - `dropConflictingValues == true` → atomically updates the schema sidecar and
    ///   strips the property's value from every member file via `SchemaTransaction`.
    @MainActor
    static func changeType(
        of propertyID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false,
        on adapter: any SingletonSchemaAdapter
    ) throws {
        guard let propIndex = adapter.schemaProperties.firstIndex(where: { $0.id == propertyID })
        else {
            throw adapter.errPropertyNotFound
        }

        let oldType = adapter.schemaProperties[propIndex].type

        if oldType == newType {
            // Lossless: schema-only write to bump modifiedAt.
            var properties = adapter.schemaProperties
            properties[propIndex].type = newType
            try adapter.writeSchema(properties: properties)
            if let updater = adapter.indexUpdater {
                let def = properties[propIndex]
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: adapter.indexOwningTypeID,
                        owningTypeKind: adapter.indexOwningTypeKind,
                        position: propIndex)
                } catch { adapter.recordIndexError(error) }
            }
            return
        }

        // Lossy cross-type change.
        guard dropConflictingValues else {
            throw adapter.errLossyChangeRequiresConfirmation
        }

        var properties = adapter.schemaProperties
        properties[propIndex].type = newType

        let tx = SchemaTransaction()

        // Stage updated schema sidecar.
        try adapter.stageSchema(properties: properties, into: tx)

        // Stage member-file rewrites: strip the conflicting property value from
        // every member file so no stale cross-type value lingers.
        let memberFiles = try adapter.memberFiles()
        for memberURL in memberFiles {
            try adapter.stripMember(at: memberURL, removing: propertyID, into: tx)
        }

        try tx.commit()

        if let updater = adapter.indexUpdater {
            let def = properties[propIndex]
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: adapter.indexOwningTypeID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }

        adapter.commitStagedSchema(properties: properties)
    }
}
