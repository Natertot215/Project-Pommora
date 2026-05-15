//
//  NexusBookmark.swift
//  Pommora
//

import Foundation

/// Security-scoped bookmark helpers for sandboxed access to a user-picked
/// nexus folder across app launches.
///
/// Apple's sandbox accounting is reference-counted: every successful
/// `startAccessing` MUST be paired with a `stopAccessing`, or the system
/// leaks the grant for the lifetime of the process.
enum NexusBookmark {
    /// Creates a security-scoped bookmark for a user-picked URL (typically
    /// returned from `NSOpenPanel`). Persist the returned `Data` and pass
    /// it to `resolve(_:)` on a later launch to regain access.
    static func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a previously-saved security-scoped bookmark.
    ///
    /// `isStale == true` means the bookmark still resolved but should be
    /// re-created and re-saved — typically because the target was renamed,
    /// moved, or its volume changed. The returned URL is still safe to use
    /// for the current session.
    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Begins access to a security-scoped resource. Must be paired with
    /// `stopAccessing(_:)` when done.
    @discardableResult
    static func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// Releases access to a previously-acquired security-scoped resource.
    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
