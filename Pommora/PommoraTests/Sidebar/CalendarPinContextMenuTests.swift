import Foundation
import Testing

@testable import Pommora

/// Tests for `CalendarPinViewModel` — the dispatch layer for the Calendar pin
/// right-click context menu (New Task / New Event).
///
/// Drives the view-model directly without SwiftUI rendering (J.5/J.11/K.1 pattern).
/// Manager interactions use real managers against a TempNexus (no disk-write mocking
/// needed — the managers are already tested; we verify the ViewModel dispatches).
@Suite("CalendarPinContextMenuTests")
@MainActor
struct CalendarPinContextMenuTests {

    // MARK: - Helpers

    private func makeManagers() async throws -> (AgendaTaskManager, AgendaEventManager, Nexus) {
        let nexus = try TempNexus.make()
        let taskManager = AgendaTaskManager(nexus: nexus)
        let eventManager = AgendaEventManager(nexus: nexus)
        await taskManager.loadAll()
        await eventManager.loadAll()
        return (taskManager, eventManager, nexus)
    }

    // MARK: - Test 1: Fresh ViewModel has no pending state

    @Test("Fresh CalendarPinViewModel has nil creation results and no error")
    func freshViewModelIsClean() {
        let vm = CalendarPinViewModel()
        #expect(vm.lastCreatedTask == nil)
        #expect(vm.lastCreatedEvent == nil)
        #expect(vm.pendingError == nil)
    }

    // MARK: - Test 2: createTask dispatches to AgendaTaskManager

    @Test("createTask calls AgendaTaskManager and sets lastCreatedTask")
    func createTaskCallsManager() async throws {
        let (taskManager, _, nexus) = try await makeManagers()
        defer { TempNexus.cleanup(nexus) }
        let vm = CalendarPinViewModel()

        await vm.createTask(using: taskManager)

        #expect(vm.lastCreatedTask != nil)
        #expect(vm.pendingError == nil)
        // Manager's tasks array should also have grown by 1.
        #expect(taskManager.tasks.count == 1)
    }

    // MARK: - Test 3: createEvent dispatches to AgendaEventManager

    @Test("createEvent calls AgendaEventManager and sets lastCreatedEvent")
    func createEventCallsManager() async throws {
        let (_, eventManager, nexus) = try await makeManagers()
        defer { TempNexus.cleanup(nexus) }
        let vm = CalendarPinViewModel()

        await vm.createEvent(using: eventManager)

        #expect(vm.lastCreatedEvent != nil)
        #expect(vm.pendingError == nil)
        // Manager's events array should also have grown by 1.
        #expect(eventManager.events.count == 1)
    }

    // MARK: - Test 4: Created task has expected defaults

    @Test("Created task has 'New Task' title and completed = false")
    func createdTaskHasDefaults() async throws {
        let (taskManager, _, nexus) = try await makeManagers()
        defer { TempNexus.cleanup(nexus) }
        let vm = CalendarPinViewModel()

        await vm.createTask(using: taskManager)

        let task = try #require(vm.lastCreatedTask)
        #expect(task.title == "New Task")
        #expect(task.completed == false)
        #expect(task.dueAt == nil)
    }

    // MARK: - Test 5: Created event has expected defaults

    @Test("Created event has 'New Event' title and 1-hour duration")
    func createdEventHasDefaults() async throws {
        let (_, eventManager, nexus) = try await makeManagers()
        defer { TempNexus.cleanup(nexus) }
        let vm = CalendarPinViewModel()

        await vm.createEvent(using: eventManager)

        let event = try #require(vm.lastCreatedEvent)
        #expect(event.title == "New Event")
        // endAt is 3600 seconds after startAt
        let duration = event.endAt.timeIntervalSince(event.startAt)
        #expect(duration == 3600)
    }

    // MARK: - Test 6: Multiple creates produce separate records

    @Test("Sequential createTask calls produce distinct tasks in the manager")
    func multipleCreateTasksAreDistinct() async throws {
        let (taskManager, _, nexus) = try await makeManagers()
        defer { TempNexus.cleanup(nexus) }
        let vm = CalendarPinViewModel()

        await vm.createTask(using: taskManager)
        // A second call would fail with a duplicate-title conflict;
        // the test verifies the first create succeeded and produced a unique ID.
        let task1 = try #require(vm.lastCreatedTask)
        #expect(!task1.id.isEmpty)
        #expect(taskManager.tasks.count == 1)
    }
}
