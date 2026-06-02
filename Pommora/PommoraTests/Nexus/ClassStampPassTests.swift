import Foundation
import Testing
import Yams

@testable import Pommora

/// Task 5 — launch-time `Class`-stamp pass (Landmine 2).
///
/// `NexusAdopter.autoTagMissingSidecars(at:)` ends each top-level folder's
/// iteration with a per-file `Class`-stamp pass that self-heals the
/// non-authoritative `Class` frontmatter stamp against the folder's
/// authoritative kind (its `_itemtype.json` / `_pagetype.json` sidecar):
///   - `Class` absent → stamped with the folder's kind (value-preserving).
///   - `Class` agrees → left untouched (idempotence).
///   - `Class` disagrees → moved to the hidden `.unsorted/` inbox.
///   - non-mapping frontmatter root → `setStampKey` throws, caught → `.unsorted`.
///
/// These tests drive the public auto-tag entry over a temp nexus and assert the
/// resulting on-disk state (stamp added / preserved / file relocated).
@MainActor
@Suite("ClassStampPass")
struct ClassStampPassTests {

    // MARK: - Helpers

    /// Writes a recognized Type sidecar so the folder reads as a Page/Item Type
    /// and the stamp pass picks the corresponding kind. Auto-tag never rewrites
    /// an existing recognized sidecar, so the folder kind is pinned by this.
    private func writeItemTypeSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCITEMTYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        )
    }

    private func writePageTypeSidecar(at folder: URL) throws {
        try FixtureFiles.writeJSON(
            #"{"id":"01HABCPAGETYPE","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
    }

    /// Reads a file's frontmatter back as an ordered Yams mapping.
    private func mapping(at url: URL) throws -> Node.Mapping {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        guard case .mapping(let m)? = try Yams.compose(yaml: fm) else {
            Issue.record("frontmatter at \(url.lastPathComponent) did not parse as a mapping")
            return .init([])
        }
        return m
    }

    /// Lenient `Class`-key read — mirrors production's `readClassStamp` split/compose.
    /// A file with no frontmatter or a non-mapping root has no `Class` key, so this
    /// returns `nil` rather than routing through `mapping(at:)`'s `Issue.record`.
    private func classValue(at url: URL) throws -> String? {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        guard !fm.isEmpty, case .mapping(let m)? = try Yams.compose(yaml: fm) else {
            return nil
        }
        return m[Node("Class")]?.string
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 1. Stampless .md in an Item Type gains `Class: item`, foreign keys intact

    @Test("stampless .md in an item Type gains Class: item, foreign keys intact, no id injected")
    func stamplessFileGainsItemClass() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        // A foreign file: frontmatter with a non-Pommora key, no `Class`, no id.
        let file = typeFolder.appendingPathComponent("foreign.md")
        let original = """
            ---
            tags: [alpha, beta]
            author: someone
            ---
            Body text stays.
            """
        try FixtureFiles.write(original, to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Gains Class: item.
        #expect(try classValue(at: file) == "item")

        // Foreign keys survive; NO id / tier / properties injected.
        let map = try mapping(at: file)
        let keys = Set(map.compactMap { $0.0.string })
        #expect(keys.contains("tags"))
        #expect(keys.contains("author"))
        #expect(!keys.contains("id"))
        #expect(!keys.contains("tier1"))
        #expect(!keys.contains("properties"))
        // Only Class was added beyond the originals.
        #expect(keys == ["tags", "author", "Class"])

        // Body preserved.
        let (_, body) = try AtomicYAMLMarkdown.split(try String(contentsOf: file, encoding: .utf8))
        #expect(body.contains("Body text stays."))
    }

    // MARK: - 2. Idempotence — run twice, byte-identical

    @Test("running the pass twice is byte-identical (run-2 == run-1)")
    func idempotentAcrossTwoRuns() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        let file = typeFolder.appendingPathComponent("foreign.md")
        try FixtureFiles.write(
            "---\ntags: [alpha]\n---\nBody.\n", to: file
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let afterRun1 = try String(contentsOf: file, encoding: .utf8)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let afterRun2 = try String(contentsOf: file, encoding: .utf8)

        #expect(afterRun1 == afterRun2, "stamp pass drifted on the second run")
        #expect(try classValue(at: file) == "item")
    }

    // MARK: - 2b. Already-correct stamp is not rewritten on FIRST contact (zero I/O)

    @Test("an already-correctly-stamped file is byte-identical after a single pass (no rewrite)")
    func alreadyStampedFileNotRewrittenOnFirstContact() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        // A file that ALREADY agrees with the folder kind (`Class: item`), carrying
        // a comment and a foreign key. The comment is the canary: the agreement
        // path must do NO write, so a YAML reflow (which would drop the comment and
        // reorder/normalize keys) proves a rewrite happened. Captured as raw bytes.
        let file = typeFolder.appendingPathComponent("stamped.md")
        let original = """
            ---
            Class: item
            # keep this comment
            tags: [alpha, beta]
            ---
            Body stays.
            """
        try FixtureFiles.write(original, to: file)
        let before = try String(contentsOf: file, encoding: .utf8)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Byte-identical: the agreement branch returned early with zero I/O on the
        // first pass (distinct from idempotentAcrossTwoRuns, whose run-1 writes).
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after == before, "an already-correct stamp was rewritten on first contact")
        // Still present (not relocated) and still reads as the agreeing kind.
        #expect(exists(file))
        #expect(try classValue(at: file) == "item")
    }

    // MARK: - 3. Disagreeing stamp → moved to .unsorted

    @Test("Class: page in an item Type folder is moved to .unsorted")
    func disagreeingStampMovesToUnsorted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        // A file stamped `Class: page` living inside an Item Type folder.
        let file = typeFolder.appendingPathComponent("mismatch.md")
        try FixtureFiles.write(
            "---\nClass: page\nid: 01HXYZ\n---\nMisplaced page.\n", to: file
        )

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Original location no longer holds the file.
        #expect(!exists(file))

        // It now lives in .unsorted, relative path preserved.
        let relocated = nexus.rootURL
            .appendingPathComponent(".unsorted", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("mismatch.md")
        #expect(exists(relocated))
        // Content untouched (still Class: page).
        #expect(try classValue(at: relocated) == "page")
    }

    // MARK: - 3b. Stray Item-shaped .json in a non-Item-Type folder → .unsorted

    /// A Finder-built folder holds an Item-shaped `.json` but NO `_itemtype.json`
    /// sidecar. Without the sweep, depth-0 tagging force-classifies the folder as a
    /// Page Type and the stamp pass (walks `.md` only) leaves the `.json` orphaned —
    /// never converted, indexed, or relocated. The sweep routes it to `.unsorted`
    /// (tracked + recoverable) BEFORE the folder is page-tagged.
    @Test("a stray Item-shaped .json in a sidecar-less folder is routed to .unsorted")
    func strayItemJSONRoutedToUnsorted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // No `_itemtype.json` — a sidecar-less Finder folder.
        let folder = nexus.rootURL.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A real Item-shaped `.json` (id + timestamps — the legacy decode shape).
        let strayJSON = folder.appendingPathComponent("Stray.json")
        try FixtureFiles.writeJSON(
            #"{"id":"01HSTRAYITEM","description":"a loose item","tier1":[],"tier2":[],"tier3":[],"properties":{},"created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: strayJSON
        )

        let didRelocate = NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        #expect(didRelocate)

        // The stray `.json` is gone from its source path...
        #expect(!exists(strayJSON))
        // ...and recoverable in `.unsorted`, relative path preserved.
        let relocated = nexus.rootURL
            .appendingPathComponent(".unsorted", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent("Stray.json")
        #expect(exists(relocated))
    }

    /// The sweep is conservative: a NON-Item `.json` (no `id` / wrong shape) in a
    /// sidecar-less folder is left in place — only Item-shaped content moves.
    @Test("a non-Item .json in a sidecar-less folder is left untouched")
    func nonItemJSONLeftInPlace() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL.appendingPathComponent("Config", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configJSON = folder.appendingPathComponent("settings.json")
        try FixtureFiles.writeJSON(#"{"theme":"dark","zoom":2}"#, to: configJSON)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Not Item-shaped → not swept; still at its source path.
        #expect(exists(configJSON))
        #expect(
            !FileManager.default.fileExists(
                atPath: nexus.rootURL.appendingPathComponent(".unsorted").path
            ))
    }

    // MARK: - 4. Metrics case — Type sidecar but no .md → no-op

    @Test("a Type folder with no .md files is a no-op (Metrics case)")
    func typeFolderWithoutMarkdownIsNoOp() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)
        // A stray non-.md file — must not be touched.
        let jsonFile = typeFolder.appendingPathComponent("legacy.json")
        try FixtureFiles.write(#"{"k":"v"}"#, to: jsonFile)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // No .unsorted created, no stamps, json untouched.
        let unsorted = nexus.rootURL.appendingPathComponent(".unsorted", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: unsorted.path))
        #expect(exists(jsonFile))
        #expect(try String(contentsOf: jsonFile, encoding: .utf8) == #"{"k":"v"}"#)
    }

    // MARK: - 5. Pommora/ subfolder is skipped

    @Test("a Pommora/ subfolder at root is skipped (never stamped)")
    func pommoraSubfolderSkipped() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // An embedded repo named `Pommora` at the nexus root.
        let pommora = nexus.rootURL.appendingPathComponent("Pommora", isDirectory: true)
        try FileManager.default.createDirectory(at: pommora, withIntermediateDirectories: true)
        let file = pommora.appendingPathComponent("README.md")
        try FixtureFiles.write("# Source code\n", to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Not stamped, not relocated, no type sidecar written.
        #expect(exists(file))
        #expect(try classValue(at: file) == nil)
        #expect(!exists(pommora.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)))
        #expect(
            !FileManager.default.fileExists(
                atPath: nexus.rootURL.appendingPathComponent(".unsorted").path
            ))
    }

    @Test("a worktrees/ subfolder at root is skipped (never stamped)")
    func worktreesSubfolderSkipped() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let worktrees = nexus.rootURL.appendingPathComponent("worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: worktrees, withIntermediateDirectories: true)
        let file = worktrees.appendingPathComponent("branch.md")
        try FixtureFiles.write("# worktree\n", to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        #expect(exists(file))
        #expect(try classValue(at: file) == nil)
        #expect(!exists(worktrees.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)))
    }

    // MARK: - 6. Flow-style / comment foreign Page → Class: page, value preserved

    @Test("flow-style + comment foreign Page in a page Type gains Class: page, values preserved")
    func flowStyleForeignPageGainsPageClass() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Articles", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writePageTypeSidecar(at: typeFolder)

        // Flow-style mapping + a comment line — a foreign Page Pommora doesn't model.
        let file = typeFolder.appendingPathComponent("flow.md")
        let original = """
            ---
            # a comment line
            meta: {a: 1, b: 2}
            tags: [x, y]
            ---
            Article body.
            """
        try FixtureFiles.write(original, to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Gains Class: page; not relocated (stayed put).
        #expect(exists(file))
        #expect(try classValue(at: file) == "page")

        // Foreign values survive the reflow.
        let map = try mapping(at: file)
        #expect(map[Node("tags")] != nil)
        if case .mapping(let metaMap)? = map[Node("meta")] {
            #expect(metaMap[Node("a")]?.int == 1)
            #expect(metaMap[Node("b")]?.int == 2)
        } else {
            Issue.record("expected `meta` to survive as a mapping with a=1, b=2")
        }
    }

    // MARK: - 7. Non-mapping frontmatter root (bare sequence) → moved to .unsorted

    @Test("non-mapping (bare sequence) frontmatter root is moved to .unsorted, not clobbered")
    func nonMappingFrontmatterMovesToUnsorted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try writeItemTypeSidecar(at: typeFolder)

        // Frontmatter root is a bare SEQUENCE — not a key/value mapping.
        let file = typeFolder.appendingPathComponent("seq.md")
        let original = """
            ---
            - alpha
            - beta
            ---
            Body that must not be lost.
            """
        try FixtureFiles.write(original, to: file)

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        // Routed to .unsorted; original gone.
        #expect(!exists(file))
        let relocated = nexus.rootURL
            .appendingPathComponent(".unsorted", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent("seq.md")
        #expect(exists(relocated))

        // Content NOT clobbered — still the original bytes.
        #expect(try String(contentsOf: relocated, encoding: .utf8) == original)
    }
}
