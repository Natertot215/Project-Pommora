//
//  SidebarView.swift
//  Pommora
//

import SwiftUI

/// Four-section sidebar: Saved / Spaces / Topics / Vaults.
///
/// Section ForEach bodies currently use the in-file `SelectableRow` as a
/// placeholder for `SpaceRow` / `TopicRow` / `VaultRow` — those land in
/// Tasks 45-47 and will replace the SelectableRow invocations inline. Sub-topic
/// and Collection disclosure trees are deferred (flat rows for now).
///
/// `.sheet(item:)` cases render `SheetStubView` until Tasks 50-56 ship the real
/// sheet views (NewSpaceSheet, IconPickerSheet, etc.).
struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(SavedConfigManager.self) private var savedConfigManager

    @Binding var selection: SidebarSelection

    @State private var editingID: String? = nil
    @State private var presentedSheet: SidebarSheet? = nil
    @State private var confirmingDelete: SidebarConfirmation? = nil

    var body: some View {
        List {
            SavedSection(selection: $selection)
            SpacesSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
            TopicsSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
            VaultsSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                  SheetStubView(label: "New Space — coming in Task 52")
            case .newTopic:                  SheetStubView(label: "New Topic — coming in Task 53")
            case .newSubtopic(let t):        SheetStubView(label: "New Sub-topic in \(t.title) — coming in Task 54")
            case .newVault:                  SheetStubView(label: "New Vault — coming in Task 55")
            case .newCollection(let v):      SheetStubView(label: "New Collection in \(v.title) — coming in Task 55")
            case .newPage(let c, _):         SheetStubView(label: "New Page in \(c.title) — coming in Task 56")
            case .newItem(let c, _):         SheetStubView(label: "New Item in \(c.title) — coming in Task 56")
            case .editTopicParents(let t):   SheetStubView(label: "Edit Topic Parents — \(t.title) — coming in Task 53")
            case .editIcon(let target):      IconPickerSheet(target: target)
            case .editColor(let s):          ColorPickerSheet(space: s)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { confirmation in
            confirmationButtons(for: confirmation)
        } message: { confirmation in
            Text(confirmationMessage(for: confirmation))
        }
    }

    private var confirmationTitle: String {
        switch confirmingDelete {
        case .deleteSpace(let s)?:      return "Delete Space \"\(s.title)\"?"
        case .deleteTopic(let t, _)?:   return "Delete Topic \"\(t.title)\"?"
        case .deleteSubtopic(let s)?:   return "Delete Sub-topic \"\(s.title)\"?"
        case .deleteVault(let v, _)?:   return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c)?: return "Delete Collection \"\(c.title)\"?"
        case nil: return ""
        }
    }

    private func confirmationMessage(for confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .deleteSpace: return "This action cannot be undone."
        case .deleteTopic(_, let count): return count > 0
            ? "Contains \(count) Sub-topic(s). Promote them or delete all?"
            : "This action cannot be undone."
        case .deleteSubtopic: return "This action cannot be undone."
        case .deleteVault(_, let cols): return "Contains \(cols) Collection(s). All contents will be deleted."
        case .deleteCollection: return "All Pages and Items inside will be deleted."
        }
    }

    @ViewBuilder
    private func confirmationButtons(for confirmation: SidebarConfirmation) -> some View {
        switch confirmation {
        case .deleteSpace(let s):
            Button("Delete", role: .destructive) {
                Task { try? await spaceManager.delete(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteTopic(let t, let count):
            if count > 0 {
                Button("Delete & Promote Sub-topics", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
                Button("Delete All", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: false); confirmingDelete = nil }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteSubtopic(let s):
            Button("Delete", role: .destructive) {
                Task { try? await topicManager.deleteSubtopic(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteVault(v); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteCollection(c); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        }
    }
}

// MARK: - Sections

struct SavedSection: View {
    @Binding var selection: SidebarSelection
    @Environment(SavedConfigManager.self) private var savedConfigManager

    var body: some View {
        Section("Saved") {
            ForEach(savedConfigManager.config.items) { item in
                SelectableRow(
                    title: item.label,
                    symbol: iconFor(item.key),
                    tag: SelectionTag.savedKey(item.key),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .savedKey(item.key) }
                )
            }
        }
    }

    private func iconFor(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents":  return "clock"
        default: return "questionmark.square"
        }
    }
}

struct SpacesSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Section("Spaces") {
            ForEach(spaceManager.spaces) { space in
                SpaceRow(
                    space: space,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newSpace
            } label: {
                Label("New Space", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct TopicsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(TopicManager.self) private var topicManager

    var body: some View {
        Section("Topics") {
            ForEach(topicManager.topics) { topic in
                TopicRow(
                    topic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newTopic
            } label: {
                Label("New Topic", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct VaultsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Section("Vaults") {
            ForEach(vaultManager.vaults) { vault in
                VaultRow(
                    vault: vault,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newVault
            } label: {
                Label("New Vault", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - SelectableRow (updated to use SelectionTag)

struct SelectableRow: View {
    let title: String
    let symbol: String
    let tag: SelectionTag
    @Binding var selection: SidebarSelection
    let accent: Color?
    let onSelect: () -> Void

    var isSelected: Bool {
        tag.matches(selection)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.accentColor : (accent ?? .primary))
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .brightness(isSelected ? 0.12 : 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.11))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 2)
                : nil
        )
    }
}

// MARK: - Sheet stubs (replaced progressively in Tasks 50-56)

private struct SheetStubView: View {
    let label: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(label).font(.title3).foregroundStyle(.secondary)
            Button("Done") { dismiss() }
        }
        .padding(40)
        .frame(minWidth: 320, minHeight: 160)
    }
}
