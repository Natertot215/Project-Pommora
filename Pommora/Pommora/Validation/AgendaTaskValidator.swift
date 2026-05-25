import Foundation

/// Validates AgendaTask CRUD inputs (title shape + EKReminder-style time-field
/// consistency + built-in `type` property). Parallel to AgendaEventValidator on
/// the Events side.
enum AgendaTaskValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case dueAllDayWithoutDue
        case missingTypeProperty
        case unknownTypeValue(String)
    }

    static func validate(
        title: String,
        dueAt: Date?,
        dueAllDay: Bool,
        properties: [String: PropertyValue],
        schema: AgendaTaskSchema
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // EKReminder-style time-field consistency: due_all_day requires due_at.
        if dueAllDay && dueAt == nil { throw ValidationError.dueAllDayWithoutDue }

        // _type Select validation: only enforce if the schema still carries _type.
        // As of Phase G.1 the default seed uses _status instead of _type; existing
        // schemas that retain _type still get validated. Skip entirely when absent.
        if let typeProp = schema.properties.first(where: { $0.id == "_type" }) {
            guard case .select(let typeValue)? = properties["type"] else {
                throw ValidationError.missingTypeProperty
            }
            let allowed = Set((typeProp.selectOptions ?? []).map(\.value))
            guard allowed.contains(typeValue) else {
                throw ValidationError.unknownTypeValue(typeValue)
            }
        }
    }
}
