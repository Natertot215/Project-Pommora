import SwiftUI

/// Compact metric constants for `IconPicker` — gathered so the panel can be
/// resized/tuned in one place. Cells fill their column (flexible width), so a
/// wider `panelWidth` automatically widens the per-icon padding; `cell` sets the
/// row height, `inset` the content rail, `gridSpacing` the gap between icons.
private enum IconMetrics {
    static let panelWidth: CGFloat = 260
    static let panelHeight: CGFloat = 306
    static let columnCount = 6
    static let cell: CGFloat = 36  // row height (cell width is flexible)
    static let glyph: CGFloat = 19
    static let gridSpacing: CGFloat = 3
    static let inset: CGFloat = 12  // == PUI.Spacing.xl; the panel's content rail
}

/// Pommora-native SF Symbol picker — a compact Liquid-Glass dropdown that
/// replaces the third-party `SymbolPicker` everywhere an entity sets an icon.
/// Built because that library hardcodes its own 540-wide macOS frame and keeps
/// its catalog `internal`, so it can be neither resized nor re-skinned.
///
/// Layout (per Nathan's 2026-05-30 mock): a pill **search bar** on top, an
/// always-on divider, then a **6-wide** scrolling grid of `IconCatalog.all`.
/// When the search box is empty and the user has pinned icons, those **Saved**
/// icons float to the top — separated from the rest by a divider that appears
/// ONLY when at least one icon is saved (no header label; the divider is the
/// only separator). Right-clicking any icon toggles it in Saved (persisted
/// app-side via `IconFavorites`). A trailing **Remove Icon** row appears only
/// when an icon is currently set (the nullable-clear affordance).
///
/// Picking an icon writes the `symbol` binding and dismisses — so each host
/// presents it in a popover with `.presentationBackground(.clear)` (see
/// `iconPickerPopover`) so the only visible surface is this view's own
/// `.chipDropdownPanel()`, never doubled under the system popover's material.
struct IconPicker: View {
    @Binding var symbol: String?

    @State private var searchText = ""
    @State private var saved: [String] = IconFavorites.load()
    @Environment(\.dismiss) private var dismiss

    /// Fixed 6-column grid — flexible columns so the row spreads the cells
    /// evenly; the inter-icon gap is just `IconMetrics.gridSpacing`.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: IconMetrics.gridSpacing),
        count: IconMetrics.columnCount
    )

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().padding(.horizontal, IconMetrics.inset)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IconMetrics.inset)
                    .padding(.vertical, PUI.Spacing.md)
            }
            if symbol != nil {
                Divider().padding(.horizontal, IconMetrics.inset)
                removeButton
            }
        }
        .frame(width: IconMetrics.panelWidth, height: IconMetrics.panelHeight)
        .chipDropdownPanel()
    }

    // MARK: - Search (pill on top)

    private var searchBar: some View {
        HStack(spacing: PUI.Spacing.sm) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, PUI.Spacing.md)
        .padding(.vertical, PUI.Spacing.sm)
        .fieldBackground()
        .padding(.horizontal, IconMetrics.inset)
        .padding(.top, IconMetrics.inset)
        .padding(.bottom, PUI.Spacing.sm)
    }

    // MARK: - Body content (Saved + divider + rest, or filtered results)

    @ViewBuilder
    private var content: some View {
        if isSearching {
            if filtered.isEmpty {
                emptyState
            } else {
                grid(filtered)
            }
        } else {
            VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                if saved.isEmpty {
                    grid(IconCatalog.all)
                } else {
                    grid(saved)
                    Divider()  // separates favorites from the rest — only when favorites exist
                    grid(IconCatalog.all)
                }
            }
        }
    }

    private func grid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: IconMetrics.gridSpacing) {
            ForEach(symbols, id: \.self) { name in
                IconCell(
                    name: name,
                    isSelected: name == symbol,
                    isSaved: savedSet.contains(name),
                    onPick: { pick(name) },
                    onToggleSave: { toggleSave(name) }
                )
            }
        }
    }

    private var emptyState: some View {
        Text("No icons match “\(searchText)”")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    /// Plain red clear affordance — mirrors the OptionEditPopover / pane-footer
    /// Delete styling (borderless red `PUI.Typography.row`).
    private var removeButton: some View {
        Button(role: .destructive) {
            symbol = nil
            dismiss()
        } label: {
            Text("Remove")
                .font(PUI.Typography.row)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, IconMetrics.inset)
        .padding(.vertical, PUI.Spacing.sm)
    }

    // MARK: - Derived state + actions

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var savedSet: Set<String> { Set(saved) }

    private var filtered: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return IconCatalog.all }
        return IconCatalog.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func pick(_ name: String) {
        symbol = name
        dismiss()
    }

    private func toggleSave(_ name: String) {
        saved = IconFavorites.toggled(name, in: saved)
        IconFavorites.persist(saved)
    }
}

// MARK: - Icon cell (plain value type — no GRDB String-overload exposure)

/// One grid cell: the symbol fills its column (tight gaps), with an accent fill
/// when it is the current value, a hover wash, and a right-click menu to
/// pin/unpin it in Saved.
private struct IconCell: View {
    let name: String
    let isSelected: Bool
    let isSaved: Bool
    let onPick: () -> Void
    let onToggleSave: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            Image(systemName: name)
                .font(.system(size: IconMetrics.glyph))
                .frame(maxWidth: .infinity, minHeight: IconMetrics.cell)
                .background(fill)
                .clipShape(.rect(cornerRadius: PUI.Radius.card, style: .continuous))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(name)
        .contextMenu {
            Button(
                isSaved ? "Remove from Saved" : "Save",
                systemImage: isSaved ? "star.slash" : "star"
            ) {
                onToggleSave()
            }
        }
    }

    private var fill: Color {
        if isSelected { return .accentColor }
        return isHovered ? Color.primary.opacity(0.08) : .clear
    }
}

// MARK: - DRY presenter

extension View {
    /// Present `IconPicker` as a clean single-glass popover anchored to this
    /// view — the canonical way to host it (mirrors `RelationValueEditor`'s
    /// `.presentationBackground(.clear)` so only the picker's own
    /// `.chipDropdownPanel()` shows). Replaces the old
    /// `.popover { SymbolPicker(...).frame(540, 460) }` blocks at every call site.
    func iconPickerPopover(isPresented: Binding<Bool>, symbol: Binding<String?>) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            IconPicker(symbol: symbol)
                .presentationBackground(.clear)
        }
    }
}
