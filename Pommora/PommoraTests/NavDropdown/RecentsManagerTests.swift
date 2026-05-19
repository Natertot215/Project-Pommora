// RecentsManagerTests.swift
import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("RecentsManager")
struct RecentsManagerTests {
    @Test("record inserts at position 0")
    func recordInsertsAtZero() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        m.record(EntityStateRef(kind: .page, id: "B", title: "Page B"))
        #expect(m.entries.first?.id == "B")
        #expect(m.entries.count == 2)
    }

    @Test("record dedupes existing entries by (kind, id)")
    func recordDedupes() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        m.record(EntityStateRef(kind: .page, id: "B", title: "Page B"))
        m.record(EntityStateRef(kind: .page, id: "A", title: "Page A renamed"))
        #expect(m.entries.count == 2)
        #expect(m.entries[0].id == "A")
        #expect(m.entries[0].title == "Page A renamed")  // title refreshes
    }

    @Test("LRU eviction at cap of 500")
    func lruEviction() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        for i in 0..<510 {
            m.record(EntityStateRef(kind: .page, id: "id\(i)", title: "Page \(i)"))
        }
        #expect(m.entries.count == 500)
        #expect(m.entries.first?.id == "id509")
        #expect(m.entries.last?.id == "id10")  // 0-9 evicted
    }

    @Test("record resets cursor to 0")
    func recordResetsCursor() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        m.record(EntityStateRef(kind: .page, id: "B", title: "Page B"))
        _ = m.stepBack()  // cursor → 1
        #expect(m.cursor == 1)
        m.record(EntityStateRef(kind: .page, id: "C", title: "Page C"))
        #expect(m.cursor == 0)
    }

    @Test("save persists to nexus state.json")
    func savePersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        try await m.save()
        let url = NexusPaths.nexusStateURL(in: nexus)
        let decoded = try AtomicJSON.decode(NexusState.self, from: url)
        #expect(decoded.recents.first?.id == "A")
    }

    @Test("load reads existing state.json on init")
    func loadReadsExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        var seed = NexusState()
        seed.recents = [EntityStateRef(kind: .page, id: "seeded", title: "Seeded")]
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus), withIntermediateDirectories: true)
        try AtomicJSON.write(seed, to: NexusPaths.nexusStateURL(in: nexus))
        let m = RecentsManager(nexus: nexus)
        await m.load()
        #expect(m.entries.first?.id == "seeded")
    }

    @Test("stepBack walks deeper into history")
    func stepBackWalksDeeper() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "A"))
        m.record(EntityStateRef(kind: .page, id: "B", title: "B"))
        m.record(EntityStateRef(kind: .page, id: "C", title: "C"))
        let back = m.stepBack()
        #expect(back?.id == "B")
        #expect(m.cursor == 1)
    }

    @Test("stepBack returns nil at deepest end")
    func stepBackBoundary() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "A"))
        _ = m.stepBack()  // cursor stays at 0 (only 1 entry)
        #expect(m.cursor == 0)
        #expect(m.stepBack() == nil)
    }

    @Test("stepForward moves toward 0")
    func stepForwardMovesToZero() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "A"))
        m.record(EntityStateRef(kind: .page, id: "B", title: "B"))
        _ = m.stepBack()
        let fwd = m.stepForward()
        #expect(fwd?.id == "B")
        #expect(m.cursor == 0)
    }

    @Test("stepForward returns nil at front")
    func stepForwardBoundary() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        m.record(EntityStateRef(kind: .page, id: "A", title: "A"))
        #expect(m.stepForward() == nil)
    }

    @Test("dropdownTop returns first 100 entries")
    func dropdownTopCap() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = RecentsManager(nexus: nexus)
        await m.load()
        for i in 0..<150 {
            m.record(EntityStateRef(kind: .page, id: "id\(i)", title: "Page \(i)"))
        }
        #expect(m.dropdownTop.count == 100)
        #expect(m.dropdownTop.first?.id == "id149")
    }
}
