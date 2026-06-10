import SwiftUI

/// Inline context-link / tier value editor: shows the current value as icon + title
/// chips (or an "Add" affordance when empty) and presents the grouped
/// `ContextPicker` in a chromeless popover on tap.
///
/// This is the reusable inline-editing + picker-hosting unit — `PropertyEditorRow`
/// (relation properties) and the Page inspector's tier rows compose it rather
/// than each re-hosting a popover. The picker owns its own fixed
/// size (the `9deb818` anti-collapse), so presenting it chromeless
/// (`.presentationBackground(.clear)`) never collapses. A nil `resolver` falls back
/// to a count label; a nil `index` still presents the picker (which shows its own
/// empty state).
struct ContextValueEditor: View {
    @Binding var ids: [String]
    let scope: PropertyDefinition.RelationTarget
    let index: PommoraIndex?
    var resolver: ContextDisplayResolver? = nil

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            trigger
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ContextPicker(
                selectedIDs: $ids,
                scope: scope,
                index: index,
                onSelect: { ids = $0 }
            )
            .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private var trigger: some View {
        if ids.isEmpty {
            Label("Add", systemImage: "plus.circle")
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let resolver {
            HStack(spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                    if let resolved = resolver.resolve(id) {
                        ContextChip(icon: resolved.icon, title: resolved.title)
                    } else {
                        Text("(missing)").font(.callout.italic()).foregroundStyle(.tertiary)
                    }
                }
            }
            .task(id: ids) { await resolver.warm(ids) }
        } else {
            Text("\(ids.count) linked").font(.callout).foregroundStyle(.secondary)
        }
    }
}
