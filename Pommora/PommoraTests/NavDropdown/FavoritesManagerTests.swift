// FavoritesManagerTests.swift
import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("FavoritesManager")
struct FavoritesManagerTests {
    @Test("toggle adds missing entry")
    func toggleAdds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = FavoritesManager(nexus: nexus)
        await m.load()
        m.toggle(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        #expect(m.entries.count == 1)
        #expect(m.contains(EntityStateRef(kind: .page, id: "A", title: "ignored")))
    }

    @Test("toggle removes existing entry")
    func toggleRemoves() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = FavoritesManager(nexus: nexus)
        await m.load()
        let ref = EntityStateRef(kind: .page, id: "A", title: "Page A")
        m.toggle(ref)
        m.toggle(ref)
        #expect(m.entries.isEmpty)
    }

    @Test("toggle add appends to end (insertion order)")
    func toggleAppendsEnd() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = FavoritesManager(nexus: nexus)
        await m.load()
        m.toggle(EntityStateRef(kind: .page, id: "A", title: "Page A"))
        m.toggle(EntityStateRef(kind: .page, id: "B", title: "Page B"))
        m.toggle(EntityStateRef(kind: .page, id: "C", title: "Page C"))
        #expect(m.entries.map(\.id) == ["A", "B", "C"])
    }

    @Test("move reorders entries via fromOffsets/toOffset")
    func moveReorders() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = FavoritesManager(nexus: nexus)
        await m.load()
        m.toggle(EntityStateRef(kind: .page, id: "A", title: "A"))
        m.toggle(EntityStateRef(kind: .page, id: "B", title: "B"))
        m.toggle(EntityStateRef(kind: .page, id: "C", title: "C"))
        m.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)  // A → end
        #expect(m.entries.map(\.id) == ["B", "C", "A"])
    }

    @Test("save persists to nexus state.json without clobbering recents")
    func savePreservesRecents() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Seed file with recents
        var seed = NexusState()
        seed.recents = [EntityStateRef(kind: .page, id: "R1", title: "Recent 1")]
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus), withIntermediateDirectories: true)
        try AtomicJSON.write(seed, to: NexusPaths.nexusStateURL(in: nexus))

        let m = FavoritesManager(nexus: nexus)
        await m.load()
        m.toggle(EntityStateRef(kind: .page, id: "F1", title: "Favorite 1"))
        try await m.save()

        let decoded = try AtomicJSON.decode(NexusState.self, from: NexusPaths.nexusStateURL(in: nexus))
        #expect(decoded.favorites.first?.id == "F1")
        #expect(decoded.recents.first?.id == "R1")  // recents preserved
    }

    @Test("load reads existing favorites")
    func loadReadsExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        var seed = NexusState()
        seed.favorites = [EntityStateRef(kind: .page, id: "F1", title: "Pinned")]
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus), withIntermediateDirectories: true)
        try AtomicJSON.write(seed, to: NexusPaths.nexusStateURL(in: nexus))
        let m = FavoritesManager(nexus: nexus)
        await m.load()
        #expect(m.entries.first?.id == "F1")
    }
}
