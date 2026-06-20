import Foundation
import Testing

@testable import Pommora

/// A corrupt `state.json` must fail loud, not silently wipe pins/recents/order.
///
/// Before the fix, `OrderPersister.mutateNexusState` used `(try? decode) ?? NexusState()`,
/// so a present-but-unparseable file was replaced with an empty state and written back —
/// destroying every pin, recent, active-view, and order entry. The fix propagates the
/// decode error; managers already funnel order-write errors into a toast.
@MainActor
@Suite("CorruptStateThrowsTests")
struct CorruptStateThrowsTests {

    @Test("order write on a corrupt state.json throws and leaves the file untouched")
    func orderWriteOnCorruptStateThrowsAndPreservesFile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = NexusPaths.nexusStateURL(in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus),
            withIntermediateDirectories: true
        )
        try "{ not valid json".data(using: .utf8)!.write(to: url)

        #expect(throws: (any Error).self) {
            try OrderPersister.setAreaOrder(["a", "b"], in: nexus)
        }

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == "{ not valid json")  // untouched, not wiped
    }
}
