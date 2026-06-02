import Foundation
import Testing

@testable import Pommora

/// Item file I/O — Items are `.md`-only (Shape A). Covers the `.md` round-trip
/// (body == description, `Class: item`), the `ItemFrontmatter` serialization
/// shape, foreign-key preservation, and the migration-only legacy `.json`
/// decode (`decodeLegacyJSON`, used solely by `ItemFormatMigration`).
@Suite("ItemFile")
struct ItemFileTests {

    // MARK: - .md round-trip

    @Test("Item round-trips through the .md envelope (body == description)")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.md")

        let original = Item(
            id: "01HITEM",
            title: "Buy groceries",
            icon: "cart",
            description: "Milk, eggs, bread\n\nMore detail in the body.",
            tier1: ["01HSPACE-PERSONAL"],
            tier2: ["01HTOPIC-ERRANDS"],
            tier3: [],
            properties: [
                "status": .select("Active"),
                "due": .date(Date(timeIntervalSince1970: 1716480000)),
            ],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Item.load(from: url)
        #expect(loaded.id == "01HITEM")
        #expect(loaded.title == "Buy groceries")  // filename stem
        #expect(loaded.icon == "cart")
        #expect(loaded.description == "Milk, eggs, bread\n\nMore detail in the body.")
        #expect(loaded.tier1 == ["01HSPACE-PERSONAL"])
        #expect(loaded.tier2 == ["01HTOPIC-ERRANDS"])
        #expect(loaded.tier3 == [])
        #expect(loaded.properties.count == 2)
        #expect(loaded.createdAt == Date(timeIntervalSince1970: 1716000000))
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("Item .md stamps Class: item and keeps the description in the body, not frontmatter")
    func classStampAndBody() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Stamped.md")

        try Item(
            id: "01H", title: "Stamped", icon: nil, description: "the body text",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        // The envelope carries the Class stamp ...
        #expect(raw.contains("Class: item"))
        // ... the body holds the description ...
        #expect(raw.contains("the body text"))
        // ... and `description` is NOT a frontmatter key (it's the body).
        let (fm, body) = try AtomicYAMLMarkdown.split(raw)
        #expect(!fm.contains("description"))
        #expect(body == "the body text")
        // No title field anywhere — filename is the title.
        #expect(!raw.contains("title:"))
    }

    @Test("Item .md frontmatter decodes Class to KindStamp.item")
    func frontmatterKindDecodes() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("K.md")
        try Item(
            id: "01H", title: "K", icon: nil, description: "x",
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)

        let (fm, _): (ItemFrontmatter, String) =
            try AtomicYAMLMarkdown.load(ItemFrontmatter.self, from: url)
        #expect(fm.kind == .item)
    }

    @Test("empty arrays + dict round-trip cleanly")
    func emptyValues() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Z.md")

        try Item(
            id: "01H", title: "Z", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)
        let loaded = try Item.load(from: url)
        #expect(loaded.tier1 == [])
        #expect(loaded.properties.isEmpty)
        #expect(loaded.description == "")
    }

    // MARK: - Foreign-key preservation (preserving write)

    @Test("a foreign frontmatter key survives an Item.save round-trip")
    func foreignKeySurvives() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Foreign.md")

        // Hand-author a valid envelope carrying a foreign (non-modeled) key plus a
        // foreign `description:` frontmatter key (the documented coexistence case).
        let raw = """
            ---
            id: 01HFOREIGN
            Class: item
            plugin_color: "#ff0000"
            description: a foreign frontmatter description
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            ---

            the real body
            """
        try raw.data(using: .utf8)!.write(to: url, options: [.atomic])

        // Load → mutate description → save (preserving write re-reads `url`).
        var item = try Item.load(from: url)
        #expect(item.id == "01HFOREIGN")
        #expect(item.description == "the real body")
        item.description = "edited body"
        try item.save(to: url)

        let after = try String(contentsOf: url, encoding: .utf8)
        // Foreign keys preserved.
        #expect(after.contains("plugin_color"))
        #expect(after.contains("a foreign frontmatter description"))
        // Body updated, no description key emitted by Pommora.
        let (_, body) = try AtomicYAMLMarkdown.split(after)
        #expect(body == "edited body")
    }

    // MARK: - Migration-only legacy .json decode

    @Test("a legacy .json Item decodes via decodeLegacyJSON (migration-only path)")
    func legacyJSONDecodes() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Legacy.json")

        // A genuine legacy `.json` Item (the pre-conversion on-disk shape).
        let original = Item(
            id: "01HLEGACY", title: "Legacy", icon: "doc",
            description: "legacy description",
            tier1: ["01HSPACE"], tier2: [], tier3: [],
            properties: ["k": .select("v")],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        try AtomicJSON.write(original, to: url)

        // The migration-only decoder reads it; title derives from the filename.
        let loaded = try Item.decodeLegacyJSON(from: url)
        #expect(loaded.id == "01HLEGACY")
        #expect(loaded.title == "Legacy")  // filename stem
        #expect(loaded.description == "legacy description")
        #expect(loaded.tier1 == ["01HSPACE"])
        #expect(loaded.properties.count == 1)
    }

    @Test("the general .md read path does NOT decode a legacy .json Item")
    func generalLoadRejectsJSON() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Legacy.json")

        let original = Item(
            id: "01HLEGACY", title: "Legacy", icon: nil, description: "x",
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(), modifiedAt: Date()
        )
        try AtomicJSON.write(original, to: url)

        // `Item.load` is `.md`-only: a JSON payload cannot decode through the
        // YAML-frontmatter envelope, so the general read path throws rather than
        // silently surfacing a `.json` Item.
        #expect(throws: (any Error).self) {
            _ = try Item.load(from: url)
        }
    }

    // MARK: - Timestamp backfill

    @Test("missing created_at/modified_at on a .md Item backfills from file attributes, not 1970")
    func timestampBackfill() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("NoDates.md")

        // A valid envelope with NO created_at / modified_at keys.
        let raw = """
            ---
            id: 01HNODATES
            Class: item
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            ---

            body
            """
        try raw.data(using: .utf8)!.write(to: url, options: [.atomic])

        let epoch = Date(timeIntervalSince1970: 0)
        let loaded = try Item.load(from: url)
        #expect(loaded.createdAt > epoch)
        #expect(loaded.modifiedAt > epoch)

        let lenient = try Item.loadLenient(from: url)
        #expect(lenient.createdAt > epoch)
        #expect(lenient.modifiedAt > epoch)
    }
}
