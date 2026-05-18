import Foundation
import Testing

@testable import Pommora

@Suite("ULIDValidator")
struct ULIDValidatorTests {

    @Test("valid ULID passes")
    func validULID() {
        let id = ULID.generate()
        #expect(ULIDValidator.isValid(id))
    }

    @Test("26 chars of Crockford alphabet passes")
    func crockfordHandwritten() {
        let id = "01HXYZ1234567890ABCDEFGHJK"
        #expect(ULIDValidator.isValid(id))
    }

    @Test("wrong length fails")
    func wrongLength() {
        #expect(!ULIDValidator.isValid("01HXYZ"))
        #expect(!ULIDValidator.isValid(""))
        #expect(!ULIDValidator.isValid(String(repeating: "0", count: 27)))
    }

    @Test("lowercase alpha fails (Crockford is upper)")
    func lowercaseFails() {
        #expect(!ULIDValidator.isValid("01hxyz1234567890abcdefghjk"))
    }

    @Test("Crockford-excluded characters fail")
    func excludedChars() {
        // I, L, O, U are explicitly excluded from Crockford base32
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHI0"))  // contains I
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHL0"))  // contains L
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHO0"))  // contains O
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHU0"))  // contains U
    }
}
