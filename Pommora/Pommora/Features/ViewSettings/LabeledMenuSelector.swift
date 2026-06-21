import SwiftUI

/// Labeled inline menu selector: a section-header title on the left + a plain
/// borderless `Menu` dropdown on the right whose label shows the current value.
/// The menu hosts an inline `Picker` (checkmark on the active row).
///
/// One shared shape for every View Settings selector that reads as
/// "label … value ▾": the Edit-Property pickers (Display As / number / date /
/// time format) and the storage Layout selector. DRY — the rendering lives
/// here only; call sites pass the title, the current value string, and the
/// inline `Picker` to host.
struct LabeledMenuSelector<P: View>: View {
    let title: String
    let value: String
    @ViewBuilder var picker: () -> P

    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            Text(title)
                .font(PUI.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                picker()
                    .pickerStyle(.inline)
            } label: {
                Text(value)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
