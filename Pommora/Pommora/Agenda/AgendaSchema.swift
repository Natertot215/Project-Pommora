import Foundation

/// `_agenda.json` schema sidecar. Defines the built-in `type` Select property
/// plus any user-defined properties + saved views.
struct AgendaSchema: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var properties: [Property]
    var views: [VaultView]  // reuse Vault's placeholder
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

    static func defaultSeed() -> AgendaSchema {
        AgendaSchema(
            schemaVersion: 1,
            icon: "calendar",
            properties: [
                Property(
                    name: "type",
                    type: .select,
                    options: [
                        PropertyDefinition.SelectOption(value: "Task", label: "Task", color: .blue),
                        PropertyDefinition.SelectOption(value: "To-Do", label: "To-Do", color: .yellow),
                        PropertyDefinition.SelectOption(value: "Phase", label: "Phase", color: .purple),
                        PropertyDefinition.SelectOption(value: "Event", label: "Event", color: .green),
                    ],
                    builtin: true,
                    defaultValue: "Task"
                )
            ],
            views: [],
            modifiedAt: Date()
        )
    }
}
