import SwiftUI

// MARK: - FrontmatterInspectorViewModel

/// View-model for FrontmatterInspector. Holds draft frontmatter state and fires
/// debounced-save via `onSave`. Testable without SwiftUI rendering (J.5 pattern).
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
        scheduleSave()
    }

    func handleTierChange(_ tier: Int, _ newIDs: [String]) {
        switch tier {
        case 1: draftTier1 = newIDs
        case 2: draftTier2 = newIDs
        case 3: draftTier3 = newIDs
        default: break
        }
        scheduleSave()
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
/// Edits debounce 300ms before triggering `onSave` with the mutated frontmatter.
///
/// `onSave` is optional so the inspector can be previewed / tested without a
/// live `PageContentManager`. The host (ContentView → PageEditorHost) supplies
/// a real save closure when wiring up.
struct FrontmatterInspector: View {
    let page: PageMeta
    let vault: PageType
    let onSave: ((PageFrontmatter) -> Void)?

    @Environment(SpaceManager.self) private var spaceManager
    @Environment(PageTypeManager.self) private var vaultManager

    @State private var vm: FrontmatterInspectorViewModel?

    init(page: PageMeta, vault: PageType, onSave: ((PageFrontmatter) -> Void)? = nil) {
        self.page = page
        self.vault = vault
        self.onSave = onSave
    }

    var body: some View {
        Form {
            pageSection
            tiersSection
            propertiesSection
        }
        .formStyle(.grouped)
        .onAppear { initVM() }
    }

    // MARK: - Page section (read-only meta)

    private var pageSection: some View {
        Section("Page") {
            LabeledContent("Title", value: page.title)
            LabeledContent("ID") {
                Text(page.frontmatter.id)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Created", value: createdAtFormatted)
            if let icon = page.frontmatter.icon, !icon.isEmpty {
                LabeledContent("Icon") {
                    Label(icon, systemImage: icon)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tiers section (read-only in inspector — editable via PropertiesPulldown)

    private var tiersSection: some View {
        Section("Tiers") {
            LabeledContent("Spaces", value: tier1Names)
            LabeledContent("Topics", value: tier2Names)
            LabeledContent("Projects", value: tier3Names)
        }
    }

    // MARK: - Properties section (live editors via PropertyEditorRow)

    private var propertiesSection: some View {
        Section("Properties") {
            if vault.properties.isEmpty {
                Text("No properties defined in this Vault's schema.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let model = vm {
                ForEach(vault.properties) { prop in
                    LabeledContent(prop.name) {
                        PropertyEditorRow(
                            definition: prop,
                            value: Binding(
                                get: { model.draftProperties[prop.id] ?? .null },
                                set: { newVal in model.handlePropertyChange(prop.id, newVal) }
                            )
                        )
                    }
                }
            } else {
                // VM not yet initialized on first render — show placeholder
                ForEach(vault.properties) { prop in
                    LabeledContent(prop.name) {
                        Text(valueLabel(for: prop))
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func initVM() {
        if vm == nil {
            vm = FrontmatterInspectorViewModel(page: page, vault: vault, onSave: onSave)
        }
    }

    private var createdAtFormatted: String {
        page.frontmatter.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var tier1Names: String {
        let names = page.frontmatter.tier1.compactMap { id in
            spaceManager.spaces.first { $0.id == id }?.title
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var tier2Names: String {
        page.frontmatter.tier2.isEmpty ? "—" : "(\(page.frontmatter.tier2.count))"
    }

    private var tier3Names: String {
        page.frontmatter.tier3.isEmpty ? "—" : "(\(page.frontmatter.tier3.count))"
    }

    /// Fallback label shown before the VM initializes. Reads directly from frontmatter.
    private func valueLabel(for prop: PropertyDefinition) -> String {
        guard let val = page.frontmatter.properties[prop.id] else { return "—" }
        switch val {
        case .null: return "—"
        case .number(let n): return n.formatted()
        case .checkbox(let b): return b ? "Yes" : "No"
        case .select(let s): return s.isEmpty ? "—" : s
        case .multiSelect(let xs): return xs.isEmpty ? "—" : xs.joined(separator: ", ")
        case .status(let s): return s.isEmpty ? "—" : s
        case .date(let d): return d.formatted(date: .abbreviated, time: .omitted)
        case .datetime(let d): return d.formatted(date: .abbreviated, time: .shortened)
        case .url(let u): return u.absoluteString
        case .relation: return "→"
        case .file(let refs): return "\(refs.count) file(s)"
        case .lastEditedTime: return DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        }
    }
}
