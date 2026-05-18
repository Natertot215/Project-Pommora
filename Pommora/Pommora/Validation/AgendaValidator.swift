import Foundation

enum AgendaValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case missingEndAt
        case endBeforeStart
        case allDayWithoutStart
        case dueAllDayWithoutDue
        case missingTypeProperty
        case unknownTypeValue(String)
    }

    static func validate(
        title: String,
        startAt: Date?,
        endAt: Date?,
        allDay: Bool,
        dueAt: Date?,
        dueAllDay: Bool,
        properties: [String: PropertyValue],
        schema: AgendaSchema
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // Time-field consistency
        if startAt != nil && endAt == nil { throw ValidationError.missingEndAt }
        if let s = startAt, let e = endAt, e < s { throw ValidationError.endBeforeStart }
        if allDay && startAt == nil { throw ValidationError.allDayWithoutStart }
        if dueAllDay && dueAt == nil { throw ValidationError.dueAllDayWithoutDue }

        // type property required + value must be one of schema's type-Select options
        guard case let .select(typeValue)? = properties["type"] else {
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
