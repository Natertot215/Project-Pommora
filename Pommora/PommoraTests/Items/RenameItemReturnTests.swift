import Testing
import Foundation
@testable import Pommora

@Suite("RenameItemReturn") @MainActor
struct RenameItemReturnTests {
    @Test func renameReturnsRenamedAndRemovesOldFile() async throws {
        let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named: "Errands")
        let created = try await manager.createItem(name: "Buy milk", inTypeRoot: itemType)
        let oldURL = NexusPaths.itemFileURL(forTitle: "Buy milk",
            in: NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Errands"))
        let renamed: Item = try await manager.renameItem(created, to: "Buy oat milk", inTypeRoot: itemType)
        #expect(renamed.title == "Buy oat milk")
        #expect(renamed.id == created.id)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    }
}
