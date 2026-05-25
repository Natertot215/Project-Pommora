import SwiftUI

// MARK: - MoveStripConfirmationDialog

/// Confirmation dialog previewing which properties would be stripped when a
/// Page or Item moves across Types.
///
/// Three outcomes:
/// - "Move and Strip" (destructive primary): calls `onMoveAndStrip`.
/// - "Add Property First": routes caller to Type Settings; calls `onAddPropertyFirst`.
/// - "Cancel": calls `onCancel`.
///
/// When `strippedProperties` is empty, only "Move" is shown (no strip warning).
struct MoveStripConfirmationDialog: View {
    let entityTitle: String
    let sourceTypeTitle: String
    let destTypeTitle: String
    let strippedProperties: [(name: String, valuePreview: String)]
    let onMoveAndStrip: () -> Void
    let onAddPropertyFirst: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MoveStripDialogContent(
            entityTitle: entityTitle,
            sourceTypeTitle: sourceTypeTitle,
            destTypeTitle: destTypeTitle,
            strippedRows: strippedProperties.map {
                MoveStripRow(name: $0.name, valuePreview: $0.valuePreview)
            },
            onMoveAndStrip: onMoveAndStrip,
            onAddPropertyFirst: onAddPropertyFirst,
            onCancel: onCancel
        )
    }
}

// MARK: - MoveStripRow (plain struct, no GRDB conformances)

/// Plain value-type row for isolated ForEach rendering.
struct MoveStripRow: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let valuePreview: String
}

// MARK: - MoveStripDialogContent (isolated sub-view)

/// Isolated sub-view receiving plain value types to avoid GRDB
/// `SQLSpecificExpressible` overload conflicts in ForEach closures.
private struct MoveStripDialogContent: View {
    let entityTitle: String
    let sourceTypeTitle: String
    let destTypeTitle: String
    let strippedRows: [MoveStripRow]
    let onMoveAndStrip: () -> Void
    let onAddPropertyFirst: () -> Void
    let onCancel: () -> Void

    var hasStrippedProperties: Bool { !strippedRows.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Heading
            Text("Move \"\(entityTitle)\" from \(sourceTypeTitle) to \(destTypeTitle)?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if hasStrippedProperties {
                strippedList
            }

            Divider()

            actionRow
        }
        .padding()
        .frame(minWidth: 340)
    }

    // MARK: - Stripped properties list

    private var strippedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The following properties will be removed:")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(strippedRows) { row in
                    MoveStripPropertyRow(row: row)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .buttonStyle(.borderless)

            Spacer()

            if hasStrippedProperties {
                Button("Add Property First") { onAddPropertyFirst() }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 8)

                Button("Move and Strip") { onMoveAndStrip() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("Move") { onMoveAndStrip() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - MoveStripPropertyRow

private struct MoveStripPropertyRow: View {
    let row: MoveStripRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red.opacity(0.8))
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.callout)
                    .fontWeight(.medium)
                if !row.valuePreview.isEmpty {
                    Text(row.valuePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}
