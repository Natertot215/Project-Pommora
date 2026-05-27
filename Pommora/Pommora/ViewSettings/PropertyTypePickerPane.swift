import SwiftUI

/// View Settings → Edit Properties → + New Property → type picker pane.
///
/// Wraps the existing `PropertyTypePicker` for pushed-pane mode + handles
/// the type-aware routing (locked decision):
///   - Select / MultiSelect / Status → commit a default property of that type
///     AND push .editProperty(propertyID:) onto the path so the user lands
///     in the option editor immediately (these types are useless without
///     options).
///   - Number / Checkbox / Date / DateTime / URL / File → commit a default
///     property of that type AND pop back to the Properties list (simple
///     types are usable as-is).
///   - Relation → defers to the existing `RelationPropertyWizard` on the
///     sheet path until v0.3.1.5; from the popover we show a one-line
///     "use Vault Settings" hint and pop. Full wizard wiring inside the
///     popover is queued.
///
/// Commits via PageTypeManager / ItemTypeManager addProperty. Schema lives
/// on the Type (Collections inherit), so Collection-scope adds route to the
/// parent Type's manager.
struct PropertyTypePickerPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var selected: PropertyType?
    @State private var commitError: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "+ New Property")

            ScrollView {
                PropertyTypePicker(selected: $selected) { type in
                    Task { await commit(type) }
                }
                .padding(.horizontal, PUI.Spacing.xl)
                .padding(.vertical, PUI.Pane.contentPadding)
            }

            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Commit

    private func commit(_ type: PropertyType) async {
        // Relation has its own multi-step wizard; defer to the sheet path
        // until v0.3.1.5 wires the wizard inside the popover.
        guard type != .relation else {
            commitError = "Use Vault Settings → Edit Properties for Relations (v0.3.1.5)"
            selected = nil
            return
        }

        let definition = makeDefaultDefinition(for: type)

        do {
            try await addProperty(definition)
        } catch {
            commitError = String(describing: error)
            return
        }

        // Type-aware routing.
        if PropertyTypePickerPane.requiresOptionConfig(type) {
            // Replace .propertyTypePicker on the stack with .editProperty so
            // back-tap from the option editor lands on Properties, not the
            // type picker we just left.
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
        case .itemType(let t):
            try await itemTypeManager.addProperty(def, to: t.id)
        case .pageCollection(let c):
            try await pageTypeManager.addProperty(def, to: c.typeID)
        case .itemCollection(let c):
            try await itemTypeManager.addProperty(def, to: c.typeID)
        default:
            return  // non-storage scopes shouldn't reach this pane
        }
    }

    /// Types that ship empty options on creation and demand the user fill
    /// them in immediately — direct routing pushes EditPropertyPane.
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
        case .relation, .lastEditedTime:
            // Relation is caught by the wizard branch above; lastEditedTime
            // isn't user-creatable (excluded from PropertyType.userCreatable).
            return PropertyDefinition(id: "", name: name, type: type)
        }
    }
}
