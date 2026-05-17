import Foundation
import Testing
@testable import Pommora

@Suite("ItemFile")
struct ItemFileTests {

    @Test("Item round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.json")

        let original = Item(
            id: "01HITEM",
            title: "Buy groceries",
            icon: "cart",
            description: "Milk, eggs, bread",
            tier1: ["01HSPACE-PERSONAL"],
            tier2: ["01HTOPIC-ERRANDS"],
            tier3: [],
            properties: [
                "status": .select("Active"),
                "due": .date(Date(timeIntervalSince1970: 1716480000))
            ],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Item.load(from: url)
        #expect(loaded.id == "01HITEM")
        #expect(loaded.title == "Buy groceries")
        #expect(loaded.icon == "cart")
        #expect(loaded.description == "Milk, eggs, bread")
        #expect(loaded.tier1 == ["01HSPACE-PERSONAL"])
        #expect(loaded.tier2 == ["01HTOPIC-ERRANDS"])
        #expect(loaded.tier3 == [])
        #expect(loaded.properties.count == 2)
    }

    @Test("Item on-disk JSON omits title field (filename = title)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.json")

        try Item(
            id: "01H", title: "X", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Item uses snake_case for tier + timestamps + descrption (sic)")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Y.json")
        try Item(
            id: "01H", title: "Y", icon: nil, description: "x",
            tier1: ["01HA"], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"tier1\""))
        #expect(raw.contains("\"created_at\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"description\""))
    }

    @Test("empty arrays + dict round-trip cleanly")
    func emptyValues() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Z.json")

        try Item(
            id: "01H", title: "Z", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)
        let loaded = try Item.load(from: url)
        #expect(loaded.tier1 == [])
        #expect(loaded.properties.isEmpty)
    }
}
