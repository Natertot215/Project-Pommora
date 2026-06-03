import SwiftUI

/// In-app design system explorer. Pommora's Storybook equivalent — a debug-only
/// window (gated behind `Cmd+Shift+D` via the Debug menu) showing every
/// custom Pommora UI primitive so Nathan can see how the SwiftUI implementation
/// translates from the Figma source-of-truth.
///
/// Sidebar is a flat per-category leaf list grouped under COMPONENTS /
/// FOUNDATIONS. Each leaf opens a **gallery** detail pane that composes all
/// of that category's variants on one page (rather than spreading every
/// component across nested disclosure rows). Categories with no shipped
/// components yet render a `CategoryPlaceholderGallery` that enumerates the
/// planned stories so the library doubles as a forward-looking roadmap.
struct ComponentLibraryView: View {
    @State private var selectedCategory: ComponentCategory? = .chips

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Pommora UIX")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedCategory) {
            ForEach(ComponentLibraryGroup.allCases, id: \.self) { group in
                Section(group.displayName) {
                    ForEach(group.categories, id: \.self) { category in
                        Label(category.displayName, systemImage: category.symbol)
                            .tag(category)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedCategory {
        case .chips:
            ChipsGallery()
        case .windows:
            WindowsGallery()
        case .pickers:
            PickersGallery()
        case .none:
            ContentUnavailableView(
                "Pick a category",
                systemImage: "square.grid.3x3",
                description: Text("Select a category on the left to explore its components.")
            )
        default:
            CategoryPlaceholderGallery(category: selectedCategory!)
        }
    }
}

// MARK: - Sidebar taxonomy

/// Top-level grouping in the sidebar — `COMPONENTS` (Pommora-custom UI)
/// vs `FOUNDATIONS` (design tokens, palettes, type scales).
enum ComponentLibraryGroup: String, CaseIterable, Hashable {
    case components
    case foundations

    var displayName: String {
        switch self {
        case .components: return "COMPONENTS"
        case .foundations: return "FOUNDATIONS"
        }
    }

    var categories: [ComponentCategory] {
        switch self {
        case .components:
            return [.chips, .sidebar, .detailViews, .pickers, .sheets, .pageEditor, .navDropdown, .windows]
        case .foundations:
            return [.colors, .typography, .materials, .symbols, .spacing]
        }
    }
}

/// Sidebar leaf — one category per row. Each category corresponds to a
/// gallery detail pane that composes every variant the category covers.
enum ComponentCategory: String, CaseIterable, Hashable {
    // Components
    case chips
    case sidebar
    case detailViews
    case pickers
    case sheets
    case pageEditor
    case navDropdown
    case windows

    // Foundations
    case colors
    case typography
    case materials
    case symbols
    case spacing

    var displayName: String {
        switch self {
        case .chips: return "Chips"
        case .sidebar: return "Sidebar"
        case .detailViews: return "Detail Views"
        case .pickers: return "Date Picker"
        case .sheets: return "Sheets"
        case .pageEditor: return "Page Editor"
        case .navDropdown: return "NavDropdown"
        case .windows: return "Windows"
        case .colors: return "Colors"
        case .typography: return "Typography"
        case .materials: return "Materials & Liquid Glass"
        case .symbols: return "Symbols"
        case .spacing: return "Spacing"
        }
    }

    var symbol: String {
        switch self {
        case .chips: return "tag.fill"
        case .sidebar: return "sidebar.left"
        case .detailViews: return "rectangle.split.3x1"
        case .pickers: return "calendar"
        case .sheets: return "doc.on.doc"
        case .pageEditor: return "text.alignleft"
        case .navDropdown: return "square.on.square"
        case .windows: return "macwindow"
        case .colors: return "paintpalette.fill"
        case .typography: return "textformat"
        case .materials: return "circle.lefthalf.filled"
        case .symbols: return "asterisk"
        case .spacing: return "ruler"
        }
    }

    /// Stories planned for this category — used by the placeholder gallery
    /// to enumerate what each category WILL cover when fully populated.
    /// `Chips` and `Windows` ship real galleries and don't go through this
    /// path, so their planned lists here are unused (kept for completeness).
    var plannedStories: [PlannedStory] {
        switch self {
        case .chips:
            return []
        case .sidebar:
            return [
                .init(name: "Selectable Row", detail: "Pure-content row primitive. Selection chrome lives at row file level via .listRowBackground(SelectionChrome(...)) per active quirk #10."),
                .init(name: "Renameable Row", detail: "Inline-rename mode for any sidebar row. Used by Space / Project / PageType / Topic / Page / PageCollection / ItemType."),
                .init(name: "Section Header", detail: "Sidebar section header strip: secondary-styled title + trailing hover-revealed + button + right-click context menu."),
                .init(name: "Selection Chrome", detail: "RoundedRectangle selection fill applied per sidebar row via .listRowBackground. Two styles: .flat and .disclosure."),
            ]
        case .detailViews:
            return [
                .init(name: "Detail Row", detail: "Row primitive consumed by all four storage-container detail-pane Tables (Vault / Type / Collection / Set)."),
            ]
        case .pickers:
            return []  // ships a real gallery (PickersGallery)
        case .sheets:
            return [
                .init(name: "New Item Sheet", detail: "Name + Icon form for creating Items. Routes to ItemContentManager.createItem(in:type:) or createItem(inTypeRoot:)."),
                .init(name: "Vault Settings Sheet", detail: "Pages-side schema editor. Add/edit/delete properties on a PageType."),
                .init(name: "Type Settings Sheet", detail: "Items-side schema editor. Add/edit/delete properties on an ItemType."),
                .init(name: "Icon Picker", detail: "Pommora-native compact Liquid-Glass SF Symbol chooser — full catalog, search, and Saved icons. Replaces the third-party SymbolPicker."),
                .init(name: "Color Picker Sheet", detail: "SpaceColor chooser — Pommora's hand-picked Space accent palette."),
            ]
        case .pageEditor:
            return [
                .init(name: "Blockquote", detail: "Always-show overlay rendering of `> ` quotes; renderer-drawn rounded card with vertical pill accent bar. Shipped v0.2.7.5."),
                .init(name: "Code Block", detail: "Code block with system-semantic colors. Shipped v0.2.7.4."),
                .init(name: "Lists", detail: "Bulleted / numbered / task list with bullet-glyph substitution and dynamic-syntax markers. Shipped v0.2.7.2."),
                .init(name: "HR", detail: "Horizontal rule with layout-constant jitter fix. Shipped v0.2.7.4."),
            ]
        case .navDropdown:
            return [
                .init(name: "NavDropdown Button", detail: "Liquid Glass dropdown navigation surface. Shipped v0.2.7.1; supersedes the earlier tab-strip model."),
                .init(name: "Entity Row", detail: "Single row inside the NavDropdown (Pinned + Recents). Icon + title + secondary metadata."),
                .init(name: "BackForward Buttons", detail: "⌘[ / ⌘] navigation through Recents stack. Shipped with NavDropdown."),
            ]
        case .windows:
            return []
        case .colors:
            return [.init(name: "Palette", detail: "PropertyChipColor palette + Apple system colors + Pommora accent palette. Cross-referenced from Guidelines/Design.md.")]
        case .typography:
            return [.init(name: "Type Scale", detail: "Apple's text scale × how Pommora applies each style. SF Pro Semibold 12pt for chip text, etc.")]
        case .materials:
            return [.init(name: "Materials", detail: "Background swatches: .regularMaterial, .sidebar, .bar; how Liquid Glass renders across contexts.")]
        case .symbols:
            return [.init(name: "Symbol Registry", detail: "Live registry from Guidelines/Symbols.md — semantic-role → SF Symbol mapping with searchable preview.")]
        case .spacing:
            return [.init(name: "Spacing Tokens", detail: "Pommora-specific spacing tokens (if/as they emerge). v1: standard SwiftUI spacing only.")]
        }
    }
}

/// One bullet entry inside a `CategoryPlaceholderGallery`. Pure-data card —
/// no behavior, just the planned name + a one-sentence description.
struct PlannedStory: Identifiable, Hashable {
    let name: String
    let detail: String
    var id: String { name }
}

// MARK: - Chips Gallery (shipped — combines all 3 chip components)

/// Aggregates PropertyChip + ChipDropdown + PropertyCheckbox into one
/// scrollable gallery. Each component gets a header + its full variant set.
private struct ChipsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                GallerySection(
                    title: "Property Chip",
                    summary: "Two variants of the same primitive. Pill carries a text label (50pt minWidth, 20pt height). Chip carries a single SF Symbol icon (32pt minWidth, 20pt height). Both share the same Capsule background."
                ) {
                    PropertyChipShowcase()
                }

                GallerySection(
                    title: "Relation Chip",
                    summary: "Relation property values — the target entity's icon + title in a standard-button-radius rounded rectangle with a quinary fill + hairline stroke (distinct from PropertyChip's Capsule). One primitive; every relation surface (table cells, picker rows, tier rows) routes through it."
                ) {
                    RelationChipShowcase()
                }

                GallerySection(
                    title: "Chip Dropdown",
                    summary: "The pill itself opens the dropdown — no surrounding trigger frame. Multi-select renders selected pills inline in the trigger area, in the dropdown's option order (drag-reorder to change). Liquid Glass panel, always-on."
                ) {
                    ChipDropdownShowcase()
                }

                GallerySection(
                    title: "Property Checkbox",
                    summary: "Standard-checkbox-shaped property control. Custom fill color + custom SF Symbol shown when checked. Distinct from PropertyChip (different shape, different mental model). Used in Status property cells when display-as = Checkbox."
                ) {
                    PropertyCheckboxShowcase()
                }

                GallerySection(
                    title: "Status Checkbox",
                    summary: "Tri-state checkbox projection of a Status value (Display As = Box): empty for the 'upcoming' group, the value's color + minus for 'in_progress', the value's color + checkmark for 'done'. The group→state mapping is standardized in StatusCheckbox so every status-checkbox surface renders identically."
                ) {
                    StatusCheckboxShowcase()
                }
            }
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Windows Gallery (stubs — buttons that pop up the actual windows)

/// Test-launcher for Pommora's popup windows. Each row is a button that
/// opens a stub representation of the target window. As real designs land,
/// the stub `WindowStubSheet` gets replaced in-place with the real window
/// chrome (Liquid Glass X + Inspector toggle, two-column body, etc.).
///
/// Currently using `.sheet(isPresented:)` for the stub popups since they're
/// just placeholders. When the real chrome ships, swap to `openWindow(id:)`
/// calls against Window scenes registered in `PommoraApp.swift`.
private struct WindowsGallery: View {
    @State private var showingItemWindow: Bool = false
    @State private var showingPagePreview: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                VStack(alignment: .leading, spacing: 16) {
                    WindowLaunchRow(
                        title: "Item Window",
                        symbol: "macwindow",
                        summary: "Popover-style Item Window — title + properties + 1000-char description. Two-column body (description left, properties right). No traffic lights; Liquid Glass X (left) + Inspector toggle (right).",
                        action: { showingItemWindow = true }
                    )

                    WindowLaunchRow(
                        title: "Page Preview",
                        symbol: "doc.richtext",
                        summary: "Standalone-window preview of a Page — full editor surface in its own window. Queued behind the cross-feature PreviewWindow primitive; chrome matches Item Window.",
                        action: { showingPagePreview = true }
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showingItemWindow) {
            WindowStubSheet(
                title: "Item Window",
                symbol: "macwindow",
                description: "Stub — real Item Window chrome lands next. Will show title + properties + 1000-char description in a two-column popover with Liquid Glass X + Inspector toggle in lieu of traffic lights."
            ) { showingItemWindow = false }
        }
        .sheet(isPresented: $showingPagePreview) {
            WindowStubSheet(
                title: "Page Preview",
                symbol: "doc.richtext",
                description: "Stub — real Page Preview chrome lands alongside the cross-feature PreviewWindow primitive. Will render the full Page editor in a standalone window with matching chrome."
            ) { showingPagePreview = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Windows")
                .font(.title.bold())
            Text("Click a row to launch the window stub. As real designs land, each stub gets replaced in-place with the real window chrome.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

/// One row in the Windows gallery. Tappable card surfacing the planned
/// window's summary; tap → opens the stub via the closure provided.
private struct WindowLaunchRow: View {
    let title: String
    let symbol: String
    let summary: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color(.controlBackgroundColor).opacity(0.8) : Color(.controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Stub popup body. Replaced in-place per-window as real designs ship.
private struct WindowStubSheet: View {
    let title: String
    let symbol: String
    let description: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()
            }

            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title2.bold())

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Text("Design lands in the Windows category as it ships.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 480, height: 360)
    }
}

// MARK: - Category placeholder gallery — for categories with no shipped stories yet

/// Renders a list of planned-story cards for any category that hasn't
/// shipped its real gallery yet. Surfaces the planned spec so the library
/// doubles as a forward-looking roadmap.
private struct CategoryPlaceholderGallery: View {
    let category: ComponentCategory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if category.plannedStories.isEmpty {
                    Text("Nothing planned yet.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(category.plannedStories) { story in
                            PlannedStoryCard(story: story)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: category.symbol)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayName)
                    .font(.title.bold())
                Text("Planned — stories ship alongside the components themselves.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

private struct PlannedStoryCard: View {
    let story: PlannedStory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(story.name)
                    .font(.headline)
                Text("soon")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color(.tertiaryLabelColor).opacity(0.18))
                    )
            }
            Text(story.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - GallerySection — heading + summary wrapper used by ChipsGallery

private struct GallerySection<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            content()
        }
    }
}

// MARK: - PropertyChip Showcase (Pill + Chip variants)

private struct PropertyChipShowcase: View {
    /// One sample SF Symbol per color, used to demonstrate the Chip variant.
    /// Swap freely — purely for showcase purposes.
    private let sampleIcons: [PropertyChipColor: String] = [
        .default: "tag.fill",
        .red: "flame.fill",
        .orange: "sun.max.fill",
        .yellow: "bolt.fill",
        .green: "checkmark.circle.fill",
        .blue: "star.fill",
        .accent: "sparkles",
        .teal: "wave.3.right",
        .indigo: "bell.fill",
        .purple: "bookmark.fill",
        .pink: "heart.fill",
        .brown: "leaf.fill",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(title: "Pill — 50pt × 20pt with Label text (10 selectable colors)") {
                paletteRow(
                    colors: PropertyChipColor.selectablePalette,
                    chipBuilder: { PropertyChip(label: $0.displayName, color: $0) }
                )
            }

            section(title: "Chip — 32pt × 20pt with SF Symbol icon (10 selectable colors)") {
                paletteRow(
                    colors: PropertyChipColor.selectablePalette,
                    chipBuilder: { PropertyChip(icon: sampleIcons[$0] ?? "circle.fill", color: $0) }
                )
            }

            section(title: "Informational — Default + Accent (not user-pickable)") {
                paletteRow(
                    colors: [.default, .accent],
                    chipBuilder: { PropertyChip(label: $0.displayName, color: $0) }
                )
                Text(
                    ".default surfaces as the No-color affordance in OptionColorPicker (writes nil to the option's color). "
                    + ".accent reflects the current Nexus accent — can't render as a fixed swatch in the picker grid."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            CodeBlock(
                title: "Usage",
                code: """
                // Pill — text label, 50pt × 20pt
                PropertyChip(label: "Personal", color: .blue)

                // Chip — SF Symbol icon, 32pt × 20pt
                PropertyChip(icon: "star.fill", color: .yellow)

                // Pommora-custom hex overrides
                //   .pink   = #E89EB8 (Pommora pink)
                //   .yellow = #FFDE21 (brighter than systemYellow)
                //
                // .green + .teal use systemGreen / systemTeal at opacity 0.7
                // for a softer fill against the chip background.
                """
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func paletteRow(
        colors: [PropertyChipColor],
        chipBuilder: @escaping (PropertyChipColor) -> PropertyChip
    ) -> some View {
        FlowingHStack {
            ForEach(colors, id: \.self) { color in
                cell(chip: chipBuilder(color), caption: ".\(color.rawValue)")
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(.horizontal)
    }

    private func cell(chip: PropertyChip, caption: String) -> some View {
        VStack(spacing: 6) {
            chip
            Text(caption)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - RelationChip Showcase

/// Showcases the relation-value chip: target icon + title in a button-radius
/// rounded rectangle with a quinary fill + hairline stroke. The single
/// render primitive every relation surface routes through.
private struct RelationChipShowcase: View {
    private let samples: [(icon: String, title: String)] = [
        ("square.dashed", "Relation"),
        ("doc.text", "Project Brief"),
        ("folder", "Q3 Planning"),
        ("checklist", "Follow up with Sam"),
        ("calendar", "Design review"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(title: "Default — target icon + title, quinary fill, button radius") {
                FlowingHStack {
                    ForEach(samples, id: \.title) { s in
                        RelationChip(icon: s.icon, title: s.title)
                    }
                }
            }

            section(title: "Against surfaces — the stroke keeps it legible on any background") {
                HStack(spacing: 16) {
                    surfaceCell(Color(.windowBackgroundColor), "window")
                    surfaceCell(Color(.controlBackgroundColor), "control")
                    surfaceCell(Color(.textBackgroundColor), "text")
                }
            }

            CodeBlock(
                title: "Usage",
                code: """
                // The single render primitive for every relation value.
                // icon + title resolve from the LINKED target entity
                // (via RelationDisplayResolver), never the source property.
                RelationChip(icon: "doc.text", title: "Project Brief")
                """
            )
            .padding(.horizontal)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(.horizontal)
    }

    private func surfaceCell(_ surface: Color, _ label: String) -> some View {
        VStack(spacing: 8) {
            RelationChip(icon: "square.dashed", title: "Relation")
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(surface))
    }
}

// MARK: - ChipDropdown Showcase

private struct ChipDropdownShowcase: View {
    @State private var optionsOrder: [PropertyChipOption] = [
        PropertyChipOption(id: "personal", label: "Personal", color: .blue),
        PropertyChipOption(id: "academics", label: "Academics", color: .red),
        PropertyChipOption(id: "business", label: "Business", color: .green),
        PropertyChipOption(id: "projects", label: "Projects", color: .purple),
        PropertyChipOption(id: "systems", label: "Systems", color: .default),
    ]
    @State private var singleSelectedID: String? = "personal"
    @State private var multiSelectedIDs: Set<String> = ["personal"]
    @State private var showingSingle: Bool = false
    @State private var showingMulti: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 48) {
                singleSelectColumn
                multiSelectColumn
            }
            .padding(.horizontal)

            CodeBlock(
                title: "Trigger + dropdown contract",
                code: """
                Trigger:
                  - The pill itself IS the trigger (no surrounding frame)
                  - Single-select: one pill; click → dropdown
                  - Multi-select: N pills inline (HStack); any pill click → dropdown

                Dropdown:
                  - Liquid Glass background (.regularMaterial) + 0.5pt border
                  - Horizontally compressed — content-driven width
                  - Multi-select rows are draggable: drag-to-reorder the options;
                    the new order propagates to the trigger field's pill order
                """
            )
            .padding(.horizontal)
        }
    }

    private var singleSelectColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Single-select").font(.headline)

            Button { showingSingle.toggle() } label: {
                if let sel = singleSelected {
                    PropertyChip(label: sel.label, color: sel.color)
                } else {
                    PropertyChip(label: "Empty", color: .default)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSingle, arrowEdge: .bottom) {
                ChipDropdown(
                    options: $optionsOrder,
                    selectionMode: .single,
                    selectedIDs: singleSelectedID.map { Set([$0]) } ?? [],
                    onPick: { opt in
                        singleSelectedID = opt.id
                        showingSingle = false
                    }
                )
            }

            Text(singleSelectedID.map { "Current: \($0)" } ?? "Current: nil")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multiSelectColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Multi-select").font(.headline)

            Button { showingMulti.toggle() } label: {
                if multiSelectedOptions.isEmpty {
                    PropertyChip(label: "Empty", color: .default)
                } else {
                    HStack(spacing: 4) {
                        ForEach(multiSelectedOptions) { opt in
                            PropertyChip(label: opt.label, color: opt.color)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingMulti, arrowEdge: .bottom) {
                ChipDropdown(
                    options: $optionsOrder,
                    selectionMode: .multi,
                    selectedIDs: multiSelectedIDs,
                    onPick: { opt in
                        if multiSelectedIDs.contains(opt.id) {
                            multiSelectedIDs.remove(opt.id)
                        } else {
                            multiSelectedIDs.insert(opt.id)
                        }
                    }
                )
            }

            Text("Current: \(multiSelectedOptions.map(\.id).joined(separator: ", "))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var singleSelected: PropertyChipOption? {
        guard let id = singleSelectedID else { return nil }
        return optionsOrder.first(where: { $0.id == id })
    }

    private var multiSelectedOptions: [PropertyChipOption] {
        optionsOrder.filter { multiSelectedIDs.contains($0.id) }
    }
}

// MARK: - PropertyCheckbox Showcase

private struct PropertyCheckboxShowcase: View {
    @State private var checks: [PropertyChipColor: Bool] = Dictionary(
        uniqueKeysWithValues: PropertyChipColor.allCases.map { ($0, false) }
    )
    @State private var sizeIndex: Int = 1
    private let sizes: [(label: String, size: CGFloat)] = [
        ("Small (12pt)", 12),
        ("Standard (16pt)", 16),
        ("Large (22pt)", 22),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Size", selection: $sizeIndex) {
                ForEach(0..<sizes.count, id: \.self) { i in
                    Text(sizes[i].label).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Checked state — colored fill + white SF Symbol")
                    .font(.headline)
                FlowingHStack {
                    ForEach(PropertyChipColor.allCases, id: \.self) { color in
                        VStack(spacing: 6) {
                            PropertyCheckbox(
                                isChecked: binding(for: color),
                                color: color,
                                icon: "checkmark",
                                size: sizes[sizeIndex].size
                            )
                            Text(".\(color.rawValue)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor).opacity(0.4))
                        )
                    }
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Custom-icon checked state — substitute any SF Symbol")
                    .font(.headline)
                HStack(spacing: 16) {
                    iconSample(icon: "checkmark", color: .green, label: "checkmark")
                    iconSample(icon: "xmark", color: .red, label: "xmark")
                    iconSample(icon: "minus", color: .default, label: "minus")
                    iconSample(icon: "star.fill", color: .yellow, label: "star.fill")
                    iconSample(icon: "exclamationmark", color: .red, label: "exclamationmark")
                }
            }
            .padding(.horizontal)

            CodeBlock(
                title: "Usage",
                code: """
                PropertyCheckbox(
                    isChecked: $isDone,
                    color: .green,
                    icon: "checkmark",      // any SF Symbol
                    size: 16                // any CGFloat
                )
                """
            )
            .padding(.horizontal)
        }
    }

    private func binding(for color: PropertyChipColor) -> Binding<Bool> {
        Binding(
            get: { checks[color] ?? false },
            set: { checks[color] = $0 }
        )
    }

    private func iconSample(icon: String, color: PropertyChipColor, label: String) -> some View {
        VStack(spacing: 6) {
            PropertyCheckbox(
                isChecked: .constant(true),
                color: color,
                icon: icon,
                size: sizes[sizeIndex].size
            )
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - StatusCheckbox Showcase

private struct StatusCheckboxShowcase: View {
    private let groups: [PropertyDefinition.StatusGroup] = [
        PropertyDefinition.StatusGroup(
            id: .upcoming, label: "Upcoming", color: .gray,
            options: [PropertyDefinition.StatusOption(value: "reserved", label: "Reserved", color: nil, groupID: .upcoming)]
        ),
        PropertyDefinition.StatusGroup(
            id: .inProgress, label: "In Progress", color: .blue,
            options: [PropertyDefinition.StatusOption(value: "active", label: "Active", color: nil, groupID: .inProgress)]
        ),
        PropertyDefinition.StatusGroup(
            id: .done, label: "Done", color: .green,
            options: [PropertyDefinition.StatusOption(value: "complete", label: "Complete", color: nil, groupID: .done)]
        ),
    ]

    var body: some View {
        HStack(spacing: 24) {
            sample("reserved", "upcoming → empty")
            sample("active", "in_progress → minus")
            sample("complete", "done → checkmark")
            sample(nil, "unset → empty")
        }
        .padding(.horizontal)
    }

    private func sample(_ value: String?, _ label: String) -> some View {
        VStack(spacing: 6) {
            StatusCheckbox(value: value, groups: groups, size: 18)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - Date Picker Gallery (shipped)

/// Live `DateTimePicker` in every mode/time configuration. The accent fill
/// reads `\.nexusAccent` — defaults to the system accent here (no live Nexus).
private struct PickersGallery: View {
    @State private var dateOnly: DateSelection? = .single(.now)
    @State private var time12: DateSelection? = .single(.now)
    @State private var time24: DateSelection? = .single(.now)
    @State private var range: DateSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                GallerySection(
                    title: "Date Picker",
                    summary: "Pommora's custom Liquid-Glass calendar. Month/year header with a chevron month menu (in-card overlay, not a nested popover) + prev/next arrows. Selection is the per-Nexus accent at a translucent fill; range in-between days get a lighter band. Optional bespoke time row below a divider."
                ) {
                    VStack(alignment: .leading, spacing: 32) {
                        variant("Single date — date only", selection: $dateOnly, mode: .single, timeFormat: .none)
                        variant("Single date — 12-hour time", selection: $time12, mode: .single, timeFormat: .twelveHour)
                        variant("Single date — 24-hour time", selection: $time24, mode: .single, timeFormat: .twentyFourHour)
                        variant("Range — accent band on in-between days", selection: $range, mode: .range, timeFormat: .none)
                    }
                    .padding(.horizontal)
                }

                CodeBlock(
                    title: "Usage",
                    code: """
                    DateTimePicker(
                        selection: $selection,    // Binding<DateSelection?>
                        mode: .single,            // or .range (Agenda events)
                        timeFormat: .twelveHour   // .none | .twelveHour | .twentyFourHour
                    )

                    // Property cells bind .single; the accent fill reads the
                    // nexusAccent environment value (system accent in previews).
                    """
                )
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func variant(
        _ title: String,
        selection: Binding<DateSelection?>,
        mode: DateSelection.Mode,
        timeFormat: TimeFormat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            DateTimePicker(selection: selection, mode: mode, timeFormat: timeFormat)
            Text(readout(selection.wrappedValue))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func readout(_ selection: DateSelection?) -> String {
        guard let selection else { return "nil" }
        switch selection {
        case .single(let d):
            return "single(\(d.formatted(date: .abbreviated, time: .shortened)))"
        case .range(let a, let b):
            return "range(\(a.formatted(date: .abbreviated, time: .omitted)) … \(b.formatted(date: .abbreviated, time: .omitted)))"
        }
    }
}

// MARK: - Library primitives

private struct CodeBlock: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.textBackgroundColor))
                )
                .textSelection(.enabled)
        }
    }
}

private struct FlowingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .init(width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
