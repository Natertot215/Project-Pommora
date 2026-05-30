import SwiftUI

// MARK: - AutoManagedFields

/// Carries the three auto-managed fields shown at the bottom of every PropertyPanel.
struct AutoManagedFields: Sendable {
    let id: String
    let createdAt: Date
    let modifiedAt: Date
}

// MARK: - PropertyPanelViewModel

/// View-model isolating PropertyPanel business logic so it can be driven in tests
/// without SwiftUI rendering. Mirrors the J.5 FileAttachmentEditorViewModel pattern.
@Observable
@MainActor
final class PropertyPanelViewModel {
    var values: [String: PropertyValue]
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var autoManagedExpanded: Bool = false

    let schema: [PropertyDefinition]
    let autoManaged: AutoManagedFields
    let onValueChange: (String, PropertyValue) -> Void
    let onTierChange: (Int, [String]) -> Void

    init(
        schema: [PropertyDefinition],
        values: [String: PropertyValue],
        tier1: [String],
        tier2: [String],
        tier3: [String],
        autoManaged: AutoManagedFields,
        onValueChange: @escaping (String, PropertyValue) -> Void,
        onTierChange: @escaping (Int, [String]) -> Void
    ) {
        self.schema = schema
        self.values = values
        self.tier1 = tier1
        self.tier2 = tier2
        self.tier3 = tier3
        self.autoManaged = autoManaged
        self.onValueChange = onValueChange
        self.onTierChange = onTierChange
    }

    // MARK: - Actions

    /// Called when the user edits a property value. Updates local state and calls the callback.
    func handleValueChange(_ propertyID: String, _ newValue: PropertyValue) {
        values[propertyID] = newValue
        onValueChange(propertyID, newValue)
    }

    func handleTierChange(_ tier: Int, _ newIDs: [String]) {
        switch tier {
        case 1: tier1 = newIDs
        case 2: tier2 = newIDs
        case 3: tier3 = newIDs
        default: break
        }
        onTierChange(tier, newIDs)
    }

    // MARK: - Queries

    /// Row count: schema properties + tier rows (always 3).
    var totalRowCount: Int { schema.count + 3 }

    var hasSchema: Bool { !schema.isEmpty }
}

// MARK: - PropertyPanel

/// Host-agnostic eager property panel. Renders ALL schema properties regardless
/// of whether values are populated. tier1/2/3 always appear. Auto-managed fields
/// (id + created_at + modified_at) sit at the bottom in a collapsed DisclosureGroup.
///
/// Delegates per-property editing to `PropertyEditorRow` for all 11 property types.
struct PropertyPanel: View {
    let schema: [PropertyDefinition]
    @Binding var values: [String: PropertyValue]
    @Binding var tier1: [String]
    @Binding var tier2: [String]
    @Binding var tier3: [String]
    let autoManaged: AutoManagedFields
    let index: PommoraIndex?
    let relationDisplay: RelationDisplayResolver
    let onValueChange: (String, PropertyValue) -> Void
    let onTierChange: (Int, [String]) -> Void

    @State private var autoManagedExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Schema properties — eager: rendered even if value is .null
            if !schema.isEmpty {
                ForEach(schema) { def in
                    PropertyEditorRow(
                        definition: def,
                        value: Binding(
                            get: { values[def.id] ?? .null },
                            set: { newVal in
                                values[def.id] = newVal
                                onValueChange(def.id, newVal)
                            }
                        )
                    )
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    Divider()
                        .padding(.horizontal, 12)
                }
            }

            // Tier relations — always rendered (icon + title chips via the shared resolver)
            RelationChipRow(label: "Spaces", ids: tier1, resolver: relationDisplay)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            Divider()
                .padding(.horizontal, 12)
            RelationChipRow(label: "Topics", ids: tier2, resolver: relationDisplay)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            Divider()
                .padding(.horizontal, 12)
            RelationChipRow(label: "Projects", ids: tier3, resolver: relationDisplay)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)

            // Auto-managed section — collapsed by default
            Divider()
            DisclosureGroup(isExpanded: $autoManagedExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    autoManagedRow(label: "ID", value: autoManaged.id)
                    autoManagedRow(
                        label: "Created",
                        value: autoManaged.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    autoManagedRow(
                        label: "Modified",
                        value: autoManaged.modifiedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            } label: {
                Text("Auto-managed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Sub-views

    private func autoManagedRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
