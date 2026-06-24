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
    case pageType(PageType)
    case pageCollection(PageSet)
    case page
    case area
    case topic
    case project
    case calendar
}

extension ViewSettingsScope {
    /// The container whose SavedView config this scope edits — the entity's own
    /// id (Vault or Collection). `nil` for non-container scopes. One source for
    /// the per-pane `containerID()` switch the View Settings panes used to repeat.
    var containerID: String? {
        switch self {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }

    /// The schema-owning Type's id — a Vault owns its schema; a Collection
    /// inherits its parent Vault's (`typeID`). `nil` for non-container scopes.
    /// One source for the per-pane `parentTypeID()` / `scopeTypeID()` switch.
    var schemaTypeID: String? {
        switch self {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.parentID
        default: return nil
        }
    }
}
