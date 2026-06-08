import Foundation

@testable import Pommora

extension TempNexus {
    /// Creates a fresh TempNexus with a single ItemType folder + sidecar on disk
    /// and a ready `ItemContentManager`. No test assertions — pure fixture setup
    /// for ItemsV2 tests that need a real filesystem root.
    @MainActor
    static func itemTypeRoot(named name: String) async throws
        -> (nexus: Nexus, itemType: ItemType, manager: ItemContentManager)
    {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(),
            title: name,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: name))
        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, manager)
    }

    /// Re-opens an existing TempNexus with a fresh `ItemContentManager` —
    /// useful for round-trip tests that want to reload state from disk.
    @MainActor
    static func reopen(_ nexus: Nexus) -> ItemContentManager {
        ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
    }
}
