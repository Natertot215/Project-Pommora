import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProperty

/// Owns the in-memory AgendaTask collection + the `_taskconfig.json` sidecar
/// for the Tasks singleton folder (discovered by sidecar presence at the nexus
/// root per locked decision #5; default `<nexus>/Tasks/` when absent — eagerly
/// seeded by `loadAll` per locked decision #9). Parallel to AgendaEventManager
/// on the Events side.
@MainActor
@Observable
final class AgendaTaskManager {
    private(set) var schema: AgendaTaskSchema = AgendaTaskSchema.defaultSeed()
    private(set) var tasks: [AgendaTask] = []
    var pendingError: (any Error)?

    /// AgendaTaskManager-specific errors that need to surface to UI.
    /// Named `AgendaTaskError` (not `Error`) to avoid shadowing Swift's `Error`
    /// protocol in the rest of the class body.
    enum AgendaTaskError: LocalizedError {
        /// Thrown by `updateTask` when the caller's `task.title` differs from
        /// the on-record title. Title changes must go through `renameTask`
        /// first so the file is moved before the metadata write.
        case titleChangeRequiresRename

        var errorDescription: String? {
            switch self {
            case .titleChangeRequiresRename:
                return
                    "An agenda task's title can only be changed via renameTask; updateTask refuses to do both at once."
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
            let dir = NexusPaths.tasksDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                schema = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
            } else {
                schema = AgendaTaskSchema.defaultSeed()
                try AtomicJSON.write(schema, to: schemaURL)
            }

            let taskFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }
            tasks = taskFiles.compactMap { try? AgendaTask.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            pendingError = nil
        } catch {
            tasks = []
            pendingError = error
        }
    }

