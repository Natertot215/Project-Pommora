import SwiftUI

/// Inline edit popover for a single Select / Multi / Status option.
///
/// Surfaces via `.popover(isPresented:)` attached to an option chip when
/// the user double-clicks. Replaces the earlier full-pane edit flow per
/// Nathan's 2026-05-26 direction — labels shouldn't require a navigation
/// hop; double-click + small popover is the canonical edit gesture.
///
/// **Content:**
///   - "Title…" TextField on the unified `.fieldBackground()` — same metrics
///     as the View Settings storage field (`.title3`, `.lg`/`.xs` padding) so
///     the two read identically (commits on Enter + focus loss + dismiss-if-dirty)
///   - 5×2 color palette grid (commits immediately on swatch tap; tapping
///     the already-selected swatch toggles back to no-color)
///   - a content-rail `Divider`, then a plain red "Delete" button matching the
///     EditPropertyPane footer Delete (no icon — same size/padding as the
///     main-window one), removing the option
struct OptionEditPopover: View {
    /// Current label — the popover holds a local draft until commit.
    let label: String
    /// Current option color (already mapped to PropertyChipColor).
    let color: PropertyChipColor?
    /// Commit a new label (called on Enter / focus loss / dismiss-if-dirty).
    let onCommitLabel: (String) -> Void
    /// Commit a new color (called on every swatch tap, including toggle-off
    /// which passes nil).
    let onCommitColor: (PropertyChipColor?) -> Void
    /// Delete the option (called when the Delete button is tapped).
    let onDelete: () -> Void

    @State private var draftLabel: String = ""
    @State private var draftColor: PropertyChipColor?
    @FocusState private var labelFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Visual constants. `contentWidth` is **derived** from the grid math so the TextField, grid, and
    /// Delete button share an exact rail with leading + trailing edges
    /// guaranteed to align.
    private let swatchSize: CGFloat = 26
    private let swatchSpacing: CGFloat = 10
    private let contentWidth: CGFloat = 170   // 5*26 + 4*10
    private let outerPadding: CGFloat = 14

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(swatchSize), spacing: swatchSpacing),
            count: 5
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            titleField
            colorGrid
            Divider().frame(width: contentWidth)
            deleteButton
        }
        .padding(outerPadding)
        .onAppear {
            draftLabel = label
            draftColor = color
            DispatchQueue.main.async { labelFocused = true }
        }
        .onDisappear { commitLabelIfDirty() }
    }

    @ViewBuilder
    private var titleField: some View {
        TextField("Title…", text: $draftLabel)
            .textFieldStyle(.plain)
            .font(.title3)
            .padding(.horizontal, PUI.Spacing.lg)
            .padding(.vertical, PUI.Spacing.xs)
            .frame(width: contentWidth, alignment: .leading)
            .fieldBackground()
            .focused($labelFocused)
            .onSubmit {
                commitLabelIfDirty()
                dismiss()
            }
            .onChange(of: labelFocused) { wasFocused, isFocused in
                if wasFocused && !isFocused {
                    commitLabelIfDirty()
                }
            }
    }

    /// 5×2 grid via `LazyVGrid` with `.fixed(swatchSize)` columns and an
    /// explicit `spacing`. With matching row + column spacing, the grid's
    /// outer extents land at exactly `(0, contentWidth)` — the same rail
    /// the TextField + Delete button share.
    @ViewBuilder
    private var colorGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: swatchSpacing) {
            ForEach(PropertyChipColor.selectablePalette, id: \.self) { color in
                swatch(color)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    @ViewBuilder
    private func swatch(_ color: PropertyChipColor) -> some View {
        Button {
            if draftColor == color {
                draftColor = nil
                onCommitColor(nil)
            } else {
                draftColor = color
                onCommitColor(color)
            }
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .opacity(draftColor == color ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
    }

    /// Plain red "Delete" — identical chrome to the EditPropertyPane footer
    /// Delete (`PUI.Typography.row`, red, borderless, no icon). Left-aligned on
    /// the shared content rail; the `Divider` above it (in `body`) mirrors the
    /// pane's `PaneDivider` + footer separation.
    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
            dismiss()
        } label: {
            Text("Delete")
                .font(PUI.Typography.row)
                .foregroundStyle(.red)
                .frame(width: contentWidth, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitLabelIfDirty() {
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != label else { return }
        onCommitLabel(trimmed)
    }
}
