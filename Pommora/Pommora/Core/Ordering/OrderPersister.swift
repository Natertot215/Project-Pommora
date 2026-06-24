import Foundation

/// Writes drag-reorder results to the appropriate sidecar JSON.
///
/// Top-level sidebar order (Areas / Topics / Page Collections) lives on
/// `<nexus>/.nexus/state.json`. Per-container child order lives on each
/// container's own sidecar — `_pagecollection.json` for the top Collection,
/// `_pageset.json` for every Set at any depth.
///
/// Every write is a read-modify-atomic-write round-trip so concurrent writes
/// by sibling managers don't get clobbered.
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
            state.collectionOrder = order.isEmpty ? nil : order
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

    // MARK: - PageSet / Page-Type-root Pages (sidecar JSON)

    static func setPageCollectionOrder(_ order: [String], in pageCollection: PageCollection, nexus: Nexus) throws {
        try mutatePageCollection(pageCollection, nexus: nexus) { t in
            t.collectionOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], inCollection collection: PageSet) throws {
        try mutateSet(collection, sidecar: NexusPaths.pageSetSidecarFilename) { c in
            c.pageOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], inVaultRoot pageCollection: PageCollection, nexus: Nexus) throws {
        try mutatePageCollection(pageCollection, nexus: nexus) { t in
            t.pageOrder = order.isEmpty ? nil : order
        }
    }

    // MARK: - PageSet (sidecar JSON)

    static func setPageSetOrder(_ order: [String], in collection: PageSet) throws {
        try mutateSet(collection, sidecar: NexusPaths.pageSetSidecarFilename) { c in
            c.setOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], in set: PageSet) throws {
        try mutateSet(set, sidecar: NexusPaths.pageSetSidecarFilename) { s in
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
            state = try AtomicJSON.decode(NexusState.self, from: url)
        } else {
            state = NexusState()
        }
        mutate(&state)
        try AtomicJSON.write(state, to: url)
    }

    private static func mutatePageCollection(
        _ pageCollection: PageCollection,
        nexus: Nexus,
        _ mutate: (inout PageCollection) -> Void
    ) throws {
        let url = NexusPaths.vaultMetadataURL(forTitle: pageCollection.title, in: nexus)
        var updated = try PageCollection.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }

    private static func mutateSet(
        _ set: PageSet,
        sidecar: String,
        _ mutate: (inout PageSet) -> Void
    ) throws {
        let url = set.folderURL.appendingPathComponent(sidecar)
        var updated = try PageSet.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }

}
