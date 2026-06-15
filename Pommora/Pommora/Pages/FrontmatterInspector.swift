import SwiftUI

// MARK: - FrontmatterInspectorViewModel

/// View-model for FrontmatterInspector. Holds draft frontmatter state and fires
/// `onSave` — immediately for discrete pickers, debounced for free-text edits
/// (Properties.md contract). Testable without SwiftUI rendering (J.5 pattern).
@Observable
@MainActor
final class FrontmatterInspectorViewModel {
    var draftProperties: [String: PropertyValue]
    var draftTier1: [String]
    var draftTier2: [String]
    var draftTier3: [String]

    let page: PageMeta
    let vault: PageType
    let onSave: ((PageFrontmatter) -> Void)?

    private var saveTask: Task<Void, Never>?
    private static let debounce: Duration = .milliseconds(300)

    init(page: PageMeta, vault: PageType, onSave: ((PageFrontmatter) -> Void)?) {
        self.page = page
        self.vault = vault
        self.onSave = onSave
        self.draftProperties = page.frontmatter.properties
        self.draftTier1 = page.frontmatter.tier1
        self.draftTier2 = page.frontmatter.tier2
        self.draftTier3 = page.frontmatter.tier3
    }

    // MARK: - Edit handlers

    func handlePropertyChange(_ propertyID: String, _ newValue: PropertyValue) {
        draftProperties[propertyID] = newValue
        // Properties.md contract: pickers commit on click; only text inputs
        // (number / url) debounce to coalesce a keystroke burst. A discrete pick
        // has nothing to coalesce, so debouncing it is pure latency to persist +
        // cross-surface propagation — commit it now.
        if isTextStreamEdit(propertyID) { scheduleSave() } else { flushNow() }
    }

    /// True only for the property types edited via a free-text `TextField`
    /// (number, url) — those stream keystrokes and must debounce. Every other
    /// type commits through a single discrete pick.
    private func isTextStreamEdit(_ propertyID: String) -> Bool {
        switch schemaProperties.first(where: { $0.id == propertyID })?.type {
        case .number, .url: return true
        default: return false
        }
    }

    func handleTierChange(_ tier: Int, _ newIDs: [String]) {
        switch tier {
        case 1: draftTier1 = newIDs
        case 2: draftTier2 = newIDs
        case 3: draftTier3 = newIDs
        default: break
        }
        // Tiers are pickers (ContextValueEditor) — commit on pick, no debounce.
        flushNow()
    }

    // MARK: - Debounced save

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.flushNow()
        }
    }

    func flushNow() {
        saveTask?.cancel()
        saveTask = nil
        var updated = page.frontmatter
        updated.properties = draftProperties
        updated.tier1 = draftTier1
        updated.tier2 = draftTier2
        updated.tier3 = draftTier3
        onSave?(updated)
    }

    // MARK: - Schema accessor

    var schemaProperties: [PropertyDefinition] { vault.properties }
}

// MARK: - FrontmatterInspector

/// Live-editable frontmatter inspector for the editor's inspector panel.
///
/// v0.3.0 Properties (Phase J.14): every property row is now a live editor
/// backed by `PropertyEditorRow` — no more "Coming v0.3.0" placeholders.
/// Picker edits commit immediately; free-text edits (number / url) debounce
/// 300ms before triggering `onSave` with the mutated frontmatter.
///
/// `onSave` is optional so the inspector can be previewed / tested without a
/// live `PageContentManager`. The host (ContentView → PageEditorHost) supplies
/// a real save closure when wiring up.
struct FrontmatterInspector: View {
    let page: PageMeta
    let vault: PageType
    let index: PommoraIndex?
    let relationDisplay: ContextDisplayResolver?
    let onSave: ((PageFrontmatter) -> Void)?
    /// Compact typographic scale for narrow mounts (the PagePreview window's
    /// 210pt pane): rows one step down, action affordances another step
    /// below, small controls, tighter rows, no section headings. The main
    /// window's ~320pt inspector stays stock.
    let compact: Bool

    @Environment(AreaManager.self) private var areaManager
    @Environment(PageTypeManager.self) private var vaultManager

    @State private var vm: FrontmatterInspectorViewModel?
    @State private var addPropertyOpen = false
    @State private var addPropertySelection: PropertyType?
    @State private var addPropertyError: String?

    init(
        page: PageMeta,
        vault: PageType,
        index: PommoraIndex? = nil,
        relationDisplay: ContextDisplayResolver? = nil,
        onSave: ((PageFrontmatter) -> Void)? = nil,
        compact: Bool = false
    ) {
        self.page = page
        self.vault = vault
        self.index = index
        self.relationDisplay = relationDisplay
        self.onSave = onSave
        self.compact = compact
    }

