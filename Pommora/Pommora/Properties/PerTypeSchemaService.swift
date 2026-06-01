import Foundation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProperty

// MARK: - Adapter

/// Per-side dependencies the per-type schema property-mutation methods need.
///
/// `PageTypeManager` and `ItemTypeManager` are "per-type" schema managers: each
/// holds `types: [Type]` keyed by a `typeID`, and its five property-mutation
/// methods (`addProperty`, `renameProperty`, `deleteProperty`, `reorderProperty`,
/// `changeType`) are near-identical between the Page and Item sides. After the
/// `Normalize-ItemType-Lookup` pass removed `ItemTypeManager.typesByID` /
/// `rebuildTypesByID`, **Item == Page on the commit path** (both just persist the
/// sidecar and assign `types[i] = updated`; there is NO `rebuildTypesByID` /
/// `commitInMemory` hook — commit is uniform). `PerTypeSchemaService` lifts the
/// Page bodies verbatim and routes every per-side bit through this adapter so each
/// manager keeps a thin delegator.
///
/// This is the per-type analogue of `SingletonSchemaAdapter`. It differs from the
/// singleton adapter by:
/// - taking a `typeID` on every read/commit (and throwing `errTypeNotFound` when
///   the type is absent), rather than operating on one implicit `schema`;
/// - carrying the paired-relation collaborators (`typeKind(forTypeID:)`,
///   `reverseRelationTarget(forTypeID:)`, `reloadType(byID:)`, `nexus`) for the
///   `DualRelationCoordinator` branches in `addProperty` / `deleteProperty`, which
///   the singletons never enter;
/// - having NO builtin-property guard (`canDelete`) — per-type managers permit
///   deleting any property — and NO `commitInMemory` / `rebuildTypesByID` hook.
///
/// Implementations own the in-memory `types` array and its on-disk sidecars; the
/// service never touches either directly.
@MainActor
protocol PerTypeSchemaAdapter: AnyObject {

    // MARK: Type / schema read

    /// The property definitions of the type identified by `typeID`. Throws
    /// `errTypeNotFound` when no such type exists.
    func properties(forTypeID typeID: String) throws -> [PropertyDefinition]

    // MARK: Schema persist

    /// Build the updated type (with `properties` substituted in and `modifiedAt`
    /// bumped), persist its sidecar atomically, and assign the in-memory
    /// `types[i] = updated`. Commit is uniform across Page and Item (no
    /// `rebuildTypesByID`). Used by the schema-only paths (`addProperty`,
    /// `renameProperty`, `reorderProperty`, lossless `changeType`). Throws
    /// `errTypeNotFound` when the type is absent.
    func commitType(properties: [PropertyDefinition], forTypeID typeID: String) throws

    /// Build the updated type (with `properties` substituted in and `modifiedAt`
    /// bumped) and **stage** its sidecar write into `tx` rather than writing it
    /// immediately. Used by the transactional paths (`deleteProperty`, lossy
    /// `changeType`) so the sidecar and member-file rewrites commit atomically
    /// together. Throws `errTypeNotFound` when the type is absent.
    func stageType(properties: [PropertyDefinition], forTypeID typeID: String, into tx: SchemaTransaction) throws

    /// Assign the in-memory `types[i]` to the value previously staged via
    /// `stageType` once `tx.commit()` has succeeded. Carries the same
    /// `properties` + bumped `modifiedAt` as the staged sidecar.
    func commitStagedType(forTypeID typeID: String)

    // MARK: Paired-relation collaborators

    /// The `DualRelationCoordinator.TypeKind` for the type identified by `typeID`
    /// (used as the source/owner of a paired relation). Throws `errTypeNotFound`.
    func typeKind(forTypeID typeID: String) throws -> DualRelationCoordinator.TypeKind

    /// The `RelationTarget` that points back at the type identified by `typeID`
    /// (the reverse scope for a paired relation). E.g. `.pageType(typeID)` on the
    /// Page side, `.itemType(typeID)` on the Item side.
    func reverseRelationTarget(forTypeID typeID: String) -> PropertyDefinition.RelationTarget

