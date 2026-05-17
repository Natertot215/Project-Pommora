import Foundation
import Testing
@testable import Pommora

@Suite("Collection")
struct CollectionTests {

    @Test("init derives title from folder name + id from URL hash")
    func deriveFromURL() {
        let url = URL(fileURLWithPath: "/tmp/pommora/MyVault/Tasks", isDirectory: true)
        let c = Collection(folderURL: url, vaultID: "01HVAULT")
        #expect(c.title == "Tasks")
        #expect(c.vaultID == "01HVAULT")
        #expect(c.folderURL == url)
        #expect(!c.id.isEmpty)
    }

    @Test("two Collections at same path produce same id")
    func stableID() {
        let url = URL(fileURLWithPath: "/tmp/x/Y/Z", isDirectory: true)
        let a = Collection(folderURL: url, vaultID: "01HV")
        let b = Collection(folderURL: url, vaultID: "01HV")
        #expect(a.id == b.id)
    }

    @Test("Collections at different paths produce different ids")
    func differentPathsDifferentIDs() {
        let a = Collection(
            folderURL: URL(fileURLWithPath: "/tmp/x/Y/Z1", isDirectory: true),
            vaultID: "01HV"
        )
        let b = Collection(
            folderURL: URL(fileURLWithPath: "/tmp/x/Y/Z2", isDirectory: true),
            vaultID: "01HV"
        )
        #expect(a.id != b.id)
    }
}
