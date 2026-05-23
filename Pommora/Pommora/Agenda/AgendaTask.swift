import Foundation

/// Agenda Task — EKReminder-aligned. Lives at `<nexus>/Agenda/Tasks/<title>.task.json`.
/// Has due date (optional), completion flag, priority, optional start ("not before") date.
///
/// Swift name prefixed (`AgendaTask`) to avoid `_Concurrency.Task` shadow per
/// the ParadigmV2 "no Pommora.X qualification" rule. UI label: "Task" (renameable).
struct AgendaTask: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String  // derived from filename on load
    var icon: String?
    var description: String

    // EKReminder fields
    var dueAt: Date?
    var dueFloating: Bool  // true = nil timezone
    var dueAllDay: Bool  // true = strip hour/minute/second
    var startAt: Date?  // EKReminder "not before"
    var completed: Bool
    var completedAt: Date?
    var priority: Int  // 0–9, mirrors EKReminder.priority

    var recurrence: Recurrence?
    var alarmOffsets: [TimeInterval]  // negative = before; matches EKAlarm.relativeOffset

    // EventKit sync state (populated only when mirrored)
    var calendarID: String?
    var eventkitUUID: String?

    // Shared
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var createdAt: Date
    var modifiedAt: Date
    var properties: [String: PropertyValue]  // includes built-in `type` Select + Status (post-Phase 9.2)

    enum CodingKeys: String, CodingKey {
        case id, icon, description, completed, priority, recurrence
        case tier1, tier2, tier3, properties
        case dueAt = "due_at"
        case dueFloating = "due_floating"
        case dueAllDay = "due_all_day"
        case startAt = "start_at"
        case completedAt = "completed_at"
        case alarmOffsets = "alarm_offsets"
        case calendarID = "calendar_id"
        case eventkitUUID = "eventkit_uuid"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?,
        description: String,
        dueAt: Date?, dueFloating: Bool, dueAllDay: Bool,
        startAt: Date?,
        completed: Bool, completedAt: Date?,
        priority: Int,
        recurrence: Recurrence?,
        alarmOffsets: [TimeInterval],
        calendarID: String?, eventkitUUID: String?,
        tier1: [String], tier2: [String], tier3: [String],
        createdAt: Date, modifiedAt: Date,
        properties: [String: PropertyValue]
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.description = description
        self.dueAt = dueAt
        self.dueFloating = dueFloating
        self.dueAllDay = dueAllDay
        self.startAt = startAt
        self.completed = completed
        self.completedAt = completedAt
        self.priority = priority
        self.recurrence = recurrence
        self.alarmOffsets = alarmOffsets
        self.calendarID = calendarID
        self.eventkitUUID = eventkitUUID
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.properties = properties
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        self.dueFloating = try c.decodeIfPresent(Bool.self, forKey: .dueFloating) ?? false
        self.dueAllDay = try c.decodeIfPresent(Bool.self, forKey: .dueAllDay) ?? false
        self.startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        self.completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.alarmOffsets = try c.decodeIfPresent([TimeInterval].self, forKey: .alarmOffsets) ?? []
        self.calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
        self.eventkitUUID = try c.decodeIfPresent(String.self, forKey: .eventkitUUID)
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(dueAt, forKey: .dueAt)
        try c.encode(dueFloating, forKey: .dueFloating)
        try c.encode(dueAllDay, forKey: .dueAllDay)
        try c.encodeIfPresent(startAt, forKey: .startAt)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encode(alarmOffsets, forKey: .alarmOffsets)
        try c.encodeIfPresent(calendarID, forKey: .calendarID)
        try c.encodeIfPresent(eventkitUUID, forKey: .eventkitUUID)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(properties, forKey: .properties)
    }
}

extension AgendaTask {
    static func load(from url: URL) throws -> AgendaTask {
        var t = try AtomicJSON.decode(AgendaTask.self, from: url)
        let filename = url.lastPathComponent
        if filename.hasSuffix(".task.json") {
            t.title = String(filename.dropLast(".task.json".count))
        } else {
            t.title = url.deletingPathExtension().lastPathComponent
        }
        return t
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
