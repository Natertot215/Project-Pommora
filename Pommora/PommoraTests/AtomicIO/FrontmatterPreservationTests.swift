import Foundation
import Testing
import Yams

@testable import Pommora

/// Task 1 — order-preserving, foreign-key-retaining frontmatter codec.
///
/// Guards the preserving `write` / `encode` overloads + `setStampKey` on
/// `AtomicYAMLMarkdown`. The OLD codec re-serialized only `CodingKeys`, so any
/// non-modeled ("foreign", e.g. plugin) frontmatter key was silently dropped on
/// the next save — these tests pin that it now survives, that cleared modeled
/// keys actually clear, and that key order is stable across saves.
@Suite("FrontmatterPreservation")
struct FrontmatterPreservationTests {

    // MARK: - Helpers

    /// A `PageFrontmatter` carrying a modeled `icon` (so the cleared-icon path is
    /// exercised by nil-ing it). `created_at` fixed for determinism.
    private func makeFM(id: String, icon: String?) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: icon,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1_716_000_000)
        )
    }

    /// Reads the on-disk frontmatter back as an ordered Yams mapping so tests can
    /// assert both key PRESENCE/value and ORDER independent of the typed model.
    private func mapping(at url: URL) throws -> Node.Mapping {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        guard case .mapping(let m)? = try Yams.compose(yaml: fm) else {
            Issue.record("frontmatter at \(url.lastPathComponent) did not parse as a mapping")
            return .init([])
        }
        return m
    }

    private func orderedKeys(_ m: Node.Mapping) -> [String] {
        m.compactMap { $0.0.string }
    }

    // MARK: - 1. Foreign survives + cleared clears + order stable across two saves

    @Test("foreign key survives, cleared modeled key clears, order stable across two saves")
    func foreignSurvivesClearedClearsOrderStable() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Plugin.md")

        // Hand-write a file with modeled keys (incl. `icon`) AND a foreign plugin
        // key (`tags`) that PageFrontmatter does not model.
        let original = """
            ---
            id: 01HPLUGIN
            icon: star.fill
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            tags:
              - alpha
              - beta
            ---
            # Plugin page

            Body text.
            """
        try FixtureFiles.write(original, to: url)

        // Save #1: load, clear the modeled `icon` (nil), write back preserving.
        var page = try PageFile.load(from: url)
        #expect(page.frontmatter.icon == "star.fill")
        page.frontmatter.icon = nil  // cleared modeled key
        try page.save(to: url)

        let map1 = try mapping(at: url)
        // Foreign key survived with its value.
        guard case .sequence(let tags1)? = map1[Node("tags")] else {
            Issue.record("foreign `tags` key was dropped on save #1")
            return
        }
        #expect(tags1.compactMap { $0.string } == ["alpha", "beta"])
        // Cleared modeled key is gone.
        #expect(map1[Node("icon")] == nil)
        let body1 = try String(contentsOf: url, encoding: .utf8)
        #expect(body1.contains("# Plugin page"))

        let keys1 = orderedKeys(map1)

        // Save #2: re-load and re-save (no changes) — order must be idempotent.
        let page2 = try PageFile.load(from: url)
        try page2.save(to: url)
        let map2 = try mapping(at: url)
        let keys2 = orderedKeys(map2)

        #expect(keys1 == keys2, "key order drifted between save #1 and save #2: \(keys1) vs \(keys2)")
        // Foreign key still present after the second save.
        #expect(map2[Node("tags")] != nil)
        // `created_at` (existing) precedes `tags` (existing) — original order held.
        #expect(keys2.firstIndex(of: "created_at")! < keys2.firstIndex(of: "tags")!)
    }

    // MARK: - 2. setStampKey on a frontmatter-less foreign file

    @Test("setStampKey on body-only file adds ONLY Class, keeps body")
    func setStampKeyOnBodyOnlyFile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("BodyOnly.md")

        let bodyOnly = "# Just a body\n\nNo frontmatter here.\n"
        try FixtureFiles.write(bodyOnly, to: url)

        try AtomicYAMLMarkdown.setStampKey(at: url, value: "item")

        let map = try mapping(at: url)
        // ONLY the Class key — no id / tier / properties injected.
        #expect(orderedKeys(map) == ["Class"])
        #expect(map[Node("Class")]?.string == "item")

        // Body preserved verbatim.
        let (_, body) = try AtomicYAMLMarkdown.split(
            try String(contentsOf: url, encoding: .utf8))
        #expect(body == bodyOnly)
    }

    // MARK: - 3. setStampKey idempotence

    @Test("setStampKey is idempotent across repeated runs")
    func setStampKeyIdempotent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Stamp.md")
        try FixtureFiles.write("Body.\n", to: url)

        try AtomicYAMLMarkdown.setStampKey(at: url, value: "item")
        let after1 = try String(contentsOf: url, encoding: .utf8)

        try AtomicYAMLMarkdown.setStampKey(at: url, value: "item")
        let after2 = try String(contentsOf: url, encoding: .utf8)

        #expect(after1 == after2, "setStampKey drifted on the second run")
    }

    // MARK: - 4. Flow-style / comment fixture (value-preserving, accepts reflow)

    @Test("flow-style + comment foreign frontmatter: value preserved (reflow OK)")
    func flowStyleAndCommentValuePreserved() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Flow.md")

        // `tags` foreign, flow style; plus a YAML comment.
        let original = """
            ---
            id: 01HFLOW
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            # a leading comment
            tags: [x, y]
            ---
            Body.
            """
        try FixtureFiles.write(original, to: url)

        let page = try PageFile.load(from: url)
        try page.save(to: url)

        let map = try mapping(at: url)
        // Value preserved (style may reflow block↔flow, comments may drop).
        guard case .sequence(let tags)? = map[Node("tags")] else {
            Issue.record("flow-style foreign `tags` was dropped")
            return
        }
        #expect(tags.compactMap { $0.string } == ["x", "y"])
    }

    // MARK: - 5. Empty-body round-trip guard (envelope/split seam)

    @Test("empty body round-trips through the preserving write")
    func emptyBodyRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("EmptyBody.md")

        // First save creates the file (preservingFrom is the absent dest → fallback).
        try PageFile(frontmatter: makeFM(id: "01HEMPTY", icon: nil), body: "").save(to: url)
        // Second save now merges over the existing file (the preserving path).
        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.body == "")
        try reloaded.save(to: url)

        let loaded = try PageFile.load(from: url)
        #expect(loaded.body == "")
        #expect(loaded.frontmatter.id == "01HEMPTY")
    }

    // MARK: - 6. Foreign key with a NESTED MAPPING (+ nested sequence) survives by value

    @Test("foreign key with a nested mapping + nested sequence value survives by value")
    func foreignNestedMappingSurvivesByValue() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Nested.md")

        // `obsidian` is a foreign plugin block whose value is itself a mapping;
        // `aliases` is a foreign sequence. PageFrontmatter models neither.
        let original = """
            ---
            id: 01HNESTED
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            obsidian:
              cssclass: wide
              pinned: true
            aliases:
              - one
              - two
            ---
            Body.
            """
        try FixtureFiles.write(original, to: url)

        // Preserving write of a PageFrontmatter that does NOT model `obsidian`.
        let page = try PageFile.load(from: url)
        try page.save(to: url)

        let map = try mapping(at: url)

        // The nested-mapping foreign key survives, and its nested values are
        // preserved by value (not just key presence).
        guard case .mapping(let obsidian)? = map[Node("obsidian")] else {
            Issue.record("foreign nested-mapping `obsidian` key was dropped or flattened")
            return
        }
        #expect(obsidian[Node("cssclass")]?.string == "wide")
        #expect(obsidian[Node("pinned")]?.bool == true)

        // The nested-sequence foreign key survives by value too.
        guard case .sequence(let aliases)? = map[Node("aliases")] else {
            Issue.record("foreign nested-sequence `aliases` key was dropped")
            return
        }
        #expect(aliases.compactMap { $0.string } == ["one", "two"])
    }

    // MARK: - 7. Modeled key present-and-CHANGED lands the new value in its original slot

    @Test("changed modeled key substitutes new value in the original slot, order stable")
    func changedModeledKeyLandsInOriginalSlot() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("ChangedIcon.md")

        // `icon` is modeled and present; `tags` is a foreign key after it.
        let original = """
            ---
            id: 01HCHANGED
            icon: star.fill
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            tags:
              - alpha
            ---
            Body.
            """
        try FixtureFiles.write(original, to: url)

        let keysBefore = try orderedKeys(mapping(at: url))

        // Change `icon` to a DIFFERENT non-nil value (substitution branch, NOT clear).
        var page = try PageFile.load(from: url)
        #expect(page.frontmatter.icon == "star.fill")
        page.frontmatter.icon = "bolt.fill"
        try page.save(to: url)

        let map = try mapping(at: url)
        // New value landed.
        #expect(map[Node("icon")]?.string == "bolt.fill")
        // Foreign key still present.
        #expect(map[Node("tags")] != nil)
        // Order unchanged — the original keys keep their positions as a stable
        // prefix; the modeled `Class` stamp (emitted by every typed Page save since
        // Task 2) is appended after them and is the ONLY addition. The substitution
        // of `icon` must not reorder the pre-existing keys.
        let keysAfter = orderedKeys(map)
        #expect(
            Array(keysAfter.prefix(keysBefore.count)) == keysBefore,
            "original key order drifted on a substitution: \(keysBefore) vs \(keysAfter)")
        #expect(
            Set(keysAfter).subtracting(keysBefore) == Set(["Class"]),
            "expected the only added key to be the Class stamp: \(keysAfter)")
        // Explicitly: `icon` still precedes `tags`.
        #expect(keysAfter.firstIndex(of: "icon")! < keysAfter.firstIndex(of: "tags")!)
    }

    // MARK: - 8. setStampKey REFUSES a non-mapping frontmatter root (no clobber)

    @Test("setStampKey throws and leaves the file byte-unchanged for non-mapping frontmatter")
    func setStampKeyRefusesNonMappingFrontmatter() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("SeqFrontmatter.md")

        // Frontmatter root is a bare SEQUENCE — not a key/value mapping.
        let original = """
            ---
            - alpha
            - beta
            ---
            Body that must not be lost.
            """
        try FixtureFiles.write(original, to: url)
        let before = try String(contentsOf: url, encoding: .utf8)

        #expect(throws: AtomicYAMLMarkdownError.self) {
            try AtomicYAMLMarkdown.setStampKey(at: url, value: "item")
        }

        // File left byte-identical — nothing destroyed.
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == before, "setStampKey clobbered a non-mapping frontmatter file")
    }

    // MARK: - VERIFY: envelope shape (one trailing newline on fm, no inner fences)

    @Test("envelope: closing fence on own line, no inner --- or ... markers")
    func envelopeShapeIsClean() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Envelope.md")

        let original = """
            ---
            id: 01HENV
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2024-05-18T00:00:00Z
            tags:
              - one
            ---
            Body line.
            """
        try FixtureFiles.write(original, to: url)
        let page = try PageFile.load(from: url)
        try page.save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.hasPrefix("---\n"))
        // Exactly one opening + one closing fence: splitting on "\n---\n" yields 2 parts.
        let parts = raw.components(separatedBy: "\n---\n")
        #expect(parts.count == 2, "expected exactly one closing fence, got \(parts.count - 1)")
        // No inner fence / document-end marker leaked into the frontmatter block.
        let (fm, _) = try AtomicYAMLMarkdown.split(raw)
        #expect(!fm.contains("---"))
        #expect(!fm.contains("\n...\n"))
        // The frontmatter block ends in exactly ONE newline: the envelope is
        // `---\n<fm>---\n\n<body>`, so the captured `parts[0]` (everything before
        // "\n---\n", incl. the opening "---\n") must end with the serialized YAML's
        // single trailing newline — i.e. parts[0] ends with the last fm line, and
        // there is no extra blank line before the closing fence.
        #expect(!parts[0].hasSuffix("\n"), "extra blank line before closing fence")
        // Body separator: exactly one blank line after the closing fence.
        #expect(parts[1].hasPrefix("\n"))
        #expect(!parts[1].hasPrefix("\n\n"))
    }
}
