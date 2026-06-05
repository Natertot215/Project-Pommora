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
    enum AgendaTaskError: LocalizedError, Equatable {
        /// Thrown by `updateTask` when the caller's `task.title` differs from
        /// the on-record title. Title changes must go through `renameTask`
        /// first so the file is moved before the metadata write.
        case titleChangeRequiresRename
        /// Thrown by `createTask` / `renameTask` when a *different* Task in the
        /// Tasks singleton already holds the desired title (case-insensitive).
        /// Two same-titled Tasks resolve to the same `.task.json` path, so the
        /// second write would silently clobber the first — reject instead
        /// (locked: no auto-rename, no overwrite). Mirrors `PageCRUDError` /
        /// `ItemCRUDError.duplicateTitle`.
        case duplicateTitle

        var errorDescription: String? {
            switch self {
            case .titleChangeRequiresRename:
                return
                    "An agenda task's title can only be changed via renameTask; updateTask refuses to do both at once."
            case .duplicateTitle:
                return "A Task with that name already exists."
            }
        }
    }

    private let nexus: Nexus

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Backing store for the lazily-constructed `schemaAdapter` (declared in the
    /// schema-CRUD extension). Held here because stored properties can't live on
    /// an extension. Not observed — purely an internal service bridge.
    @ObservationIgnored fileprivate var _schemaAdapter: TaskSchemaAdapter?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    // MARK: - Title uniqueness (same-singleton collision)
    //
    // `AgendaTaskValidator` owns title shape + time-field consistency, but it
    // can't see sibling Tasks. The same-container collision rule — which prevents
    // a create/rename from silently overwriting another Task's `.task.json` —
    // lives here, delegated to the shared `NameCollisionValidator` so Pages,
    // Items, and Agenda enforce one identical rule. "Same container" = the Tasks
    // singleton (a flat folder), so the sibling list is the whole `tasks` array.
    private func enforceTitleUniqueness(_ desiredTitle: String, excluding: AgendaTask? = nil) throws {
        try NameCollisionValidator.validate(
            desiredTitle: desiredTitle, siblings: tasks, excludingID: excluding?.id,
            else: AgendaTaskError.duplicateTitle  // preserve the Task-side contract
        )
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.tasksDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                var loaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
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
            try enforceTitleUniqueness(task.title)
            let dir = NexusPaths.tasksDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.taskFileURL(forTitle: task.title, in: nexus)
            try Filesystem.guardNoFile(at: url, else: AgendaTaskError.duplicateTitle)
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
            try enforceTitleUniqueness(newTitle, excluding: task)

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
        // Best-effort cascade: move the entity's attachments folder to trash.
        let attachmentsURL = NexusPaths.attachmentsDir(for: task.id, in: nexus.rootURL)
        if FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? Filesystem.moveToTrash(attachmentsURL, in: nexus)
        }
    }

    // MARK: - Context-delete cascade (Phase 18b)

    /// Removes a deleted Context's ID from the `tier` array of every AgendaTask
    /// that references it. Source-side cascade: invoked at the Context-delete
    /// call site (×4, once per content manager) **before** the Context file is
    /// removed.
    ///
    /// Mirrors `PageContentManager.unlinkTier` — see that method for the full
    /// contract. Agenda files live in a flat singleton folder, so (unlike Pages /
    /// Items) there is no container to resolve: the on-disk URL derives directly
    /// from the title carried by `incomingContextLinks` (sourced from the
    /// `agenda_tasks` table), with an in-memory fallback for index/disk drift.
    /// Each referencing Task is loaded, mutated through the `setRelationIDs`
    /// adapter (tiers route to the Task root, NOT `properties["_tierN"]`),
    /// atomically rewritten, its in-memory cache entry refreshed if loaded, and
    /// re-indexed so the stale `context_links` rows reconcile away.
    ///
    /// Resilient per-entity: a Task that can't be located or loaded is skipped
    /// (the first failure is recorded on `pendingError`) so one bad file never
    /// aborts the cascade.
    func unlinkTier(contextID: String, tier: Int, index: PommoraIndex) async throws {
        guard let tierPropID = ReservedPropertyID.tierPropertyID(forTier: tier) else { return }

        let refs = try await IndexQuery(index).incomingContextLinks(targetID: contextID)
        let taskRefs = refs.filter { $0.kind == .agendaTask }

        for ref in taskRefs {
            do {
                guard let url = locateTaskFile(ref: ref) else { continue }

                var task = try AgendaTask.load(from: url)
                let current = task.relationIDs(forPropertyID: tierPropID)
                guard current.contains(contextID) else { continue }

                task.setRelationIDs(current.filter { $0 != contextID }, forPropertyID: tierPropID)
                task.modifiedAt = Date()
                try task.save(to: url)

                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i] = task
                }

                if let updater = indexUpdater {
                    do { try updater.upsertAgendaTask(task) } catch { self.pendingError = error }
                }
            } catch {
                // Continue-on-individual-failure: a single unreadable / unwritable
                // Task must not block the rest of the cascade.
                self.pendingError = error
                continue
            }
        }
    }

    /// Resolves an AgendaTask's `.task.json` URL from an `incomingContextLinks`
    /// ref. Prefers the in-memory record's current title (rename-fresh), falling
    /// back to the index-sourced `ref.title`; returns the title-derived URL only
    /// if a file exists there.
    private func locateTaskFile(ref: EntityRef) -> URL? {
        let title = tasks.first(where: { $0.id == ref.id })?.title ?? ref.title
        let url = NexusPaths.taskFileURL(forTitle: title, in: nexus)
        return Filesystem.fileExists(at: url) ? url : nil
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
        do { try SingletonSchemaService.addProperty(definition, on: schemaAdapter) } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// name are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, to newName: String) async throws {
        do { try SingletonSchemaService.renameProperty(id: propertyID, to: newName, on: schemaAdapter) } catch {
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
        do { try SingletonSchemaService.deleteProperty(id: propertyID, on: schemaAdapter) } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, toIndex newIndex: Int) async throws {
        do { try SingletonSchemaService.reorderProperty(id: propertyID, toIndex: newIndex, on: schemaAdapter) } catch {
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
            try SingletonSchemaService.changeType(
                of: propertyID,
                to: newType,
                dropConflictingValues: dropConflictingValues,
                on: schemaAdapter)
        } catch {
            self.pendingError = error
            throw error
        }
    }
}

