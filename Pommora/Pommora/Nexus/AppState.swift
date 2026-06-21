//
//  AppState.swift
//  Pommora
//

import Foundation

/// Machine-specific app state that does not belong inside any individual nexus.
///
/// Persisted as a pretty-printed JSON file at:
///   `~/Library/Application Support/com.nathantaichman.Pommora/state.json`
///
/// v0.2.7 added `pageInspectorOpen`: per-Page boolean for whether the editor's
/// inspector panel was last visible. Keyed by PageMeta.id; missing key = use
/// global default (closed). App-level rather than per-nexus to keep the shape
/// flat — same nexus opened on two machines is fine to diverge inspector state.
///
/// Vault-portable per-nexus state (open tabs, sidebar collapsed state)
/// would live separately at `<nexus>/.nexus/state.json` if we needed it;
/// no per-nexus state file exists yet — extend this type for v0.2 needs.
struct AppState: Codable, Equatable {
    var schemaVersion: Int
    var lastNexusBookmark: Data?
    /// Security-scoped bookmark to the active nexus's PARENT folder. The sandbox
    /// grants only the nexus itself, so a root-folder rename (a write to the
    /// parent directory) needs this. Requested at initial nexus load; nil until
    /// granted, and survives the nexus being renamed (the parent is unchanged).
    var parentFolderBookmark: Data?
    /// Pommora pageID → whether the inspector panel was visible last time
    /// this Page was opened. Missing key = closed (the global default).
    var pageInspectorOpen: [String: Bool]

    init(
        schemaVersion: Int = 2,
        lastNexusBookmark: Data? = nil,
        parentFolderBookmark: Data? = nil,
        pageInspectorOpen: [String: Bool] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.lastNexusBookmark = lastNexusBookmark
        self.parentFolderBookmark = parentFolderBookmark
        self.pageInspectorOpen = pageInspectorOpen
    }

    // Custom init(from:) keeps backwards-compat: an existing v1 state.json
    // file (no `pageInspectorOpen` key) decodes cleanly with an empty map.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, lastNexusBookmark, parentFolderBookmark, pageInspectorOpen
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.lastNexusBookmark = try c.decodeIfPresent(Data.self, forKey: .lastNexusBookmark)
        self.parentFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .parentFolderBookmark)
        self.pageInspectorOpen =
            try c.decodeIfPresent([String: Bool].self, forKey: .pageInspectorOpen) ?? [:]
    }
}

extension AppState {
    /// Loads state from a JSON file at the given URL.
    /// Throws if the file is missing — callers decide whether that means
    /// "first launch, default state" or a hard error.
    static func load(from url: URL) throws -> AppState {
        try AtomicJSON.decode(AppState.self, from: url)
    }

    /// Atomically writes state as pretty-printed JSON via AtomicJSON.
    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }

    // MARK: - Inspector persistence (v0.2.7)

    /// Look up the inspector-open flag for a Page. Returns false if the file
    /// can't be read or the key is missing. Read-only convenience for views.
    static func pageInspectorOpen(pageID: String) -> Bool {
        guard let url = try? NexusStore.appStateURL(),
            let state = try? AppState.load(from: url)
        else { return false }
        return state.pageInspectorOpen[pageID] ?? false
    }

    /// Persist a single Page's inspector-open flag. Load → mutate → save.
    /// Silent on failure — inspector toggle persistence is not load-bearing.
    static func setPageInspectorOpen(_ open: Bool, pageID: String) {
        do {
            let url = try NexusStore.appStateURL()
            var state = (try? AppState.load(from: url)) ?? AppState()
            state.pageInspectorOpen[pageID] = open
            try state.save(to: url)
        } catch {
            // Best-effort — inspector preference is not critical state.
        }
    }
}
