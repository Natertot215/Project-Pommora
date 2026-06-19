//
//  NexusFileWatcherTests.swift
//  PommoraTests
//
//  Integration coverage for the FSEvents binding: proves the watcher actually
//  reports external writes and honors the index-database intake exclusion.
//  These exercise the real kernel event stream, so they poll with a timeout
//  rather than assuming synchronous delivery.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite(.serialized)
struct NexusFileWatcherTests {

    /// Collects handler callbacks on the main actor (where the watcher delivers).
    @MainActor
    final class Collector {
        var urls: [URL] = []
        func names() -> [String] { urls.map { $0.lastPathComponent } }
    }

    /// Polls until `condition` holds or the timeout elapses. FSEvents delivery is
    /// asynchronous (≈0.1s stream latency plus scheduling), so callers wait on the
    /// observable effect instead of a fixed sleep.
    private func waitUntil(
        timeout: Duration = .seconds(4), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".nexus", isDirectory: true),
            withIntermediateDirectories: true)
        return root
    }

    @Test("Reports an external file write")
    func detectsExternalWrite() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = Collector()
        let watcher = NexusFileWatcher(
            rootURL: root,
            indexDatabaseURL: root.appendingPathComponent(".nexus/index.db")
        ) { paths in collector.urls.append(contentsOf: paths) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))  // let the stream arm

        try "hello".write(
            to: root.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)

        let saw = await waitUntil { collector.names().contains("Note.md") }
        #expect(saw, "watcher should report the external write of Note.md")
    }

    @Test("Excludes the index database at intake")
    func excludesIndexDatabase() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let indexDB = root.appendingPathComponent(".nexus/index.db")
        let collector = Collector()
        let watcher = NexusFileWatcher(rootURL: root, indexDatabaseURL: indexDB) { paths in
            collector.urls.append(contentsOf: paths)
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        // Churn the index database AND write a real content file.
        try Data("db".utf8).write(to: indexDB)
        try "x".write(
            to: root.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)

        // Wait on the content file (proves the watcher is live), then assert the
        // index database never came through.
        let sawOther = await waitUntil { collector.names().contains("Other.md") }
        #expect(sawOther, "watcher should report the content file")
        #expect(
            !collector.names().contains("index.db"),
            "index database must be excluded at intake")
    }
}
