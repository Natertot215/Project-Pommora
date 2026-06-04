import SwiftUI

/// T4.3 — scene root for the floating Item Window. Hosted by
/// `WindowGroup(for: ItemRef.self)` in `PommoraApp`; takes an `ItemRef`, reaches
/// the live per-Nexus environment via `AppGlobals.current` (a static, NOT an
/// `@Environment` — so the scene root itself can never SIGTRAP on an un-injected
/// manager), resolves the ref to its Item + Type + Set, and hosts
/// `ItemWindowRenderer` wrapped in `PreviewWindow` chrome.
///
/// **Quirk #15 safety.** The renderer reads several `@Environment(Manager)`
/// values (RelationDisplayResolver, TierConfigManager, ItemTypeManager). Those
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
            // Cold-launch restore before any Nexus opened — render a small card
            // rather than crash. `.restorationBehavior(.disabled)` on the scene
            // should normally prevent this path entirely.
            PreviewWindow {
                Text("No Nexus open")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

/// Resolves the `ItemRef` against the live env and injects EVERY per-Nexus
/// manager (`.injectNexusEnvironment`) so the renderer's `@Environment` reads are
/// all satisfied (quirk #15). `ItemContentManager` loads its Items lazily on
/// detail-view appear, so a freshly-opened window may resolve `nil` for an Item
/// whose container hasn't been browsed yet — a `.task` triggers the container
/// load first. `ItemContentManager` is `@Observable` and `body` reads its
/// `items(in:)` through `ref.resolve`, so the load's mutation re-runs the resolve
/// and the renderer appears with no explicit refresh trigger.
private struct ItemWindowSceneContent: View {
    let ref: ItemRef
    let env: NexusEnvironment

    var body: some View {
        Group {
            if let resolved = ref.resolve(
                itemTypeManager: env.itemTypeManager,
                itemContentManager: env.itemContentManager
            ) {
                PreviewWindow {
                    ItemWindowRenderer(
                        item: resolved.0,
                        template: TemplateResolver.effective(type: resolved.1, collection: resolved.2),
                        itemType: resolved.1,
                        collection: resolved.2
                    )
                }
            } else {
                PreviewWindow {
                    Text("Item no longer available")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .injectNexusEnvironment(env)  // quirk #15: satisfies every @Environment the renderer reads.
        // Trigger the lazy container load for the ref's container so a cold-open
        // window (container never browsed) still resolves. The live open-path
        // always goes through the already-loaded sidebar, so this is a no-op
        // (re-load) in the common case.
        .task(id: ref) {
            await loadContainer()
        }
    }

    /// Loads the Items for the ref's container (Set if present, else Type root)
    /// so `ItemContentManager.items(in:)` is populated before resolution.
    private func loadContainer() async {
        guard let itemType = env.itemTypeManager.types.first(where: { $0.id == ref.typeID }) else { return }
        if let collectionID = ref.collectionID {
            guard let collection = env.itemTypeManager.itemCollections(in: itemType)
                .first(where: { $0.id == collectionID }) else { return }
            await env.itemContentManager.loadAll(for: collection)
        } else {
            await env.itemContentManager.loadAll(for: itemType)
        }
    }
}
