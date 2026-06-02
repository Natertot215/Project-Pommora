import Foundation
import Testing

@testable import Pommora

/// Tests for the sidecar-less content-sniff classification path.
///
/// Since Items became `.md` (Items-as-Markdown), content-sniffing reads file
/// extensions, not frontmatter — so it can no longer distinguish an Item-Type
/// folder from a Page-Type folder. A sidecar-less folder therefore ALWAYS
/// adopts as a Page Type, regardless of whether it holds `.md` or `.json`
/// children. Item-Type identity comes solely from a hand-added
/// `_itemtype.json` sidecar, recognized upstream before content-sniff runs.
///
/// `contentSniff` is private, so these exercise it through the public surface:
///   - `NexusAdopter.scan` → fresh-folder classification (`freshSidecars`).
///   - `NexusAdopter.autoTagMissingSidecars` → depth-0 sidecar writing.
@MainActor
@Suite("ContentSniff")
struct ContentSniffTests {

    // MARK: - markdown children → Page Type

    @Test("sidecar-less folder with .md children classifies as Page Type")
    func markdownChildrenArePageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Today", to: folder.appendingPathComponent("Today.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageType)
    }

    // MARK: - empty folder → Page Type (default)

    @Test("empty sidecar-less folder defaults to Page Type")
    func emptyFolderDefaultsToPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageType)
    }

    // MARK: - the behavior change: .json children → Page Type (NOT Item Type)

    @Test("sidecar-less folder with user .json children now classifies as Page Type")
    func jsonChildrenNoLongerInferItemType() throws {
        // The Task 4 behavior change. Pre-Task-4 a `.json`-only folder was
        // sniffed as an ItemType (`hasUserJSON` → `.itemType`). Now that Items
        // are `.md`, that inference is wrong and removed: a sidecar-less folder
        // with `.json` children adopts as a Page Type.
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
        #expect(plan.freshSidecars.first?.kind == .pageType)
    }

    // MARK: - auto-tag writes a PageType sidecar for a sidecar-less .md folder

    @Test("auto-tag writes _pagetype.json (not _itemtype.json) for a sidecar-less folder")
    func autoTagSidecarLessFolderWritesPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Stray", to: folder.appendingPathComponent("Stray.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let ptMeta = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let itMeta = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: ptMeta.path))
        #expect(!FileManager.default.fileExists(atPath: itMeta.path))
    }

    // MARK: - Item Types are still recognized — via the sidecar (upstream)

    @Test("a folder carrying _itemtype.json stays an Item Type (sidecar wins, not content-sniff)")
    func sidecarItemTypeRecognizedUpstream() throws {
        // Item-Type identity now lives in the sidecar, recognized upstream
        // BEFORE content-sniff runs (`tagDepth0IfMissing` early-returns when a
        // recognized sidecar exists). With an `_itemtype.json` present, the
        // auto-tagger neither overwrites it nor reclassifies the folder as a
        // Page Type — even though its children are `.md`.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HSIDECARITEM","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        )
        try FixtureFiles.write("Risotto\n", to: folder.appendingPathComponent("risotto.md"))

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // ItemType sidecar preserved; no PageType sidecar written.
        let itMeta = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let ptMeta = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: itMeta.path))
        #expect(!FileManager.default.fileExists(atPath: ptMeta.path))
        let it = try ItemType.load(from: itMeta)
        #expect(it.id == "01HSIDECARITEM")
    }
}
