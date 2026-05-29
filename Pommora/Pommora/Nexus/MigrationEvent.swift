import Foundation

/// One per-property event surfaced in the adoption preview sheet during nexus
/// open. Aggregates into per-Type summaries for AdoptionPreviewView.
enum MigrationEvent: Sendable, Equatable {
    /// Legacy single `$rel` tagged object was wrapped into a one-element array.
    case relationShapeWrapped(propertyID: String, entityID: String)
    /// `allows_multiple` field stripped from a PropertyDefinition.
    case allowsMultipleStripped(propertyID: String, typeID: String)
    /// `page_collection` scope rewrote to `page_type` via the Collection-parent map.
    case pageCollectionRewritten(propertyID: String, from: String, to: String)
    /// `item_collection` scope rewrote to `item_type` via the Collection-parent map.
    case itemCollectionRewritten(propertyID: String, from: String, to: String)
    /// User-created PropertyDefinition with `target = .contextTier(N)` dropped from a Type schema.
    case contextTierDropped(propertyID: String, tier: Int, typeID: String)
    /// AgendaTaskSchema or AgendaEventSchema migrated from `Property` shape to `PropertyDefinition`.
    case agendaSchemaUnified(typeID: String, propertyCount: Int)
}
