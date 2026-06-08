import Foundation

/// Resolves the effective template for an Item: Collection override → Type
/// default (LD-10). Pure; callers pass the resolved Type + optional Collection.
enum TemplateResolver {
    static func effective(type: ItemType, collection: ItemCollection?) -> ItemTemplateConfig {
        collection?.templateConfig ?? type.templateConfig ?? ItemTemplateConfig()
    }
    // (No standalone `layout()` wrapper — callers read `effective(...).layout ?? .standard` inline.)
    /// Promoted set, migrating a legacy `ItemCollection.pinnedProperties` ([String])
    /// when the template carries none yet (display defaults to nil → archetype default).
    static func promoted(type: ItemType, collection: ItemCollection?) -> [PromotedProperty] {
        if let explicit = effective(type: type, collection: collection).promotedProperties { return explicit }
        return (collection?.pinnedProperties ?? []).map { PromotedProperty(id: $0, display: nil) }
    }

    /// Promoted entries paired with their definitions, in the renderer's partition
    /// order, dropping any promoted id with no matching definition. One source for
    /// both the live renderer (promotedSchema) and the template pane (promotedEntries).
    ///
    /// Reproduces `ItemWindowRenderer.partition(...).main`: promoted order, real
    /// ids only (a promoted id absent from `type.properties` is dropped, never
    /// crashed). Each surviving id joins to its `PropertyDefinition` from
    /// `type.properties`. Pure value code — both call sites consume the array.
    static func promotedEntries(
        type: ItemType, collection: ItemCollection?
    ) -> [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        let promoted = self.promoted(type: type, collection: collection)
        let definitionByID = Dictionary(
            type.properties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return promoted.compactMap { promotion in
            guard let definition = definitionByID[promotion.id] else { return nil }
            return (promotion, definition)
        }
    }

    /// The chip-eligible subset of `promotedEntries` — promoted properties whose
    /// type is in `ItemWindowZoneConfig.v1Checkable` (`.select` / `.multiSelect`),
    /// in the same partition order. Additive over `promotedEntries` (never
    /// modifies it): the Item Window's segmented property bar + inspector consume
    /// this to keep only V1-checkable pinned properties.
    static func promotedForField(
        type: ItemType, collection: ItemCollection?
    ) -> [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        promotedEntries(type: type, collection: collection)
            .filter { ItemWindowZoneConfig.v1Checkable.contains($0.definition.type) }
    }
}
