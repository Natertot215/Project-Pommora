import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProperty

/// Owns the in-memory AgendaEvent collection + the `_eventconfig.json` sidecar
/// for the Events singleton folder (discovered by sidecar presence at the nexus
/// root per locked decision #5; default `<nexus>/Events/` when absent — eagerly
/// seeded by `loadAll` per locked decision #9). Parallel to AgendaTaskManager
/// on the Tasks side.
@MainActor
@Observable
final class AgendaEventManager {
    private(set) var schema: AgendaEventSchema = AgendaEventSchema.defaultSeed()
    private(set) var events: [AgendaEvent] = []
    var pendingError: (any Error)?

    /// AgendaEventManager-specific errors that need to surface to UI.
    /// Named `AgendaEventError` (not `Error`) to avoid shadowing Swift's `Error`
    /// protocol in the rest of the class body.
    enum AgendaEventError: LocalizedError {
        /// Thrown by `updateEvent` when the caller's `event.title` differs from
        /// the on-record title. Title changes must go through `renameEvent`
        /// first so the file is moved before the metadata write.
        case titleChangeRequiresRename

        var errorDescription: String? {
            switch self {
            case .titleChangeRequiresRename:
                return
                    "An agenda event's title can only be changed via renameEvent; updateEvent refuses to do both at once."
            }
        }
    }

    private let nexus: Nexus

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.eventsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                var loaded = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
                // G.3: backfill _status if the existing sidecar pre-dates Phase G.
                // Prepend so _status appears first in the schema; write atomically
                // via SchemaTransaction so a partial write doesn't corrupt the sidecar.
                if loaded.properties.first(where: { $0.id == "_status" }) == nil {
                    let statusDef = PropertyDefinition(
                        id: "_status",
                        name: "Status",
                        type: .status,
                        statusGroups: PropertyDefinition.StatusGroup.defaultSeed()
                    )
                    loaded.properties.insert(statusDef, at: 0)
                    loaded.modifiedAt = Date()
                    let tx = SchemaTransaction()
                    try tx.stage(loaded, to: schemaURL)
                    try tx.commit()
                }
                schema = loaded
            } else {
                schema = AgendaEventSchema.defaultSeed()
                try AtomicJSON.write(schema, to: schemaURL)
            }

            let eventFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }
            events = eventFiles.compactMap { try? AgendaEvent.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            pendingError = nil
        } catch {
            events = []
            pendingError = error
        }
    }

    func createEvent(_ event: AgendaEvent) async throws {
        do {
            try AgendaEventValidator.validate(
                title: event.title,
                startAt: event.startAt, endAt: event.endAt,
                properties: event.properties,
                schema: schema
            )
            let dir = NexusPaths.eventsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.eventFileURL(forTitle: event.title, in: nexus)
            try event.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertAgendaEvent(event) } catch { self.pendingError = error }
            }

            events.append(event)
            events.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Updates an existing AgendaEvent in place. **Refuses to rename**: if the
    /// caller's `event.title` differs from the on-record title, throws
    /// `AgendaEventError.titleChangeRequiresRename`. Title changes must go
    /// through `renameEvent(_:to:)` first so the file move is atomic with the
    /// metadata update.
    func updateEvent(_ event: AgendaEvent) async throws {
        do {
            if let prev = events.first(where: { $0.id == event.id }), prev.title != event.title {
                throw AgendaEventError.titleChangeRequiresRename
            }

            try AgendaEventValidator.validate(
                title: event.title,
                startAt: event.startAt, endAt: event.endAt,
                properties: event.properties,
                schema: schema
            )
            var updated = event
            updated.modifiedAt = Date()
            let url = NexusPaths.eventFileURL(forTitle: event.title, in: nexus)
            try updated.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertAgendaEvent(updated) } catch { self.pendingError = error }
            }

            if let i = events.firstIndex(where: { $0.id == event.id }) {
                events[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Renames an AgendaEvent on disk and updates the in-memory record. Mirrors
    /// the rename-atomicity rollback pattern used elsewhere — if the metadata
    /// save fails the file rename is reverted; if the revert also fails a
    /// `RenameAtomicityError` is surfaced.
    func renameEvent(_ event: AgendaEvent, to newTitle: String) async throws {
        do {
            try AgendaEventValidator.validate(
                title: newTitle,
                startAt: event.startAt, endAt: event.endAt,
                properties: event.properties,
                schema: schema
            )

            let oldURL = NexusPaths.eventFileURL(forTitle: event.title, in: nexus)
            let newURL = NexusPaths.eventFileURL(forTitle: newTitle, in: nexus)

            var updated = event
            updated.title = newTitle
            updated.modifiedAt = Date()

            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertAgendaEvent(updated) } catch { self.pendingError = error }
            }

            if let i = events.firstIndex(where: { $0.id == event.id }) {
                events[i] = updated
                events.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteEvent(_ event: AgendaEvent) async throws {
        do {
            let url = NexusPaths.eventFileURL(forTitle: event.title, in: nexus)
            try Filesystem.moveToTrash(url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteAgendaEvent(id: event.id) } catch { self.pendingError = error }
            }
            events.removeAll { $0.id == event.id }
        } catch {
            self.pendingError = error
            throw error
        }
        // Best-effort cascade: move the entity's attachments folder to trash.
        let attachmentsURL = NexusPaths.attachmentsDir(for: event.id, in: nexus.rootURL)
        if FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? Filesystem.moveToTrash(attachmentsURL, in: nexus)
        }
    }
}