    /// Resolve a paired-relation target's `DualRelationCoordinator.TypeKind` from
    /// its `RelationTarget` scope. Same-side reads in-memory `types`; cross-side
    /// and Agenda singletons load from disk. Throws `errTypeNotFound` (or
    /// `errPropertyNotFound` for collection / context-tier scopes that never carry
    /// a `dualProperty`).
    func resolveDualTargetKind(
        for scope: PropertyDefinition.RelationTarget
    ) throws
        -> DualRelationCoordinator.TypeKind

    /// Reload the type identified by `typeID` into memory after a coordinator
    /// write. Same-side (a type this manager owns) reloads from disk inline;
    /// cross-manager targets route through the injected `reloadTypeByID?` hook so
    /// the OTHER manager refreshes without a restart.
    func reloadType(byID typeID: String)

    /// The active `Nexus` passed to `DualRelationCoordinator` for sidecar-URL
    /// resolution in the paired-relation branches.
    var nexusForCoordinator: Nexus { get }

    // MARK: Member files

    /// All member files (`.md` Pages / `.json` Items) belonging to the type
    /// identified by `typeID`. Throws `errTypeNotFound` when the type is absent.
    func memberFiles(forTypeID typeID: String) throws -> [URL]

    /// Strip `propertyID` from every member file of the type identified by
    /// `typeID`, staging the rewrites into `tx`. The per-side load / strip /
    /// re-encode lives entirely inside this method (Page preserves the Markdown
    /// body; Item has no body), wrapped in `MemberFileStrip.forEach` so an
    /// unreadable member never aborts the mutation. Throws `errTypeNotFound` when
    /// the type is absent (URL resolution failure), but not for per-member decode
    /// failures (those are skipped resiliently).
    func stripPropertyFromMembers(
        _ propertyID: String, forTypeID typeID: String, into tx: SchemaTransaction) throws

    // MARK: Index

    var indexOwningTypeKind: String { get }  // "page_type" / "item_type"
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
/// lifted verbatim from `PageTypeManager` and parameterized over a
/// `PerTypeSchemaAdapter`. Methods **throw** on error; they do NOT set
/// `pendingError` for the thrown error — the manager's delegator keeps the
/// `catch { pendingError = error; throw }` wrapper. (Non-fatal index-write
/// failures are still routed to `adapter.recordIndexError`, matching the original
/// `if let updater { ... } catch { self.pendingError = error }` shape.)
///
/// Methods are synchronous `throws`: the Page bodies contain no `await` (the
/// `DualRelationCoordinator` calls are synchronous), so the service does not need
/// to be `async`. The managers' delegators remain `async throws` for their public
/// surface and call these synchronous methods directly.
enum PerTypeSchemaService {

    // MARK: - Add property

    /// Adds a property definition to a Type's schema. If `definition.id` is empty,
    /// a new user-property ID (`prop_<ulid>`) is minted. Validates against existing
    /// properties via `PropertyDefinitionValidator`. Schema-only write (member
    /// files are not touched — identity is stored by ID).
    ///
    /// **Paired relations** (`type == .relation && dualProperty != nil`): routed
    /// through `DualRelationCoordinator.createPairedRelation` which writes both
    /// Type sidecars atomically. The authoritative target kind+id is
    /// `definition.relationTarget`; the reverse scope points back to the source
    /// type. After the coordinator write, the source type and (if distinct) the
    /// target type are reloaded into memory.
    @MainActor
    static func addProperty(
        _ definition: PropertyDefinition,
        in typeID: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forTypeID: typeID)

        var def = definition
        if def.id.isEmpty {
            def.id = ReservedPropertyID.mintUserPropertyID()
        }

