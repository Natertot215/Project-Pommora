import SwiftUI

/// View Settings → Edit Properties → + New Property → type picker pane.
///
/// Wraps the existing `PropertyTypePicker` for pushed-pane mode + handles
/// the type-aware routing:
///   - Select / MultiSelect / Status → commit a default property of that type
///     AND push .editProperty(propertyID:) onto the path so the user lands in
///     the configuration editor immediately (these types need post-create
///     setup).
///   - Number / Checkbox / Date / DateTime / URL / File / Relation → commit a
///     default property of that type AND pop back to the Properties list.
///
/// Commits via PageTypeManager addProperty. Schema lives on the Type
/// (Collections inherit), so Collection-scope adds route to the parent
/// Type's manager.
///
/// The minted property ID is generated up-front via
/// `ReservedPropertyID.mintUserPropertyID()` so the route argument carries
/// a real ULID. Without this, struct-by-value semantics into `addProperty`
/// would discard the manager's internal mint and the caller would push
/// `.editProperty(propertyID: "")` — landing on a "Property not found"
/// dead-end.
struct PropertyTypePickerPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager

    @State private var selected: PropertyType?
    @State private var commitError: String?

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            PropertyTypePicker(selected: $selected) { type in
                commitError = nil
                Task { await commit(type) }
            }
            .padding(.horizontal, PUI.Spacing.xl)
            .padding(.vertical, PUI.Pane.contentPadding)
        } footer: {
            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Commit

    private func commit(_ type: PropertyType) async {
        var definition = makeDefaultDefinition(for: type)
        // Mint the property ID in the caller so the route argument carries
        // the real ULID. The manager would otherwise mint internally and
        // throw the value away (struct-by-value boundary).
        if definition.id.isEmpty {
            definition.id = ReservedPropertyID.mintUserPropertyID()
        }

        do {
            try await addProperty(definition)
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
            return
        }

        // Type-aware routing.
        if PropertyTypePickerPane.requiresOptionConfig(type) {
            // Replace .propertyTypePicker on the stack with .editProperty so
            // back-tap from the editor lands on Properties, not the type
            // picker we just left.
            if path.last == .propertyTypePicker {
                path.removeLast()
            }
            path.append(.editProperty(propertyID: definition.id))
        } else {
            // Pop back to Properties list. Drop the .propertyTypePicker frame
            // we're rendering inside.
            if path.last == .propertyTypePicker {
                path.removeLast()
            }
        }
    }

    private func addProperty(_ def: PropertyDefinition) async throws {
        switch scope {
        case .pageType(let t):
            try await pageTypeManager.addProperty(def, to: t.id)
        case .pageCollection(let c):
            try await pageTypeManager.addProperty(def, to: c.typeID)
        default:
            return  // non-storage scopes shouldn't reach this pane
        }
    }

    /// Types that ship empty configuration on creation and demand the user
    /// fill in options before the property is useful — auto-routes to
    /// `EditPropertyPane` in edit mode.
    static func requiresOptionConfig(_ type: PropertyType) -> Bool {
        switch type {
        case .select, .multiSelect, .status:
            return true
        default:
            return false
        }
    }

    /// Build a minimal-defaults PropertyDefinition for each user-creatable
    /// type. Caller (addProperty) mints the ID if empty.
    private func makeDefaultDefinition(for type: PropertyType) -> PropertyDefinition {
        let name = "New \(type.displayName)"
        switch type {
        case .number:
            return PropertyDefinition(id: "", name: name, type: .number, numberFormat: .decimal)
        case .checkbox:
            return PropertyDefinition(id: "", name: name, type: .checkbox)
        case .date:
            return PropertyDefinition(id: "", name: name, type: .date)
        case .datetime:
            return PropertyDefinition(id: "", name: name, type: .datetime)
        case .select:
            // Seed one default option so PropertyDefinitionValidator passes on
            // create (it throws .selectMissingOptions for an empty options
            // array). User customizes / removes the placeholder in
            // EditPropertyPane.
            return PropertyDefinition(
                id: "", name: name, type: .select,
                selectOptions: [
                    PropertyDefinition.SelectOption(value: "option_1", label: "Option 1", color: nil)
                ]
            )
        case .multiSelect:
            return PropertyDefinition(
                id: "", name: name, type: .multiSelect,
                selectOptions: [
                    PropertyDefinition.SelectOption(value: "option_1", label: "Option 1", color: nil)
                ]
            )
        case .status:
            return PropertyDefinition(
                id: "", name: name, type: .status,
                statusGroups: PropertyDefinition.StatusGroup.defaultSeed()
            )
        case .url:
            return PropertyDefinition(id: "", name: name, type: .url)
        case .file:
            return PropertyDefinition(id: "", name: name, type: .file)
        case .relation:
            // Kept only to satisfy the exhaustive switch over PropertyType
            // (KEEP-substrate: .relation case must not be removed).
            return PropertyDefinition(id: "", name: name, type: .relation)
        case .lastEditedTime:
            // Excluded from PropertyType.userCreatable — unreachable, but
            // the exhaustive switch requires a case.
            return PropertyDefinition(id: "", name: name, type: type)
        }
    }
}
