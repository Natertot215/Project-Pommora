import Foundation
import Testing

@testable import Pommora

/// FIX 2 regression coverage: the same-singleton name-collision data-loss bug on
/// the Agenda side. Two same-titled Tasks (or Events) resolve to the SAME
/// `.task.json` / `.event.json` path; the second `AtomicJSON.write(.atomic)`
/// would silently clobber the first. Locked behavior: REJECT (no auto-rename, no
/// overwrite), mirroring Pages + Items via the shared `NameCollisionValidator`.
///
/// "Same container" = the Tasks singleton (for Tasks) / the Events singleton
/// (for Events) — both flat folders, so every sibling participates.
///
/// Filename = struct name (`AgendaNameCollisionTests`) so `-only-testing`
/// actually runs these (branch quirks #1 / #17).
@MainActor
@Suite("AgendaNameCollisionTests")
struct AgendaNameCollisionTests {

    // MARK: - Tasks

    @Test("createTask duplicate title throws duplicateTitle + first task's data intact")
    func taskCreateDuplicateRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // First task with a distinguishing description written to disk.
        var first = makeTask(title: "Buy milk")
        first.description = "PRECIOUS"
        try await manager.createTask(first)

        // Colliding create must throw.
        await #expect(throws: AgendaTaskManager.AgendaTaskError.duplicateTitle) {
            try await manager.createTask(makeTask(title: "Buy milk"))
        }

        // First task's file is intact (NOT clobbered) + still one task in memory.
        let url = NexusPaths.taskFileURL(forTitle: "Buy milk", in: nexus)
        let reloaded = try AgendaTask.load(from: url)
        #expect(reloaded.id == first.id)
        #expect(reloaded.description == "PRECIOUS")
        #expect(manager.tasks.count == 1)
    }

    @Test("createTask collision is case-insensitive (Buy milk vs BUY MILK)")
    func taskCreateCaseInsensitiveRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createTask(makeTask(title: "Buy milk"))
        await #expect(throws: AgendaTaskManager.AgendaTaskError.duplicateTitle) {
            try await manager.createTask(makeTask(title: "BUY MILK"))
        }
        #expect(manager.tasks.count == 1)
    }

    @Test("renameTask onto an existing sibling's title throws + both files intact")
    func taskRenameOntoSiblingRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createTask(makeTask(title: "Buy milk"))
        try await manager.createTask(makeTask(title: "Buy bread"))
        let bread = manager.tasks.first { $0.title == "Buy bread" }!

        await #expect(throws: AgendaTaskManager.AgendaTaskError.duplicateTitle) {
            try await manager.renameTask(bread, to: "Buy milk")
        }

        // Both files survive with their original titles.
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.taskFileURL(forTitle: "Buy milk", in: nexus).path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.taskFileURL(forTitle: "Buy bread", in: nexus).path))
        #expect(manager.tasks.count == 2)
    }

    @Test("renameTask onto a sibling differing only in case still throws")
    func taskRenameOntoCaseVariantSiblingRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createTask(makeTask(title: "Buy milk"))
        try await manager.createTask(makeTask(title: "Buy bread"))
        let bread = manager.tasks.first { $0.title == "Buy bread" }!

        await #expect(throws: AgendaTaskManager.AgendaTaskError.duplicateTitle) {
            try await manager.renameTask(bread, to: "BUY MILK")
        }
        #expect(manager.tasks.count == 2)
    }

    // MARK: - Events

    @Test("createEvent duplicate title throws duplicateTitle + first event's data intact")
    func eventCreateDuplicateRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        var first = makeEvent(title: "Team standup")
        first.description = "PRECIOUS"
        try await manager.createEvent(first)

        await #expect(throws: AgendaEventManager.AgendaEventError.duplicateTitle) {
            try await manager.createEvent(makeEvent(title: "Team standup"))
        }

        let url = NexusPaths.eventFileURL(forTitle: "Team standup", in: nexus)
        let reloaded = try AgendaEvent.load(from: url)
        #expect(reloaded.id == first.id)
        #expect(reloaded.description == "PRECIOUS")
        #expect(manager.events.count == 1)
    }

    @Test("createEvent collision is case-insensitive (Team standup vs TEAM STANDUP)")
    func eventCreateCaseInsensitiveRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createEvent(makeEvent(title: "Team standup"))
        await #expect(throws: AgendaEventManager.AgendaEventError.duplicateTitle) {
            try await manager.createEvent(makeEvent(title: "TEAM STANDUP"))
        }
        #expect(manager.events.count == 1)
    }

    @Test("renameEvent onto an existing sibling's title throws + both files intact")
    func eventRenameOntoSiblingRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createEvent(makeEvent(title: "Team standup"))
        try await manager.createEvent(makeEvent(title: "Design review"))
        let review = manager.events.first { $0.title == "Design review" }!

        await #expect(throws: AgendaEventManager.AgendaEventError.duplicateTitle) {
            try await manager.renameEvent(review, to: "Team standup")
        }

        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.eventFileURL(forTitle: "Team standup", in: nexus).path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.eventFileURL(forTitle: "Design review", in: nexus).path))
        #expect(manager.events.count == 2)
    }

    @Test("renameEvent onto a sibling differing only in case still throws")
    func eventRenameOntoCaseVariantSiblingRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createEvent(makeEvent(title: "Team standup"))
        try await manager.createEvent(makeEvent(title: "Design review"))
        let review = manager.events.first { $0.title == "Design review" }!

        await #expect(throws: AgendaEventManager.AgendaEventError.duplicateTitle) {
            try await manager.renameEvent(review, to: "TEAM STANDUP")
        }
        #expect(manager.events.count == 2)
    }

    // MARK: - Builders (mirror AgendaTaskManagerTests / AgendaEventManagerTests)

    private func makeTask(id: String = ULID.generate(), title: String) -> AgendaTask {
        AgendaTask(
            id: id,
            title: title,
            icon: nil,
            description: "",
            dueAt: nil,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: false,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
    }

    private func makeEvent(
        id: String = ULID.generate(),
        title: String,
        startAt: Date = Date(timeIntervalSince1970: 1_716_480_000),
        endAt: Date = Date(timeIntervalSince1970: 1_716_483_600)
    ) -> AgendaEvent {
        AgendaEvent(
            id: id,
            title: title,
            icon: nil,
            description: "",
            startAt: startAt,
            endAt: endAt,
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: ["type": .select("Event")]
        )
    }
}