    func createTask(_ task: AgendaTask) async throws {
        do {
            try AgendaTaskValidator.validate(
                title: task.title,
                dueAt: task.dueAt, dueAllDay: task.dueAllDay,
                properties: task.properties,
                schema: schema
            )
            let dir = NexusPaths.tasksDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.taskFileURL(forTitle: task.title, in: nexus)
            try task.save(to: url)
            if let updater = indexUpdater {
                do { try updater.upsertAgendaTask(task) } catch { self.pendingError = error }
            }
            tasks.append(task)
            tasks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Updates an existing AgendaTask in place. **Refuses to rename**: if the
    /// caller's `task.title` differs from the on-record title, throws
    /// `AgendaTaskError.titleChangeRequiresRename`. Title changes must go
    /// through `renameTask(_:to:)` first so the file move is atomic with the
    /// metadata update.
    func updateTask(_ task: AgendaTask) async throws {
        do {
            if let prev = tasks.first(where: { $0.id == task.id }), prev.title != task.title {
                throw AgendaTaskError.titleChangeRequiresRename
            }

            try AgendaTaskValidator.validate(
                title: task.title,
                dueAt: task.dueAt, dueAllDay: task.dueAllDay,
                properties: task.properties,
                schema: schema
            )
            var updated = task
            updated.modifiedAt = Date()
            let url = NexusPaths.taskFileURL(forTitle: task.title, in: nexus)
            try updated.save(to: url)
            if let updater = indexUpdater {
                do { try updater.upsertAgendaTask(updated) } catch { self.pendingError = error }
            }
            if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Renames an AgendaTask on disk and updates the in-memory record. Mirrors
    /// the rename-atomicity rollback pattern used elsewhere — if the metadata
    /// save fails the file rename is reverted; if the revert also fails a
    /// `RenameAtomicityError` is surfaced.
    func renameTask(_ task: AgendaTask, to newTitle: String) async throws {
        do {
            try AgendaTaskValidator.validate(
                title: newTitle,
                dueAt: task.dueAt, dueAllDay: task.dueAllDay,
                properties: task.properties,
                schema: schema
            )

            let oldURL = NexusPaths.taskFileURL(forTitle: task.title, in: nexus)
            let newURL = NexusPaths.taskFileURL(forTitle: newTitle, in: nexus)

            var updated = task
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
                do { try updater.upsertAgendaTask(updated) } catch { self.pendingError = error }
            }

            if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[i] = updated
                tasks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteTask(_ task: AgendaTask) async throws {
        do {
            let url = NexusPaths.taskFileURL(forTitle: task.title, in: nexus)
            try Filesystem.moveToTrash(url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteAgendaTask(id: task.id) } catch { self.pendingError = error }
            }
            tasks.removeAll { $0.id == task.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}

// MARK: - Schema CRUD errors

enum AgendaTaskManagerError: Error, Equatable {
    case propertyNotFound
    /// Thrown when attempting to delete a built-in property (`_type`, `_status`, etc.)
    /// that Pommora manages and requires for core functionality.
    case cannotDeleteBuiltinProperty
    case lossyChangeRequiresConfirmation
    case indexOutOfBounds
}

// MARK: - Schema CRUD methods

extension AgendaTaskManager {

    // MARK: - Add property

    /// Adds a property definition to the Tasks singleton schema. If `definition.id` is
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

            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                let position = updated.properties.count - 1
                do { try updater.upsertPropertyDefinition(def, owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema", position: position) } catch { self.pendingError = error }
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
                throw AgendaTaskManagerError.propertyNotFound
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

            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                do { try updater.upsertPropertyDefinition(renamedDef, owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema", position: propIndex) } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the Tasks singleton schema. Built-in properties
    /// (`_type`, `_status`) cannot be deleted — throws `cannotDeleteBuiltinProperty`.
    /// Atomically removes the schema entry and strips the corresponding key from
    /// every `.task.json` member file via `SchemaTransaction`.
    func deleteProperty(id propertyID: String) async throws {
        do {
            // Block deletion of built-in reserved properties.
            // _status non-deletable per plan; _type non-deletable as core select.
            let builtinIDs: Set<String> = ["_type", "_status"]
            guard !builtinIDs.contains(propertyID) else {
                throw AgendaTaskManagerError.cannotDeleteBuiltinProperty
            }

            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaTaskManagerError.propertyNotFound
            }

            var updated = schema
            updated.properties.remove(at: propIndex)
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            try tx.stage(updated, to: schemaURL)

            // Stage member-file rewrites: strip the property key from every task file.
            let dir = NexusPaths.tasksDir(in: nexus)
            let taskFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }
            for taskURL in taskFiles {
                var task = try AtomicJSON.decode(AgendaTask.self, from: taskURL)
                guard task.properties[propertyID] != nil else { continue }
                task.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(task), to: taskURL)
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
                throw AgendaTaskManagerError.propertyNotFound
            }

            var props = schema.properties
            let clampedIndex = min(max(newIndex, 0), props.count - 1)
            guard clampedIndex != propIndex else { return }

            guard clampedIndex >= 0 && clampedIndex < props.count else {
                throw AgendaTaskManagerError.indexOutOfBounds
            }

            props.move(
                fromOffsets: IndexSet(integer: propIndex),
                toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex
            )

            var updated = schema
            updated.properties = props
            updated.modifiedAt = Date()

            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            try AtomicJSON.write(updated, to: schemaURL)

            if let updater = indexUpdater {
                for (pos, def) in updated.properties.enumerated() {
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema", position: pos) } catch { self.pendingError = error }
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
    ///   strips the property's value from every `.task.json` member file via
    ///   `SchemaTransaction`.
    func changeType(
        of propertyID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        do {
            guard let propIndex = schema.properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw AgendaTaskManagerError.propertyNotFound
            }

            let oldType = schema.properties[propIndex].type

            if oldType == newType {
                // Lossless: schema-only write to bump modifiedAt.
                var updated = schema
                updated.properties[propIndex].type = newType
                updated.modifiedAt = Date()
                let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
                try AtomicJSON.write(updated, to: schemaURL)
                if let updater = indexUpdater {
                    let def = updated.properties[propIndex]
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema", position: propIndex) } catch { self.pendingError = error }
                }
                schema = updated
                return
            }

            // Lossy cross-type change.
            guard dropConflictingValues else {
                throw AgendaTaskManagerError.lossyChangeRequiresConfirmation
            }

            var updated = schema
            updated.properties[propIndex].type = newType
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            try tx.stage(updated, to: schemaURL)

            // Stage member-file rewrites: strip the conflicting property value from
            // every task file so no stale cross-type value lingers.
            let dir = NexusPaths.tasksDir(in: nexus)
            let taskFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }
            for taskURL in taskFiles {
                var task = try AtomicJSON.decode(AgendaTask.self, from: taskURL)
                guard task.properties[propertyID] != nil else { continue }
                task.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(task), to: taskURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                let def = updated.properties[propIndex]
                do { try updater.upsertPropertyDefinition(def, owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema", position: propIndex) } catch { self.pendingError = error }
            }

            schema = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
