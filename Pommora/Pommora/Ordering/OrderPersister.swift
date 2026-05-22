import Foundation

/// Writes drag-reorder results to the appropriate sidecar JSON (v0.2.8.0).
///
/// Top-level sidebar order (Spaces / Topics / Vaults) lives on
/// `<nexus>/.nexus/state.json` — the same file PinnedManager and RecentsManager
/// own. Per-container child order lives on each container's own sidecar
/// (`_vault.json`, `_collection.json`, `_topic.json`).
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

    // MARK: - Subtopic order (_topic.json)

    static func setSubtopicOrder(_ order: [String], in topic: Topic, nexus: Nexus) throws {
        let url = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
        var updated = try Topic.load(from: url)
        updated.subtopicOrder = order.isEmpty ? nil : order
        try updated.save(to: url)
    }

    // MARK: - Collection / vault-root Pages + Items (_vault.json / _collection.json)

    static func setCollectionOrder(_ order: [String], in vault: Vault, nexus: Nexus) throws {
        try mutateVault(vault, nexus: nexus) { v in
            v.collectionOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], in collection: Pommora.Collection) throws {
        try mutateCollection(collection) { c in
            c.pageOrder = order.isEmpty ? nil : order
        }
    }

    static func setPageOrder(_ order: [String], inVault vault: Vault, nexus: Nexus) throws {
        try mutateVault(vault, nexus: nexus) { v in
            v.pageOrder = order.isEmpty ? nil : order
        }
    }

    static func setItemOrder(_ order: [String], in collection: Pommora.Collection) throws {
        try mutateCollection(collection) { c in
            c.itemOrder = order.isEmpty ? nil : order
        }
    }

    static func setItemOrder(_ order: [String], inVault vault: Vault, nexus: Nexus) throws {
        try mutateVault(vault, nexus: nexus) { v in
            v.itemOrder = order.isEmpty ? nil : order
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

    private static func mutateVault(
        _ vault: Vault,
        nexus: Nexus,
        _ mutate: (inout Vault) -> Void
    ) throws {
        let url = NexusPaths.vaultMetadataURL(forTitle: vault.title, in: nexus)
        var updated = try Vault.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }

    private static func mutateCollection(
        _ collection: Pommora.Collection,
        _ mutate: (inout Pommora.Collection) -> Void
    ) throws {
        let url = collection.folderURL.appendingPathComponent("_collection.json")
        var updated = try Pommora.Collection.load(from: url)
        mutate(&updated)
        try updated.save(to: url)
    }
}
