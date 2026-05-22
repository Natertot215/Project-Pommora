import Foundation
import Testing

@testable import Pommora

@Suite("PageFile lenient")
struct PageFileLenientTests {

    @Test("loadLenient reads bare markdown without frontmatter and synthesizes id")
    func bareMarkdown() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Plain.md")
        try FixtureFiles.write("# Plain\n\nJust a paragraph.\n", to: url)

        let page = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)

        #expect(page.title == "Plain")
        #expect(page.body == "# Plain\n\nJust a paragraph.\n")
        #expect(page.frontmatter.id.hasPrefix("adopted-"))
        #expect(page.frontmatter.tier1.isEmpty)
        #expect(page.frontmatter.tier2.isEmpty)
        #expect(page.frontmatter.tier3.isEmpty)
        #expect(page.frontmatter.properties.isEmpty)
    }

    @Test("loadLenient synthesizes a stable id across loads")
    func stableID() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Stable.md")
        try FixtureFiles.write("body\n", to: url)

        let first = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)
        let second = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)
        #expect(first.frontmatter.id == second.frontmatter.id)
    }

    @Test("loadLenient differentiates ids by relative path")
    func differentPathsGiveDifferentIDs() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url1 = nexus.rootURL.appendingPathComponent("A.md")
        let url2 = nexus.rootURL.appendingPathComponent("B.md")
        try FixtureFiles.write("body\n", to: url1)
        try FixtureFiles.write("body\n", to: url2)

        let a = try PageFile.loadLenient(from: url1, nexusRoot: nexus.rootURL)
        let b = try PageFile.loadLenient(from: url2, nexusRoot: nexus.rootURL)
        #expect(a.frontmatter.id != b.frontmatter.id)
    }

    @Test("loadLenient honors existing id when frontmatter is present")
    func keepsExplicitID() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Real.md")
        let raw = """
            ---
            id: 01HEXPLICIT
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2026-05-01T00:00:00Z
            ---

            body
            """
        try FixtureFiles.write(raw, to: url)

        let page = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)
        #expect(page.frontmatter.id == "01HEXPLICIT")
    }

    @Test("loadLenient does not modify the file on disk")
    func noWriteBack() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Untouched.md")
        let original = "# Untouched\n\nObsidian-style.\n"
        try FixtureFiles.write(original, to: url)

        _ = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == original)
    }

    @Test("loadLenient tolerates partial frontmatter (missing id only)")
    func partialFrontmatter() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Partial.md")
        let raw = """
            ---
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            ---

            body
            """
        try FixtureFiles.write(raw, to: url)

        let page = try PageFile.loadLenient(from: url, nexusRoot: nexus.rootURL)
        #expect(page.frontmatter.id.hasPrefix("adopted-"))
    }
}
