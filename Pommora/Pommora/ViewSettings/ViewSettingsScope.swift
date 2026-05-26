import Foundation

/// Tags which surface the View Settings popover is currently reflecting.
///
/// The four storage cases carry their concrete entity so the popover body
/// can render schema-aware content (Edit Properties pane reads the parent
/// Type's `properties: [PropertyDefinition]`; Property Visibility pane reads
/// `views[0].visibleProperties`; etc.). Other cases stay case-only — they
/// don't have a schema-bearing entity to populate from. Task 6 (v0.3.1)
/// gained the associated values; the chrome slice (v0.3.0.5) shipped this
/// as case-only.
///
/// Mirrors `SidebarSelection`'s shape one-to-one with two adjustments:
///   - `.savedKey("calendar")` collapses to `.calendar` (saved-key strings
///     are an implementation detail of the sidebar; the popover speaks in
///     surface kinds).
///   - All other `.savedKey(_)` values (`"homepage"`, `"recents"`, unknown)
///     collapse to `.none` — they aren't view-settings surfaces.
enum ViewSettingsScope: Equatable, Sendable {
    case none
    case pageType(PageType)
    case pageCollection(PageCollection)
    case itemType(ItemType)
    case itemCollection(ItemCollection)
    case page
    case space
    case topic
    case project
    case calendar
}
