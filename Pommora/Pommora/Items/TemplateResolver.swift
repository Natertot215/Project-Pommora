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
}
