import Foundation
@testable import Pommora

/// Convenience for writing arbitrary string content to a path inside a test nexus.
enum FixtureFiles {
    static func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(_ json: String, to url: URL) throws {
        try write(json, to: url)
    }
}
