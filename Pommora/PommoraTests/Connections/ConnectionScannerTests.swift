import Testing
@testable import Pommora

@Suite struct ConnectionScannerTests {
    /// `[[ ]]` is the ONLY connection syntax (PagesV2 decision #3): wiki-links
    /// normalize + aggregate, `{{ }}` is never scanned, `![[ ]]` embeds are excluded.
    @Test func scansWikiLinksOnlyNormalizedAndCounted() {
        let body = "See [[ Alpha ]] and {{Beta}}, again [[alpha]]. Image ![[pic]] ignored."
        let found = ConnectionScanner.scan(body: body)
        let alpha = found.first { $0.normalizedTitle == "alpha" }
        #expect(alpha?.multiplicity == 2)
        #expect(found.contains { $0.normalizedTitle == "beta" } == false)
        #expect(found.contains { $0.normalizedTitle == "pic" } == false)
    }
    @Test func normalizeTrimsAndLowercases() {
        #expect(ConnectionTitle.normalize("  Foo Bar ") == "foo bar")
    }
}
