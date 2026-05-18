import Foundation
@testable import Pommora

/// Spins up a throwaway nexus under `/tmp` for tests that need real filesystem ops.
/// Each call returns a unique nexus rooted at a fresh UUID-named directory with
/// `.nexus/` already created — every test gets isolation.
enum TempNexus {
    /// Creates `<tmp>/pommora-test-<uuid>/.nexus/` and returns a `Nexus` rooted there.
    static func make() throws -> Nexus {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".nexus", isDirectory: true),
            withIntermediateDirectories: true
        )
        return Nexus(id: ULID.generate(), rootURL: tmp)
    }

    /// Removes the entire temp tree. Call from test teardown / `defer`.
    static func cleanup(_ nexus: Nexus) {
        try? FileManager.default.removeItem(at: nexus.rootURL)
    }
}
