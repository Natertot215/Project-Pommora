import Foundation

/// Debug-only launch breadcrumb trail for diagnosing a stuck launch from
/// OUTSIDE the process (the unified log surfaces nothing for this app, and a
/// dead-ended `loadOnLaunch` leaves no other evidence). Appends one
/// timestamped line per mark to the app container's tmp directory —
/// sandbox-writable, host-readable at
/// `~/Library/Containers/<bundle-id>/Data/tmp/launch-trace.log`.
/// Compiles in Release as a no-op so call sites stay unconditional.
enum LaunchTrace {
    static func mark(_ message: String) {
        #if DEBUG
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("launch-trace.log")
            let line = "\(Date().formatted(.iso8601)) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        #endif
    }
}
