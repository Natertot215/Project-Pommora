import Foundation
import Observation

@MainActor
@Observable
final class HomepageManager {
    var homepage: Homepage = Homepage.defaultSeed()
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.homepageURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                homepage = try AtomicJSON.decode(Homepage.self, from: url)
            } else {
                homepage = Homepage.defaultSeed()
                try AtomicJSON.write(homepage, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        homepage.modifiedAt = Date()
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(homepage, to: url)
    }
}
