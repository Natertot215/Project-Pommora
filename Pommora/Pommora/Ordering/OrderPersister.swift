import Foundation

/// Writes drag-reorder results to the appropriate sidecar JSON (v0.2.8.0).
///
/// Top-level sidebar order (Areas / Topics / Page Types) lives on
/// `<nexus>/.nexus/state.json` — the same file PinnedManager and RecentsManager
/// own. Per-container child order lives on each container's own per-kind
/// sidecar:
///   - PageType  → `_pagetype.json`
///   - PageCollection → `_pagecollection.json`
///
/// Every write is a read-modify-atomic-write round-trip: the file is
/// re-decoded just before mutation so concurrent writes by sibling managers
/// (PinnedManager, etc.) don't get clobbered.
@MainActor
enum OrderPersister {

    // MARK: - Top-level (state.json)

    static func setAreaOrder(_ order: [String], in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.areaOrder = order.isEmpty ? nil : order
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

    static func setProjectOrder(_ order: [String], in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.projectOrder = order.isEmpty ? nil : order
        }
    }

    static func setActiveView(_ viewID: String, forContainer containerID: String, in nexus: Nexus) throws {
        try mutateNexusState(in: nexus) { state in
            state.activeViews[containerID] = viewID
        }
    }

    // MARK: - PageCollection / Page-Type-root Pages (sidecar JSON)

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

    // MARK: - PageSet (sidecar JSON)

    static func setPageSetOrder(_ order: [String], in collection: PageCollection) throws {
        try mutatePageCollection(collection) { c in
            c.setOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], in set: PageSet) throws {
        try mutatePageSet(set) { s in
            s.pageOrder = order.isEmpty ? nil : order
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

    private static func mutatePageSet(
        _ set: PageSet,
        _ mutate: (inout PageSet) -> Void
    ) throws {
        let url = set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        var updated = try PageSet.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }

}
