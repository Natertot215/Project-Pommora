import Foundation

/// NavigationStack destinations for the View Settings popover's per-scope
/// menus. Hashable so SwiftUI's `NavigationStack(path:)` API can drive
/// push / pop via `[ViewSettingsRoute]` state.
///
/// The root menu (StorageMenuRoot) hosts buttons that append these routes
/// onto the path; each route resolves to a pushed pane via the popover's
/// `.navigationDestination(for:)`:
///   - `.editProperties` (PropertiesListPane)
///   - `.propertyTypePicker` (PropertyTypePickerPane)
///   - `.editProperty(propertyID:)` (EditPropertyPane)
///   - `.propertyVisibility` (PropertyVisibilityPane)
///
/// Option editing is NOT a route — the live editor is the inline
/// `OptionEditPopover` (double-click a chip). The former `.editOption` route
/// + its unwired `EditOptionPane` were removed 2026-05-27.
enum ViewSettingsRoute: Hashable {
    case editProperties
    case propertyTypePicker
    case editProperty(propertyID: String)
    case propertyVisibility
    case itemTemplate
}

extension ViewSettingsRoute {
    /// Human label for the pane this route resolves to. Used by `PaneHeader`
    /// to name the *previous* pane in the back affordance ("‹ Edit Properties").
    var paneTitle: String {
        switch self {
        case .editProperties: return "Edit Properties"
        case .propertyTypePicker: return "New Property"
        case .editProperty: return "Edit Property"
        case .propertyVisibility: return "Property Visibility"
        case .itemTemplate: return "Templates"
        }
    }
}
