import Foundation

/// Agenda Event — EKEvent-aligned. Lives at
/// `<nexus>/Events/<title>.event.json` (Events singleton folder is renameable
/// per Settings). Has required `start_at` + `end_at`, location, all-day flag.
/// NO completion concept.
///
/// Swift name prefixed (`AgendaEvent`) per the ParadigmV2 "no Pommora.X
/// qualification" rule, paralleling `AgendaTask`. UI label: "Event" (renameable).
struct AgendaEvent: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String  // derived from filename on load
    var icon: String?
    var description: String

    // EKEvent fields — both startAt + endAt REQUIRED.
    var startAt: Date
    var endAt: Date
    var allDay: Bool
    var location: String?
    var recurrence: Recurrence?
    var alarmOffsets: [TimeInterval]  // negative = before; matches EKAlarm.relativeOffset
    var alarmAbsolute: [Date]

    // EventKit sync state (populated only when mirrored)
    var calendarID: String?
    var eventkitUUID: String?

    // Shared
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var createdAt: Date
    var modifiedAt: Date
    var properties: [String: PropertyValue]  // includes the built-in `_status` (Status)

    enum CodingKeys: String, CodingKey {
        case id, icon, description, location, recurrence
        case tier1, tier2, tier3, properties
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case alarmOffsets = "alarm_offsets"
        case alarmAbsolute = "alarm_absolute"
        case calendarID = "calendar_id"
        case eventkitUUID = "eventkit_uuid"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?,
        description: String,
        startAt: Date, endAt: Date, allDay: Bool,
        location: String?, recurrence: Recurrence?,
        alarmOffsets: [TimeInterval], alarmAbsolute: [Date],
        calendarID: String?, eventkitUUID: String?,
        tier1: [String], tier2: [String], tier3: [String],
        createdAt: Date, modifiedAt: Date,
        properties: [String: PropertyValue]
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.location = location
        self.recurrence = recurrence
        self.alarmOffsets = alarmOffsets
        self.alarmAbsolute = alarmAbsolute
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
        self.startAt = try c.decode(Date.self, forKey: .startAt)
        self.endAt = try c.decode(Date.self, forKey: .endAt)
        self.allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.alarmOffsets = try c.decodeIfPresent([TimeInterval].self, forKey: .alarmOffsets) ?? []
        self.alarmAbsolute = try c.decodeIfPresent([Date].self, forKey: .alarmAbsolute) ?? []
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
        try c.encode(startAt, forKey: .startAt)
        try c.encode(endAt, forKey: .endAt)
        try c.encode(allDay, forKey: .allDay)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encode(alarmOffsets, forKey: .alarmOffsets)
        try c.encode(alarmAbsolute, forKey: .alarmAbsolute)
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

extension AgendaEvent {
    static func load(from url: URL) throws -> AgendaEvent {
        var e = try AtomicJSON.decode(AgendaEvent.self, from: url)
        let filename = url.lastPathComponent
        if filename.hasSuffix(".event.json") {
            e.title = String(filename.dropLast(".event.json".count))
        } else {
            e.title = url.deletingPathExtension().lastPathComponent
        }
        return e
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}

extension AgendaEvent {
    /// Canonical READ for any relation-typed property, including the three built-in
    /// tier properties whose values live at the event root.
    func relationIDs(forPropertyID id: String) -> [String] {
        switch id {
        case ReservedPropertyID.tier1: return tier1
        case ReservedPropertyID.tier2: return tier2
        case ReservedPropertyID.tier3: return tier3
        default:
            if case .relation(let ids)? = properties[id] { return ids }
            return []
        }
    }

    /// Canonical WRITE. Tier IDs route to the root field; user relations route to
    /// `properties`. An empty user-relation value OMITS the key (no empty array on
    /// disk) so the schema-blind decoder never sees an ambiguous `[]`.
    mutating func setRelationIDs(_ ids: [String], forPropertyID id: String) {
        switch id {
        case ReservedPropertyID.tier1: tier1 = ids
        case ReservedPropertyID.tier2: tier2 = ids
        case ReservedPropertyID.tier3: tier3 = ids
        default: properties[id] = ids.isEmpty ? nil : .relation(ids)
        }
    }
}