// MARK: - Schema CRUD errors

enum AgendaEventManagerError: Error, Equatable {
    case propertyNotFound
    /// Thrown when attempting to delete a built-in property (`_type`) that Pommora
    /// manages and requires for core functionality. Events have no `_status`.
    case cannotDeleteBuiltinProperty
    case lossyChangeRequiresConfirmation
    case indexOutOfBounds
}

// MARK: - Schema CRUD methods

extension AgendaEventManager {

    // MARK: - Add property

    /// Adds a property definition to the Events singleton schema. If `definition.id` is
    /// empty, a new user-property ID (`prop_<ulid>`) is minted. Validates against
    /// existing properties via `PropertyDefinitionValidator`. Schema-only write (member
    /// files are not touched — identity is stored by ID).
    func addProperty(_ definition: PropertyDefinition) async throws {
        do {
            var def = definition
            if def.id.isEmpty {
                def.id = ReservedPropertyID.mintUserPropertyID()
            }

            try PropertyDefinitionValidator.validate(def, in: schema.properties)

            var updated = schema
            updated.properties.append(def)
            updated.modifiedAt = Date()

            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: "agenda_events",
                        owningTypeKind: "agenda_event_schema",
                        position: updated.properties.count - 1
                    )
                } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// name are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, to newName: String) async throws {
        do {
            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaEventManagerError.propertyNotFound
            }

            var renamedDef = schema.properties[propIndex]
            renamedDef.name = newName

            // Build the schema with the renamed definition substituted in, so validation
            // can check name-uniqueness against the rest of the schema (excluding itself).
            var otherProps = schema.properties
            otherProps.remove(at: propIndex)
            // Validate name only — supply a fresh temp-unique ID so the duplicate-ID
            // rule doesn't fire. We only care about the name-uniqueness check here.
            var validationDef = renamedDef
            validationDef.id = ReservedPropertyID.mintUserPropertyID()
            try PropertyDefinitionValidator.validate(validationDef, in: otherProps)

