import Testing
@testable import Pommora

@Suite struct ConnectionScannerTests {
    @Test func scansBothSyntaxesNormalizedAndCounted() {
        let body = "See [[ Alpha ]] and {{Beta}}, again [[alpha]]. Image ![[pic]] ignored."
        let found = ConnectionScanner.scan(body: body)
        let alpha = found.first { $0.normalizedTitle == "alpha" && $0.syntax == .page }
        #expect(alpha?.multiplicity == 2)
        #expect(found.contains { $0.normalizedTitle == "beta" && $0.syntax == .item })
        #expect(found.contains { $0.normalizedTitle == "pic" } == false)
    }
    @Test func normalizeTrimsAndLowercases() {
        #expect(ConnectionTitle.normalize("  Foo Bar ") == "foo bar")
    }
}
