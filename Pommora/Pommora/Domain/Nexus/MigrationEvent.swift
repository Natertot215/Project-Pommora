import Foundation

/// One per-property event surfaced in the adoption preview sheet during nexus
/// open. Aggregates into per-Type summaries for AdoptionPreviewView.
enum MigrationEvent: Sendable, Equatable {
    /// Legacy single `$rel` tagged object was wrapped into a one-element array.
    case relationShapeWrapped(propertyID: String, entityID: String)
    /// `allows_multiple` field stripped from a PropertyDefinition.
    case allowsMultipleStripped(propertyID: String, collectionID: String)
    /// AgendaTaskSchema or AgendaEventSchema migrated from `Property` shape to `PropertyDefinition`.
    case agendaSchemaUnified(collectionID: String, propertyCount: Int)
}
