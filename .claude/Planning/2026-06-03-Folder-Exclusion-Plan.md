## Folder Exclusion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Build/verify via a **background** Agent (`xcodebuild ... -only-testing:PommoraTests`) per CLAUDE.md quirk #13 — never let `xcodebuild` grab window focus. ALWAYS visually confirm a **non-zero executed count** (quirk #1).

**Goal:** Give each Nexus a user-editable `excluded_folders` list in `.nexus/settings.json` that makes Pommora ignore the listed folders completely — never adopted, never shown in the sidebar, never indexed, never walked for content — at any depth.

**Architecture:** A single per-Nexus `FolderFilter` value (built by reading `.nexus/settings.json` directly) is consulted as a *veto in front of* every user-content folder-discovery site. Each kind keeps its own positive discovery (Page Types find `_pagetype.json`, etc.); the filter only *subtracts*. The filter is applied inside the two shared `Filesystem` primitives via a defaulted parameter, so root-content callers opt in and the exempt `.nexus/` internal reads (Contexts) simply don't pass it. Because discovery happens in **two passes at two layers** (index rebuild in `NexusManager`, before `NexusEnvironment` exists; then manager `loadAll` in `NexusEnvironment`), the filter is produced by a **static disk-reading factory** `FolderFilter.load(for:)` rather than injected through `SettingsManager` — one source serves both passes with no launch-ordering barrier.

**Tech Stack:** Swift 6 (strict concurrency + ExistentialAny), SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), GRDB (SQLite index), Foundation `FileManager` directory enumeration.

---

### Context — verified architecture (read before any task)

All facts below are `file:line`-verified (research sweep 2026-06-03). Treat them as ground truth; re-confirm with the file before editing if a line has drifted.

