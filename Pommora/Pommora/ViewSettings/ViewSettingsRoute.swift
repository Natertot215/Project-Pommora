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
///   - `.editProperty(propertyID:)` (EditPropertyPane — edit-existing mode)
///   - `.newRelation` (EditPropertyPane — relation create-draft mode)
///   - `.propertyVisibility` (PropertyVisibilityPane)
///
/// `.newRelation` carries no propertyID: the property doesn't exist yet. The
/// pane holds a draft and only commits (via the source manager's paired
/// `addProperty`) when the user taps Save. Picking `.relation` in the type
/// picker routes here instead of pre-adding a shell.
///
/// Option editing is NOT a route — the live editor is the inline
/// `OptionEditPopover` (double-click a chip). The former `.editOption` route
/// + its unwired `EditOptionPane` were removed 2026-05-27.
enum ViewSettingsRoute: Hashable {
    case editProperties
    case propertyTypePicker
    case editProperty(propertyID: String)
    case newRelation
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
        case .newRelation: return "New Relation"
        case .propertyVisibility: return "Property Visibility"
        case .itemTemplate: return "Templates"
        }
    }
}
