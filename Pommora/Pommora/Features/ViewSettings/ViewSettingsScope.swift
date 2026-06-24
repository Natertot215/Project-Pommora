import Foundation

/// Tags which surface the View Settings popover is currently reflecting.
///
/// The storage cases carry their concrete entity so the popover body
/// can render schema-aware content (Edit Properties pane reads the parent
/// Type's `properties: [PropertyDefinition]`; the Layout pane's visibility
/// list reads `views[0].propertyOrder`; etc.). Other cases stay case-only — they
/// don't have a schema-bearing entity to populate from.
///
/// Mirrors `SidebarSelection`'s shape one-to-one with two adjustments:
///   - `.savedKey("calendar")` collapses to `.calendar` (saved-key strings
///     are an implementation detail of the sidebar; the popover speaks in
///     surface kinds).
///   - All other `.savedKey(_)` values (`"homepage"`, `"recents"`, unknown)
///     collapse to `.none` — they aren't view-settings surfaces.
enum ViewSettingsScope: Equatable, Sendable {
    case none
    case pageCollection(PageCollection)
    case pageSet(PageSet)
    case page
    case area
    case topic
    case project
    case calendar
}

extension ViewSettingsScope {
    /// The container whose SavedView config this scope edits — the entity's own id.
    /// `nil` for non-container scopes.
    var containerID: String? {
        switch self {
        case .pageCollection(let t): return t.id
        case .pageSet(let c): return c.id
        default: return nil
        }
    }

    /// The schema-owning PageCollection's id — the top PageCollection owns the
    /// schema; nested PageSets inherit it via `parentID`. `nil` for non-container scopes.
    var schemaTypeID: String? {
        switch self {
        case .pageCollection(let t): return t.id
        case .pageSet(let c): return c.parentID
        default: return nil
        }
    }
}
