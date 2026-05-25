import Foundation
import Testing

@testable import Pommora

/// Round-trip tests for `DetailRowDragPayload` — the `Transferable` payload
/// carried during table-row drag in detail-pane Tables.
@Suite("DetailRowDragPayloadTests")
struct DetailRowDragPayloadTests {
    @Test("Payload round-trips JSON encoded/decoded")
    func roundTrip() throws {
        let payload = DetailRowDragPayload(rowID: "item_abc", zone: .typeRootItem)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(DetailRowDragPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Zone enum covers all six storage-view contexts")
    func zoneCoverage() {
        let zones: Set<DetailRowDragPayload.Zone> = [
            .typeRootItem, .typeSet, .collectionItem, .vaultPage, .vaultCollection, .setItem
        ]
        #expect(zones.count == 6)
    }
}