            var updated = schema
            updated.properties[propIndex] = renamedDef
            updated.modifiedAt = Date()

            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                do {
                    try updater.upsertPropertyDefinition(
                        renamedDef,
                        owningTypeID: "agenda_events",
                        owningTypeKind: "agenda_event_schema",
                        position: propIndex
                    )
                } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the Events singleton schema. Built-in properties
    /// (`_type`, `_status`) cannot be deleted — throws `cannotDeleteBuiltinProperty`.
    /// Atomically removes the schema entry and strips the corresponding key from
    /// every `.event.json` member file via `SchemaTransaction`.
    func deleteProperty(id propertyID: String) async throws {
        do {
            // Block deletion of built-in reserved properties.
            let builtinIDs: Set<String> = ["_type", "_status"]
            guard !builtinIDs.contains(propertyID) else {
                throw AgendaEventManagerError.cannotDeleteBuiltinProperty
            }

            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaEventManagerError.propertyNotFound
            }

            var updated = schema
            updated.properties.remove(at: propIndex)
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            try tx.stage(updated, to: schemaURL)

            // Stage member-file rewrites: strip the property key from every event file.
            let dir = NexusPaths.eventsDir(in: nexus)
            let eventFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }
            for eventURL in eventFiles {
                var event = try AtomicJSON.decode(AgendaEvent.self, from: eventURL)
                guard event.properties[propertyID] != nil else { continue }
                event.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(event), to: eventURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                do { try updater.deletePropertyDefinition(id: propertyID) } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, toIndex newIndex: Int) async throws {
        do {
            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaEventManagerError.propertyNotFound
            }

            var props = schema.properties
            let clampedIndex = min(max(newIndex, 0), props.count - 1)
            guard clampedIndex != propIndex else { return }

            guard clampedIndex >= 0 && clampedIndex < props.count else {
                throw AgendaEventManagerError.indexOutOfBounds
            }

            props.move(
                fromOffsets: IndexSet(integer: propIndex),
                toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex
            )

            var updated = schema
            updated.properties = props
            updated.modifiedAt = Date()

            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                for (pos, def) in updated.properties.enumerated() {
                    do {
                        try updater.upsertPropertyDefinition(
                            def,
                            owningTypeID: "agenda_events",
                            owningTypeKind: "agenda_event_schema",
                            position: pos
                        )
                    } catch { self.pendingError = error }
                }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
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
    ///   strips the property's value from every `.event.json` member file via
    ///   `SchemaTransaction`.
    func changeType(
        of propertyID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        do {
            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaEventManagerError.propertyNotFound
            }

            let oldType = schema.properties[propIndex].type

            if oldType == newType {
                // Lossless: schema-only write to bump modifiedAt.
                var updated = schema
                updated.properties[propIndex].type = newType
                updated.modifiedAt = Date()
                let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
                try AtomicJSON.write(updated, to: schemaURL)
                if let updater = indexUpdater {
                    let def = updated.properties[propIndex]
                    do {
                        try updater.upsertPropertyDefinition(
                            def,
                            owningTypeID: "agenda_events",
                            owningTypeKind: "agenda_event_schema",
                            position: propIndex
                        )
                    } catch { self.pendingError = error }
                }
                schema = updated
                return
            }

            // Lossy cross-type change.
            guard dropConflictingValues else {
                throw AgendaEventManagerError.lossyChangeRequiresConfirmation
            }

            var updated = schema
            updated.properties[propIndex].type = newType
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            try tx.stage(updated, to: schemaURL)

            // Stage member-file rewrites: strip the conflicting property value from
            // every event file so no stale cross-type value lingers.
            let dir = NexusPaths.eventsDir(in: nexus)
            let eventFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }
            for eventURL in eventFiles {
                var event = try AtomicJSON.decode(AgendaEvent.self, from: eventURL)
                guard event.properties[propertyID] != nil else { continue }
                event.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(event), to: eventURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                let def = updated.properties[propIndex]
                do {
                    try updater.upsertPropertyDefinition(
                        def,
                        owningTypeID: "agenda_events",
                        owningTypeKind: "agenda_event_schema",
                        position: propIndex
                    )
                } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
