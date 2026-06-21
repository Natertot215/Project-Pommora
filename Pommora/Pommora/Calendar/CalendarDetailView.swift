import SwiftUI

// MARK: - View Model

/// Extracted view-model for CalendarDetailView. Holds sorting + filtering logic so
/// tests can exercise behaviour without constructing SwiftUI views directly.
/// Reads from the injected managers; does NOT own them.
@MainActor
@Observable
final class CalendarDetailViewModel {

    private let taskManager: AgendaTaskManager
    private let eventManager: AgendaEventManager

    init(taskManager: AgendaTaskManager, eventManager: AgendaEventManager) {
        self.taskManager = taskManager
        self.eventManager = eventManager
    }

    /// Tasks sorted by dueAt ascending; tasks with nil dueAt sort last.
    var sortedTasks: [AgendaTask] {
        taskManager.tasks.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case (.some(let l), .some(let r)): return l < r
            case (.some, .none):               return true
            case (.none, .some):               return false
            case (.none, .none):               return false
            }
        }
    }

    /// Events sorted by startAt ascending.
    var sortedEvents: [AgendaEvent] {
        eventManager.events.sorted { $0.startAt < $1.startAt }
    }
}

// MARK: - Main View

/// Placeholder Calendar detail pane. No calendar grid yet.
/// Two-section list: Tasks (sorted by due date) above Events (sorted by start date).
@MainActor
struct CalendarDetailView: View {

    let taskManager: AgendaTaskManager
    let eventManager: AgendaEventManager

    var body: some View {
        CalendarDetailContent(
            taskManager: taskManager,
            eventManager: eventManager
        )
    }
}

// MARK: - Content (private sub-view, avoids GRDB String overload pollution)

@MainActor
private struct CalendarDetailContent: View {

    let taskManager: AgendaTaskManager
    let eventManager: AgendaEventManager

    @State private var viewModel: CalendarDetailViewModel

    init(taskManager: AgendaTaskManager, eventManager: AgendaEventManager) {
        self.taskManager = taskManager
        self.eventManager = eventManager
        _viewModel = State(
            initialValue: CalendarDetailViewModel(
                taskManager: taskManager,
                eventManager: eventManager
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Calendar")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            List {
                // MARK: Tasks section
                Section {
                    if viewModel.sortedTasks.isEmpty {
                        Text("No tasks")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    } else {
                        ForEach(viewModel.sortedTasks) { task in
                            TaskRow(task: task)
                        }
                    }
                } header: {
                    Text("Tasks")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                // MARK: Events section
                Section {
                    if viewModel.sortedEvents.isEmpty {
                        Text("No events")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    } else {
                        ForEach(viewModel.sortedEvents) { event in
                            EventRow(event: event)
                        }
                    }
                } header: {
                    Text("Events")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Task Row

private struct TaskRow: View {

    let task: AgendaTask

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            // Status pill: filled capsule — green for done, gray for everything else.
            Capsule()
                .fill(task.completed ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityLabel(task.completed ? "Done" : "Not done")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)

                if let due = task.dueAt {
                    Text(Self.dateFormatter.string(from: due))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Event Row

private struct EventRow: View {

    let event: AgendaEvent

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.body)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Text(Self.dateFormatter.string(from: event.startAt))
                Text("→")
                Text(Self.dateFormatter.string(from: event.endAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
