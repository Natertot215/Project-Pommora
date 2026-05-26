import Foundation

/// Tags which surface the View Settings popover is currently reflecting.
///
/// At v0.3.1.x chrome slice this enum is case-only — the placeholder popover
/// body doesn't read entity state. In v0.3.1 (first real pane) the cases
/// gain associated values carrying the concrete entity (PageType, PageCollection,
/// ItemType, ItemCollection, PageMeta, Space, Topic, Project). Adding associated
/// values is a source-compatible change for code that doesn't destructure the
/// cases (the only consumer at this slice is the placeholder popover, which
/// only checks `case .none`).
///
/// Mirrors `SidebarSelection`'s shape one-to-one with two adjustments:
///   - `.savedKey("calendar")` collapses to `.calendar` (saved-key strings
///     are an implementation detail of the sidebar; the popover speaks in
///     surface kinds).
///   - All other `.savedKey(_)` values (`"homepage"`, `"recents"`, unknown)
///     collapse to `.none` — they aren't view-settings surfaces.
enum ViewSettingsScope: Equatable, Sendable {
    case none
    case pageType
    case pageCollection
    case itemType
    case itemCollection
    case page
    case space
    case topic
    case project
    case calendar
}
