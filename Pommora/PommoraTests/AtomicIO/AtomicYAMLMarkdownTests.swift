import Foundation
import Testing
@testable import Pommora

@Suite("AtomicYAMLMarkdown")
struct AtomicYAMLMarkdownTests {

    private struct Sample: Codable, Equatable {
        var id: String
        var tags: [String]
        var count: Int
    }

    @Test("write + load round-trip with frontmatter and body")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("page.md")

        let original = Sample(id: "01H123", tags: ["a", "b"], count: 3)
        let body = "# Title\n\nSome paragraph.\n"
        try AtomicYAMLMarkdown.write(frontmatter: original, body: body, to: url)

        let (loaded, loadedBody): (Sample, String) =
            try AtomicYAMLMarkdown.load(Sample.self, from: url)
        #expect(loaded == original)
        #expect(loadedBody == body)
    }

    @Test("file with no frontmatter envelope → empty frontmatter, body is whole file")
    func bodyOnlyFile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("body-only.md")
        try FixtureFiles.write("# Just a body\n\nNo metadata here.\n", to: url)

        struct EmptyFM: Codable, Equatable {
            init() {}
        }
        let (fm, body): (EmptyFM, String) = try AtomicYAMLMarkdown.load(EmptyFM.self, from: url)
        #expect(fm == EmptyFM())
        #expect(body == "# Just a body\n\nNo metadata here.\n")
    }

    @Test("malformed envelope (opening --- but no closing) throws")
    func malformedThrows() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("malformed.md")
        try FixtureFiles.write("---\nid: 01H123\nno closing fence\n\nbody here\n", to: url)

        struct FM: Codable { var id: String }
        #expect(throws: AtomicYAMLMarkdown.LoadError.malformedEnvelope) {
            let _: (FM, String) = try AtomicYAMLMarkdown.load(FM.self, from: url)
        }
    }

    @Test("written file starts with --- envelope and contains body verbatim")
    func writeFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("formatted.md")

        let fm = Sample(id: "01H", tags: [], count: 0)
        let body = "Hello\nworld\n"
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: body, to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.hasPrefix("---\n"), "file must open with --- envelope")
        #expect(raw.contains("\n---\n"), "file must contain closing fence")
        #expect(raw.hasSuffix(body), "body must be present verbatim at end")
    }

    @Test("empty body still round-trips")
    func emptyBody() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("empty-body.md")

        let fm = Sample(id: "01H", tags: ["x"], count: 1)
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: url)
        let (loaded, body): (Sample, String) = try AtomicYAMLMarkdown.load(Sample.self, from: url)
        #expect(loaded == fm)
        #expect(body == "")
    }
}
