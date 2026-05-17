import Foundation
import Observation

@MainActor
@Observable
final class SavedConfigManager {
    var config: SavedConfig = SavedConfig.defaultSeed()
    var pendingError: (any Error)?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.savedConfigURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                config = try AtomicJSON.decode(SavedConfig.self, from: url)
            } else {
                config = SavedConfig.defaultSeed()
                try AtomicJSON.write(config, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        let url = NexusPaths.savedConfigURL(in: nexus)
        try AtomicJSON.write(config, to: url)
    }
}
