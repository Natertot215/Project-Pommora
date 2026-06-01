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
    enum AgendaEventError: LocalizedError, Equatable {
        /// Thrown by `updateEvent` when the caller's `event.title` differs from
        /// the on-record title. Title changes must go through `renameEvent`
        /// first so the file is moved before the metadata write.
        case titleChangeRequiresRename
        /// Thrown by `createEvent` / `renameEvent` when a *different* Event in the
        /// Events singleton already holds the desired title (case-insensitive).
        /// Two same-titled Events resolve to the same `.event.json` path, so the
        /// second write would silently clobber the first — reject instead
        /// (locked: no auto-rename, no overwrite). Mirrors `PageCRUDError` /
        /// `ItemCRUDError.duplicateTitle`.
        case duplicateTitle

        var errorDescription: String? {
            switch self {
            case .titleChangeRequiresRename:
                return
                    "An agenda event's title can only be changed via renameEvent; updateEvent refuses to do both at once."
            case .duplicateTitle:
                return "An Event with that name already exists."
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
    @ObservationIgnored fileprivate var _schemaAdapter: EventSchemaAdapter?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    // MARK: - Title uniqueness (same-singleton collision)
    //
    // `AgendaEventValidator` owns title shape + start/end consistency, but it
    // can't see sibling Events. The same-container collision rule — which
    // prevents a create/rename from silently overwriting another Event's
    // `.event.json` — lives here, delegated to the shared
    // `NameCollisionValidator` so Pages, Items, and Agenda enforce one identical
    // rule. "Same container" = the Events singleton (a flat folder), so the
    // sibling list is the whole `events` array.
    private func enforceTitleUniqueness(_ desiredTitle: String, excluding: AgendaEvent? = nil) throws {
        try NameCollisionValidator.validate(
            desiredTitle: desiredTitle, siblings: events, excludingID: excluding?.id,
            else: AgendaEventError.duplicateTitle  // preserve the Event-side contract
        )
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
            try enforceTitleUniqueness(event.title)
            let dir = NexusPaths.eventsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.eventFileURL(forTitle: event.title, in: nexus)
            try Filesystem.guardNoFile(at: url, else: AgendaEventError.duplicateTitle)
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
            try enforceTitleUniqueness(newTitle, excluding: event)

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

    // MARK: - Context-delete cascade (Phase 18b)

    /// Removes a deleted Context's ID from the `tier` array of every AgendaEvent
    /// that references it. Source-side cascade: invoked at the Context-delete
    /// call site (×4, once per content manager) **before** the Context file is
    /// removed.
    ///
    /// Mirrors `PageContentManager.unlinkTier` — see that method for the full
    /// contract. Agenda files live in a flat singleton folder, so (unlike Pages /
    /// Items) there is no container to resolve: the on-disk URL derives directly
    /// from the title carried by `incomingRelations` (sourced from the
    /// `agenda_events` table), with an in-memory fallback for index/disk drift.
    /// Each referencing Event is loaded, mutated through the `setRelationIDs`
    /// adapter (tiers route to the Event root, NOT `properties["_tierN"]`),
    /// atomically rewritten, its in-memory cache entry refreshed if loaded, and
    /// re-indexed so the stale `relations` rows reconcile away.
    ///
    /// Resilient per-entity: an Event that can't be located or loaded is skipped
    /// (the first failure is recorded on `pendingError`) so one bad file never
    /// aborts the cascade.
    func unlinkTier(contextID: String, tier: Int, index: PommoraIndex) async throws {
        guard let tierPropID = ReservedPropertyID.tierPropertyID(forTier: tier) else { return }

        let refs = try await IndexQuery(index).incomingRelations(targetID: contextID)
        let eventRefs = refs.filter { $0.kind == .agendaEvent }

        for ref in eventRefs {
            do {
                guard let url = locateEventFile(ref: ref) else { continue }

                var event = try AgendaEvent.load(from: url)
                let current = event.relationIDs(forPropertyID: tierPropID)
                guard current.contains(contextID) else { continue }

                event.setRelationIDs(current.filter { $0 != contextID }, forPropertyID: tierPropID)
                event.modifiedAt = Date()
                try event.save(to: url)

                if let i = events.firstIndex(where: { $0.id == event.id }) {
                    events[i] = event
                }

                if let updater = indexUpdater {
                    do { try updater.upsertAgendaEvent(event) } catch { self.pendingError = error }
                }
            } catch {
                // Continue-on-individual-failure: a single unreadable / unwritable
                // Event must not block the rest of the cascade.
                self.pendingError = error
                continue
            }
        }
    }

    /// Resolves an AgendaEvent's `.event.json` URL from an `incomingRelations`
    /// ref. Prefers the in-memory record's current title (rename-fresh), falling
    /// back to the index-sourced `ref.title`; returns the title-derived URL only
    /// if a file exists there.
    private func locateEventFile(ref: EntityRef) -> URL? {
        let title = events.first(where: { $0.id == ref.id })?.title ?? ref.title
        let url = NexusPaths.eventFileURL(forTitle: title, in: nexus)
        return Filesystem.fileExists(at: url) ? url : nil
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

    /// Deletes a property from the Events singleton schema. Built-in properties
    /// (`_type`, `_status`) cannot be deleted — throws `cannotDeleteBuiltinProperty`.
    /// Atomically removes the schema entry and strips the corresponding key from
    /// every `.event.json` member file via `SchemaTransaction`.
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
    ///   strips the property's value from every `.event.json` member file via
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

extension AgendaEventManager {

    /// Once-constructed adapter that supplies the Event-side per-side bits to the
    /// shared `SingletonSchemaService`. Constructed lazily so `self` is fully
    /// initialized before the `unowned` back-reference is captured.
    fileprivate var schemaAdapter: EventSchemaAdapter {
        if let existing = _schemaAdapter { return existing }
        let adapter = EventSchemaAdapter(self)
        _schemaAdapter = adapter
        return adapter
    }

    /// Bridges `AgendaEventManager`'s in-memory `schema` + `_eventconfig.json`
    /// sidecar to `SingletonSchemaService`. Reproduces the original five method
    /// bodies' per-side behavior verbatim. `unowned` because the manager owns the
    /// adapter for its full lifetime.
    fileprivate final class EventSchemaAdapter: SingletonSchemaAdapter {
        unowned let m: AgendaEventManager
        /// Holds the schema staged by `stageSchema` so `commitStagedSchema`
        /// assigns the byte-identical value (same `modifiedAt`) to `m.schema` —
        /// matching the original's single `updated` computed once and reused.
        private var stagedSchema: AgendaEventSchema?

        init(_ m: AgendaEventManager) { self.m = m }

        // MARK: Schema read

        var schemaProperties: [PropertyDefinition] { m.schema.properties }

        // MARK: Schema persist

        func writeSchema(properties: [PropertyDefinition]) throws {
            var updated = m.schema
            updated.properties = properties
            updated.modifiedAt = Date()
            try AtomicJSON.write(updated, to: NexusPaths.eventSchemaURL(in: m.nexus))
            m.schema = updated
        }

        func stageSchema(properties: [PropertyDefinition], into tx: SchemaTransaction) throws {
            var updated = m.schema
            updated.properties = properties
            updated.modifiedAt = Date()
            try tx.stage(updated, to: NexusPaths.eventSchemaURL(in: m.nexus))
            stagedSchema = updated
        }

        func commitStagedSchema() {
            guard let updated = stagedSchema else { return }
            m.schema = updated
            stagedSchema = nil
        }

        // MARK: Member files

        func stripPropertyFromMembers(_ propertyID: String, into tx: SchemaTransaction) throws {
            let eventFiles = try Filesystem.children(of: NexusPaths.eventsDir(in: m.nexus)) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }
            MemberFileStrip.forEach(eventFiles) { url in
                var event = try AtomicJSON.decode(AgendaEvent.self, from: url)
                guard event.properties[propertyID] != nil else { return }
                event.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(event), to: url)
            }
        }

        // MARK: Guards / validation

        // NOTE: `_status` is included here even though Events have no `_status`
        // per spec. This preserves the existing behavior of the pre-refactor
        // `deleteProperty` guard (`builtinIDs: Set<String> = ["_type", "_status"]`).
        // The doc-comment inconsistency in `AgendaEventManagerError.cannotDeleteBuiltinProperty`
        // is tracked separately and must not be "fixed" during this refactor.
        func canDelete(propertyID: String) -> Bool {
            !["_type", "_status"].contains(propertyID)
        }

        var validationContext: NexusContext { NexusContext.forTypeResolution(in: m.nexus) }

        // MARK: Index

        var indexOwningTypeID: String { "agenda_events" }
        var indexOwningTypeKind: String { "agenda_event_schema" }
        var indexUpdater: IndexUpdater? { m.indexUpdater }

        // MARK: Errors

        var errPropertyNotFound: any Error { AgendaEventManagerError.propertyNotFound }
        var errCannotDeleteBuiltin: any Error { AgendaEventManagerError.cannotDeleteBuiltinProperty }
        var errLossyChangeRequiresConfirmation: any Error {
            AgendaEventManagerError.lossyChangeRequiresConfirmation
        }
        var errIndexOutOfBounds: any Error { AgendaEventManagerError.indexOutOfBounds }

        // MARK: pendingError sink

        func recordIndexError(_ error: any Error) { m.pendingError = error }
    }
}