// MARK: - Singleton schema adapter

extension AgendaTaskManager {

    /// Once-constructed adapter that supplies the Task-side per-side bits to the
    /// shared `SingletonSchemaService`. Constructed lazily so `self` is fully
    /// initialized before the `unowned` back-reference is captured.
    fileprivate var schemaAdapter: TaskSchemaAdapter {
        if let existing = _schemaAdapter { return existing }
        let adapter = TaskSchemaAdapter(self)
        _schemaAdapter = adapter
        return adapter
    }

    /// Bridges `AgendaTaskManager`'s in-memory `schema` + `_taskconfig.json`
    /// sidecar to `SingletonSchemaService`. Reproduces the original five method
    /// bodies' per-side behavior verbatim. `unowned` because the manager owns the
    /// adapter for its full lifetime.
    fileprivate final class TaskSchemaAdapter: SingletonSchemaAdapter {
        unowned let m: AgendaTaskManager
        /// Holds the schema staged by `stageSchema` so `commitStagedSchema`
        /// assigns the byte-identical value (same `modifiedAt`) to `m.schema` —
        /// matching the original's single `updated` computed once and reused.
        private var stagedSchema: AgendaTaskSchema?

        init(_ m: AgendaTaskManager) { self.m = m }

        // MARK: Schema read

        var schemaProperties: [PropertyDefinition] { m.schema.properties }

        // MARK: Schema persist

        func writeSchema(properties: [PropertyDefinition]) throws {
            var updated = m.schema
            updated.properties = properties
            updated.modifiedAt = Date()
            try AtomicJSON.write(updated, to: NexusPaths.taskSchemaURL(in: m.nexus))
            m.schema = updated
        }

        func stageSchema(properties: [PropertyDefinition], into tx: SchemaTransaction) throws {
            var updated = m.schema
            updated.properties = properties
            updated.modifiedAt = Date()
            try tx.stage(updated, to: NexusPaths.taskSchemaURL(in: m.nexus))
            stagedSchema = updated
        }

        func commitStagedSchema() {
            guard let updated = stagedSchema else { return }
            m.schema = updated
            stagedSchema = nil
        }

        // MARK: Member files

        func stripPropertyFromMembers(_ propertyID: String, into tx: SchemaTransaction) throws {
            let taskFiles = try Filesystem.children(of: NexusPaths.tasksDir(in: m.nexus)) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }
            MemberFileStrip.forEach(taskFiles) { url in
                var task = try AtomicJSON.decode(AgendaTask.self, from: url)
                guard task.properties[propertyID] != nil else { return }
                task.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(task), to: url)
            }
        }

        // MARK: Guards / validation

        func canDelete(propertyID: String) -> Bool {
            !["_type", "_status"].contains(propertyID)
        }

        var validationContext: NexusContext { NexusContext.forTypeResolution(in: m.nexus) }

        // MARK: Index

        var indexOwningTypeID: String { "agenda_tasks" }
        var indexOwningTypeKind: String { "agenda_task_schema" }
        var indexUpdater: IndexUpdater? { m.indexUpdater }

        // MARK: Errors

        var errPropertyNotFound: any Error { AgendaTaskManagerError.propertyNotFound }
        var errCannotDeleteBuiltin: any Error { AgendaTaskManagerError.cannotDeleteBuiltinProperty }
        var errLossyChangeRequiresConfirmation: any Error {
            AgendaTaskManagerError.lossyChangeRequiresConfirmation
        }
        var errIndexOutOfBounds: any Error { AgendaTaskManagerError.indexOutOfBounds }

        // MARK: pendingError sink

        func recordIndexError(_ error: any Error) { m.pendingError = error }
    }
}
