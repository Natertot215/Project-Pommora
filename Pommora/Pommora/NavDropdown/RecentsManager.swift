// RecentsManager.swift
import Foundation
import Observation

@MainActor
@Observable
final class RecentsManager {
    static let storeCap = 500
    static let dropdownCap = 100

    private(set) var entries: [EntityStateRef] = []
    private(set) var cursor: Int = 0
    var pendingError: (any Error)?

    /// When true, sidebar-selection observers should NOT call `record(...)`.
    /// Routing layer sets this around programmatic selection changes
    /// (e.g., back/forward stepping) so the manager doesn't double-record.
    var isNavigatingHistory: Bool = false

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    /// Top of the store, capped for dropdown rendering.
    var dropdownTop: [EntityStateRef] {
        Array(entries.prefix(Self.dropdownCap))
    }

    var canStepBack: Bool { cursor < entries.count - 1 }
    var canStepForward: Bool { cursor > 0 }

    func load() async {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            let state = try AtomicJSON.decode(NexusState.self, from: url)
            // Drop any entries from prior versions that recorded organizational
            // surfaces (Spaces / Topics / Sub-topics / Vaults / Collections);
            // those no longer belong in Recents.
            let filtered = state.recents.filter { ref in
                guard let kind = ref.typedKind else { return false }
                return Self.recordableKinds.contains(kind)
            }
            self.entries = filtered
            self.cursor = min(state.cursor, max(0, filtered.count - 1))
            if filtered.count != state.recents.count {
                Task { try? await save() }
            }
        } catch {
            self.pendingError = error
        }
    }

    /// Only Pages, Items, and Agenda entries belong in Recents. Contexts
    /// (Spaces / Topics / Sub-topics) and Vault containers (Vaults /
    /// Collections) are organizational surfaces — they can still be Pinned,
    /// but selecting them never enters the Recents history.
    static let recordableKinds: Set<EntityStateRef.Kind> = [.page, .item, .agenda]

    func record(_ ref: EntityStateRef) {
        guard let kind = ref.typedKind, Self.recordableKinds.contains(kind) else { return }
        entries.removeAll { $0 == ref }
        entries.insert(ref, at: 0)
        if entries.count > Self.storeCap {
            entries.removeLast(entries.count - Self.storeCap)
        }
        cursor = 0
        Task { try? await save() }
    }

    @discardableResult
    func stepBack() -> EntityStateRef? {
        guard canStepBack else { return nil }
        cursor += 1
        Task { try? await save() }
        return entries[cursor]
    }

    @discardableResult
    func stepForward() -> EntityStateRef? {
        guard canStepForward else { return nil }
        cursor -= 1
        Task { try? await save() }
        return entries[cursor]
    }

    func save() async throws {
        let url = NexusPaths.nexusStateURL(in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus),
            withIntermediateDirectories: true
        )
        // Read-modify-write the shared file (pinned entries managed separately).
        var state: NexusState
        if FileManager.default.fileExists(atPath: url.path) {
            state = (try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()
        } else {
            state = NexusState()
        }
        state.recents = entries
        state.cursor = cursor
        do {
            try AtomicJSON.write(state, to: url)
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
