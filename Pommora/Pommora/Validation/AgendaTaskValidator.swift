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

        // type property required + value must be one of schema's type-Select options
        guard case .select(let typeValue)? = properties["type"] else {
            throw ValidationError.missingTypeProperty
        }
        guard let typeProp = schema.properties.first(where: { $0.name == "type" }) else {
            throw ValidationError.missingTypeProperty
        }
        let allowed = Set((typeProp.options ?? []).map(\.value))
        guard allowed.contains(typeValue) else {
            throw ValidationError.unknownTypeValue(typeValue)
        }
    }
}
