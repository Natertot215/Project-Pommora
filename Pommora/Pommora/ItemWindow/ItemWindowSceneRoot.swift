import SwiftUI

/// T4.3 — scene root for the floating Item Window. Hosted by
/// `WindowGroup(for: ItemRef.self)` in `PommoraApp`; takes an `ItemRef`, reaches
/// the live per-Nexus environment via `AppGlobals.current` (a static, NOT an
/// `@Environment` — so the scene root itself can never SIGTRAP on an un-injected
/// manager), resolves the ref to its Item + Type + Set, and hosts
/// `ItemWindowRenderer` directly in a real titled floating window.
///
/// **Quirk #15 safety.** The renderer reads several `@Environment(Manager)`
/// values (ContextDisplayResolver, TierConfigManager, ItemTypeManager). Those
/// are satisfied by `.injectNexusEnvironment(env)` applied in
/// `ItemWindowSceneContent`. Nothing in THIS file reads a per-Nexus manager
/// through `@Environment` outside that modifier — the env is passed as a plain
/// value and the managers are read off it directly.
struct ItemWindowSceneRoot: View {
    let ref: ItemRef

    var body: some View {
        if let env = AppGlobals.current {
            ItemWindowSceneContent(ref: ref, env: env)
        } else {
            // Cold-launch restore before any Nexus opened — render a small label
            // rather than crash. `.restorationBehavior(.disabled)` on the scene
            // should normally prevent this path entirely.
            Text("No Nexus open")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
    }
}

/// Owns the live `ItemWindowViewModel` for the open Item and injects EVERY
/// per-Nexus manager (`.injectNexusEnvironment`) so the renderer's `@Environment`
/// reads are all satisfied (quirk #15). `ItemContentManager` loads its Items
/// lazily on detail-view appear, so a freshly-opened window may resolve `nil` for
/// an Item whose container hasn't been browsed yet — the `.task(id: ref)` triggers
/// the container load FIRST, then resolves the ref and constructs the VM on the
/// main actor (never in `View.init` — mirrors `PageEditorHost`).
///
/// **Re-resolve, never value-capture.** Filenames ARE titles, so the manager
/// seams derive each file URL from `item.title`. The VM's seam closures therefore
/// must NOT close over the resolved `Item` by value: after a rename `vm.item`
/// updates but a value-captured copy would still hold the stale title, so the next
/// write would target a file that no longer exists. Each closure instead captures
/// the manager + stable IDs and re-resolves the current Item via `currentItem()`
/// (the manager's cache is kept current by `renameItem`).
private struct ItemWindowSceneContent: View {
    let ref: ItemRef
    let env: NexusEnvironment

    @State private var vm: ItemWindowViewModel?
    @State private var resolveFailed = false

    /// Thrown by the rename seam when the Item can no longer be resolved (e.g. it
    /// was deleted out from under an open window mid-edit). `onRename` returns an
    /// `Item`, so it can't silently no-op like the void seams — it must throw, and
    /// the VM's `handleTitleCommit` surfaces the message inline + reverts the draft.
    private enum ItemWindowSceneError: Error { case itemUnavailable }

    var body: some View {
        Group {
            if let vm {
                ItemWindowRenderer(vm: vm)
                    // Fresh subtree (and fresh child @State) per Item — mirrors
                    // PageEditorView's `.id(vm.page.id)`. `.task(id: ref)` only
                    // re-fires when `ref` changes, which is the desired per-item re-init.
                    .id(ref)
                    // Window identity: the title bar shows the Item's title (the
                    // user asked for title + icon in the chrome; the icon lands as
                    // a toolbar item in the renderer rework).
                    .navigationTitle(vm.item.title)
            } else if resolveFailed {
                Text("Item no longer available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        // Non-minimizable: this is an auxiliary floating panel tied to Pommora, not
        // a standalone window. `.windowMinimizeBehavior(.disabled)` (macOS 15+,
        // WindowInteractionBehavior) configures the enclosing window in every state.
        .windowMinimizeBehavior(.disabled)
        .injectNexusEnvironment(env)  // quirk #15: satisfies every @Environment the renderer reads.
        // Load the ref's container (so `items(in:)` is populated), THEN resolve +
        // build the VM. Construction lives here — `.task` runs on the main actor,
        // where `@MainActor`-constructing the VM is safe (never in a `View.init`).
        .task(id: ref) {
            await loadContainer()
            buildViewModel()
        }
        // Dismissal safety net: commit BOTH title and body (both VM methods are
        // idempotent). The per-Nexus managers outlive the window, so the
        // fire-and-forget save completes after close.
        .onDisappear {
            Task { [vm] in
                await vm?.handleTitleCommit()
                await vm?.flushBodyNow()
            }
        }
    }

    /// Resolves the ref to its live Item + Type + Set and constructs the VM with
    /// re-resolving seam closures. Sets `resolveFailed` when the chain is missing.
    private func buildViewModel() {
        guard
            let resolved = ref.resolve(
                itemTypeManager: env.itemTypeManager,
                itemContentManager: env.itemContentManager
            )
        else {
            vm = nil
            resolveFailed = true
            return
        }

        let manager = env.itemContentManager
        let itemID = resolved.0.id  // stable across rename
        let itemType = resolved.1
        let collection = resolved.2

        // Re-resolve the current Item by id on every seam call (never capture it
        // by value — a stale title would target a renamed-away file).
        let currentItem: @MainActor () -> Item? = {
            let pool = collection.map { manager.items(in: $0) } ?? manager.items(in: itemType)
            return pool.first { $0.id == itemID }
        }

        vm = ItemWindowViewModel(
            item: resolved.0,
            itemType: itemType,
            collection: collection,
            onUpdateProperty: { id, value in
                guard let cur = currentItem() else { return }
                try await manager.updateItemProperty(
                    cur, propertyID: id, newValue: value, type: itemType, collection: collection)
            },
            onUpdateIcon: { icon in
                guard let cur = currentItem() else { return }
                try await manager.updateItemIcon(cur, to: icon, type: itemType, collection: collection)
            },
            onUpdateBody: { body in
                guard let cur = currentItem() else { return }
                var edited = cur
                edited.description = body
                if let collection {
                    try await manager.updateItem(edited, in: collection, type: itemType, isBodyEdit: true)
                } else {
                    try await manager.updateItem(edited, inTypeRoot: itemType, isBodyEdit: true)
                }
            },
            onRename: { newTitle in
                guard let cur = currentItem() else { throw ItemWindowSceneError.itemUnavailable }
                if let collection {
                    return try await manager.renameItem(cur, to: newTitle, in: collection, type: itemType)
                } else {
                    return try await manager.renameItem(cur, to: newTitle, inTypeRoot: itemType)
                }
            },
            onDeleteItem: {
                guard let cur = currentItem() else { return }
                if let collection {
                    try await manager.deleteItem(cur, in: collection)
                } else {
                    try await manager.deleteItem(cur, inTypeRoot: itemType)
                }
            }
        )
        resolveFailed = false
    }

    /// Loads the Items for the ref's container (Set if present, else Type root)
    /// so `ItemContentManager.items(in:)` is populated before resolution.
    private func loadContainer() async {
        guard let itemType = env.itemTypeManager.types.first(where: { $0.id == ref.typeID }) else { return }
        if let collectionID = ref.collectionID {
            guard
                let collection = env.itemTypeManager.itemCollections(in: itemType)
                    .first(where: { $0.id == collectionID })
            else { return }
            await env.itemContentManager.loadAll(for: collection)
        } else {
            await env.itemContentManager.loadAll(for: itemType)
        }
    }
}