    var body: some View {
        // One component, two mounts: the main window's inspector pane and
        // the PagePreview window both render THIS Form, so the surfaces
        // cannot drift. This grouped Form is the baseline look for
        // menu-grouping-like interfaces.
        Form {
            tiersSection
            propertiesSection
        }
        .formStyle(.grouped)
        .font(compact ? .subheadline : nil)
        .controlSize(compact ? .small : .regular)
        .environment(\.defaultMinListRowHeight, compact ? 24 : 32)
        // The page ID — pinned to the BOTTOM EDGE of the pane (a frame
        // footer, not a scroll footer), on both mounts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("ID: \(page.frontmatter.id)")
                    .font(.caption2)
                    // Explicit label color — the hierarchical `.secondary`
                    // picks up the inspector pane's vibrancy and reads
                    // near-primary there.
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PUI.Spacing.xl)
            .padding(.vertical, PUI.Spacing.sm)
        }
        .onAppear { initVM() }
    }

    /// Compact row metrics: condensed system insets (not custom padding) so
    /// the rows densify and the contexts card's first divider lands on the
    /// title-bar hairline by arithmetic — card top inset + one row height.
    /// `nil` keeps the stock Form insets in the full-size mount.
    private var rowInsets: EdgeInsets? {
        compact ? EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10) : nil
    }

    /// Inspector action affordances ("+ Add", value editors) sit one
    /// typography step below the row labels in compact.
    private var editorFont: Font? { compact ? .caption : nil }

    // MARK: - Tiers section (editable via ContextValueEditor; persists through the VM's debounced onSave)

    private var tiersSection: some View {
        Section {
            if let model = vm {
                tierRow("Areas", tier: 1, ids: tierBinding(model, 1))
                tierRow("Topics", tier: 2, ids: tierBinding(model, 2))
                tierRow("Projects", tier: 3, ids: tierBinding(model, 3))
            } else {
                LabeledContent("Areas", value: tier1Names)
                LabeledContent("Topics", value: tier2Names)
                LabeledContent("Projects", value: tier3Names)
            }
        } header: {
            // Compact drops the section headings entirely; the full-size
            // mount keeps them.
            if !compact { Text("Contexts") }
        }
    }

    private func tierRow(_ label: String, tier: Int, ids: Binding<[String]>) -> some View {
        LabeledContent(label) {
            ContextValueEditor(ids: ids, scope: .contextTier(tier), index: index, resolver: relationDisplay)
                .font(editorFont)
        }
        .listRowInsets(rowInsets)
    }

    private func tierBinding(_ model: FrontmatterInspectorViewModel, _ tier: Int) -> Binding<[String]> {
        switch tier {
        case 1: return Binding(get: { model.draftTier1 }, set: { model.handleTierChange(1, $0) })
        case 2: return Binding(get: { model.draftTier2 }, set: { model.handleTierChange(2, $0) })
        default: return Binding(get: { model.draftTier3 }, set: { model.handleTierChange(3, $0) })
        }
    }

    // MARK: - Properties section (live editors via PropertyEditorRow)

    private var propertiesSection: some View {
        Section {
            if let model = vm {
                ForEach(liveProperties) { prop in
                    LabeledContent(prop.name) {
                        PropertyEditorRow(
                            definition: prop,
                            value: Binding(
                                get: { model.draftProperties[prop.id] ?? .null },
                                set: { newVal in model.handlePropertyChange(prop.id, newVal) }
                            ),
                            index: index,
                            relationDisplay: relationDisplay,
                            // LabeledContent carries the name; the editor's
                            // internal label would double it.
                            showsName: false
                        )
                        .font(editorFont)
                    }
                    .listRowInsets(rowInsets)
                }
            } else {
                // VM not yet initialized on first render — show placeholder
                ForEach(liveProperties) { prop in
                    LabeledContent(prop.name) {
                        Text(valueLabel(for: prop))
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                    .listRowInsets(rowInsets)
                }
            }
            addPropertyRow
                .listRowInsets(rowInsets)
        } header: {
            if !compact { Text("Properties") }
        }
    }

    /// Schema rows resolved LIVE from the manager (not the `vault`
    /// snapshot passed at init) so any schema edit — from the affordance
    /// below or View Settings — appears immediately in every mount.
    private var liveProperties: [PropertyDefinition] {
        vaultManager.types.first(where: { $0.id == vault.id })?.properties ?? vault.properties
    }

    /// "Add Property" — small secondary label under the property rows.
    /// Opens the established property-type picker; commits through the same
    /// `PropertyCreation` path as View Settings. Option-bearing types
    /// (select / multi-select / status) are created with their seeded
    /// defaults; option configuration stays in View Settings.
    private var addPropertyRow: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
            Button {
                addPropertyOpen = true
            } label: {
                // One tight single-label affordance (glyph + text read as ONE
                // button), one typography step below the rows so it stays
                // subordinate, never another property.
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Property")
                }
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a property to this Vault's schema")
            .popover(isPresented: $addPropertyOpen, arrowEdge: .bottom) {
                PropertyTypePicker(selected: $addPropertySelection) { type in
                    addPropertyError = nil
                    Task {
                        do {
                            try await PropertyCreation.commitDefault(
                                type, toTypeID: vault.id, manager: vaultManager)
                            addPropertyOpen = false
                        } catch {
                            addPropertyError = PropertyEditorErrorMessage.string(for: error)
                        }
                    }
                }
                .padding(PUI.Spacing.xl)
                .frame(width: 280)
            }
            if let err = addPropertyError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func initVM() {
        if vm == nil {
            vm = FrontmatterInspectorViewModel(page: page, vault: vault, onSave: onSave)
        }
    }

    private var tier1Names: String {
        let names = page.frontmatter.tier1.compactMap { id in
            areaManager.areas.first { $0.id == id }?.title
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var tier2Names: String {
        page.frontmatter.tier2.isEmpty ? "—" : "(\(page.frontmatter.tier2.count))"
    }

    private var tier3Names: String {
        page.frontmatter.tier3.isEmpty ? "—" : "(\(page.frontmatter.tier3.count))"
    }

    /// Fallback label shown before the VM initializes. Reads directly from
    /// frontmatter and routes through `PropertyCellDisplay.placeholder(for:)` —
    /// the single source of truth for value→string placeholders — rather than
    /// duplicating the per-type switch here.
    private func valueLabel(for prop: PropertyDefinition) -> String {
        PropertyCellDisplay.placeholder(for: page.frontmatter.properties[prop.id])
    }
}
