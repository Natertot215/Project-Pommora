import Foundation
import Observation

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
            tasks.removeAll { $0.id == task.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
