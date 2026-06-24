import Foundation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProperty

// MARK: - Adapter

/// Per-side dependencies the per-type schema property-mutation methods need.
///
/// `PageCollectionManager` is a "per-type" schema manager: it holds
/// `types: [Type]` keyed by a `collectionID`, and its five property-mutation
/// methods (`addProperty`, `renameProperty`, `deleteProperty`, `reorderProperty`,
/// `changeType`) persist the sidecar and assign `types[i] = updated` (there is
/// NO `rebuildTypesByID` / `commitInMemory` hook — commit is uniform).
/// `PerTypeSchemaService` holds the shared bodies and routes every per-side bit
/// through this adapter so the manager keeps a thin delegator.
///
/// This is the per-type analogue of `SingletonSchemaAdapter`. It differs from the
/// singleton adapter by:
/// - taking a `collectionID` on every read/commit (and throwing `errTypeNotFound` when
///   the type is absent), rather than operating on one implicit `schema`;
/// - having NO builtin-property guard (`canDelete`) — per-type managers permit
///   deleting any property — and NO `commitInMemory` / `rebuildTypesByID` hook.
///
/// Implementations own the in-memory `types` array and its on-disk sidecars; the
/// service never touches either directly.
@MainActor
protocol PerTypeSchemaAdapter: AnyObject {

    // MARK: Type / schema read

    /// The property definitions of the type identified by `collectionID`. Throws
    /// `errTypeNotFound` when no such type exists.
    func properties(forCollectionID collectionID: String) throws -> [PropertyDefinition]

    // MARK: Schema persist

    /// Build the updated type (with `properties` substituted in and `modifiedAt`
    /// bumped), persist its sidecar atomically, and assign the in-memory
    /// `types[i] = updated`. Commit is uniform (no
    /// `rebuildTypesByID`). Used by the schema-only paths (`addProperty`,
    /// `renameProperty`, `reorderProperty`, lossless `changeType`). Throws
    /// `errTypeNotFound` when the type is absent.
    func commitType(properties: [PropertyDefinition], forCollectionID collectionID: String) throws

    /// Build the updated type (with `properties` substituted in and `modifiedAt`
    /// bumped) and **stage** its sidecar write into `tx` rather than writing it
    /// immediately. Used by the transactional paths (`deleteProperty`, lossy
    /// `changeType`) so the sidecar and member-file rewrites commit atomically
    /// together. Throws `errTypeNotFound` when the type is absent.
    func stageType(properties: [PropertyDefinition], forCollectionID collectionID: String, into tx: SchemaTransaction) throws

    /// Assign the in-memory `types[i]` to the value previously staged via
    /// `stageType` once `tx.commit()` has succeeded. Carries the same
    /// `properties` + bumped `modifiedAt` as the staged sidecar.
    func commitStagedType(forCollectionID collectionID: String)

    // MARK: Member files

    /// All member files (`.md` Pages) belonging to the type identified by
    /// `collectionID`. Throws `errTypeNotFound` when the type is absent.
    func memberFiles(forCollectionID collectionID: String) throws -> [URL]

    /// Strip `propertyID` from every member file of the type identified by
    /// `collectionID`, staging the rewrites into `tx`. The load / strip / re-encode
    /// lives entirely inside this method (preserving the Markdown body),
    /// wrapped in `MemberFileStrip.forEach` so an unreadable member never
    /// aborts the mutation. Throws `errTypeNotFound` when the type is absent
    /// (URL resolution failure), but not for per-member decode failures
    /// (those are skipped resiliently).
    func stripPropertyFromMembers(
        _ propertyID: String, forCollectionID collectionID: String, into tx: SchemaTransaction) throws

    // MARK: Index

    var indexOwningTypeKind: String { get }  // "page_collection"
    var indexUpdater: IndexUpdater? { get }

    // MARK: Validation

    /// The validation context for `PropertyDefinitionValidator.validate`
    /// (replaces `NexusContext.forTypeResolution(in: nexus)`).
    var validationContext: NexusContext { get }

    // MARK: Errors (per-side enum, surfaced as `any Error`)

    var errTypeNotFound: any Error { get }
    var errPropertyNotFound: any Error { get }
    var errLossyChangeRequiresConfirmation: any Error { get }
    var errIndexOutOfBounds: any Error { get }

    // MARK: pendingError sink

    /// Best-effort sink for non-fatal index-write failures (the filesystem is
    /// canonical). Mirrors the `self.pendingError = error` assignments inside the
    /// original `if let updater` blocks.
    func recordIndexError(_ error: any Error)
}

// MARK: - Service

/// Shared implementation of the five per-type schema property-mutation methods,
/// lifted verbatim from `PageCollectionManager` and parameterized over a
/// `PerTypeSchemaAdapter`. Methods **throw** on error; they do NOT set
/// `pendingError` for the thrown error — the manager's delegator keeps the
/// `catch { pendingError = error; throw }` wrapper. (Non-fatal index-write
/// failures are still routed to `adapter.recordIndexError`, matching the original
/// `if let updater { ... } catch { self.pendingError = error }` shape.)
///
/// Methods are synchronous `throws`: the Page bodies contain no `await`, so the
/// service does not need to be `async`. The managers' delegators remain `async throws`
/// for their public surface and call these synchronous methods directly.
enum PerTypeSchemaService {

