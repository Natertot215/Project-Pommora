import Foundation

/// Native FSEvents watch on the Nexus root. Detects on-disk changes from any
/// source (the app, Obsidian, vim, Finder, cloud sync) and emits batches of
/// changed paths to a handler on the main actor.
///
/// The index database (`.nexus/index.db` + WAL/journal) is excluded at intake —
/// the app rewrites it on every reconcile, so watching it would self-feed. A
/// `[path: mtime]` gate drops duplicate events and the app's own save-echoes; a
/// vanished path (delete / move-away) always passes. The gate is lazy: with
/// `sinceWhen = now` only post-`start()` changes are reported, so no seed scan
/// is needed.
///
/// `nonisolated` (the module defaults to `@MainActor`): the callback fires on a
/// private serial queue where `stream` + `lastSeen` are confined; only the
/// handler call hops to the main actor. Confinement is asserted via
/// `@unchecked Sendable`.
nonisolated final class NexusFileWatcher: @unchecked Sendable {

    /// Called on the main actor with the surviving (gated) changed paths.
    typealias Handler = @MainActor @Sendable ([URL]) -> Void

    private let rootURL: URL
    private let excludedPaths: Set<String>
    private let handler: Handler

    private let queue = DispatchQueue(label: "com.pommora.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    /// path → last observed modification time. Confined to `queue`.
    private var lastSeen: [String: TimeInterval] = [:]

    /// - Parameters:
    ///   - rootURL: the Nexus root to watch recursively.
    ///   - indexDatabaseURL: `<root>/.nexus/index.db`; this and its sidecars are
    ///     excluded at intake.
    ///   - handler: receives the gated batch on the main actor.
    init(rootURL: URL, indexDatabaseURL: URL, handler: @escaping Handler) {
        self.rootURL = rootURL.standardizedFileURL
        let db = indexDatabaseURL.standardizedFileURL.path
        self.excludedPaths = [db, db + "-journal", db + "-wal", db + "-shm"]
        self.handler = handler
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, self.stream == nil else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)

            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes)

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &context,
                [self.rootURL.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.1,                 // latency: coalesce bursts + atomic-write temp churn
                flags
            ) else { return }

            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    /// Synchronous so the stream is fully invalidated before the watcher can be
    /// deallocated — the C callback holds `self` unretained, so a live stream
    /// after dealloc would fire into freed memory. `queue.sync` also drains any
    /// in-flight callback (the queue is serial) before teardown.
    func stop() {
        queue.sync {
            guard let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            self.lastSeen.removeAll()
        }
    }

    deinit {
        // Fallback; `stop()` is the explicit teardown. Safe — at deinit no
        // reference remains, so no callback can be in flight.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Event handling (runs on `queue`)

    /// The C trampoline. Non-capturing; recovers `self` from the stream context.
    /// `eventPaths` is a `CFArray` of `CFString` only because the stream sets
    /// `kFSEventStreamCreateFlagUseCFTypes` — the bit-cast and that flag are a
    /// paired invariant.
    private static let callback: FSEventStreamCallback = {
        _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<NexusFileWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
        // A must-scan-subdirs flag means the kernel coalesced past file
        // granularity (dropped events) — force a reconcile so nothing is missed.
        let dropped = (0..<count).contains {
            eventFlags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
        }
        watcher.process(paths: Array(paths.prefix(count)), forceReconcile: dropped)
    }

    private func process(paths: [String], forceReconcile: Bool) {
        var survivors: [URL] = []
        for path in paths {
            if excludedPaths.contains(path) { continue }

            let mtime = Self.modificationTime(ofPath: path)
            if let mtime {
                // Existing file: pass only if it advanced past what we last saw
                // (drops duplicate events and the app's own save-echoes).
                if let seen = lastSeen[path], mtime <= seen { continue }
                lastSeen[path] = mtime
            } else {
                // Gone (delete / move-away): always pass; the reconciler decides.
                lastSeen.removeValue(forKey: path)
            }
            survivors.append(URL(fileURLWithPath: path))
        }

        // Dropped-events recovery: re-deliver the root so the reconciler re-reads
        // the tree even when the gate found nothing new.
        if forceReconcile { survivors.append(rootURL) }

        guard !survivors.isEmpty else { return }
        let batch = survivors
        let handler = self.handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(batch) } }
    }

    private static func modificationTime(ofPath path: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date
        else { return nil }
        return date.timeIntervalSinceReferenceDate
    }
}
