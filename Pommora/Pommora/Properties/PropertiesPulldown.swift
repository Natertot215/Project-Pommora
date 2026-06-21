import SwiftUI

// MARK: - PropertiesPulldownViewModel

/// Business logic for `PropertiesPulldown`. Drives tests without SwiftUI rendering.
/// Lazy: only populated properties are considered "visible." Built-in + lastEditedTime
/// excluded from the "+ Add property" picker per L15.
@Observable
@MainActor
final class PropertiesPulldownViewModel {
    var isExpanded: Bool = false

    let schema: [PropertyDefinition]
    var values: [String: PropertyValue]
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
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

    // MARK: - Lazy queries

    /// Schema properties that have a populated (non-null) value.
    var populatedProperties: [PropertyDefinition] {
        schema.filter { def in
            let val = values[def.id]
            guard let val else { return false }
            if case .null = val { return false }
            // lastEditedTime is virtual — never persisted, always filtered from lazy view
            if case .lastEditedTime = val { return false }
            return true
        }
    }

    /// Schema properties that are NOT yet populated — candidates for "+ Add property".
    /// Excludes built-ins and .lastEditedTime per L15.
    var addableProperties: [PropertyDefinition] {
        let reservedIDs = ReservedPropertyID.all
        return schema.filter { def in
            guard !reservedIDs.contains(def.id) else { return false }
            guard def.type != .lastEditedTime else { return false }
            let val = values[def.id]
            if val == nil { return true }
            if case .null = val! { return true }
            return false
        }
    }

    var populatedCount: Int { populatedProperties.count }

    /// Whether tier1 should be visible in lazy mode (non-empty).
    var showTier1: Bool { !tier1.isEmpty }
    var showTier2: Bool { !tier2.isEmpty }
    var showTier3: Bool { !tier3.isEmpty }

    func handleValueChange(_ propertyID: String, _ newValue: PropertyValue) {
        values[propertyID] = newValue
        onValueChange(propertyID, newValue)
    }

    func addProperty(id: String, defaultValue: PropertyValue = .null) {
        values[id] = defaultValue
        onValueChange(id, defaultValue)
    }
}

// MARK: - PropertiesPulldown

/// Lazy property surface for Pages. Default-closed; shows populated properties only.
/// "+ Add property" exposes schema entries not yet populated. Empty state always visible
/// (never collapses to invisible per L24). Auto-managed section at the bottom, default closed.
struct PropertiesPulldown: View {
    let schema: [PropertyDefinition]
    @Binding var values: [String: PropertyValue]
    @Binding var tier1: [String]
    @Binding var tier2: [String]
    @Binding var tier3: [String]
    let autoManaged: AutoManagedFields
    let index: PommoraIndex?
    let onValueChange: (String, PropertyValue) -> Void
    let onTierChange: (Int, [String]) -> Void

    @State private var isExpanded: Bool = false
    @State private var autoManagedExpanded: Bool = false
    @State private var showAddPicker: Bool = false

    // Lazy queries (computed each render)

    private var populatedProperties: [PropertyDefinition] {
        schema.filter { def in
            guard let val = values[def.id] else { return false }
            if case .null = val { return false }
            if case .lastEditedTime = val { return false }
            return true
        }
    }

    private var addableProperties: [PropertyDefinition] {
        let reservedIDs = ReservedPropertyID.all
        return schema.filter { def in
            guard !reservedIDs.contains(def.id) else { return false }
            guard def.type != .lastEditedTime else { return false }
            let val = values[def.id]
            if val == nil { return true }
            if case .null = val! { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chevron header — always visible
            header
            if isExpanded {
                Divider()
                expandedContent
            }
        }
        .background(Color(.windowBackgroundColor).opacity(0.6))
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(populatedProperties.isEmpty ? "Properties" : "Properties (\(populatedProperties.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if populatedProperties.isEmpty && tier1.isEmpty && tier2.isEmpty && tier3.isEmpty {
                // Empty state — always visible (L24)
                emptyState
            } else {
                // Populated properties
                ForEach(populatedProperties) { def in
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
                    .padding(.horizontal, 16)
                    Divider()
                        .padding(.horizontal, 16)
                }

                // Tier rows — lazy: only if non-empty
                if !tier1.isEmpty {
                    tierRow(label: "Areas", ids: tier1)
                    Divider().padding(.horizontal, 16)
                }
                if !tier2.isEmpty {
                    tierRow(label: "Topics", ids: tier2)
                    Divider().padding(.horizontal, 16)
                }
                if !tier3.isEmpty {
                    tierRow(label: "Projects", ids: tier3)
                    Divider().padding(.horizontal, 16)
                }
            }

            // "+ Add property" affordance — always visible in expanded state
            addPropertyRow

            // Auto-managed section — collapsed by default
            Divider()
            autoManagedSection
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Text("No properties")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tier row

    private func tierRow(label: String, ids: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(ids.joined(separator: ", "))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
    }

    // MARK: - Add property row

    @ViewBuilder
    private var addPropertyRow: some View {
        if addableProperties.isEmpty {
            HStack {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Add property")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else {
            Menu {
                ForEach(addableProperties) { def in
                    Button {
                        values[def.id] = .null
                        onValueChange(def.id, .null)
                    } label: {
                        Text(def.name)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Add property")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Auto-managed section

    private var autoManagedSection: some View {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        } label: {
            Text("Auto-managed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private func autoManagedRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 70, alignment: .leading)
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
