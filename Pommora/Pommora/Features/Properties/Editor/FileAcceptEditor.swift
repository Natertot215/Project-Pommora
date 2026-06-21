import SwiftUI

/// Shared editor for a File property's `accept` MIME-type whitelist.
///
/// Extracted from VaultSettingsSheet + TypeSettingsSheet (Task 8) where the
/// implementations were byte-for-byte copies. Both sheets now reference
/// this shared definition; future View Settings popover panes will too.
///
/// The binding is `String` (comma-separated) — the calling sheet parses on
/// commit. Empty string means "any MIME type allowed."
struct FileAcceptEditor: View {
    @Binding var accept: String

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Allowed MIME types (comma-separated, leave blank for any)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. application/pdf, image/*", text: $accept)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }
}
