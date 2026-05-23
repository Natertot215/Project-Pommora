import Foundation

/// `_schema.json` for `<nexus>/Agenda/Tasks/`. Defines built-in `type` Select
/// property + user-defined additions + saved views.
///
/// Status property seeding deferred to Phase 9.2 (v0.3.0 reconciliation) once
/// PropertyDefinition.StatusGroup exists.
struct AgendaTaskSchema: Codable, Equatable, Hashable, Sendable {
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

    static func defaultSeed() -> AgendaTaskSchema {
        AgendaTaskSchema(
            schemaVersion: 1,
            icon: "checkmark.circle",
            properties: [
                Property(
                    name: "type",
                    type: .select,
                    options: [
                        PropertyDefinition.SelectOption(value: "Task", label: "Task", color: .blue),
                        PropertyDefinition.SelectOption(value: "To-Do", label: "To-Do", color: .yellow),
                        PropertyDefinition.SelectOption(value: "Phase", label: "Phase", color: .purple),
                    ],
                    builtin: true,
                    defaultValue: "Task"
                )
                // Status seeding deferred to Phase 9.2 (v0.3.0 reconciliation)
            ],
            views: [],
            modifiedAt: Date()
        )
    }
}
