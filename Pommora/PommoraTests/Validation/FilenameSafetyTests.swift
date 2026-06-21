import Foundation
import Testing

@testable import Pommora

@Suite("FilenameSafety")
struct FilenameSafetyTests {

    enum E: Error { case empty, bad }

    @Test("trims whitespace and returns the trimmed title")
    func trimsAndReturns() throws {
        let result = try FilenameSafety.validatedTitle(
            "  Hi  ", empty: E.empty, invalidCharacters: E.bad)
        #expect(result == "Hi")
    }

    @Test("whitespace-only title throws the supplied empty error")
    func emptyThrows() {
        #expect(throws: E.empty) {
            _ = try FilenameSafety.validatedTitle(
                "   ", empty: E.empty, invalidCharacters: E.bad)
        }
    }

    @Test("invalid character throws the supplied invalidCharacters error")
    func invalidCharThrows() {
        #expect(throws: E.bad) {
            _ = try FilenameSafety.validatedTitle(
                "a/b", empty: E.empty, invalidCharacters: E.bad)
        }
    }
}
