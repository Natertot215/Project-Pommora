import SwiftUI

/// View Settings → Edit Properties → + New Property → type picker pane.
///
/// Wraps the existing `PropertyTypePicker` for pushed-pane mode + handles
/// routing: every type commits a default property AND pushes
/// `.editProperty(propertyID:)` so the user lands in the configuration
/// editor immediately after creation.
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
        // Non-storage scopes shouldn't reach this pane.
        guard let typeID = schemaTypeID else { return }

        let definition: PropertyDefinition
        do {
            // Shared mint + seed + commit path (`PropertyCreation`) — also
            // used by the inspector's Add Property affordance.
            definition = try await PropertyCreation.commitDefault(
                type, toTypeID: typeID, manager: pageTypeManager)
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
            return
        }

        // Replace .propertyTypePicker on the stack with .editProperty so
        // back-tap from the editor lands on Properties, not the type picker.
        if path.last == .propertyTypePicker {
            path.removeLast()
        }
        path.append(.editProperty(propertyID: definition.id))
    }

    /// The Type schema that owns this scope's properties (Collections inherit
    /// from their parent Type). `nil` for non-storage scopes.
    private var schemaTypeID: String? { scope.schemaTypeID }

}
