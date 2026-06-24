import Foundation

/// Per-Nexus veto consulted by every user-content folder-discovery site. Holds
/// the user's `excluded_folders` list (from `.nexus/settings.json`), normalized
/// for case-insensitive, Unicode-stable matching against on-disk folder paths.
///
/// Scope: USER exclusions only. Convention exclusions (dot/underscore/
/// `node_modules`, `.skipsHiddenFiles`) stay in the existing discovery code
/// paths — this type does not touch them.
///
/// `Sendable` value type — crosses freely into `@Sendable` index-write regions
/// and `async let` discovery tasks under Swift 6 strict concurrency.
struct FolderFilter: Sendable, Equatable {
    private let nexusRootPath: String
    private let excluded: Set<String>

    static let empty = FolderFilter(nexusRootPath: "", excluded: [])

    init(nexusRoot: URL, excludedFolders: [String]) {
        self.nexusRootPath = nexusRoot.standardizedFileURL.path
        self.excluded = Set(excludedFolders.compactMap { FolderFilter.normalizeEntry($0) })
    }

    private init(nexusRootPath: String, excluded: Set<String>) {
        self.nexusRootPath = nexusRootPath
        self.excluded = excluded
    }

    /// Reads `.nexus/settings.json` directly — no `SettingsManager` dependency,
    /// so it works in the index-rebuild pass that runs before NexusEnvironment
    /// exists. Missing/unreadable settings ⇒ an empty (no-op) filter.
    static func load(for nexus: Nexus) -> FolderFilter {
        let list =
            (try? AtomicJSON.decode(
                Settings.self, from: NexusPaths.settingsFileURL(in: nexus)))?.excludedFolders ?? []
        return FolderFilter(nexusRoot: nexus.rootURL, excludedFolders: list)
    }

    var isEmpty: Bool { excluded.isEmpty }

    /// True when `folderURL` is itself an excluded folder or sits inside one.
    func isExcluded(_ folderURL: URL) -> Bool {
        guard !excluded.isEmpty else { return false }
        guard let rel = relativePath(of: folderURL) else { return false }
        var accum = ""
        for seg in rel.split(separator: "/") {
            accum = accum.isEmpty ? String(seg) : accum + "/" + seg
            if excluded.contains(accum) { return true }
        }
        return false
    }

    private func relativePath(of url: URL) -> String? {
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(nexusRootPath + "/") else { return nil }
        return FolderFilter.fold(String(p.dropFirst(nexusRootPath.count + 1)))
    }

    // MARK: - Normalization

    /// Normalizes a raw user entry; nil for empty/invalid or collection-escaping (`..`).
    static func normalizeEntry(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\\", with: "/")
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }
        while s.contains("//") { s = s.replacingOccurrences(of: "//", with: "/") }
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        let comps = s.split(separator: "/").map(String.init)
        guard !comps.contains(".."), !comps.contains(".") else { return nil }
        return fold(s)
    }

    /// NFC + Unicode case-fold — applied to both user entries and on-disk paths.
    static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: nil)
    }
}
