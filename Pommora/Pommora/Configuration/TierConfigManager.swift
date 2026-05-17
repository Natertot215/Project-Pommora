import Foundation
import Observation

@MainActor
@Observable
final class TierConfigManager {
    var config: TierConfig = TierConfig.defaultSeed()
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.tierConfigURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                config = try AtomicJSON.decode(TierConfig.self, from: url)
            } else {
                config = TierConfig.defaultSeed()
                try AtomicJSON.write(config, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        let url = NexusPaths.tierConfigURL(in: nexus)
        try AtomicJSON.write(config, to: url)
    }
}
