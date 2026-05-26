import SwiftUI

/// Shared segmented picker for a Number property's `numberFormat` config.
///
/// Extracted from VaultSettingsSheet + TypeSettingsSheet (Task 8) where the
/// implementations were byte-for-byte copies. Both sheets now reference
/// this shared definition; future View Settings popover panes (EditPropertyPane —
/// Task 11) will reuse the same picker.
struct NumberFormatPicker: View {
    @Binding var format: PropertyDefinition.NumberFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Format")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Format", selection: $format) {
                ForEach(PropertyDefinition.NumberFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue.capitalized).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
