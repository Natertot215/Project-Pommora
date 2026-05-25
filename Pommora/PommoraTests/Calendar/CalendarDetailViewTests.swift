import Foundation
import Testing

@testable import Pommora

// MARK: - CalendarDetailViewTests
//
// Tests exercise CalendarDetailViewModel directly (pure logic layer).
// All tests are @MainActor because both managers + the view-model are @MainActor.

@MainActor
@Suite("CalendarDetailView")
struct CalendarDetailViewTests {

    // MARK: - Helpers

    private func makeManagers() async throws -> (AgendaTaskManager, AgendaEventManager) {
        let nexus = try TempNexus.make()
        let taskManager = AgendaTaskManager(nexus: nexus)
        let eventManager = AgendaEventManager(nexus: nexus)
        await taskManager.loadAll()
        await eventManager.loadAll()
        return (taskManager, eventManager)
    }

    private func makeTask(
        title: String,
        dueAt: Date? = nil,
        completed: Bool = false
    ) -> AgendaTask {
        AgendaTask(
            id: ULID.generate(),
            title: title,
            icon: nil,
            description: "",
            dueAt: dueAt,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: completed,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        )
    }

    private func makeEvent(
        title: String,
        startAt: Date,
        endAt: Date? = nil
    ) -> AgendaEvent {
        AgendaEvent(
            id: ULID.generate(),
            title: title,
            icon: nil,
            description: "",
            startAt: startAt,
            endAt: endAt ?? startAt.addingTimeInterval(3600),
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        )
    }

    // MARK: - Empty state

    @Test("Empty managers produce empty sorted arrays")
    func emptyManagersProduceEmptySortedArrays() async throws {
        let (taskManager, eventManager) = try await makeManagers()
        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        #expect(vm.sortedTasks.isEmpty)
        #expect(vm.sortedEvents.isEmpty)
    }

    // MARK: - Task count

    @Test("Three tasks appear in sortedTasks")
    func threeTasksProduceThreeRows() async throws {
        let (taskManager, eventManager) = try await makeManagers()

        let t1 = makeTask(title: "Alpha")
        let t2 = makeTask(title: "Beta")
        let t3 = makeTask(title: "Gamma")

        try await taskManager.createTask(t1)
        try await taskManager.createTask(t2)
        try await taskManager.createTask(t3)

        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        #expect(vm.sortedTasks.count == 3)
    }

    // MARK: - Task sort order (due_at ascending, nil last)

    @Test("Tasks sort by dueAt ascending with nil dates last")
    func tasksSortByDueAtAscendingNilLast() async throws {
        let (taskManager, eventManager) = try await makeManagers()

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let early = makeTask(title: "Early",  dueAt: base)
        let mid   = makeTask(title: "Middle", dueAt: base.addingTimeInterval(3600))
        let late  = makeTask(title: "Late",   dueAt: base.addingTimeInterval(7200))
        let nilDue = makeTask(title: "NilDue", dueAt: nil)

        // Insert in non-sorted order to ensure the view-model does the sorting.
        try await taskManager.createTask(nilDue)
        try await taskManager.createTask(late)
        try await taskManager.createTask(early)
        try await taskManager.createTask(mid)

        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        let sorted = vm.sortedTasks
        #expect(sorted.count == 4)
        #expect(sorted[0].title == "Early")
        #expect(sorted[1].title == "Middle")
        #expect(sorted[2].title == "Late")
        #expect(sorted[3].title == "NilDue")
    }

    // MARK: - Event sort order

    @Test("Events sort by startAt ascending")
    func eventsSortByStartAtAscending() async throws {
        let (taskManager, eventManager) = try await makeManagers()

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let first  = makeEvent(title: "First",  startAt: base)
        let second = makeEvent(title: "Second", startAt: base.addingTimeInterval(3600))
        let third  = makeEvent(title: "Third",  startAt: base.addingTimeInterval(7200))

        // Insert out-of-order.
        try await eventManager.createEvent(third)
        try await eventManager.createEvent(first)
        try await eventManager.createEvent(second)

        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        let sorted = vm.sortedEvents
        #expect(sorted.count == 3)
        #expect(sorted[0].title == "First")
        #expect(sorted[1].title == "Second")
        #expect(sorted[2].title == "Third")
    }

    // MARK: - Mixed nil + non-nil dueAt

    @Test("Tasks with mixed nil and non-nil dueAt sort correctly")
    func mixedNilAndNonNilDueAt() async throws {
        let (taskManager, eventManager) = try await makeManagers()

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let withDate1 = makeTask(title: "WithDate1", dueAt: base)
        let noDate    = makeTask(title: "NoDate",    dueAt: nil)
        let withDate2 = makeTask(title: "WithDate2", dueAt: base.addingTimeInterval(1800))

        try await taskManager.createTask(noDate)
        try await taskManager.createTask(withDate2)
        try await taskManager.createTask(withDate1)

        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        let sorted = vm.sortedTasks
        #expect(sorted.count == 3)
        // Both nil-dueAt tasks go last; dated tasks are ordered ascending.
        #expect(sorted[0].title == "WithDate1")
        #expect(sorted[1].title == "WithDate2")
        #expect(sorted[2].title == "NoDate")
    }

    // MARK: - Done task visual signal

    @Test("Completed task has completed flag set (drives strikethrough + status pill)")
    func completedTaskHasCompletedFlag() async throws {
        let (taskManager, eventManager) = try await makeManagers()

        let doneTask = makeTask(title: "Done task", completed: true)
        let pendingTask = makeTask(title: "Pending task", completed: false)

        try await taskManager.createTask(doneTask)
        try await taskManager.createTask(pendingTask)

        let vm = CalendarDetailViewModel(
            taskManager: taskManager,
            eventManager: eventManager
        )

        // Both tasks present; verify completed flag is preserved through sorting.
        let doneSorted = vm.sortedTasks.first { $0.title == "Done task" }
        let pendingSorted = vm.sortedTasks.first { $0.title == "Pending task" }

        #expect(doneSorted != nil)
        #expect(pendingSorted != nil)
        #expect(doneSorted?.completed == true,  "done task must expose .completed = true")
        #expect(pendingSorted?.completed == false, "pending task must expose .completed = false")
    }
}