    // MARK: - Add property

    /// Adds a property definition to a Type's schema. If `definition.id` is empty,
    /// a new user-property ID (`prop_<ulid>`) is minted. Validates against existing
    /// properties via `PropertyDefinitionValidator`. Schema-only write (member
    /// files are not touched — identity is stored by ID).
    @MainActor
    static func addProperty(
        _ definition: PropertyDefinition,
        in collectionID: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forCollectionID: collectionID)

        var def = definition
        if def.id.isEmpty {
            def.id = ReservedPropertyID.mintUserPropertyID()
        }

        try PropertyDefinitionValidator.validate(
            def, in: typeProperties, nexus: adapter.validationContext)

        var properties = typeProperties
        properties.append(def)

        try adapter.commitType(properties: properties, forCollectionID: collectionID)

        if let updater = adapter.indexUpdater {
            let position = properties.count - 1
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: collectionID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: position)
            } catch { adapter.recordIndexError(error) }
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed
    /// by `id` are not touched (rename-safe by design per the domain model).
    @MainActor
    static func renameProperty(
        id propertyID: String,
        in collectionID: String,
        to newName: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forCollectionID: collectionID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        var renamedDef = typeProperties[propIndex]
        renamedDef.name = newName

        // Build the schema with the renamed definition substituted in, so validation
        // can check name-uniqueness against the rest of the schema (excluding itself).
        var otherProps = typeProperties
        otherProps.remove(at: propIndex)
        // Validate name only — supply a fresh temp-unique ID so the duplicate-ID
        // rule doesn't fire. We only care about the name-uniqueness check here.
        var validationDef = renamedDef
        validationDef.id = ReservedPropertyID.mintUserPropertyID()
        try PropertyDefinitionValidator.validate(
            validationDef, in: otherProps, nexus: adapter.validationContext)

        var properties = typeProperties
        properties[propIndex] = renamedDef

        try adapter.commitType(properties: properties, forCollectionID: collectionID)

        if let updater = adapter.indexUpdater {
            do {
                try updater.upsertPropertyDefinition(
                    renamedDef,
                    owningTypeID: collectionID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the schema. Atomically removes the schema entry and
    /// strips the corresponding key from every member file via `SchemaTransaction`.
    @MainActor
    static func deleteProperty(
        id propertyID: String,
        in collectionID: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forCollectionID: collectionID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        var properties = typeProperties
        properties.remove(at: propIndex)

        let tx = SchemaTransaction()

        // Stage updated schema sidecar.
        try adapter.stageType(properties: properties, forCollectionID: collectionID, into: tx)

        // Stage member-file rewrites: strip the property key from every member
        // file. The load / strip / re-encode (preserving the Page body) lives
        // inside the adapter, wrapped in `MemberFileStrip.forEach`.
        try adapter.stripPropertyFromMembers(propertyID, forCollectionID: collectionID, into: tx)

        try tx.commit()

        if let updater = adapter.indexUpdater {
            do { try updater.deletePropertyDefinition(id: propertyID) } catch {
                adapter.recordIndexError(error)
            }
        }

        adapter.commitStagedType(forCollectionID: collectionID)
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    @MainActor
    static func reorderProperty(
        id propertyID: String,
        in collectionID: String,
        toIndex newIndex: Int,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forCollectionID: collectionID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        var props = typeProperties
        let clampedIndex = min(max(newIndex, 0), props.count - 1)
        guard clampedIndex != propIndex else { return }

        props.move(
            fromOffsets: IndexSet(integer: propIndex),
            toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex)

        try adapter.commitType(properties: props, forCollectionID: collectionID)

        if let updater = adapter.indexUpdater {
            for (pos, def) in props.enumerated() {
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: collectionID,
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
        in collectionID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forCollectionID: collectionID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        let oldType = typeProperties[propIndex].type

        if oldType == newType {
            // Lossless: schema-only write to bump modifiedAt.
            var properties = typeProperties
            properties[propIndex].type = newType
            try adapter.commitType(properties: properties, forCollectionID: collectionID)
            if let updater = adapter.indexUpdater {
                let def = properties[propIndex]
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: collectionID,
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

        var properties = typeProperties
        properties[propIndex].type = newType

        let tx = SchemaTransaction()

        // Stage updated schema sidecar.
        try adapter.stageType(properties: properties, forCollectionID: collectionID, into: tx)

        // Stage member-file rewrites: strip the conflicting property value from
        // every member file so no stale cross-type value lingers. The per-side
        // load / strip / re-encode lives inside the adapter.
        try adapter.stripPropertyFromMembers(propertyID, forCollectionID: collectionID, into: tx)

        try tx.commit()

        if let updater = adapter.indexUpdater {
            let def = properties[propIndex]
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: collectionID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }

        adapter.commitStagedType(forCollectionID: collectionID)
    }
}
