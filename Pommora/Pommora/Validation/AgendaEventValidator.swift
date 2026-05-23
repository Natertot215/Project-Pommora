import Foundation

/// Validates AgendaEvent CRUD inputs (title shape + EKEvent-style time-field
/// consistency + built-in `type` property). Parallel to AgendaTaskValidator on
/// the Tasks side; events REQUIRE both `start_at` + `end_at` and enforce
/// `end >= start`.
enum AgendaEventValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case endBeforeStart
        case missingTypeProperty
        case unknownTypeValue(String)
    }

    static func validate(
        title: String,
        startAt: Date,
        endAt: Date,
        properties: [String: PropertyValue],
        schema: AgendaEventSchema
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // EKEvent-style time-field consistency: end_at must not precede start_at.
        if endAt < startAt { throw ValidationError.endBeforeStart }

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
