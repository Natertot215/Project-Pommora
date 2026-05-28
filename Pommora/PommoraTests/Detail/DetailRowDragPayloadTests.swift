import Foundation
import Testing

@testable import Pommora

/// Round-trip test for `DetailRowDragPayload` — the `Transferable` payload
/// carried during table-row drag in detail-pane Tables.
@Suite("DetailRowDragPayloadTests")
struct DetailRowDragPayloadTests {
    @Test("Payload round-trips JSON encoded/decoded")
    func roundTrip() throws {
        let payload = DetailRowDragPayload(rowID: "item_abc")
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(DetailRowDragPayload.self, from: data)
        #expect(decoded == payload)
    }
}
