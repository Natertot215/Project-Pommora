import AppKit
import Testing
@testable import MarkdownPM

/// CHARACTERIZES the CURRENT number of whole-document Apple parses per
/// supplemental-style pass via direct calls. Phase 3 RETIRES/rewrites these
/// once the parse moves into the cached memo (the second-pass assertion
/// becomes == 0). Asserts against a TINY inline doc because parse count is
/// size-independent — the large fixture is for the Phase-3 Instruments
/// capture, not these counts.
@MainActor
struct ParseCountProbeTests {

    // Size-independent: the count tracks call sites, not document length.
    private static let tinyDoc = "# A\n> q\nbody\n"

    @Test("CURRENT: one supplemental-style pass triggers exactly one whole-doc parse (RETIRED in P3)")
    func supplementalParseCountIsOne() {
        AppleDocumentParseProbe.reset()
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default)
        // CURRENT behavior: the supplemental styler parses the document exactly
        // once per call. Phase 3 routes this through the cache; this direct-call
        // characterization is retired/rewritten when that lands.
        #expect(AppleDocumentParseProbe.count == 1)
    }

    @Test("CURRENT: two passes on identical text re-parse, no cache yet (RETIRED in P3)")
    func uncachedRepeatedParse_currentBehavior() {
        AppleDocumentParseProbe.reset()
        let font = NSFont.systemFont(ofSize: 15)
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc, baseFont: font, theme: .default)
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc, baseFont: font, theme: .default)
        // CURRENT: 2 (no cache). Phase 3 drives the second identical-text pass
        // to a cache hit (count == 1 total); this characterization is then
        // RETIRED/rewritten. This is the #9 regression anchor (ledger #9-PARSE).
        #expect(AppleDocumentParseProbe.count == 2)
    }
}
