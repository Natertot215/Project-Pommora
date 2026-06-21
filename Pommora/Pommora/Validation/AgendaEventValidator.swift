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
    ) throws(ValidationError) {
        _ = try FilenameSafety.validatedTitle(
            title,
            empty: ValidationError.emptyTitle,
            invalidCharacters: ValidationError.invalidTitleCharacters)

        // EKEvent-style time-field consistency: end_at must not precede start_at.
        if endAt < startAt { throw ValidationError.endBeforeStart }

        // _type Select validation: only enforce if the schema still carries _type.
        // As of Phase G.2 the default seed uses _status instead of _type; existing
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
