// FavoritesManager.swift
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FavoritesManager {
    private(set) var entries: [EntityStateRef] = []
    var pendingError: (any Error)?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let state = try AtomicJSON.decode(NexusState.self, from: url)
            self.entries = state.favorites
        } catch {
            self.pendingError = error
        }
    }

    func contains(_ ref: EntityStateRef) -> Bool {
        entries.contains(ref)
    }

    /// Add if absent, remove if present (by (kind, id)).
    func toggle(_ ref: EntityStateRef) {
        if let idx = entries.firstIndex(of: ref) {
            entries.remove(at: idx)
        } else {
            entries.append(ref)
        }
        Task { try? await save() }
    }

    /// SwiftUI `.onMove(perform:)` shape.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        Task { try? await save() }
    }

    func save() async throws {
        let url = NexusPaths.nexusStateURL(in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus),
            withIntermediateDirectories: true
        )
        var state: NexusState
        if FileManager.default.fileExists(atPath: url.path) {
            state = (try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()
        } else {
            state = NexusState()
        }
        state.favorites = entries
        do {
            try AtomicJSON.write(state, to: url)
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
