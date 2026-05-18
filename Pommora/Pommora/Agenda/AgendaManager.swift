import Foundation
import Observation

@MainActor
@Observable
final class AgendaManager {
    private(set) var schema: AgendaSchema = AgendaSchema.defaultSeed()
    private(set) var items: [AgendaItem] = []
    var pendingError: (any Error)?

    /// AgendaManager-specific errors that need to surface to UI.
    /// Named `AgendaError` (not `Error`) to avoid shadowing Swift's `Error`
    /// protocol in the rest of the class body.
    enum AgendaError: LocalizedError {
        /// Thrown by `updateItem` when the caller's `item.title` differs from
        /// the on-record title. Title changes must go through `renameAgendaItem`
        /// first so the file is moved before the metadata write.
        case titleChangeRequiresRename

        var errorDescription: String? {
            switch self {
            case .titleChangeRequiresRename:
                return
                    "An agenda item's title can only be changed via renameAgendaItem; updateItem refuses to do both at once."
            }
        }
    }

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.agendaDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.agendaSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                schema = try AtomicJSON.decode(AgendaSchema.self, from: schemaURL)
            } else {
                schema = AgendaSchema.defaultSeed()
                try AtomicJSON.write(schema, to: schemaURL)
            }

            let itemFiles = try Filesystem.children(of: dir) { url in
                url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "agenda"
            }
            items = itemFiles.compactMap { try? AgendaItem.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            pendingError = nil
        } catch {
            items = []
            pendingError = error
        }
    }

    func createItem(_ item: AgendaItem) async throws {
        do {
            try AgendaValidator.validate(
                title: item.title,
                startAt: item.startAt, endAt: item.endAt, allDay: item.allDay,
                dueAt: item.dueAt, dueAllDay: item.dueAllDay,
                properties: item.properties,
                schema: schema
            )
            let dir = NexusPaths.agendaDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
            try item.save(to: url)
            items.append(item)
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Updates an existing AgendaItem in place. **Refuses to rename**: if the
    /// caller's `item.title` differs from the on-record title, throws
    /// `Error.titleChangeRequiresRename`. Title changes must go through
    /// `renameAgendaItem(_:to:)` first so the file move is atomic with the
    /// metadata update.
    func updateItem(_ item: AgendaItem) async throws {
        do {
            if let prev = items.first(where: { $0.id == item.id }), prev.title != item.title {
                throw AgendaError.titleChangeRequiresRename
            }

            try AgendaValidator.validate(
                title: item.title,
                startAt: item.startAt, endAt: item.endAt, allDay: item.allDay,
                dueAt: item.dueAt, dueAllDay: item.dueAllDay,
                properties: item.properties,
                schema: schema
            )
            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
            try updated.save(to: url)
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Renames an AgendaItem on disk and updates the in-memory record. Mirrors
    /// the rename-atomicity rollback pattern used elsewhere — if the metadata
    /// save fails the file rename is reverted; if the revert also fails a
    /// `RenameAtomicityError` is surfaced.
    func renameAgendaItem(_ item: AgendaItem, to newTitle: String) async throws {
        do {
            try AgendaValidator.validate(
                title: newTitle,
                startAt: item.startAt, endAt: item.endAt, allDay: item.allDay,
                dueAt: item.dueAt, dueAllDay: item.dueAllDay,
                properties: item.properties,
                schema: schema
            )

            let oldURL = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
            let newURL = NexusPaths.agendaItemFileURL(forTitle: newTitle, in: nexus)

            var updated = item
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

            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i] = updated
                items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteItem(_ item: AgendaItem) async throws {
        do {
            let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
            try Filesystem.moveToTrash(url, in: nexus)
            items.removeAll { $0.id == item.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
