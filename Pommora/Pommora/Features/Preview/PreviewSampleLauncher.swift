#if DEBUG
    import Foundation

    /// Debug-only: resolves the first available Page (collection roots first, then
    /// collections) and hands its `PageRef` to `open` — shared by the Component
    /// Library's PagePreview launcher and the `-openPreviewSample` launch
    /// argument (screenshot-driven UI verification without scripted clicks).
    @MainActor
    enum PreviewSampleLauncher {
        static func run(env: NexusEnvironment, open: @escaping (PageRef) -> Void) {
            Task { @MainActor in
                // Managers load in parallel after env construction — wait for
                // the collection list (bounded; gives up quietly after ~10s).
                var ticks = 0
                while env.collectionManager.types.isEmpty && ticks < 100 {
                    try? await Task.sleep(for: .milliseconds(100))
                    ticks += 1
                }
                for pageCollection in env.collectionManager.types {
                    await env.contentManager.loadAll(for: pageCollection)
                    if let page = env.contentManager.pages(in: pageCollection).first {
                        open(PageRef(page: page, inCollectionRoot: pageCollection))
                        return
                    }
                    for collection in env.collectionManager.pageCollections(in: pageCollection) {
                        await env.contentManager.loadAll(forCollection: collection)
                        if let page = env.contentManager.pages(inCollection: collection).first {
                            open(PageRef(page: page, in: collection, pageCollection: pageCollection))
                            return
                        }
                    }
                }
            }
        }
    }
#endif
