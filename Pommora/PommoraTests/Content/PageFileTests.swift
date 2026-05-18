import Foundation
import Testing
@testable import Pommora

@Suite("PageFile")
struct PageFileTests {

    @Test("PageFile round-trips frontmatter + body")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Notes.md")

        let fm = PageFrontmatter(
            id: "01HPAGE",
            icon: "doc.text",
            tier1: ["01HSPACE"],
            tier2: [],
            tier3: ["01HSUBTOPIC"],
            properties: ["status": .select("Active")],
            createdAt: Date(timeIntervalSince1970: 1716000000)
        )
        let body = "# Notes\n\nA paragraph.\n"
        let page = PageFile(frontmatter: fm, body: body)
        try page.save(to: url)

        let loaded = try PageFile.load(from: url)
        #expect(loaded.frontmatter.id == "01HPAGE")
        #expect(loaded.frontmatter.icon == "doc.text")
        #expect(loaded.frontmatter.tier1 == ["01HSPACE"])
        #expect(loaded.frontmatter.tier3 == ["01HSUBTOPIC"])
        #expect(loaded.body == body)
        #expect(loaded.title == "Notes")
    }

    @Test("body-only .md (no frontmatter envelope) now throws — id is mandatory (Part 5.1)")
    func bodyOnlyThrows() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Plain.md")
        try FixtureFiles.write("# Plain\n\nJust body.\n", to: url)

        // Per Commit 4 / Part 5.1: PageFrontmatter.id must decode (not be
        // defaulted to ""). A body-only .md decodes the frontmatter from "{}",
        // which lacks the required `id`, so PageFile.load now throws.
        #expect(throws: (any Error).self) {
            _ = try PageFile.load(from: url)
        }
    }

    @Test("frontmatter uses snake_case keys on disk")
    func snakeCaseFrontmatter() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.md")

        try PageFile(
            frontmatter: PageFrontmatter(
                id: "01H", icon: nil, tier1: ["01HA"], tier2: [], tier3: [],
                properties: [:], createdAt: Date(timeIntervalSince1970: 0)
            ),
            body: ""
        ).save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("created_at:"))
        #expect(raw.contains("tier1:"))
    }
}
