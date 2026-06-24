import Foundation
import Testing

@testable import Pommora

/// Tests for the sidecar-less content-sniff classification path.
///
/// A sidecar-less folder ALWAYS adopts as a Page Type, regardless of whether
/// it holds `.md` or `.json` children (PagesV2 — the item side is retired).
///
/// `contentSniff` is private, so these exercise it through the public surface:
///   - `NexusAdopter.scan` → fresh-folder classification (`freshSidecars`).
///   - `NexusAdopter.autoTagMissingSidecars` → depth-0 sidecar writing.
@MainActor
@Suite("ContentSniff")
struct ContentSniffTests {

    // MARK: - markdown children → Page Type

    @Test("sidecar-less folder with .md children classifies as Page Type")
    func markdownChildrenArePageCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Today", to: folder.appendingPathComponent("Today.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageCollection)
    }

    // MARK: - empty folder → Page Type (default)

    @Test("empty sidecar-less folder defaults to Page Type")
    func emptyFolderDefaultsToPageCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageCollection)
    }

    // MARK: - the behavior change: .json children → Page Type (NOT Item Type)

    @Test("sidecar-less folder with user .json children now classifies as Page Type")
    func jsonChildrenNoLongerInferItemType() throws {
        // Pre-Task-4 a `.json`-only folder was sniffed as an ItemType
        // (`hasUserJSON` → `.itemType`). That inference is removed: a
        // sidecar-less folder with `.json` children adopts as a Page Type.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HI"}"#,
            to: folder.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageCollection)
    }

    // MARK: - auto-tag writes a PageCollection sidecar for a sidecar-less .md folder

    @Test("auto-tag writes _pagetype.json (not _itemtype.json) for a sidecar-less folder")
    func autoTagSidecarLessFolderWritesPageCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Stray", to: folder.appendingPathComponent("Stray.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let ptMeta = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let itMeta = folder.appendingPathComponent("_itemtype.json")
        #expect(FileManager.default.fileExists(atPath: ptMeta.path))
        #expect(!FileManager.default.fileExists(atPath: itMeta.path))
    }
}
