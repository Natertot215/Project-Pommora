import Foundation

/// Writes drag-reorder results to the appropriate sidecar JSON (v0.2.8.0).
///
/// Top-level sidebar order (Spaces / Topics / Page Types) lives on
/// `<nexus>/.nexus/state.json` — the same file PinnedManager and RecentsManager
/// own. Per-container child order lives on each container's own sidecar
/// (`_schema.json` for Page Types + Page Collections; `_topic.json` for Topics).
///
/// Every write is a read-modify-atomic-write round-trip: the file is
/// re-decoded just before mutation so concurrent writes by sibling managers
/// (PinnedManager, etc.) don't get clobbered.
@MainActor
enum OrderPersister {

    // MARK: - Top-level (state.json)

    static func setSpaceOrder(_ order: [String], in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.spaceOrder = order.isEmpty ? nil : order
        }
    }

    static func setTopicOrder(_ order: [String], in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.topicOrder = order.isEmpty ? nil : order
        }
    }

    static func setVaultOrder(_ order: [String], in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.vaultOrder = order.isEmpty ? nil : order
        }
    }

    // MARK: - Project order (_topic.json)

    static func setProjectOrder(_ order: [String], in topic: Topic, nexus: Nexus) throws {
        let url = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
        var updated = try Topic.load(from: url)
        updated.projectOrder = order.isEmpty ? nil : order
        try updated.save(to: url)
    }

    // MARK: - PageCollection / Page-Type-root Pages + Items (sidecar JSON)

    static func setPageCollectionOrder(_ order: [String], in pageType: PageType, nexus: Nexus) throws {
        try mutatePageType(pageType, nexus: nexus) { t in
            t.collectionOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], in collection: PageCollection) throws {
        try mutatePageCollection(collection) { c in
            c.pageOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], inVault pageType: PageType, nexus: Nexus) throws {
        try mutatePageType(pageType, nexus: nexus) { t in
            t.pageOrder = order.isEmpty ? nil : order
        }
    }

    static func setItemOrder(_ order: [String], inVault pageType: PageType, nexus: Nexus) throws {
        try mutatePageType(pageType, nexus: nexus) { t in
            t.itemOrder = order.isEmpty ? nil : order
        }
    }

    // MARK: - Private read-mutate-write helpers

    private static func mutateNexusState(
        in nexus: Nexus,
        _ mutate: (inout NexusState) -> Void
    ) throws {
        let url = NexusPaths.nexusStateURL(in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus),
            withIntermediateDirectories: true
        )
        var state: NexusState
        if FileManager.default.fileExists(atPath: url.path) {
            state = (try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()
        } else {
            state = NexusState()
        }
        mutate(&state)
        try AtomicJSON.write(state, to: url)
    }

    private static func mutatePageType(
        _ pageType: PageType,
        nexus: Nexus,
        _ mutate: (inout PageType) -> Void
    ) throws {
        let url = NexusPaths.vaultMetadataURL(forTitle: pageType.title, in: nexus)
        var updated = try PageType.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }

    private static func mutatePageCollection(
        _ collection: PageCollection,
        _ mutate: (inout PageCollection) -> Void
    ) throws {
        let url = collection.folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        var updated = try PageCollection.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }
}
