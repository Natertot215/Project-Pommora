import SwiftUI

/// The sidebar's context area (Contexts Decoupling): ONE Section with a
/// "Contexts" header, holding exactly three TierDisclosureRows — homogeneous
/// siblings (quirk #6). Tier rows are expand/collapse only; entity rows inside
/// keep selection.
struct ContextsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            // Display order is Areas → Topics → Projects (tier 1 → 3, broadest
            // first); the tier1/2/3 data model is unchanged — render order only.
            TierDisclosureRow(
                label: settingsManager.settings.labels.sidebarSections.areas,
                createLabel: "Area",
                onCreate: { createArea() }
            ) {
                ForEach(areaManager.areas) { area in
                    AreaRow(
                        area: area,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.area(area.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        areaManager.reorderAreas(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            TierDisclosureRow(
                label: settingsManager.settings.labels.sidebarSections.topics,
                createLabel: "Topic",
                onCreate: { createTopic() }
            ) {
                ForEach(topicManager.topics) { topic in
                    TopicRow(
                        topic: topic,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.topic(topic.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        topicManager.reorderTopics(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            TierDisclosureRow(
                // Reuses the existing entity label pair — no new settings key
                // (second-pass ruling; sidebarSections gains nothing).
                label: settingsManager.settings.labels.project.plural,
                createLabel: settingsManager.settings.labels.project.singular,
                onCreate: { createProject() }
            ) {
                ForEach(projectManager.projects) { project in
                    ProjectRow(
                        project: project,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.project(project.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        projectManager.reorderProjects(fromOffsets: source, toOffset: destination)
                    }
                }
            }
        } header: {
            Text("Contexts")
                .foregroundStyle(.secondary)
        }
    }

    // Stub-and-edit creation flows — bodies MOVED VERBATIM from the deleted
    // AreasSection.createArea / TopicsSection.createTopic and TopicRow's
    // deleted createProject, re-pointed at projectManager.create(name:icon:).
    @State private var isCreatingArea: Bool = false
    @State private var isCreatingTopic: Bool = false
    @State private var isCreatingProject: Bool = false

    private func createArea() {
        guard !isCreatingArea else { return }
        isCreatingArea = true
        let existing = areaManager.areas.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Area", existingTitles: existing)
        Task {
            defer { isCreatingArea = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await areaManager.create(name: title, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }

    private func createTopic() {
        guard !isCreatingTopic else { return }
        isCreatingTopic = true
        let existing = topicManager.topics.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Topic", existingTitles: existing)
        Task {
            defer { isCreatingTopic = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await topicManager.create(name: title, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }

    private func createProject() {
        guard !isCreatingProject else { return }
        isCreatingProject = true
        let label = settingsManager.settings.labels.project.singular
        let existing = projectManager.projects.map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingProject = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await projectManager.create(name: title, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }
}

/// A tier container row: DisclosureGroup whose label is `square.grid.2x2` +
/// the tier's settings label. Expand/collapse only — NO `.tag`, never
/// selectable. Creation: context menu + hover "+" (the affordances the old
/// SectionHeader carried).
struct TierDisclosureRow<Children: View>: View {
    let label: String
    let createLabel: String
    let onCreate: () -> Void
    @ViewBuilder let children: () -> Children

    @State private var expanded: Bool = false
    @State private var hovered: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            children()
        } label: {
            HStack(spacing: PUI.Spacing.md) {
                Image(systemName: "square.grid.2x2")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16, alignment: .center)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
                .allowsHitTesting(hovered)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
            .padding(.leading, PUI.Spacing.xs)
            .padding(.vertical, PUI.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .contextMenu {
                Button("New \(createLabel)") { onCreate() }
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }
}
