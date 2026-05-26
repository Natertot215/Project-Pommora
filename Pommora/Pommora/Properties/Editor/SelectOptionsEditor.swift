import SwiftUI

/// Shared editor for a Select / Multi-Select property's options array.
///
/// Extracted from VaultSettingsSheet + TypeSettingsSheet (Task 8) where the
/// implementations were byte-for-byte copies. Both sheets now reference
/// this shared definition; future View Settings popover panes (EditPropertyPane —
/// Task 11) will reuse the same editor.
///
/// Drag-only reordering ships at Task 11 (option-row drag handles); v0.3.1
/// callers here use the existing simple add-on/remove form. The minus-circle
/// per-row delete + bottom "New option…" + Add affordance are unchanged from
/// the pre-extraction shape.
struct SelectOptionsEditor: View {
    @Binding var options: [PropertyDefinition.SelectOption]
    @State private var newOptionLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Options")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                SelectOptionsRow(
                    option: option,
                    onDelete: { options.removeAll { $0.value == option.value } }
                )
            }

            HStack {
                TextField("New option…", text: $newOptionLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button("Add") {
                    let label = newOptionLabel.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else { return }
                    let value = label.lowercased().replacingOccurrences(of: " ", with: "_")
                    options.append(PropertyDefinition.SelectOption(value: value, label: label, color: nil))
                    newOptionLabel = ""
                }
                .buttonStyle(.borderless)
                .disabled(newOptionLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct SelectOptionsRow: View {
    let option: PropertyDefinition.SelectOption
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(option.label)
                .font(.callout)
            Spacer()
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
