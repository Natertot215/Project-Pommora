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
            tier3: ["01HPROJECT0"],
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
        #expect(loaded.frontmatter.tier3 == ["01HPROJECT0"])
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

    @Test("foldedHeadings round-trips through YAML")
    func foldedHeadingsRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Folded.md")

        let folded = ["## Implementation notes", "### Edge cases"]
        let fm = PageFrontmatter(
            id: "01HFOLD",
            icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1_716_000_000),
            foldedHeadings: folded
        )
        try PageFile(frontmatter: fm, body: "# Folded\n\nBody.\n").save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("folded_headings:"))

        let loaded = try PageFile.load(from: url)
        #expect(loaded.frontmatter.foldedHeadings == folded)
    }

    @Test("foldedHeadings omitted from YAML when nil or empty")
    func foldedHeadingsOmitWhenEmpty() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let nilURL = nexus.rootURL.appendingPathComponent("Nil.md")
        let emptyURL = nexus.rootURL.appendingPathComponent("Empty.md")

        let baseFM = PageFrontmatter(
            id: "01HNIL", icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        try PageFile(frontmatter: baseFM, body: "").save(to: nilURL)

        var emptyFM = baseFM
        emptyFM.id = "01HEMPTY"
        emptyFM.foldedHeadings = []
        try PageFile(frontmatter: emptyFM, body: "").save(to: emptyURL)

        let nilRaw = try String(contentsOf: nilURL, encoding: .utf8)
        let emptyRaw = try String(contentsOf: emptyURL, encoding: .utf8)
        #expect(!nilRaw.contains("folded_headings"))
        #expect(!emptyRaw.contains("folded_headings"))

        // Decoded back, both round-trip to nil — no spurious empty array.
        let nilLoaded = try PageFile.load(from: nilURL)
        let emptyLoaded = try PageFile.load(from: emptyURL)
        #expect(nilLoaded.frontmatter.foldedHeadings == nil)
        #expect(emptyLoaded.frontmatter.foldedHeadings == nil)
    }

    @Test("foldedHeadings tolerates missing key from older files")
    func foldedHeadingsLegacyAbsent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Legacy.md")

        // Hand-write a pre-foldable-headings frontmatter envelope (no key).
        let legacy = """
            ---
            id: 01HLEGACY
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-22T00:00:00Z
            ---
            # Body
            """
        try FixtureFiles.write(legacy, to: url)

        let loaded = try PageFile.load(from: url)
        #expect(loaded.frontmatter.foldedHeadings == nil)
    }
}
