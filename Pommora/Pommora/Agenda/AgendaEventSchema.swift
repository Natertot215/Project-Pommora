import Foundation

/// `_schema.json` for `<nexus>/Agenda/Events/`. Defines built-in `type` Select
/// property + user-defined additions + saved views.
///
/// Parallel to AgendaTaskSchema but carries NO Status — events have no
/// completion concept (EKEvent has no `isCompleted` field).
struct AgendaEventSchema: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var properties: [Property]
    var views: [SavedView]  // saved view configurations
    var modifiedAt: Date

    struct Property: Codable, Equatable, Hashable, Sendable {
        var name: String
        var type: PropertyType
        var options: [PropertyDefinition.SelectOption]?
        var builtin: Bool
        var defaultValue: String?

        enum CodingKeys: String, CodingKey {
            case name, type, options, builtin
            case defaultValue = "default"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, properties, views
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> AgendaEventSchema {
        AgendaEventSchema(
            schemaVersion: 1,
            icon: "calendar",
            properties: [
                Property(
                    name: "type",
                    type: .select,
                    options: [
                        PropertyDefinition.SelectOption(value: "Event", label: "Event", color: .green),
                        PropertyDefinition.SelectOption(value: "Meeting", label: "Meeting", color: .blue),
                        PropertyDefinition.SelectOption(value: "Appointment", label: "Appointment", color: .purple),
                    ],
                    builtin: true,
                    defaultValue: "Event"
                )
            ],
            views: [],
            modifiedAt: Date()
        )
    }
}