        // Paired relation: a non-nil `dualProperty` is the pairing signal; route
        // through DualRelationCoordinator. The reverse name flows via
        // `def.reverseName` (the empty `syncedPropertyID` is filled with the minted
        // reverse-property ID by the coordinator post-creation).
        if def.type == .relation, def.dualProperty != nil {
            guard let scope = def.relationTarget else {
                throw adapter.errPropertyNotFound
            }
            let sourceKind = try adapter.typeKind(forTypeID: typeID)
            // Resolve the target TypeKind from the authoritative `relationTarget`.
            // Same-side reads in-memory `types`; cross-side ItemType and Agenda
            // singletons load from disk (they live outside this manager).
            let targetKind = try adapter.resolveDualTargetKind(for: scope)
            // Reverse scope points back to source Type.
            let targetScope = adapter.reverseRelationTarget(forTypeID: typeID)
            // Reverse name: caller carries the reverse display name in `reverseName`
            // at add-time; the coordinator later mints the reverse property's ID.
            let reverseName = (def.reverseName?.isEmpty == false) ? def.reverseName! : def.name

            let (srcID, _) = try DualRelationCoordinator.createPairedRelation(
                source: sourceKind,
                sourcePropertyName: def.name,
                sourceScope: scope,
                target: targetKind,
                targetPropertyName: reverseName,
                targetScope: targetScope,
                sourceIcon: def.icon,
                targetIcon: def.reverseIcon,
                nexus: adapter.nexusForCoordinator
            )
            // Reload source type from disk so in-memory reflects the coordinator's write.
            adapter.reloadType(byID: typeID)
            // Reload the target so the reverse property appears immediately (not
            // after restart). Same-manager reloads inline; cross-manager routes
            // through the injected hook. Agenda targets reject dual pairing and
            // never reach here.
            let targetID = targetKind.typeID
            if targetID != typeID {
                adapter.reloadType(byID: targetID)
            }
            if let updater = adapter.indexUpdater {
                let reloadedProps = (try? adapter.properties(forTypeID: typeID)) ?? []
                if let addedDef = reloadedProps.first(where: { $0.id == srcID }) {
                    let position = reloadedProps.count - 1
                    do {
                        try updater.upsertPropertyDefinition(
                            addedDef,
                            owningTypeID: typeID,
                            owningTypeKind: adapter.indexOwningTypeKind,
                            position: position)
                    } catch { adapter.recordIndexError(error) }
                }
            }
            return
        }

        try PropertyDefinitionValidator.validate(
            def, in: typeProperties, nexus: adapter.validationContext)

        var properties = typeProperties
        properties.append(def)

        try adapter.commitType(properties: properties, forTypeID: typeID)

        if let updater = adapter.indexUpdater {
            let position = properties.count - 1
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: typeID,
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
        in typeID: String,
        to newName: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forTypeID: typeID)
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

        try adapter.commitType(properties: properties, forTypeID: typeID)

