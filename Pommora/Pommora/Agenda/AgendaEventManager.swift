import Foundation
import Observation

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

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.eventsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                schema = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
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
            events.removeAll { $0.id == event.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
