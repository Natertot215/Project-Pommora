import Foundation
import Observation

@MainActor
@Observable
final class AgendaManager {
    private(set) var schema: AgendaSchema = AgendaSchema.defaultSeed()
    private(set) var items: [AgendaItem] = []
    var pendingError: (any Error)?

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
                url.pathExtension == "json" &&
                url.deletingPathExtension().pathExtension == "agenda"
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
    }

    func updateItem(_ item: AgendaItem) async throws {
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
    }

    func deleteItem(_ item: AgendaItem) async throws {
        let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
        try Filesystem.deleteFile(at: url)
        items.removeAll { $0.id == item.id }
    }
}
