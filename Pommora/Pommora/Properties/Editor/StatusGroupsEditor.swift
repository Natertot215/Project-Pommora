import SwiftUI

/// Shared editor for a Status property's 3 fixed groups + their options.
///
/// Extracted from VaultSettingsSheet + TypeSettingsSheet (Task 8) where the
/// implementations were byte-for-byte copies. Both sheets now reference
/// this shared definition; future View Settings popover panes (EditPropertyPane —
/// Task 11) will reuse the same editor.
///
/// The 3 group IDs (upcoming / inProgress / done) are fixed — only group
/// labels are renameable, never the structural set. Per-group option add /
/// remove + inline label edit are unchanged from the pre-extraction shape.
/// Drag-between-groups and group reorder land in Task 11.
struct StatusGroupsEditor: View {
    @Binding var groups: [PropertyDefinition.StatusGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status Groups")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($groups) { $group in
                StatusGroupEditor(group: $group)
            }
        }
    }
}

private struct StatusGroupEditor: View {
    @Binding var group: PropertyDefinition.StatusGroup
    @State private var newOptionLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Group label", text: $group.label)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Text(group.id.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach($group.options) { $option in
                HStack {
                    TextField("Option label", text: $option.label)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button(role: .destructive) {
                        group.options.removeAll { $0.value == option.value }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
            }

            HStack {
                TextField("New option…", text: $newOptionLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .padding(.leading, 12)
                Button("Add") {
                    let label = newOptionLabel.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else { return }
                    let value = "\(group.id.rawValue)_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))"
                    group.options.append(PropertyDefinition.StatusOption(
                        value: value, label: label, color: nil, groupID: group.id
                    ))
                    newOptionLabel = ""
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(newOptionLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
