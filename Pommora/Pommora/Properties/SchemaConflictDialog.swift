import SwiftUI

// MARK: - Payload

/// Carries the drift-detection output from `SchemaConflictDetector.detectDrift`
/// into the SwiftUI sheet. Identifiable so it can be used with `.sheet(item:)`.
struct SchemaConflictPayload: Identifiable {
    var id: String { "\(removed.joined())|\(typeChanged.joined())" }
    let removed: [String]
    let typeChanged: [String]
}

// MARK: - Dialog view

/// Sheet that surfaces a schema-drift event to the user when `ItemWindow.save()`
/// detects that the parent ItemType's schema changed while the editor was open.
///
/// Three paths:
/// - **Reload** (primary): re-fetch the schema and Item from disk; let the
///   user re-edit against the fresh schema.
/// - **Save valid subset** (secondary): drop stale or type-mismatched values,
///   save everything else.
/// - **Cancel**: dismiss the dialog; the editor remains open so the user can
///   manually copy values before deciding.
struct SchemaConflictDialog: View {
    @Binding var isPresented: Bool
    let removedPropertyNames: [String]
    let typeChangedPropertyNames: [String]
    var onReload: () -> Void
    var onSaveValidSubset: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title + icon
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("Schema changed")
                    .font(.headline)
            }

            // Description
            Text(descriptionText)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Change list
            if !removedPropertyNames.isEmpty || !typeChangedPropertyNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !removedPropertyNames.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Removed properties:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ForEach(removedPropertyNames, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    if !typeChangedPropertyNames.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Type-changed properties:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ForEach(typeChangedPropertyNames, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer(minLength: 0)

            // Buttons — stacked vertically for clarity (three paths)
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                    isPresented = false
                }
                Spacer()
                Button("Save valid subset") {
                    onSaveValidSubset()
                    isPresented = false
                }
                Button("Reload") {
                    onReload()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, maxWidth: 480)
    }

    // MARK: - Description text

    private var descriptionText: String {
        var parts: [String] = []
        if !removedPropertyNames.isEmpty {
            let count = removedPropertyNames.count
            parts.append(
                count == 1
                    ? "1 property was removed from this Item Type's schema."
                    : "\(count) properties were removed from this Item Type's schema."
            )
        }
        if !typeChangedPropertyNames.isEmpty {
            let count = typeChangedPropertyNames.count
            parts.append(
                count == 1
                    ? "1 property changed type while you were editing."
                    : "\(count) properties changed type while you were editing."
            )
        }
        parts.append(
            "Choose how to proceed: reload from disk, save only the values that still fit the schema, or cancel to copy values manually."
        )
        return parts.joined(separator: " ")
    }
}
