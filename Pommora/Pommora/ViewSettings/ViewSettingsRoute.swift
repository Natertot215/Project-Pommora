import Foundation

/// NavigationStack destinations for the View Settings popover's per-scope
/// menus. Hashable so SwiftUI's `NavigationStack(path:)` API can drive
/// push / pop via `[ViewSettingsRoute]` state.
///
/// The root menu (StorageMenuRoot at Task 7) hosts buttons that append
/// these routes onto the path; each route resolves to a pushed pane via
/// the popover's `.navigationDestination(for:)`. v0.3.1 ships:
///   - `.editProperties` (PropertiesListPane — Task 9)
///   - `.propertyTypePicker` (PropertyTypePickerPane — Task 10)
///   - `.editProperty(propertyID:)` (EditPropertyPane — Task 11)
///   - `.editOption(propertyID:optionValue:)` (EditOptionPane — Task 11b)
///   - `.propertyVisibility` (PropertyVisibilityPane — Task 12)
///
/// At Task 7 scaffold these are wired to placeholder destinations; later
/// tasks replace them in-place per quirk #8.
enum ViewSettingsRoute: Hashable {
    case editProperties
    case propertyTypePicker
    case editProperty(propertyID: String)
    case editOption(propertyID: String, optionValue: String)
    case propertyVisibility
}