**Two discovery passes, two layers** (the load-bearing finding):
1. **Index rebuild** — `IndexBuilder.populate(index:from:)` is called from `NexusManager.openIndex` ([NexusManager.swift:473](../../Pommora/Pommora/Nexus/NexusManager.swift#L473)), which runs *before* `currentNexus` is set and *before* any `NexusEnvironment`/`SettingsManager` exists. The filter here MUST come from disk, not in-memory settings.
2. **Manager load** — the six managers' `loadAll()` fire from the `Task` in `NexusEnvironment.init` ([NexusEnvironment.swift:210-223](../../Pommora/Pommora/Nexus/NexusEnvironment.swift#L210-L223)), after pass 1.

**The two shared primitives** ([Filesystem.swift](../../Pommora/Pommora/AtomicIO/Filesystem.swift)):
- `childFolders(of:)` (:267) → `children(of:where:)` (:253): only `.skipsHiddenFiles` (drops dot-folders); callers add inline `.`/`_` filters.
- `descendantFiles(of:excluding:where:)` (:306): `.skipsHiddenFiles` + inline `.`/`_`/`node_modules` (:336) + an existing `excluding: Set<URL>` subtree-prune param (:337). This is the recursive content walk.

**Root-content discovery callers that MUST honor exclusion** (thread the filter here):
- Sidebar/managers: `PageTypeManager.loadAll` ([:72-74 types, :106-108 collections](../../Pommora/Pommora/Vaults/PageTypeManager.swift#L72)), `ItemTypeManager.loadAll` ([:83-85, :115-117](../../Pommora/Pommora/Items/ItemTypeManager.swift#L83)).
- Index: `IndexBuilder.collectPageTypes` ([:181,:192-194](../../Pommora/Pommora/Index/IndexBuilder.swift#L181)), `collectItemTypes` ([:254,:264-266](../../Pommora/Pommora/Index/IndexBuilder.swift#L254)).
- Content roll-up (type-level page/item walk): `PageContentManager.loadAll(for: pageType)` ([:157,:163-167](../../Pommora/Pommora/Content/PageContentManager.swift#L157)), `ItemContentManager.loadAll(for: itemType)` ([:109,:117-121](../../Pommora/Pommora/Items/ItemContentManager.swift#L109)).
- Adoption: `NexusAdopter.scan` ([:296-302](../../Pommora/Pommora/Nexus/NexusAdopter.swift#L296)) + auto-tag path ([:963](../../Pommora/Pommora/Nexus/NexusAdopter.swift#L963)).

**EXEMPT — `.nexus/` internal reads that MUST NOT be filtered** (never pass a filter here):
- `TopicManager.loadAll` ([:48,:55](../../Pommora/Pommora/Contexts/TopicManager.swift#L48)) — reads `.nexus/topics/`.
- `SpaceManager.loadAll` ([:31](../../Pommora/Pommora/Contexts/SpaceManager.swift#L31)) — reads `.nexus/spaces/`.
- `IndexBuilder.collectContexts` ([:405 spaces, :418 topics, :428 projects](../../Pommora/Pommora/Index/IndexBuilder.swift#L405)).

**Why the filter goes in the primitives (gated), not the callers' inline filters:** the rule lives in ONE place (`FolderFilter`); applying it inside `childFolders`/`descendantFiles` behind a defaulted `folderFilter:` parameter means root-content callers opt in by passing it, exempt reads opt out by omitting it, and `descendantFiles` gets correct subtree pruning for free. Convention exclusion (`.`/`_`/`node_modules`) stays exactly where it is — untouched, zero regression risk to the load-bearing sidebar (quirk #8).

---

### Locked Decisions

- **LD-1 — "Ignore completely" = never adopted, shown, indexed, or walked.** Nathan's explicit choice. Adoption IS in scope (it is the first recognition surface; skipping it prevents Pommora writing sidecars into ignored folders).
- **LD-2 — Vault-owned storage.** The list lives on `.nexus/settings.json` as `excluded_folders: [String]`, reusing `SettingsManager`'s machinery. No new file, no new manager.
- **LD-3 — Anchored, exact, vault-relative paths.** An entry is a path from the nexus root (`Templates`, `Projects/Old Stuff`). `Templates` matches ONLY the root-level `Templates`, never a buried `Notes/Templates`. "Any depth" means *you may name a deeply-nested path*, not *match a name anywhere*. (git's leading-slash-anchored model, NOT Obsidian's substring model.)
- **LD-4 — Excluding a folder excludes its whole subtree.** Implemented by ancestor-walk match + `descendantFiles` subtree pruning.
- **LD-5 — Case-insensitive, NFC-normalized matching.** Default APFS is case-insensitive + Unicode-normalizing; both user entries and on-disk paths are folded via `.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)`.
- **LD-6 — `FolderFilter` covers USER exclusions only.** Convention defaults (dot/underscore/`node_modules`, and `.skipsHiddenFiles`) stay in the existing code paths, untouched. Consolidating those into the filter is an explicit non-goal of this plan (a future cleanup; touching it risks the load-bearing sidebar for a cosmetic DRY win).
- **LD-7 — Static disk-reading factory, not SettingsManager injection.** `FolderFilter.load(for: nexus)` reads `.nexus/settings.json` directly so it works in the pre-`NexusEnvironment` index pass.
- **LD-8 — Stale entries are inert.** An entry pointing at a renamed/deleted folder simply never matches — no warning, no auto-rewrite, no error (git semantics). Foreign/unknown entries are preserved on write.
- **LD-9 — No editing UI in this plan.** The list is hand-edited in the legible JSON (or by an agent). The Settings editor (v0.6.0) wires a row to the existing field later. A `SettingsManager.updateExcludedFolders` mutator is out of scope here.
- **LD-10 — Path escapes rejected.** A normalized entry containing `..` (or a bare `.`) is dropped, never honored.

---

### FolderFilter matching spec

Normalization of a raw user entry (`normalizeEntry`), in order: trim whitespace → `\` to `/` → strip leading `./` and `/` → collapse `//` → strip trailing `/` → drop if empty → reject if any component is `..` or `.` → fold (NFC + case-insensitive). The same fold is applied to a discovered folder's nexus-relative path before comparison.

Match (`isExcluded`): compute the folder's folded nexus-relative path; walk its ancestor chain (`a`, `a/b`, `a/b/c`); if any ancestor is in the excluded set, the folder is excluded. O(depth), and a fast `excluded.isEmpty` bail makes the common (no-exclusions) case free.

---

### File structure

- **Create** `Pommora/Pommora/AtomicIO/FolderFilter.swift` — the value type + `load(for:)` factory + normalization/match. One responsibility: "is this folder user-excluded?"
- **Modify** `Pommora/Pommora/AtomicIO/Filesystem.swift` — add defaulted `folderFilter:` param to `childFolders` (:267) and `descendantFiles` (:306).
- **Modify** `Pommora/Pommora/Settings/Settings.swift` — add `excludedFolders` field + CodingKey + decode + seed + `currentDefaultsVersion` 3→4 + v3→v4 migration step.
- **Modify** `Pommora/Pommora/Nexus/NexusManager.swift` — build the filter in `openIndex`, pass to `IndexBuilder.populate`.
- **Modify** `Pommora/Pommora/Index/IndexBuilder.swift` — thread filter into `populate` → `collectPageTypes`/`collectItemTypes` (NOT `collectContexts`).
- **Modify** `Pommora/Pommora/Nexus/NexusEnvironment.swift` — build the filter, thread into the discovery managers' `loadAll`.
- **Modify** `Pommora/Pommora/Vaults/PageTypeManager.swift`, `Items/ItemTypeManager.swift` — `loadAll(filter:)`, filter root + collection walks.
- **Modify** `Pommora/Pommora/Content/PageContentManager.swift`, `Items/ItemContentManager.swift` — type-level roll-up walk honors the filter.
- **Modify** `Pommora/Pommora/Nexus/NexusAdopter.swift` — `scan(filter:)` skips excluded folders.
- **Create** `Pommora/PommoraTests/AtomicIO/FolderFilterTests.swift` (suite `FolderFilterTests`).
- **Create** `Pommora/PommoraTests/Settings/ExcludedFoldersSettingsTests.swift` (suite `ExcludedFoldersSettingsTests`).
- **Create** `Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift` (suite `FolderExclusionDiscoveryTests`).

> **Quirk #1 reminder:** each test struct's TYPE name must equal the filename stem, or `-only-testing:PommoraTests/<Name>` silently runs 0 tests. The three suite names above satisfy this.

**Run command (background Agent only):**
```
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -destination 'platform=macOS' -only-testing:PommoraTests/<SuiteName> 2>&1 | tail -40
```

---

### Task 1: `FolderFilter` value type + `Filesystem` integration

**Files:**
- Create: `Pommora/Pommora/AtomicIO/FolderFilter.swift`
- Modify: `Pommora/Pommora/AtomicIO/Filesystem.swift:267` (childFolders), `:306-342` (descendantFiles)
- Test: `Pommora/PommoraTests/AtomicIO/FolderFilterTests.swift`

- [ ] **Step 1 — Write the failing test** (`FolderFilterTests.swift`):

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("FolderFilter") struct FolderFilterTests {

    private func filter(_ paths: [String], root: URL = URL(fileURLWithPath: "/N")) -> FolderFilter {
        FolderFilter(nexusRoot: root, excludedFolders: paths)
    }
    private func url(_ rel: String, root: String = "/N") -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(rel)
    }

    @Test func emptyFilterExcludesNothing() {
        #expect(FolderFilter.empty.isExcluded(url("Archive")) == false)
        #expect(filter([]).isExcluded(url("Archive")) == false)
    }

    @Test func exactTopLevelMatch() {
        let f = filter(["Archive"])
        #expect(f.isExcluded(url("Archive")))
        #expect(f.isExcluded(url("Notes")) == false)
    }

    @Test func anchoredNotSubstring() {
        // "Archive" must NOT match a buried "Notes/Archive" nor "ArchiveOld".
        let f = filter(["Archive"])
        #expect(f.isExcluded(url("Notes/Archive")) == false)
        #expect(f.isExcluded(url("ArchiveOld")) == false)
    }

    @Test func nestedPathAndSubtree() {
        let f = filter(["Projects/Old Stuff"])
        #expect(f.isExcluded(url("Projects/Old Stuff")))
        #expect(f.isExcluded(url("Projects/Old Stuff/2024")))   // descendant
        #expect(f.isExcluded(url("Projects")) == false)          // ancestor not excluded
    }

    @Test func caseInsensitiveAndNormalized() {
        let f = filter(["Archive"])
        #expect(f.isExcluded(url("archive")))                    // case-insensitive (APFS default)
        let g = filter([" ./Drafts/ "])                          // sloppy input normalizes
        #expect(g.isExcluded(url("Drafts")))
    }

    @Test func rejectsEscapesAndEmpty() {
        #expect(filter(["../Secret"]).isExcluded(url("../Secret")) == false) // dropped
        #expect(filter([""]).isExcluded(url("")) == false)
    }

    @Test func outsideRootIsNeverExcluded() {
        let f = filter(["Archive"], root: URL(fileURLWithPath: "/N"))
        #expect(f.isExcluded(URL(fileURLWithPath: "/Other/Archive")) == false)
    }
}
```

- [ ] **Step 2 — Run, verify it fails** (`cannot find 'FolderFilter'`). Background Agent: `-only-testing:PommoraTests/FolderFilterTests`.

- [ ] **Step 3 — Create `FolderFilter.swift`:**

```swift
import Foundation

/// Per-Nexus veto consulted by every user-content folder-discovery site. Holds
/// the user's `excluded_folders` list (from `.nexus/settings.json`), normalized
/// for case-insensitive, Unicode-stable matching against on-disk folder paths.
///
/// Scope: USER exclusions only. Convention exclusions (dot/underscore/
/// `node_modules`, `.skipsHiddenFiles`) stay in the existing discovery code
/// paths — this type does not touch them (see plan LD-6).
///
/// `Sendable` value type — crosses freely into `@Sendable` index-write regions
/// and `async let` discovery tasks under Swift 6 strict concurrency.
struct FolderFilter: Sendable, Equatable {
    /// Standardized absolute path of the nexus root (no trailing slash).
    private let nexusRootPath: String
    /// Normalized excluded relative paths (NFC + case-folded, `/`-separated, no
    /// leading/trailing slash). Empty ⇒ the filter is a no-op.
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
        let list = (try? AtomicJSON.decode(
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

    /// Folder's folded path relative to the nexus root; nil if it is the root
    /// or lies outside it.
    private func relativePath(of url: URL) -> String? {
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(nexusRootPath + "/") else { return nil }
        return FolderFilter.fold(String(p.dropFirst(nexusRootPath.count + 1)))
    }

    // MARK: - Normalization

    /// Normalizes a raw user entry; nil for empty/invalid or vault-escaping (`..`).
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
```

- [ ] **Step 4 — Run, verify `FolderFilterTests` passes** (8 tests, non-zero count).

- [ ] **Step 5 — Add the defaulted `folderFilter:` param to the two primitives** (`Filesystem.swift`). Replace `childFolders` (:266-273):

```swift
    /// Returns immediate child folders (not files). When `folderFilter` is
    /// non-empty, user-excluded folders are dropped (plan LD-6). Pass `.empty`
    /// (the default) for internal `.nexus/` reads that must NOT be filtered.
    static func childFolders(of folderURL: URL, folderFilter: FolderFilter = .empty) throws -> [URL] {
        try children(of: folderURL) { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        .filter { !folderFilter.isExcluded($0) }
    }
```

In `descendantFiles`, add the param to the signature (:306-310) and the check in the directory branch (:333-341):

```swift
    static func descendantFiles(
        of folderURL: URL,
        excluding excludedFolderURLs: Set<URL> = [],
        folderFilter: FolderFilter = .empty,
        where predicate: (URL) -> Bool
    ) throws -> [URL] {
```
```swift
            if isDir {
                let name = url.lastPathComponent
                let isExcludedByName =
                    name.hasPrefix(".") || name.hasPrefix("_") || name == "node_modules"
                let isExcludedByPath = excludedPaths.contains(url.standardizedFileURL.path)
                if isExcludedByName || isExcludedByPath || folderFilter.isExcluded(url) {
                    enumerator.skipDescendants()
                }
                continue
            }
```

- [ ] **Step 6 — Add a Filesystem-level test** to `FolderFilterTests.swift` proving the primitives honor the filter on a real temp tree:

```swift
    @Test func childFoldersDropsExcluded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-\(UUID().uuidString)")
        let keep = root.appendingPathComponent("Notes")
        let drop = root.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let f = FolderFilter(nexusRoot: root, excludedFolders: ["Archive"])
        let names = try Filesystem.childFolders(of: root, folderFilter: f)
            .map(\.lastPathComponent).sorted()
        #expect(names == ["Notes"])
        // Default (.empty) is unchanged behavior:
        let all = try Filesystem.childFolders(of: root).map(\.lastPathComponent).sorted()
        #expect(all == ["Archive", "Notes"])
    }
```

- [ ] **Step 7 — Run `FolderFilterTests` (now 9), verify pass. Commit:**

```bash
git add Pommora/Pommora/AtomicIO/FolderFilter.swift \
        Pommora/Pommora/AtomicIO/Filesystem.swift \
        Pommora/PommoraTests/AtomicIO/FolderFilterTests.swift
git commit -m "feat(exclusion): FolderFilter value type + Filesystem primitive integration"
```

---

### Task 2: `Settings.excludedFolders` field + migration

**Files:**
- Modify: `Pommora/Pommora/Settings/Settings.swift` (:29 field, :36 version, :45 CodingKey, :54/:61 init, :74 decode, :86 seed, :131-137 migrate)
- Test: `Pommora/PommoraTests/Settings/ExcludedFoldersSettingsTests.swift`

- [ ] **Step 1 — Write failing tests** (`ExcludedFoldersSettingsTests.swift`). Mirrors `SettingsShowPageIconTests` (the brand-new-field precedent) + `SettingsTests` round-trip:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("ExcludedFoldersSettings") struct ExcludedFoldersSettingsTests {

    @Test func freshSeedHasEmptyExcludedFolders() {
        let s = Settings.defaultSeed()
        #expect(s.excludedFolders == [])
        #expect(s.defaultsVersion == Settings.currentDefaultsVersion)
    }

    @Test func roundTripsAsSnakeCaseArray() throws {
        var s = Settings.defaultSeed()
        s.excludedFolders = ["Archive", "Projects/Old"]
        let data = try AtomicJSON.encodeData(s)                  // see note below
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"excluded_folders\""))
        let back = try AtomicJSON.decode(Settings.self, from: data)
        #expect(back.excludedFolders == ["Archive", "Projects/Old"])
    }

    @Test func legacyFileWithoutExcludedFoldersMigrates() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // v?-era file: no defaults_version, no excluded_folders, a user accent.
        let legacy = """
        {"version":1,"accent_color":"purple","labels":\(Self.minimalLabelsJSON),
         "show_page_icon":false,"modified_at":"2026-01-01T00:00:00Z"}
        """
        try legacy.data(using: .utf8)!.write(to: NexusPaths.settingsFileURL(in: nexus))

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.settings.excludedFolders == [])           // new field defaulted
        #expect(m.settings.accentColor == .purple)          // user value preserved
        #expect(m.pendingError == nil)
    }
}
```

> Implementation notes for the test author: `AtomicJSON.encodeData` / `encode` and the labels JSON literal — match the exact helpers used in `SettingsTests.swift` and `SettingsShowPageIconTests.swift`; copy their `minimalLabelsJSON` constant and encode helper verbatim rather than inventing names. (Confirm symbol names by reading those two files first.)

- [ ] **Step 2 — Run, verify fail** (`value of type 'Settings' has no member 'excludedFolders'`).

- [ ] **Step 3 — Edit `Settings.swift`.** Add the stored property after `showPageIcon` (:29):

```swift
    /// Vault-relative folder paths excluded from all user-content discovery
    /// (adoption, sidebar, index, content walks). Empty by default. Anchored
    /// to the nexus root (e.g. "Archive", "Projects/Old"). See FolderFilter.
    var excludedFolders: [String]
```

Bump `currentDefaultsVersion` (:36) `3` → `4`. Add CodingKey after `showPageIcon` (:45):

```swift
        case excludedFolders = "excluded_folders"
```

Memberwise init — add param after `showPageIcon: Bool = false` (:54) and assign (after :61):

```swift
        excludedFolders: [String] = [],
        // ...
        self.excludedFolders = excludedFolders
```

`init(from:)` — after the `showPageIcon` decode (:74):

```swift
        // Old files lack "excluded_folders" → default to none (matches the new
        // default, so migration has nothing to rewrite — see migrate v3→v4).
        excludedFolders = (try? c.decode([String].self, forKey: .excludedFolders)) ?? []
```

`defaultSeed()` — after `showPageIcon: false` (:86):

```swift
            excludedFolders: [],
```

`migrate(_:)` — after the `s.defaultsVersion < 3` block (:131-137), before the clamp (:140):

```swift
        if s.defaultsVersion < 4 {
            // v3→v4: added `excludedFolders`. Brand-new field — absent in older
            // files, decoded as `[]`, which already equals the new default, so
            // there's nothing to rewrite. Just record the version.
            s.defaultsVersion = 4
        }
```

- [ ] **Step 4 — Run `ExcludedFoldersSettingsTests` (3) + the full existing Settings suites, verify all pass** (the migration precedent guards re-persist stability — confirm `SettingsManagerAutoMigrationTests` still green).

- [ ] **Step 5 — Commit:**

```bash
git add Pommora/Pommora/Settings/Settings.swift \
        Pommora/PommoraTests/Settings/ExcludedFoldersSettingsTests.swift
git commit -m "feat(exclusion): add excluded_folders to Settings (+ v3→v4 migration)"
```

---

### Task 3: Pass-1 — index rebuild honors exclusion

**Files:**
- Modify: `Pommora/Pommora/Index/IndexBuilder.swift` (`populate` :147, `collectPageTypes` :179/:184-185 + collection walk :192-194, `collectItemTypes` :252/:257-258 + :264-266; do NOT touch `collectContexts` :405/:418/:428)
- Modify: `Pommora/Pommora/Nexus/NexusManager.swift` (`openIndex` :466-473)
- Test: `Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift` (case T6)

- [ ] **Step 1 — Write failing test** (`FolderExclusionDiscoveryTests.swift`, new file). Uses the disk-sidecar idiom from `LoadAllIndexSyncTests.swift:40-52` and the SQLite-count idiom from `IndexBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("FolderExclusionDiscovery") struct FolderExclusionDiscoveryTests {

    /// Writes `excluded_folders` into the nexus settings file on disk so
    /// FolderFilter.load(for:) picks it up.
    private func setExcluded(_ paths: [String], in nexus: Nexus) throws {
        var s = Settings.defaultSeed()
        s.excludedFolders = paths
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))
    }

    /// Creates a PageType folder on disk (sidecar idiom).
    private func makePageType(_ title: String, id: String, in nexus: Nexus) throws {
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pt = PageType(id: id, title: title, icon: nil, properties: [], views: [], modifiedAt: Date())
        try pt.save(to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
    }

    @Test func excludedFolderAbsentFromIndexAfterBuild() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: index, from: nexus)

        let notes = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?",
                             arguments: ["PT_NOTES"]) ?? -1
        }
        let archive = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?",
                             arguments: ["PT_ARCHIVE"]) ?? -1
        }
        #expect(notes == 1)
        #expect(archive == 0)
    }
}
```

- [ ] **Step 2 — Run, verify fail** (`archive == 1`, not 0 — the index still contains the excluded type).

- [ ] **Step 3 — Thread the filter through `IndexBuilder`.** Add `filter: FolderFilter = .empty` to `populate` (:147) and pass it down to `collectPageTypes(from:filter:)` and `collectItemTypes(from:filter:)`. In each root-folder loop (`collectPageTypes` :184-185, `collectItemTypes` :257-258) and the collection sub-walks (:192-194, :264-266), add `&& !filter.isExcluded(folder)` to the `where` clause. Concretely, `collectPageTypes` root loop becomes:

```swift
        for folder in topLevel
        where !folder.lastPathComponent.hasPrefix(".")
           && !folder.lastPathComponent.hasPrefix("_")
           && !filter.isExcluded(folder) {
```

Apply the identical `&& !filter.isExcluded(sub)` to the collection sub-folder loops. **Do NOT** add the filter to `collectContexts` (:405/:418/:428) — those read `.nexus/`.

- [ ] **Step 4 — Build the filter in `NexusManager.openIndex`** (:466-473). `nexus` is already in scope:

```swift
                let filter = FolderFilter.load(for: nexus)
                try await IndexBuilder.populate(index: idx, from: nexus, filter: filter)
```

- [ ] **Step 5 — Run T6, verify pass** (`notes == 1`, `archive == 0`). Run the full `-only-testing:PommoraTests/IndexBuilderTests` + `LoadAllIndexSyncTests` to confirm no regression.

- [ ] **Step 6 — Commit:**

```bash
git add Pommora/Pommora/Index/IndexBuilder.swift \
        Pommora/Pommora/Nexus/NexusManager.swift \
        Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift
git commit -m "feat(exclusion): index rebuild skips excluded folders (pass 1)"
```

---

### Task 4: Pass-2 — managers (sidebar) honor exclusion

**Files:**
- Modify: `Pommora/Pommora/Vaults/PageTypeManager.swift` (`loadAll` :60, root walk :72-74, collection walk :106-108)
- Modify: `Pommora/Pommora/Items/ItemTypeManager.swift` (`loadAll` :74, :83-85, :115-117)
- Modify: `Pommora/Pommora/Nexus/NexusEnvironment.swift` (load `Task` :210-223)
- Test: `FolderExclusionDiscoveryTests.swift` (cases T5, T8, T9)

- [ ] **Step 1 — Write failing tests** (append to `FolderExclusionDiscoveryTests`):

```swift
    @Test func excludedTypeAbsentFromPageTypeLoadAll() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)
        try setExcluded(["Archive"], in: nexus)

        let mgr = PageTypeManager(nexus: nexus)
        await mgr.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(mgr.types.contains { $0.title == "Notes" })
        #expect(!mgr.types.contains { $0.title == "Archive" })
    }

    @Test func removingFromListReExposesType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makePageType("Archive", id: "PT_ARCHIVE", in: nexus)

        try setExcluded(["Archive"], in: nexus)
        let m1 = PageTypeManager(nexus: nexus)
        await m1.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(!m1.types.contains { $0.title == "Archive" })

        try setExcluded([], in: nexus)                      // user removes it
        let m2 = PageTypeManager(nexus: nexus)
        await m2.loadAll(filter: FolderFilter.load(for: nexus))
        #expect(m2.types.contains { $0.title == "Archive" })   // reappears, non-destructive
    }
```

> T8 (nested collection excluded via `Notes/Archive` carrying `_pagecollection.json`, asserted absent from `pageCollections(in:)`) — author it mirroring `LoadAllIndexSyncTests.swift` two-level idiom; reuse `NexusPaths.collectionFolderURL`. Include it in this step.

- [ ] **Step 2 — Run, verify fail** (`Archive` present; and `loadAll` has no `filter:` param yet → compile error, which IS the failing state).

- [ ] **Step 3 — Add `filter:` to the managers.** `PageTypeManager.loadAll` (:60):

```swift
    func loadAll(filter: FolderFilter = .empty) async {
```

Root walk (:72), pass the filter into `childFolders` (it drops user-excluded folders; the inline convention filters stay):

```swift
            let topLevel = try Filesystem.childFolders(of: root, folderFilter: filter)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }
```

Collection walk (:106): `let cols = try Filesystem.childFolders(of: folder, folderFilter: filter)` (keep the existing `.filter` chain). Apply the symmetric changes to `ItemTypeManager.loadAll` (:74, :83, :115).

- [ ] **Step 4 — Thread the filter from `NexusEnvironment`** (:210-223). Before the `Task`, build it once; pass to the two discovery managers (leave Space/Topic/Agenda bare — exempt or non-folder-walking):

```swift
        let folderFilter = FolderFilter.load(for: nexus)
        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll(filter: folderFilter)
            async let _ = itemTypeMgr.loadAll(filter: folderFilter)
            async let _ = agendaTaskMgr.loadAll()
            async let _ = agendaEventMgr.loadAll()
            // ... unchanged tail (homepage/tier/saved/settings/recents/pinned)
        }
```

- [ ] **Step 5 — Run T5, T8, T9, verify pass. Run `-only-testing:PommoraTests` whole-target once to confirm the defaulted `loadAll(filter:)` didn't break existing callers (they use the `.empty` default).**

- [ ] **Step 6 — Commit:**

```bash
git add Pommora/Pommora/Vaults/PageTypeManager.swift \
        Pommora/Pommora/Items/ItemTypeManager.swift \
        Pommora/Pommora/Nexus/NexusEnvironment.swift \
        Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift
git commit -m "feat(exclusion): Page/Item type managers skip excluded folders (pass 2)"
```

---

### Task 5: Content roll-up leak plug

An excluded folder *nested inside a non-excluded Type* (a Collection or a loose sub-folder) would otherwise have its `.md` files rolled up into the type-level page/item list and the index. Pruning them via the `descendantFiles` filter closes the leak.

**Files:**
- Modify: `Pommora/Pommora/Content/PageContentManager.swift` (`loadAll(for: pageType)` :150-167)
- Modify: `Pommora/Pommora/Items/ItemContentManager.swift` (`loadAll(for: itemType)` :109-121)
- Modify: their callers to pass the filter (the detail-load path / `NexusEnvironment` — confirm call sites by reading the files; thread `filter: FolderFilter = .empty`).
- Test: `FolderExclusionDiscoveryTests.swift` (case T-leak)

- [ ] **Step 1 — Write failing test:** a PageType `Notes` (not excluded) with a loose folder `Notes/Scratch/secret.md`; exclude `Notes/Scratch`; after the type-level page load, `secret.md` must NOT appear, and its row must be absent from `pages` in the index. (Reuse `FixtureFiles.write` for the `.md`; assert via the manager's page list and a `SELECT COUNT(*) FROM pages WHERE title='secret'`.)

- [ ] **Step 2 — Run, verify fail** (`secret` rolls up).

- [ ] **Step 3 — Thread the filter into the type-root walk.** `PageContentManager.loadAll(for: pageType)` gains `filter: FolderFilter = .empty`; pass it into the `descendantFiles` call (:163) via the new `folderFilter:` param (keep the existing `excluding: collectionFolders`):

```swift
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder, excluding: excludedCollectionFolders, folderFilter: filter
            ) { /* existing predicate */ }
```

Mirror in `ItemContentManager.loadAll(for: itemType)` (:117). Thread `filter` from the call sites (detail-view load / wherever the type-level content load is triggered — pass `FolderFilter.load(for: nexus)` or the env's filter).

- [ ] **Step 4 — Run T-leak, verify pass. Full-target run to confirm content loading is unbroken for the non-excluded case.**

- [ ] **Step 5 — Commit:**

```bash
git add Pommora/Pommora/Content/PageContentManager.swift \
        Pommora/Pommora/Items/ItemContentManager.swift \
        Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift
git commit -m "feat(exclusion): prune excluded subtrees from type-level content roll-up"
```

---

### Task 6: Adoption skips excluded folders

Per LD-1, an excluded folder must never be adopted (no sidecar written into it). Higher blast-radius (adoption writes to disk) — isolated as its own task, fully tested. Mirror the existing convention-skip precedent test `NexusAdopterTests.scanSkipsHiddenAndUnderscore` (:315-329).

**Files:**
- Modify: `Pommora/Pommora/Nexus/NexusAdopter.swift` (`scan` :288/:296-302; auto-tag entry :963 if it classifies folders for sidecar writes)
- Modify: caller in `NexusManager` (the launch-migration/adoption path) to pass `FolderFilter.load(for: nexus)`
- Test: `FolderExclusionDiscoveryTests.swift` (case T7)

- [ ] **Step 1 — Write failing test:**

```swift
    @Test func excludedFolderSkippedByAdoptionScan() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Two plain user folders with loose markdown (fresh-sidecar candidates).
        for name in ["Notes", "Archive"] {
            let f = nexus.rootURL.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            FixtureFiles.write("# x", to: f.appendingPathComponent("Note.md"))
        }
        var s = Settings.defaultSeed(); s.excludedFolders = ["Archive"]
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL,
                                         filter: FolderFilter.load(for: nexus))
        let names = plan.freshSidecars.map { $0.folderURL.lastPathComponent }
        #expect(names.contains("Notes"))
        #expect(!names.contains("Archive"))   // excluded → not an adoption candidate
    }
```

- [ ] **Step 2 — Run, verify fail** (compile error: `scan` has no `filter:`; that is the failing state).

- [ ] **Step 3 — Add `filter: FolderFilter = .empty` to `NexusAdopter.scan`** (:288). In the top-level loop (:297-302), after the existing dot/underscore/`adoptionExcludedSubFolderNames` skips, add:

```swift
            if filter.isExcluded(folder) { skipped.append(folder); continue }
```

If `autoTagMissingSidecars` (:963 path) writes sidecars by walking folders, thread the same filter there and skip excluded folders before any write. Update the `NexusManager` caller to pass `FolderFilter.load(for: nexus)`.

- [ ] **Step 4 — Run T7, verify pass. Run `-only-testing:PommoraTests/NexusAdopterTests` to confirm the convention-skip precedent + all adoption shapes still pass.**

- [ ] **Step 5 — Commit:**

```bash
git add Pommora/Pommora/Nexus/NexusAdopter.swift \
        Pommora/Pommora/Nexus/NexusManager.swift \
        Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift
git commit -m "feat(exclusion): adoption scan skips excluded folders"
```

---

### Task 7: Regression guard + integrated verification

The highest-value safety net: prove the convention defaults still hold independently of the user list, and that the root-level veto never leaks into the exempt `.nexus/topics` internal read.

**Files:**
- Test: `FolderExclusionDiscoveryTests.swift` (case T10)

- [ ] **Step 1 — Write the guard test:**

```swift
    @Test func conventionsHoldAndContextsSurvive() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // (i) Convention skips work with an EMPTY user list.
        for name in [".obsidian", "_internal", "node_modules"] {
            try FileManager.default.createDirectory(
                at: nexus.rootURL.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try makePageType("Notes", id: "PT_NOTES", in: nexus)
        let mgr = PageTypeManager(nexus: nexus)
        await mgr.loadAll(filter: FolderFilter.load(for: nexus))   // empty list
        #expect(mgr.types.map(\.title) == ["Notes"])

        // (ii) A root-level exclusion named "topics" must NOT suppress the
        //      Contexts read inside .nexus/topics.
        let topicMgr = TopicManager(nexus: nexus)
        try await topicMgr.createTopic(name: "Research")           // writes .nexus/topics/Research
        var s = Settings.defaultSeed(); s.excludedFolders = ["topics"]
        try AtomicJSON.write(s, to: NexusPaths.settingsFileURL(in: nexus))

        let topicMgr2 = TopicManager(nexus: nexus)
        await topicMgr2.loadAll()                                  // exempt — no filter param
        #expect(topicMgr2.topics.contains { $0.title == "Research" })
    }
```

> Confirm `TopicManager.createTopic` / `.topics` exact names by reading `TopicManager.swift` first; adjust to the real API. The assertion's intent is fixed: Contexts survive a root-level `"topics"` exclusion.

- [ ] **Step 2 — Run T10, verify pass.**

- [ ] **Step 3 — Full integrated run** (background Agent, whole target): `-only-testing:PommoraTests`. Confirm a non-zero executed count and **0 failures**. Spot-check the new suites all executed (not silently 0).

- [ ] **Step 4 — Commit:**

```bash
git add Pommora/PommoraTests/Nexus/FolderExclusionDiscoveryTests.swift
git commit -m "test(exclusion): convention + Contexts-survival regression guard"
```

- [ ] **Step 5 — Docs.** Update `Features/Architecture.md` ("Hidden + private" section) + `Features/Settings`-related note to document `excluded_folders`; add a `History.md` entry; refresh `Handoff.md` via `/handoff`. (Docs-only commit, separate from code per quirk #4.)

---

### Self-review notes (author ran before handoff)

- **Spec coverage:** LD-1 (never adopted/shown/indexed/walked) → Tasks 3 (index), 4 (sidebar), 5 (content), 6 (adoption); LD-2/LD-7 (settings storage + factory) → Tasks 1-2; LD-3/4/5 (anchored, subtree, case-insensitive) → Task 1 tests; LD-8 (stale inert) → covered by ancestor-walk returning false; exempt `.nexus` reads → Task 7 (ii). All requirements map to a task.
- **Type consistency:** `FolderFilter` API (`isExcluded(_:)`, `load(for:)`, `.empty`, `init(nexusRoot:excludedFolders:)`) is used identically in every later task. `loadAll(filter:)` / `populate(...,filter:)` / `scan(...,filter:)` / `descendantFiles(...,folderFilter:)` / `childFolders(...,folderFilter:)` signatures are consistent across tasks.
- **Open confirmations for the executor** (resolve by reading the file, not guessing — Handoff cornerstone): the exact `AtomicJSON` encode-helper + `minimalLabelsJSON` constant in the Settings tests (Task 2); `PageContentManager`/`ItemContentManager` type-level-load call sites (Task 5); `TopicManager.createTopic`/`.topics` API (Task 7); whether `autoTagMissingSidecars` writes sidecars that need the filter (Task 6).
- **Risk note:** Tasks 4 + 6 touch the load-bearing sidebar discovery + adoption. Each ships as its own green commit with a focused regression run before proceeding (quirk #8). Re-assess this plan between green commits (CLAUDE.md hard rule) — if a task surfaces a wrong assumption, rewrite the affected later tasks before dispatching the next.