        if let updater = adapter.indexUpdater {
            do {
                try updater.upsertPropertyDefinition(
                    renamedDef,
                    owningTypeID: typeID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the schema. Atomically removes the schema entry and
    /// strips the corresponding key from every member file via `SchemaTransaction`.
    ///
    /// **Paired relations** (`property.dualProperty != nil`): routed through
    /// `DualRelationCoordinator.deletePair` which cascades the delete to both Type
    /// sidecars and strips all values from member files on each side. A property
    /// delete must NEVER be blocked by an unresolvable reverse — if reverse
    /// resolution fails, the reverse index row is best-effort cleaned and the path
    /// falls through to the owner-only removal below.
    @MainActor
    static func deleteProperty(
        id propertyID: String,
        in typeID: String,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forTypeID: typeID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        let prop = typeProperties[propIndex]

        // Paired relation: route through DualRelationCoordinator (cascades both
        // sides). The reverse Type may live in EITHER manager — resolve it
        // cross-manager via the SAME resolver `addProperty` uses
        // (`prop.relationTarget` is the scope pointing at the reverse Type).
        if prop.type == .relation, let dualConfig = prop.dualProperty,
            let scope = prop.relationTarget
        {
            // Best-effort reverse cascade. A property delete must NEVER be blocked
            // by an unresolvable reverse (legacy collection scope, or a
            // drifted/missing target type id) — if resolution fails, skip the
            // reverse cleanup and fall through to the owner-only removal below so
            // the owner property can always be deleted.
            if let reverseKind = try? adapter.resolveDualTargetKind(for: scope) {
                let ownerKind = try adapter.typeKind(forTypeID: typeID)
                let targetTypeID = reverseKind.typeID  // == dualConfig.syncedPropertyDefinedOnTypeID
                try DualRelationCoordinator.deletePair(
                    propertyID: propertyID,
                    owner: ownerKind,
                    reverse: reverseKind,
                    nexus: adapter.nexusForCoordinator
                )
                // Reload the owning (source) type in-memory.
                adapter.reloadType(byID: typeID)
                // Reload the reverse type in-memory: same-manager inline,
                // cross-manager via the injected router hook so it doesn't need a
                // restart.
                adapter.reloadType(byID: targetTypeID)
                if let updater = adapter.indexUpdater {
                    do { try updater.deletePropertyDefinition(id: propertyID) } catch {
                        adapter.recordIndexError(error)
                    }
                    do { try updater.deletePropertyDefinition(id: dualConfig.syncedPropertyID) } catch {
                        adapter.recordIndexError(error)
                    }
                }
                return
            }
            // Unresolvable reverse: best-effort clean the reverse index row, then
            // fall through to the owner-only delete below.
            try? adapter.indexUpdater?.deletePropertyDefinition(id: dualConfig.syncedPropertyID)
        }

        var properties = typeProperties
        properties.remove(at: propIndex)

        let tx = SchemaTransaction()

        // Stage updated schema sidecar.
        try adapter.stageType(properties: properties, forTypeID: typeID, into: tx)

        // Stage member-file rewrites: strip the property key from every member
        // file. The per-side load / strip / re-encode (Page preserves body; Item
        // has none) lives inside the adapter, wrapped in `MemberFileStrip.forEach`.
        try adapter.stripPropertyFromMembers(propertyID, forTypeID: typeID, into: tx)

        try tx.commit()

        if let updater = adapter.indexUpdater {
            do { try updater.deletePropertyDefinition(id: propertyID) } catch {
                adapter.recordIndexError(error)
            }
        }

        adapter.commitStagedType(forTypeID: typeID)
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    @MainActor
    static func reorderProperty(
        id propertyID: String,
        in typeID: String,
        toIndex newIndex: Int,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forTypeID: typeID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        var props = typeProperties
        let clampedIndex = min(max(newIndex, 0), props.count - 1)
        guard clampedIndex != propIndex else { return }

        props.move(
            fromOffsets: IndexSet(integer: propIndex),
            toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex)

        try adapter.commitType(properties: props, forTypeID: typeID)

        if let updater = adapter.indexUpdater {
            for (pos, def) in props.enumerated() {
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: typeID,
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
        in typeID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false,
        on adapter: any PerTypeSchemaAdapter
    ) throws {
        let typeProperties = try adapter.properties(forTypeID: typeID)
        guard let propIndex = typeProperties.firstIndex(where: { $0.id == propertyID }) else {
            throw adapter.errPropertyNotFound
        }

        let oldType = typeProperties[propIndex].type

        if oldType == newType {
            // Lossless: schema-only write to bump modifiedAt.
            var properties = typeProperties
            properties[propIndex].type = newType
            try adapter.commitType(properties: properties, forTypeID: typeID)
            if let updater = adapter.indexUpdater {
                let def = properties[propIndex]
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: typeID,
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
        try adapter.stageType(properties: properties, forTypeID: typeID, into: tx)

        // Stage member-file rewrites: strip the conflicting property value from
        // every member file so no stale cross-type value lingers. The per-side
        // load / strip / re-encode lives inside the adapter.
        try adapter.stripPropertyFromMembers(propertyID, forTypeID: typeID, into: tx)

        try tx.commit()

        if let updater = adapter.indexUpdater {
            let def = properties[propIndex]
            do {
                try updater.upsertPropertyDefinition(
                    def,
                    owningTypeID: typeID,
                    owningTypeKind: adapter.indexOwningTypeKind,
                    position: propIndex)
            } catch { adapter.recordIndexError(error) }
        }

        adapter.commitStagedType(forTypeID: typeID)
    }
}
