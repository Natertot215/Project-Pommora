import Foundation

/// Maps a property-editor commit error to a user-facing sentence.
///
/// Replaces the raw `String(describing: error)` pattern that surfaced enum
/// case names like `"duplicateName"` / `"typeNotFound"` / `"propertyNotFound"`
/// in the popover error banner. Shared across PropertyTypePickerPane,
/// EditPropertyPane, EditOptionPane so every commit surface speaks the same
/// language.
///
/// Unknown error types fall through to the localised description so we never
/// render a totally empty string — but the goal is to map every error the
/// PageCollection manager actually throws so the fallback rarely fires.
enum PropertyEditorErrorMessage {
    nonisolated static func string(for error: any Error) -> String {
        if let v = error as? PropertyDefinitionValidator.ValidationError {
            return string(for: v)
        }
        if let p = error as? PageCollectionManagerError {
            return string(for: p)
        }
        return error.localizedDescription
    }

    nonisolated private static func string(for error: PropertyDefinitionValidator.ValidationError) -> String {
        switch error {
        case .emptyName:
            return "Property name can't be empty."
        case .reservedID:
            return "That property ID is reserved."
        case .duplicateID:
            return "A property with that ID already exists."
        case .duplicateName:
            return "A property with that name already exists."
        case .selectMissingOptions:
            return "Select properties need at least one option."
        case .duplicateSelectOptionValue:
            return "Two options share the same value."
        }
    }

    nonisolated private static func string(for error: PageCollectionManagerError) -> String {
        switch error {
        case .typeNotFound:
            return "The Vault for this property was just removed."
        case .propertyNotFound:
            return "This property was just removed."
        case .lossyChangeRequiresConfirmation:
            return "Changing this type drops existing values — confirm first."
        case .indexOutOfBounds:
            return "Couldn't move the property to that position."
        case .cannotDeleteLastView:
            return "A container must keep at least one view."
        }
    }
}
