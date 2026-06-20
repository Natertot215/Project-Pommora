import Foundation
import Observation

@MainActor
@Observable
final class HomepageManager {
    var homepage: Homepage = Homepage.defaultSeed()
    var pendingError: (any Error)?

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
        do {
            homepage.modifiedAt = Date()
            let url = NexusPaths.homepageURL(in: nexus)
            try AtomicJSON.write(homepage, to: url)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Persists the homepage banner image path (`banner` in `homepage.json`).
    /// `path` is the nexus-relative path returned by `CoverAssetStore`, or nil to
    /// clear it. Mutating `homepage` drives the live view; `save` writes + sets
    /// `pendingError` on failure (mirrors the container `setBanner` write path).
    func setBanner(_ path: String?) async throws {
        homepage.banner = path
        try await save()
    }
}
