import Foundation
import Testing
@testable import Pommora

@Suite("ReservedPropertyID") struct ReservedPropertyIDTests {
    @Test func reservedIDsAreRecognised() {
        for reserved in [
            "_id", "_created_at", "_modified_at",
            "_status",
            "_tier1", "_tier2", "_tier3",
            "_wikilinks",
        ] {
            #expect(ReservedPropertyID.isReserved(reserved))
        }
    }

    @Test func userPropertyIDsAreNotReserved() {
        #expect(!ReservedPropertyID.isReserved("prop_01HABC"))
        #expect(!ReservedPropertyID.isReserved("custom"))
        #expect(!ReservedPropertyID.isReserved(""))
        // The bare display name "status" (no underscore prefix) is NOT reserved —
        // only the ID `_status` is. Per L9.
        #expect(!ReservedPropertyID.isReserved("status"))
    }

    @Test func mintGeneratesPropPrefixedULID() {
        let id = ReservedPropertyID.mintUserPropertyID()
        #expect(id.hasPrefix("prop_"))
        // ULID is 26 chars; total length is "prop_" (5) + 26 = 31.
        #expect(id.count == 31)
        // The minted ID itself must not collide with the reserved set.
        #expect(!ReservedPropertyID.isReserved(id))
    }

    @Test func mintReturnsDistinctIDsOnSuccessiveCalls() {
        let a = ReservedPropertyID.mintUserPropertyID()
        let b = ReservedPropertyID.mintUserPropertyID()
        #expect(a != b)
    }
}
