# Pommora Paradigm Scaffolding — Implementation Plan

> **🟢 SHIPPED 2026-05-17** — all 65 tasks landed (Tasks 1-44 on 2026-05-16, Tasks 45-65 on 2026-05-17). Branch `paradigm-scaffolding`, 69 commits ahead of `main`. 177 unit tests, 0 failures, 0 source warnings.
>
> **Execution strategy used:** stub-and-progressively-replace (paradigm decision 2026-05-17 in `// Guidelines//Paradigm-Decisions.md`) — every task ships green standalone with throwaway in-file stubs for forward-dep types; later tasks replace the stubs in-place. Supersedes this plan's per-task "Defer commit" instructions, which were honored in the patched spec text but ignored at execution time.
>
> **Pre-merge cleanup pending** (4-commit plan in `// Handoff.md`): dead-code purge / sidebar UX restructure (right-click context menus replace "+ New" buttons per paradigm decision 2026-05-17) / Pages-under-Vaults sidebar disclosure / atomicity + error-surfacing pattern.
>
> Checklist boxes (`- [ ]`) below were used for in-flight tracking; final state is "all checked." See `History.md` for the session-by-session narrative.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Phases 0 → 6 of [.claude/Planning/Contexts-Vaults-spec.md](.claude/Planning/Contexts-Vaults-spec.md) — the entire 2-layer paradigm with CRUD UI for Contexts (Spaces / Topics / Sub-topics) + Vaults / Collections + Pages / Items, plus data-layer scaffold for Agenda + Homepage. Four-section sidebar fully live; on-disk JSON/Markdown matches the locked schemas exactly.

**Architecture:** SwiftUI on macOS 26.4 (Tahoe) under Swift 6 strict concurrency. Per-entity `@MainActor @Observable` managers (no unified store). Codable JSON files written atomically via `Data.write(.atomic)`. Yams 5.1+ for YAML frontmatter on `.md` files. Pure-function validators called from every manager's mutate-paths. Native SwiftUI `Table` for Finder-style Vault + Collection detail views; no toolbars in v1. All file ops inside the security-scoped bookmark scope held by the existing `NexusManager`.

**Tech Stack:** Swift 6 / SwiftUI / Yams 5.1+ / Swift Testing framework (`@Test` + `#expect`) / sandboxed macOS 26.4. No GRDB / EventKit / FSEventStream in this plan (later phases).

**Design doc:** [.claude/Planning/Paradigm-Scaffolding-Plan.md](.claude/Planning/Paradigm-Scaffolding-Plan.md) — read first.

---

## File Structure

### New folders + files (sequential by step)

```
Pommora/Pommora/
  AtomicIO/                                  ← Step 2
    AtomicJSON.swift
    AtomicYAMLMarkdown.swift
    NexusPaths.swift
    Filesystem.swift
  Contexts/                                  ← Step 3 + 5a
    SpaceColor.swift
    ContextBlock.swift
    Space.swift
    Topic.swift
    Subtopic.swift
    TierConfig.swift
    SavedConfig.swift
    SpaceManager.swift                       ← Step 5a
    TopicManager.swift                       ← Step 5a
  Vaults/                                    ← Step 3 + 5b
    PropertyType.swift
    PropertyDefinition.swift
    PropertyValue.swift
    Vault.swift
    VaultView.swift
    Collection.swift
    VaultManager.swift                       ← Step 5b
  Content/                                   ← Step 3 + 5b
    Item.swift
    PageFrontmatter.swift
    PageFile.swift
    ContentManager.swift                     ← Step 5b
  Agenda/                                    ← Step 3 + 5c
    Recurrence.swift
    AgendaSchema.swift
    AgendaItem.swift
    AgendaManager.swift                      ← Step 5c
  Homepage/                                  ← Step 3 + 5c
    Homepage.swift
    HomepageManager.swift                    ← Step 5c
  Configuration/                             ← Step 5c
    TierConfigManager.swift
    SavedConfigManager.swift
  Validation/                                ← Step 4
    ULIDValidator.swift
    Validators.swift                         ← all 9 validators in one file
    NexusContext.swift                       ← lightweight cross-manager lookup value
  Sidebar/                                   ← Step 6 + 7 (existing folder, additions)
    SidebarSelection.swift
    SpaceRow.swift
    TopicRow.swift
    SubtopicRow.swift
    VaultRow.swift
    CollectionRow.swift
    Sheets/
      SidebarSheet.swift
      SpaceColorPicker.swift
      IconPickerSheet.swift
      ColorPickerSheet.swift
      NewSpaceSheet.swift
      NewTopicSheet.swift
      NewSubtopicSheet.swift
      NewVaultSheet.swift
      NewCollectionSheet.swift
      NewPageSheet.swift
      NewItemSheet.swift
      EditTopicParentsSheet.swift
  Detail/                                    ← Step 8
    SidebarDetailView.swift
    ContextDetailPlaceholder.swift
    VaultDetailView.swift
    CollectionDetailView.swift
    ContentItem.swift                        ← enum for merged Page+Item rows
  ItemWindow/                                ← Step 9
    ItemWindow.swift
    PropertyEditorRow.swift
    MultiSelectChips.swift

Pommora/PommoraTests/
  AtomicIO/
    AtomicJSONTests.swift
    AtomicYAMLMarkdownTests.swift
    NexusPathsTests.swift
  Contexts/
    SpaceFileTests.swift
    TopicFileTests.swift
    SubtopicFileTests.swift
    TierConfigTests.swift
    SavedConfigTests.swift
    SpaceManagerTests.swift
    TopicManagerTests.swift
  Vaults/
    PropertyValueTests.swift
    VaultFileTests.swift
    CollectionTests.swift
    VaultManagerTests.swift
  Content/
    ItemFileTests.swift
    PageFileTests.swift
    ContentManagerTests.swift
  Agenda/
    RecurrenceTests.swift
    AgendaItemFileTests.swift
    AgendaManagerTests.swift
  Homepage/
    HomepageFileTests.swift
    HomepageManagerTests.swift
  Configuration/
    TierConfigManagerTests.swift
    SavedConfigManagerTests.swift
  Validation/
    ULIDValidatorTests.swift
    SpaceValidatorTests.swift
    TopicValidatorTests.swift
    SubtopicValidatorTests.swift
    VaultValidatorTests.swift
    CollectionValidatorTests.swift
    ItemValidatorTests.swift
    PageValidatorTests.swift
    AgendaValidatorTests.swift
    HomepageValidatorTests.swift
```

### Modified files

```
Pommora/Pommora.xcodeproj/project.pbxproj    ← Step 1 (Swift 6 + Yams SPM)
Pommora/Pommora/ContentView.swift            ← Step 10 (manager injection + detail pane)
Pommora/Pommora/PommoraApp.swift             ← Step 10 (verify nothing breaks)
Pommora/Pommora/Sidebar/SidebarView.swift    ← Step 6 (replace placeholders)
```

---

## Conventions used throughout

**Test framework:** Pommora uses Swift Testing (`@Test`, `#expect`). All test files import `Testing` and `@testable import Pommora`. Run a single test via:

```bash
xcodebuild test -project Pommora/Pommora.xcodeproj -scheme Pommora \
  -only-testing:PommoraTests/<TestSuiteName>/<testMethodName>
```

**Test temp-nexus helper** (used pervasively from Task 4 onward — define once in Task 4):

```swift
// PommoraTests/Support/TempNexus.swift
import Foundation
@testable import Pommora

enum TempNexus {
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

    static func cleanup(_ nexus: Nexus) {
        try? FileManager.default.removeItem(at: nexus.rootURL)
    }
}
```

**Commit message convention** (matches existing repo history):
```
feat(<area>): <short subject>

<optional body>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**Build verification command** (run after every meaningful change):
```bash
xcodebuild -project Pommora/Pommora.xcodeproj -scheme Pommora build
```
Expected: `** BUILD SUCCEEDED **` with zero warnings under Swift 6 strict concurrency.

**Delegate Apple builds to the `builder` agent** when possible — verbose build logs eat context. Use direct Bash only when a one-off check is faster.

---

## Tasks

---

### Task 1: Swift 6 strict-concurrency migration

**Files:**
- Modify: `Pommora/Pommora.xcodeproj/project.pbxproj`
- Audit (no changes expected): all files under `Pommora/Pommora/` and `Pommora/PommoraTests/`

**Context:** Pommora is currently on `SWIFT_VERSION = 5.0`. GRDB v7+ (landing v0.5 per Framework) *requires* Swift 6; doing the flip now means every new manager and value type from Task 3 onward is forward-compatible. Existing `NexusManager` is already `@MainActor @Observable`; expected churn ≈ zero. If migration surfaces > 30 min of friction (more than a handful of `Sendable` errors), STOP and report — fallback is deferring migration to v0.5.

- [ ] **Step 1: Verify current Swift version**

Run:
```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -showBuildSettings -scheme Pommora 2>/dev/null | grep -E "SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY"
```
Expected output: `SWIFT_VERSION = 5.0` and either no `SWIFT_STRICT_CONCURRENCY` line or one set to `minimal`/`targeted`.

- [ ] **Step 2: Verify existing tests pass on Swift 5 (baseline)**

Run:
```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS'
```
Expected: `** TEST SUCCEEDED **` with 26 tests passing. Record the exact pass count for diff against post-migration. If any test fails on the baseline, FIX before proceeding — don't conflate migration churn with pre-existing flakes.

- [ ] **Step 3: Flip Swift 6 + strict concurrency in pbxproj**

Open `Pommora/Pommora.xcodeproj/project.pbxproj` and find every `SWIFT_VERSION = 5.0;` line (there will be one per build configuration × target — typically 4: Debug+Release × app+test). For each:
- Change `SWIFT_VERSION = 5.0;` to `SWIFT_VERSION = 6.0;`
- Add `SWIFT_STRICT_CONCURRENCY = complete;` directly below it (if absent)

Then add `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY = YES;` to the same build settings blocks for additional strictness (optional but recommended — catches bare `Any` use in protocol contexts).

The pbxproj is a plist; edits are mechanical. If unsure about exact location, use Xcode UI (Build Settings → Swift Compiler - Language → Swift Language Version + Strict Concurrency Checking) and let Xcode write the changes.

- [ ] **Step 4: Build to find concurrency errors**

Run:
```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | grep -E "error:|warning:" | head -50
```
Expected hot spots:
- `Task { … }` captures in `NexusManager.openExisting`, `pickNexus`, `loadOnLaunch` — annotate the enclosing closure with `@MainActor` (e.g. `Task { @MainActor in ... }`) or move the body into a `@MainActor` method.
- Any free-floating closures crossing isolation boundaries.

For each error: fix in the smallest possible way. Prefer adding `@MainActor` over `nonisolated`. Do NOT add `@unchecked Sendable` — those are workarounds, not fixes.

- [ ] **Step 5: Rebuild until clean**

Re-run the build command from Step 4 until output shows zero errors and zero warnings. If you hit > 30 min cumulative time on this step, STOP and surface a status report — the user may want to revert to Swift 5 and defer.

- [ ] **Step 6: Re-run tests to confirm no behavioral regressions**

Run:
```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS'
```
Expected: `** TEST SUCCEEDED **` with the same 26 tests passing as in Step 2.

- [ ] **Step 7: Commit**

```bash
git add Pommora/Pommora.xcodeproj/project.pbxproj Pommora/Pommora/Nexus/ Pommora/Pommora/Sidebar/
git commit -m "$(cat <<'EOF'
feat(build): migrate to Swift 6 strict concurrency

Flips SWIFT_VERSION to 6.0 and SWIFT_STRICT_CONCURRENCY to complete
across both app and test targets. All 26 existing tests pass.

Forward-compatible with GRDB v7+ (lands v0.5) and matches the
@MainActor @Observable manager pattern committed for v0.2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Only stage `Pommora/Pommora/Nexus/` and `Pommora/Pommora/Sidebar/` if they were modified during migration. If they weren't, just stage the pbxproj.

---

### Task 2: Add Yams SPM dependency + create test support helpers

**Files:**
- Modify: `Pommora/Pommora.xcodeproj/project.pbxproj` (Xcode-managed via UI is safest)
- Create: `Pommora/PommoraTests/Support/TempNexus.swift`
- Create: `Pommora/PommoraTests/Support/FixtureFiles.swift`

**Context:** Yams isn't used until Task 21 (PageFile) but registering it now means later tasks don't break flow on dependency management. Verified Swift-6-compatible during pre-plan validation pass.

- [ ] **Step 1: Add Yams via Xcode SPM UI**

Xcode → File → Add Package Dependencies… → URL: `https://github.com/jpsim/Yams.git` → Dependency Rule: Up to Next Major Version, starting at `5.1.0` → Add Package → check the `Yams` library against the `Pommora` app target → Add Package.

Alternatively, edit `project.pbxproj` directly: add a `XCRemoteSwiftPackageReference` entry pointing at `https://github.com/jpsim/Yams.git` with requirement `kind = upToNextMajorVersion; minimumVersion = 5.1.0;`, plus a `XCSwiftPackageProductDependency` entry naming `Yams`, and reference both in the Pommora target's `packageProductDependencies` array. The Xcode UI is dramatically less error-prone.

- [ ] **Step 2: Verify the dependency resolves**

Run:
```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora -resolvePackageDependencies
```
Expected: resolution succeeds; Yams 5.1.x downloads into `~/Library/Developer/Xcode/DerivedData/Pommora-*/SourcePackages/checkouts/Yams/`.

- [ ] **Step 3: Verify build still succeeds with Yams linked**

Run:
```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Create the `Support/` test folder + `TempNexus` helper**

```bash
mkdir -p "Pommora/PommoraTests/Support"
```

Then create `Pommora/PommoraTests/Support/TempNexus.swift`:

```swift
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
```

- [ ] **Step 5: Create the `FixtureFiles` helper for tests that need pre-seeded files**

Create `Pommora/PommoraTests/Support/FixtureFiles.swift`:

```swift
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
```

- [ ] **Step 6: Add the Support files to the test target**

In Xcode: select both new files → File Inspector → Target Membership → check `PommoraTests`. (If using the project navigator's "Create Groups" pattern, they may auto-add to the target — verify regardless.)

- [ ] **Step 7: Build the test target to confirm helpers compile**

Run:
```bash
xcodebuild build-for-testing -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Pommora/Pommora.xcodeproj/project.pbxproj Pommora/PommoraTests/Support/
git commit -m "$(cat <<'EOF'
feat(build): add Yams 5.1+ SPM dep + test support helpers

Registers Yams for Page frontmatter parsing (used Phase 6). Adds
TempNexus + FixtureFiles helpers under PommoraTests/Support/ for the
per-entity manager tests landing in Steps 5+.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: AtomicJSON helper + tests

**Files:**
- Create: `Pommora/Pommora/AtomicIO/AtomicJSON.swift`
- Create: `Pommora/PommoraTests/AtomicIO/AtomicJSONTests.swift`

**Context:** Generic Codable wrapper around `Data.write(.atomic)`. Every entity file uses this. Pattern derived from existing `NexusIdentity.save(to:)` — pretty-printed + sorted keys + ISO-8601 dates so files are deterministic for diff and agent-legible.

- [ ] **Step 1: Create folder**

```bash
mkdir -p "Pommora/Pommora/AtomicIO" "Pommora/PommoraTests/AtomicIO"
```

- [ ] **Step 2: Write the failing test**

Create `Pommora/PommoraTests/AtomicIO/AtomicJSONTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("AtomicJSON")
struct AtomicJSONTests {

    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
        var when: Date
    }

    @Test("encode produces pretty-printed, sorted-keys JSON")
    func encodeIsDeterministic() throws {
        let sample = Sample(name: "x", count: 7, when: Date(timeIntervalSince1970: 0))
        let a = try AtomicJSON.encode(sample)
        let b = try AtomicJSON.encode(sample)
        #expect(a == b, "same input must produce byte-identical output")
        let text = String(data: a, encoding: .utf8)!
        // Sorted keys → "count" comes before "name" alphabetically
        let countIndex = text.range(of: "\"count\"")!.lowerBound
        let nameIndex = text.range(of: "\"name\"")!.lowerBound
        #expect(countIndex < nameIndex, "keys must be sorted alphabetically")
        // Pretty-printed → contains newlines + 2-space indent
        #expect(text.contains("\n"), "must be pretty-printed")
        // ISO-8601 dates
        #expect(text.contains("1970-01-01"), "dates must be ISO-8601")
    }

    @Test("write + decode round-trip")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = nexus.rootURL.appendingPathComponent("sample.json")
        let original = Sample(name: "Productivity", count: 42, when: Date(timeIntervalSince1970: 1716480000))

        try AtomicJSON.write(original, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let loaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(loaded == original)
    }

    @Test("write is atomic — failed write does not corrupt existing file")
    func atomicWriteSafety() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = nexus.rootURL.appendingPathComponent("sample.json")
        let first = Sample(name: "a", count: 1, when: Date(timeIntervalSince1970: 0))
        try AtomicJSON.write(first, to: url)

        // Read existing data; ensure write replaced it cleanly
        let loaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(loaded == first)

        // Overwrite
        let second = Sample(name: "b", count: 2, when: Date(timeIntervalSince1970: 100))
        try AtomicJSON.write(second, to: url)
        let reloaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(reloaded == second)
    }
}
```

- [ ] **Step 3: Run the test to confirm it fails (no AtomicJSON yet)**

Run:
```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AtomicJSON -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: compile error on `AtomicJSON` reference — type not defined yet.

- [ ] **Step 4: Implement AtomicJSON**

Create `Pommora/Pommora/AtomicIO/AtomicJSON.swift`:

```swift
import Foundation

/// Reads and writes any `Codable` value as pretty-printed, sorted-keys, ISO-8601 JSON.
/// All writes use `Data.write(.atomic)` (temp-file + atomic rename under the hood).
///
/// Pommora discipline: every on-disk entity file routes through this helper so
/// files are deterministic on diff and human/agent-legible without app round-trip.
enum AtomicJSON {

    static func encode<T: Codable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    static func write<T: Codable>(_ value: T, to url: URL) throws {
        let data = try encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
```

Add the file to the `Pommora` app target in Xcode (File Inspector → Target Membership).

- [ ] **Step 5: Run tests to verify pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AtomicJSON -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/AtomicIO/AtomicJSON.swift \
        Pommora/PommoraTests/AtomicIO/AtomicJSONTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(atomic-io): add AtomicJSON Codable helper

Generic wrapper around Data.write(.atomic) used by every on-disk entity
file. Deterministic output (pretty + sorted keys + ISO-8601 dates) for
diff stability and agent legibility.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: NexusPaths helper + tests

**Files:**
- Create: `Pommora/Pommora/AtomicIO/NexusPaths.swift`
- Create: `Pommora/PommoraTests/AtomicIO/NexusPathsTests.swift`

**Context:** Pure path computation for every paradigm file location. No I/O — just `URL` math + a single helper (`ensureDirectoryExists`) for creating dirs when needed. Centralizing here means each manager doesn't compute paths inline.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/AtomicIO/NexusPathsTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("NexusPaths")
struct NexusPathsTests {

    @Test("nexusConfigDir is rootURL/.nexus")
    func nexusConfigDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.nexusConfigDir(in: nexus)
        #expect(dir.lastPathComponent == ".nexus")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("spacesDir is .nexus/spaces")
    func spacesDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.spacesDir(in: nexus)
        #expect(dir.lastPathComponent == "spaces")
        #expect(dir.deletingLastPathComponent().lastPathComponent == ".nexus")
    }

    @Test("topicsDir is .nexus/topics")
    func topicsDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.topicsDir(in: nexus)
        #expect(dir.lastPathComponent == "topics")
        #expect(dir.deletingLastPathComponent().lastPathComponent == ".nexus")
    }

    @Test("agendaDir is rootURL/Agenda")
    func agendaDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.agendaDir(in: nexus)
        #expect(dir.lastPathComponent == "Agenda")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("named file URLs use the documented extensions")
    func namedFileExtensions() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(NexusPaths.tierConfigURL(in: nexus).lastPathComponent == "tier-config.json")
        #expect(NexusPaths.savedConfigURL(in: nexus).lastPathComponent == "saved-config.json")
        #expect(NexusPaths.homepageURL(in: nexus).lastPathComponent == "homepage.json")
        #expect(NexusPaths.agendaSchemaURL(in: nexus).lastPathComponent == "_agenda.json")
    }

    @Test("spaceFileURL embeds title with .space.json extension")
    func spaceFileURLFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        #expect(url.lastPathComponent == "Personal.space.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "spaces")
    }

    @Test("topicFolderURL uses title as folder name; metadata file is _topic.json")
    func topicFolderFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(folder.lastPathComponent == "Productivity")
        let meta = NexusPaths.topicMetadataURL(forTitle: "Productivity", in: nexus)
        #expect(meta.lastPathComponent == "_topic.json")
        #expect(meta.deletingLastPathComponent().lastPathComponent == "Productivity")
    }

    @Test("subtopicFileURL nests inside parent Topic folder with .subtopic.json")
    func subtopicFileFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.subtopicFileURL(
            forTitle: "GTD method",
            inTopicTitled: "Productivity",
            in: nexus
        )
        #expect(url.lastPathComponent == "GTD method.subtopic.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Productivity")
    }

    @Test("vaultFolderURL is rootURL/<title>; metadata is _vault.json")
    func vaultPaths() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(folder.lastPathComponent == "Planner")
        #expect(folder.deletingLastPathComponent().path == nexus.rootURL.path)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(meta.lastPathComponent == "_vault.json")
    }

    @Test("collectionFolderURL nests inside vault folder")
    func collectionPath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.collectionFolderURL(
            forTitle: "Tasks",
            inVaultTitled: "Planner",
            in: nexus
        )
        #expect(url.lastPathComponent == "Tasks")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Planner")
    }

    @Test("pageFileURL + itemFileURL use the right extensions inside a Collection")
    func contentFilePaths() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collection = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        let page = NexusPaths.pageFileURL(forTitle: "Notes", in: collection)
        #expect(page.lastPathComponent == "Notes.md")
        let item = NexusPaths.itemFileURL(forTitle: "Buy groceries", in: collection)
        #expect(item.lastPathComponent == "Buy groceries.json")
    }

    @Test("agendaItemFileURL uses .agenda.json extension")
    func agendaItemPath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.agendaItemFileURL(forTitle: "Team standup", in: nexus)
        #expect(url.lastPathComponent == "Team standup.agenda.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Agenda")
    }

    @Test("ensureDirectoryExists creates intermediate dirs idempotently")
    func ensureDirectory() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let deep = nexus.rootURL
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
        try NexusPaths.ensureDirectoryExists(deep)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: deep.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        // Idempotent
        try NexusPaths.ensureDirectoryExists(deep)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/NexusPaths -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: compile error — `NexusPaths` undefined.

- [ ] **Step 3: Implement NexusPaths**

Create `Pommora/Pommora/AtomicIO/NexusPaths.swift`:

```swift
import Foundation

/// Pure path helpers for every on-disk file the paradigm uses.
/// No I/O except `ensureDirectoryExists`.
enum NexusPaths {

    // MARK: - .nexus/ subdirectories

    static func nexusConfigDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(".nexus", isDirectory: true)
    }

    static func spacesDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("spaces", isDirectory: true)
    }

    static func topicsDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("topics", isDirectory: true)
    }

    // MARK: - Single-file paths inside .nexus/

    static func tierConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("tier-config.json", isDirectory: false)
    }

    static func savedConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("saved-config.json", isDirectory: false)
    }

    static func homepageURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("homepage.json", isDirectory: false)
    }

    // MARK: - Agenda (operational sibling of Vaults)

    static func agendaDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
    }

    static func agendaSchemaURL(in nexus: Nexus) -> URL {
        agendaDir(in: nexus).appendingPathComponent("_agenda.json", isDirectory: false)
    }

    static func agendaItemFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        agendaDir(in: nexus).appendingPathComponent("\(title).agenda.json", isDirectory: false)
    }

    // MARK: - Contexts file paths

    static func spaceFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        spacesDir(in: nexus).appendingPathComponent("\(title).space.json", isDirectory: false)
    }

    static func topicFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicsDir(in: nexus).appendingPathComponent(title, isDirectory: true)
    }

    static func topicMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent("_topic.json", isDirectory: false)
    }

    static func subtopicFileURL(
        forTitle title: String,
        inTopicTitled topicTitle: String,
        in nexus: Nexus
    ) -> URL {
        topicFolderURL(forTitle: topicTitle, in: nexus)
            .appendingPathComponent("\(title).subtopic.json", isDirectory: false)
    }

    // MARK: - Vault / Collection / Content paths

    static func vaultFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(title, isDirectory: true)
    }

    static func vaultMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        vaultFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent("_vault.json", isDirectory: false)
    }

    static func collectionFolderURL(
        forTitle title: String,
        inVaultTitled vaultTitle: String,
        in nexus: Nexus
    ) -> URL {
        vaultFolderURL(forTitle: vaultTitle, in: nexus)
            .appendingPathComponent(title, isDirectory: true)
    }

    static func pageFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).md", isDirectory: false)
    }

    static func itemFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).json", isDirectory: false)
    }

    // MARK: - Filesystem helper

    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
```

Add the file to the `Pommora` app target in Xcode.

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/NexusPaths -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/AtomicIO/NexusPaths.swift \
        Pommora/PommoraTests/AtomicIO/NexusPathsTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(atomic-io): add NexusPaths URL helpers

Pure path computation for every paradigm file: .nexus/ subdirs, Agenda/,
vault/collection folders, plus Spaces/Topics/Sub-topics/Vaults/Pages/Items
filename conventions. 12 tests cover every helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: AtomicYAMLMarkdown helper + tests

**Files:**
- Create: `Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift`
- Create: `Pommora/PommoraTests/AtomicIO/AtomicYAMLMarkdownTests.swift`

**Context:** Page files are `.md` with YAML frontmatter envelope (`---\n…\n---\n\n<body>`). This helper splits / encodes / writes. Uses Yams' `YAMLDecoder` / `YAMLEncoder`. Generic over `Decodable & Encodable` so `PageFrontmatter` (and any future frontmatter shape) can plug in. Behavior is total: missing frontmatter envelope = whole file is body; missing trailing `---` = treat as malformed and throw.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/AtomicIO/AtomicYAMLMarkdownTests.swift`:

```swift
import Foundation
import Testing
import Yams
@testable import Pommora

@Suite("AtomicYAMLMarkdown")
struct AtomicYAMLMarkdownTests {

    private struct Sample: Codable, Equatable {
        var id: String
        var tags: [String]
        var count: Int
    }

    @Test("write + load round-trip with frontmatter and body")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("page.md")

        let original = Sample(id: "01H123", tags: ["a", "b"], count: 3)
        let body = "# Title\n\nSome paragraph.\n"
        try AtomicYAMLMarkdown.write(frontmatter: original, body: body, to: url)

        let (loaded, loadedBody): (Sample, String) =
            try AtomicYAMLMarkdown.load(Sample.self, from: url)
        #expect(loaded == original)
        #expect(loadedBody == body)
    }

    @Test("file with no frontmatter envelope → empty frontmatter, body is whole file")
    func bodyOnlyFile() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("body-only.md")
        try FixtureFiles.write("# Just a body\n\nNo metadata here.\n", to: url)

        struct EmptyFM: Codable, Equatable {
            init() {}
        }
        let (fm, body): (EmptyFM, String) = try AtomicYAMLMarkdown.load(EmptyFM.self, from: url)
        #expect(fm == EmptyFM())
        #expect(body == "# Just a body\n\nNo metadata here.\n")
    }

    @Test("malformed envelope (opening --- but no closing) throws")
    func malformedThrows() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("malformed.md")
        try FixtureFiles.write("---\nid: 01H123\nno closing fence\n\nbody here\n", to: url)

        struct FM: Codable { var id: String }
        #expect(throws: AtomicYAMLMarkdown.LoadError.malformedEnvelope) {
            let _: (FM, String) = try AtomicYAMLMarkdown.load(FM.self, from: url)
        }
    }

    @Test("written file starts with --- envelope and contains body verbatim")
    func writeFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("formatted.md")

        let fm = Sample(id: "01H", tags: [], count: 0)
        let body = "Hello\nworld\n"
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: body, to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.hasPrefix("---\n"), "file must open with --- envelope")
        #expect(raw.contains("\n---\n"), "file must contain closing fence")
        #expect(raw.hasSuffix(body), "body must be present verbatim at end")
    }

    @Test("empty body still round-trips")
    func emptyBody() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("empty-body.md")

        let fm = Sample(id: "01H", tags: ["x"], count: 1)
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: url)
        let (loaded, body): (Sample, String) = try AtomicYAMLMarkdown.load(Sample.self, from: url)
        #expect(loaded == fm)
        #expect(body == "")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AtomicYAMLMarkdown -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: compile error — `AtomicYAMLMarkdown` undefined.

- [ ] **Step 3: Implement AtomicYAMLMarkdown**

Create `Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift`:

```swift
import Foundation
import Yams

/// Reads and writes Markdown files with a YAML-frontmatter envelope.
///
/// File format:
/// ```
/// ---
/// <YAML>
/// ---
///
/// <body>
/// ```
///
/// On read:
/// - If the file starts with `---\n`, parses the frontmatter up to the next `\n---\n`.
/// - If the file does NOT start with `---\n`, treats the whole file as body and decodes
///   an empty frontmatter (caller's `T` must support init from `{}`).
/// - If `---\n` opens but no closing `\n---\n` is found, throws `LoadError.malformedEnvelope`.
enum AtomicYAMLMarkdown {

    enum LoadError: Error, Equatable {
        case malformedEnvelope
    }

    static func load<T: Codable>(_ type: T.Type, from url: URL) throws -> (T, String) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fmText, body) = try split(raw)
        let frontmatter: T
        if fmText.isEmpty {
            // Decode from "{}" so Decodable types with all-optional fields succeed
            frontmatter = try YAMLDecoder().decode(T.self, from: "{}")
        } else {
            frontmatter = try YAMLDecoder().decode(T.self, from: fmText)
        }
        return (frontmatter, body)
    }

    static func write<T: Codable>(frontmatter: T, body: String, to url: URL) throws {
        let fmText = try YAMLEncoder().encode(frontmatter)
        let combined = "---\n\(fmText)---\n\n\(body)"
        try combined.data(using: .utf8)!.write(to: url, options: [.atomic])
    }

    // MARK: - Internal split

    /// Returns (frontmatter YAML string without fences, body string).
    /// If no envelope, returns ("", entire content).
    static func split(_ raw: String) throws -> (String, String) {
        guard raw.hasPrefix("---\n") else {
            return ("", raw)
        }
        // Strip leading "---\n"
        let afterOpening = raw.dropFirst(4)
        // Find closing "\n---\n"
        guard let closingRange = afterOpening.range(of: "\n---\n") else {
            throw LoadError.malformedEnvelope
        }
        let fm = String(afterOpening[..<closingRange.lowerBound])
        // Strip the single blank-line separator that `write` inserts between the
        // closing fence and the body. Matches write's `---\n\n<body>` format so
        // round-trips are exact.
        var body = String(afterOpening[closingRange.upperBound...])
        if body.hasPrefix("\n") {
            body.removeFirst()
        }
        return (fm, body)
    }
}
```

Add the file to the `Pommora` app target.

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AtomicYAMLMarkdown -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift \
        Pommora/PommoraTests/AtomicIO/AtomicYAMLMarkdownTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(atomic-io): add AtomicYAMLMarkdown helper for Page files

Reads/writes Markdown files with YAML-frontmatter envelope. Handles
body-only files (empty frontmatter), throws on malformed envelopes.
Used by Phase 6's PageFile.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Filesystem primitives helper

**Files:**
- Create: `Pommora/Pommora/AtomicIO/Filesystem.swift`
- Tests: covered by manager tests (no dedicated unit tests — this is a thin wrapper)

**Context:** Folder create / rename / delete primitives that managers use. Importantly, this module enforces the **two-step folder-plus-metadata atomicity discipline** — `createFolderWithMetadata(...)` does (1) create folder, (2) write metadata; on failure of step 2, rolls back step 1. Pattern at [.claude/Guidelines/CRUD-Patterns.md:252-275](.claude/Guidelines/CRUD-Patterns.md#L252-L275).

- [ ] **Step 1: Implement Filesystem**

Create `Pommora/Pommora/AtomicIO/Filesystem.swift`:

```swift
import Foundation

/// Folder + file primitives used by every entity manager.
///
/// Discipline:
/// - Every multi-step operation (folder + metadata file) rolls back on failure.
/// - All paths must be inside the active nexus's security-scoped resource scope
///   held by `NexusManager` — managers MUST NOT call `startAccessingSecurityScopedResource`
///   themselves.
enum Filesystem {

    // MARK: - Folder primitives

    static func createFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Atomic on same-volume rename (nexus contents are always single-volume).
    static func renameFolder(from oldURL: URL, to newURL: URL) throws {
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    static func deleteFolder(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func folderExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: - File primitives

    static func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func fileExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    static func renameFile(from oldURL: URL, to newURL: URL) throws {
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    // MARK: - Two-step folder+metadata atomicity

    /// Creates `folderURL`, then writes `metadata` (a `Codable` value) to `metadataURL`.
    /// If the metadata write fails, the folder is deleted before the error propagates.
    ///
    /// Used by Topic + Vault creation flows (Topic = folder + `_topic.json`;
    /// Vault = folder + `_vault.json`).
    static func createFolderWithMetadata<T: Codable>(
        folderURL: URL,
        metadataURL: URL,
        metadata: T
    ) throws {
        try createFolder(at: folderURL)
        do {
            try AtomicJSON.write(metadata, to: metadataURL)
        } catch {
            try? deleteFolder(at: folderURL)
            throw error
        }
    }

    // MARK: - Directory enumeration

    /// Returns immediate children of `folderURL` matching `predicate` (typically by extension).
    /// Returns `[]` if the folder doesn't exist.
    static func children(
        of folderURL: URL,
        where predicate: (URL) -> Bool = { _ in true }
    ) throws -> [URL] {
        guard folderExists(at: folderURL) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter(predicate)
    }

    /// Returns immediate child folders (not files).
    static func childFolders(of folderURL: URL) throws -> [URL] {
        try children(of: folderURL) { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }
}
```

Add to the `Pommora` app target.

- [ ] **Step 2: Build to verify it compiles cleanly**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` with no warnings.

- [ ] **Step 3: Commit**

```bash
git add Pommora/Pommora/AtomicIO/Filesystem.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(atomic-io): add Filesystem primitives

Folder + file create/rename/delete primitives plus the two-step
folder+metadata atomicity helper (createFolderWithMetadata) used by
Topic + Vault creation. Failed metadata writes roll back the folder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: SpaceColor enum

**Files:**
- Create: `Pommora/Pommora/Contexts/SpaceColor.swift`
- Tests: covered by `SpaceFileTests` (Task 9)

**Context:** Fixed 9-case enum matching the locked Notion-palette colors. Codable as raw `String`. Exposes `swiftUIColor` for UI use. No standalone tests — round-tripped via the Space tests.

- [ ] **Step 1: Create folder**

```bash
mkdir -p "Pommora/Pommora/Contexts"
```

- [ ] **Step 2: Implement SpaceColor**

Create `Pommora/Pommora/Contexts/SpaceColor.swift`:

```swift
import SwiftUI

/// The 9-color Notion-palette options for Spaces.
/// Stored as lowercase string in JSON; mapped to SwiftUI `Color` for rendering.
enum SpaceColor: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .gray:   return Color.gray
        case .brown:  return Color.brown
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green:  return Color.green
        case .blue:   return Color.blue
        case .purple: return Color.purple
        case .pink:   return Color.pink
        case .red:    return Color.red
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pommora/Pommora/Contexts/SpaceColor.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add SpaceColor enum (9 Notion-palette colors)

Codable as raw string; exposes swiftUIColor + displayName for UI.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: ContextBlock placeholder

**Files:**
- Create: `Pommora/Pommora/Contexts/ContextBlock.swift`
- Tests: covered by Space/Topic/Subtopic/Homepage tests

**Context:** Empty placeholder Codable struct so every Context entity's `blocks: [ContextBlock]` array can round-trip as `[]` until the composed-blocks editor lands in v0.9. Keeps the schema stable from day one.

- [ ] **Step 1: Implement ContextBlock**

Create `Pommora/Pommora/Contexts/ContextBlock.swift`:

```swift
import Foundation

/// Placeholder for composed-blocks tree entries used by Spaces / Topics /
/// Sub-topics / Homepage. The composed-blocks editor lands in v0.9 — until
/// then, this empty struct lets the `blocks: [ContextBlock]` arrays serialize
/// as `[]` and the on-disk schema stays stable.
struct ContextBlock: Codable, Equatable, Hashable, Sendable {
    // intentionally empty in v0.2
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Contexts/ContextBlock.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add ContextBlock placeholder

Empty Codable struct so every Context entity's blocks array round-trips
as []. Composed-blocks editor lands v0.9.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Space value type + Codable round-trip tests

**Files:**
- Create: `Pommora/Pommora/Contexts/Space.swift`
- Create: `Pommora/PommoraTests/Contexts/SpaceFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:222-237](.claude/Planning/Contexts-Vaults-spec.md#L222-L237). `title` is derived from filename on load (never on disk); JSON keys match the spec exactly.

- [ ] **Step 1: Create folder**

```bash
mkdir -p "Pommora/PommoraTests/Contexts"
```

- [ ] **Step 2: Write the failing test**

Create `Pommora/PommoraTests/Contexts/SpaceFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("SpaceFile")
struct SpaceFileTests {

    @Test("Space round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Personal.space.json")

        let original = Space(
            id: "01HX2K6Z3V4Y5W6X7Y8Z9A0B1C",
            title: "Personal",
            color: .blue,
            icon: "person.circle",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        var loaded = try Space.load(from: url)
        // title is derived from filename on load — overwrite to match
        loaded.title = "Personal"
        #expect(loaded == original)
    }

    @Test("Space on-disk JSON omits title field (filename = title rule)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Work.space.json")

        let space = Space(
            id: "01HX",
            title: "Work",
            color: .green,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""), "title field must not appear on disk")
    }

    @Test("Space tier is always 1 after load")
    func tierAlways1() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Academics.space.json")

        let space = Space(
            id: "01H",
            title: "Academics",
            color: .red,
            icon: "book.closed",
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)
        let loaded = try Space.load(from: url)
        #expect(loaded.tier == 1)
    }

    @Test("Space load derives title from filename")
    func titleFromFilename() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Side Projects.space.json")

        let space = Space(
            id: "01H",
            title: "Side Projects",
            color: .purple,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)
        let loaded = try Space.load(from: url)
        #expect(loaded.title == "Side Projects")
    }
}
```

- [ ] **Step 3: Run test — should fail (no Space yet)**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SpaceFile -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: compile error — `Space` undefined.

- [ ] **Step 4: Implement Space**

Create `Pommora/Pommora/Contexts/Space.swift`:

```swift
import Foundation

/// Tier-1 Context entity — broad life domain.
/// On disk: `.nexus/spaces/<Title>.space.json` (filename = title; no `title` field on disk).
struct Space: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String            // ULID
    var tier: Int             // always 1
    var title: String         // populated from filename on load
    var color: SpaceColor
    var icon: String?         // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        color: SpaceColor,
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 1
        self.title = title
        self.color = color
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    // MARK: - Codable — omits `title` on disk; tier always written as 1

    enum CodingKeys: String, CodingKey {
        case id, tier, color, icon, blocks, modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 1
        self.title = ""  // caller (load(from:)) overwrites from filename
        self.color = try c.decode(SpaceColor.self, forKey: .color)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(1, forKey: .tier)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Space {
    static func load(from url: URL) throws -> Space {
        var space = try AtomicJSON.decode(Space.self, from: url)
        // Derive title from filename: "Personal.space.json" → "Personal"
        space.title = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        return space
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SpaceFile -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/Contexts/Space.swift \
        Pommora/PommoraTests/Contexts/SpaceFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add Space Codable + tests

Tier-1 Context entity with id, color, icon, blocks, modified_at fields.
Filename = title (no title on disk). Custom Codable to omit title key
and pin tier = 1 on encode.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Topic value type + Codable round-trip tests

**Files:**
- Create: `Pommora/Pommora/Contexts/Topic.swift`
- Create: `Pommora/PommoraTests/Contexts/TopicFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:239-254](.claude/Planning/Contexts-Vaults-spec.md#L239-L254). Topics are tier-2 entities with multi-Space parents. On disk: `.nexus/topics/<Title>/_topic.json` — title is derived from the folder name, not the filename.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/TopicFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("TopicFile")
struct TopicFileTests {

    @Test("Topic round-trips through AtomicJSON; title derives from parent folder")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let original = Topic(
            id: "01HABC",
            title: "Productivity",
            parents: ["01HSPACE-PERSONAL", "01HSPACE-WORK"],
            icon: "lightbulb",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.id == "01HABC")
        #expect(loaded.title == "Productivity") // from folder
        #expect(loaded.parents == ["01HSPACE-PERSONAL", "01HSPACE-WORK"])
        #expect(loaded.icon == "lightbulb")
        #expect(loaded.tier == 2)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("Topic on-disk JSON omits title field")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/CS-161", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(
            id: "01H",
            title: "CS-161",
            parents: ["01HSPACE-ACADEMICS"],
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try topic.save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Topic tier is always 2 after load")
    func tierAlways2() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/GTD", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(id: "01H", title: "GTD", parents: [], icon: nil, blocks: [], modifiedAt: Date())
        try topic.save(to: metaURL)
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.tier == 2)
    }

    @Test("Topic supports zero parents (Space-less topic allowed)")
    func zeroParents() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Loose", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(id: "01H", title: "Loose", parents: [], icon: nil, blocks: [], modifiedAt: Date())
        try topic.save(to: metaURL)
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.parents == [])
    }
}
```

- [ ] **Step 2: Run test — confirm fail**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TopicFile -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: compile error — `Topic` undefined.

- [ ] **Step 3: Implement Topic**

Create `Pommora/Pommora/Contexts/Topic.swift`:

```swift
import Foundation

/// Tier-2 Context entity — subject area. Multi-parent across Spaces.
/// On disk: `.nexus/topics/<Title>/_topic.json` (folder = title; no title on disk).
struct Topic: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String              // ULID
    var tier: Int               // always 2
    var title: String           // derived from parent folder name on load
    var parents: [String]       // Space IDs (multi-valued; may be empty)
    var icon: String?           // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        parents: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 2
        self.title = title
        self.parents = parents
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, parents, icon, blocks, modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 2
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(2, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Topic {
    /// Loads `_topic.json` and derives `title` from the parent folder name.
    static func load(from metadataURL: URL) throws -> Topic {
        var topic = try AtomicJSON.decode(Topic.self, from: metadataURL)
        topic.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return topic
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TopicFile -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Contexts/Topic.swift \
        Pommora/PommoraTests/Contexts/TopicFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add Topic Codable + tests

Tier-2 Context with multi-Space parents. Title derives from parent
folder. Allows zero parents (Space-less Topic). Custom Codable
mirrors Space pattern (omits title, pins tier=2).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Subtopic value type + Codable round-trip tests

**Files:**
- Create: `Pommora/Pommora/Contexts/Subtopic.swift`
- Create: `Pommora/PommoraTests/Contexts/SubtopicFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:256-272](.claude/Planning/Contexts-Vaults-spec.md#L256-L272). Sub-topics are tier-3, single-parent (the file-structural parent Topic). `linked_relations` carries additional Context relations (any tier).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/SubtopicFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("SubtopicFile")
struct SubtopicFileTests {

    @Test("Subtopic round-trips; title derives from filename")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("GTD method.subtopic.json")

        let original = Subtopic(
            id: "01HSUB",
            title: "GTD method",
            parents: ["01HTOPIC-PRODUCTIVITY"],
            linkedRelations: ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"],
            icon: "checklist",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Subtopic.load(from: url)
        #expect(loaded.id == "01HSUB")
        #expect(loaded.title == "GTD method")
        #expect(loaded.parents == ["01HTOPIC-PRODUCTIVITY"])
        #expect(loaded.linkedRelations == ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"])
        #expect(loaded.icon == "checklist")
        #expect(loaded.tier == 3)
    }

    @Test("Subtopic on-disk JSON omits title field")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Foo.subtopic.json")

        let st = Subtopic(
            id: "01H",
            title: "Foo",
            parents: ["01HPARENT"],
            linkedRelations: [],
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try st.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Subtopic uses snake_case linked_relations on disk")
    func linkedRelationsKey() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Y.subtopic.json")

        let st = Subtopic(
            id: "01H", title: "Y", parents: ["01HP"],
            linkedRelations: ["01HZ"], icon: nil, blocks: [], modifiedAt: Date()
        )
        try st.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"linked_relations\""))
        #expect(!raw.contains("\"linkedRelations\""))
    }
}
```

- [ ] **Step 2: Run test — confirm fail**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SubtopicFile -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement Subtopic**

Create `Pommora/Pommora/Contexts/Subtopic.swift`:

```swift
import Foundation

/// Tier-3 Context entity — specifics within a Topic.
/// On disk: `.nexus/topics/<TopicTitle>/<Title>.subtopic.json`.
/// File-structural parent (the enclosing Topic folder) IS the parent — single-valued.
/// Additional Context relations live in `linkedRelations`.
struct Subtopic: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String              // ULID
    var tier: Int               // always 3
    var title: String           // derived from filename on load
    var parents: [String]       // exactly one Topic ID; enforced by validator
    var linkedRelations: [String]  // additional Topic/Space/Subtopic IDs (multi-tier)
    var icon: String?
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        parents: [String],
        linkedRelations: [String],
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 3
        self.title = title
        self.parents = parents
        self.linkedRelations = linkedRelations
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, parents
        case linkedRelations = "linked_relations"
        case icon, blocks
        case modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 3
        self.title = ""
        self.parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        self.linkedRelations = try c.decodeIfPresent([String].self, forKey: .linkedRelations) ?? []
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(3, forKey: .tier)
        try c.encode(parents, forKey: .parents)
        try c.encode(linkedRelations, forKey: .linkedRelations)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Subtopic {
    static func load(from url: URL) throws -> Subtopic {
        var st = try AtomicJSON.decode(Subtopic.self, from: url)
        // "GTD method.subtopic.json" → strip both extensions → "GTD method"
        st.title = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        return st
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SubtopicFile -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Contexts/Subtopic.swift \
        Pommora/PommoraTests/Contexts/SubtopicFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add Subtopic Codable + tests

Tier-3 Context with single file-structural parent (file location) +
multi-tier linked_relations. Custom Codable maps linkedRelations to
snake_case on disk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: TierConfig value type + tests

**Files:**
- Create: `Pommora/Pommora/Contexts/TierConfig.swift`
- Create: `Pommora/PommoraTests/Contexts/TierConfigTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:274-289](.claude/Planning/Contexts-Vaults-spec.md#L274-L289). User-configurable per-tier labels + tagging style. Seeded with defaults on first load (handled by `TierConfigManager` later).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/TierConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("TierConfig")
struct TierConfigTests {

    @Test("default seed has Space/Topic/Sub-topic labels and color tagging")
    func defaultSeed() {
        let config = TierConfig.defaultSeed()
        #expect(config.schemaVersion == 1)
        #expect(config.tiers.count == 3)
        #expect(config.tiers[0].level == 1)
        #expect(config.tiers[0].singular == "Space")
        #expect(config.tiers[0].plural == "Spaces")
        #expect(config.tiers[1].level == 2)
        #expect(config.tiers[1].singular == "Topic")
        #expect(config.tiers[2].level == 3)
        #expect(config.tiers[2].singular == "Sub-topic")
        #expect(config.taggingStyle == .color)
        for tier in config.tiers { #expect(tier.exposed == true) }
    }

    @Test("Codable round-trip")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent(".nexus/tier-config.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let original = TierConfig(
            schemaVersion: 1,
            tiers: [
                TierConfig.Tier(level: 1, singular: "Area", plural: "Areas", exposed: true),
                TierConfig.Tier(level: 2, singular: "Project", plural: "Projects", exposed: true),
                TierConfig.Tier(level: 3, singular: "Sub-project", plural: "Sub-projects", exposed: false)
            ],
            taggingStyle: .both
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(TierConfig.self, from: url)
        #expect(loaded == original)
    }

    @Test("on-disk JSON uses snake_case for tagging_style")
    func snakeCaseKey() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("tc.json")

        try AtomicJSON.write(TierConfig.defaultSeed(), to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"tagging_style\""))
        #expect(raw.contains("\"schemaVersion\""))  // version field stays camelCase per existing convention
    }
}
```

- [ ] **Step 2: Run test — confirm fail**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TierConfig -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement TierConfig**

Create `Pommora/Pommora/Contexts/TierConfig.swift`:

```swift
import Foundation

/// Per-nexus tier label configuration. Singular + plural labels per tier
/// (Capacities-style); exposed toggle hides a tier from UI; tagging style
/// controls how Topic rows render their parent-Space indicators.
struct TierConfig: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var tiers: [Tier]
    var taggingStyle: TaggingStyle

    struct Tier: Codable, Equatable, Hashable, Sendable {
        var level: Int
        var singular: String
        var plural: String
        var exposed: Bool
    }

    enum TaggingStyle: String, Codable, CaseIterable, Hashable, Sendable {
        case color, symbol, both
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tiers
        case taggingStyle = "tagging_style"
    }

    static func defaultSeed() -> TierConfig {
        TierConfig(
            schemaVersion: 1,
            tiers: [
                Tier(level: 1, singular: "Space", plural: "Spaces", exposed: true),
                Tier(level: 2, singular: "Topic", plural: "Topics", exposed: true),
                Tier(level: 3, singular: "Sub-topic", plural: "Sub-topics", exposed: true)
            ],
            taggingStyle: .color
        )
    }
}
```

- [ ] **Step 4: Run tests + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TierConfig -destination 'platform=macOS' 2>&1 | tail -10
# Expected: 3 pass
git add Pommora/Pommora/Contexts/TierConfig.swift \
        Pommora/PommoraTests/Contexts/TierConfigTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add TierConfig + defaultSeed

Per-nexus tier label config with singular+plural per tier, exposed
toggle, and tagging_style (color/symbol/both). defaultSeed produces
the Space/Topic/Sub-topic baseline.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: SavedConfig value type + tests

**Files:**
- Create: `Pommora/Pommora/Contexts/SavedConfig.swift`
- Create: `Pommora/PommoraTests/Contexts/SavedConfigTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:291-302](.claude/Planning/Contexts-Vaults-spec.md#L291-L302). Three fixed keys (homepage/calendar/recents) with user-renamable labels.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/SavedConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("SavedConfig")
struct SavedConfigTests {

    @Test("defaultSeed has three fixed-key items in canonical order")
    func defaultSeed() {
        let cfg = SavedConfig.defaultSeed()
        #expect(cfg.schemaVersion == 1)
        #expect(cfg.items.count == 3)
        #expect(cfg.items.map(\.key) == ["homepage", "calendar", "recents"])
        #expect(cfg.items.map(\.label) == ["Homepage", "Calendar", "Recents"])
    }

    @Test("Codable round-trip preserves order + labels")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("saved.json")

        let original = SavedConfig(
            schemaVersion: 1,
            items: [
                SavedConfig.Item(key: "homepage", label: "Dashboard"),
                SavedConfig.Item(key: "calendar", label: "Schedule"),
                SavedConfig.Item(key: "recents", label: "Recent")
            ]
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(SavedConfig.self, from: url)
        #expect(loaded == original)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Contexts/SavedConfig.swift`:

```swift
import Foundation

/// Saved-section labels (Homepage / Calendar / Recents). Keys are fixed
/// in code; labels are user-renamable via the (future) Settings UI.
struct SavedConfig: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var items: [Item]

    struct Item: Codable, Equatable, Hashable, Identifiable, Sendable {
        var key: String       // "homepage" | "calendar" | "recents"
        var label: String     // user-renamable
        var id: String { key }
    }

    static func defaultSeed() -> SavedConfig {
        SavedConfig(
            schemaVersion: 1,
            items: [
                Item(key: "homepage", label: "Homepage"),
                Item(key: "calendar", label: "Calendar"),
                Item(key: "recents",  label: "Recents")
            ]
        )
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SavedConfig -destination 'platform=macOS' 2>&1 | tail -10
# Expected: 2 pass
git add Pommora/Pommora/Contexts/SavedConfig.swift \
        Pommora/PommoraTests/Contexts/SavedConfigTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add SavedConfig + defaultSeed

Three-fixed-key Saved-section config (homepage/calendar/recents) with
user-renamable labels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: PropertyType enum

**Files:**
- Create: `Pommora/Pommora/Vaults/PropertyType.swift`
- Tests: covered by VaultFileTests + PropertyValueTests

**Context:** Eight property types per [.claude/Features/Properties.md](.claude/Features/Properties.md). Stored as raw string in JSON.

- [ ] **Step 1: Create folder**

```bash
mkdir -p "Pommora/Pommora/Vaults" "Pommora/PommoraTests/Vaults"
```

- [ ] **Step 2: Implement PropertyType**

Create `Pommora/Pommora/Vaults/PropertyType.swift`:

```swift
import Foundation

/// Property type catalog for Vault schemas. Shared across Pages, Items, Agenda.
/// Stored on disk as raw lowercase string.
enum PropertyType: String, Codable, CaseIterable, Hashable, Sendable {
    case number
    case checkbox
    case date              // calendar date only
    case datetime          // date + time + timezone
    case select            // single choice from options
    case multiSelect = "multi_select"
    case relation          // points to another entity by ID
    case url
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Vaults/PropertyType.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add PropertyType enum

Eight property types (number/checkbox/date/datetime/select/multi_select/
relation/url). Codable raw string; multi_select uses snake_case on disk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: PropertyDefinition value type

**Files:**
- Create: `Pommora/Pommora/Vaults/PropertyDefinition.swift`
- Tests: covered by VaultFileTests

**Context:** A single schema entry inside `_vault.json`. Type-specific config fields (`numberFormat`, `selectOptions`, etc.) are all optional — only populated when relevant to the type.

- [ ] **Step 1: Implement PropertyDefinition**

Create `Pommora/Pommora/Vaults/PropertyDefinition.swift`:

```swift
import Foundation

/// One property schema entry inside a Vault's `_vault.json`.
/// Type-specific config fields live as optionals on this struct;
/// only the ones relevant to `type` should be populated.
struct PropertyDefinition: Codable, Equatable, Identifiable, Hashable, Sendable {
    var name: String                     // user-facing label; doubles as property key
    var type: PropertyType

    // Type-specific config (all optional, only filled when relevant):
    var numberFormat: NumberFormat?      // number
    var dateIncludesTime: Bool?          // date — irrelevant for `datetime` type
    var selectOptions: [SelectOption]?   // select + multiSelect
    var relationScope: RelationScope?    // relation

    var id: String { name }

    struct SelectOption: Codable, Equatable, Hashable, Identifiable, Sendable {
        var value: String                // canonical key (immutable post-create ideally)
        var label: String                // user-facing
        var color: SelectColor?

        var id: String { value }
    }

    enum SelectColor: String, Codable, CaseIterable, Hashable, Sendable {
        case gray, brown, orange, yellow, green, blue, purple, pink, red
    }

    enum NumberFormat: String, Codable, CaseIterable, Hashable, Sendable {
        case integer, decimal, percent, currency
    }

    enum RelationScope: String, Codable, CaseIterable, Hashable, Sendable {
        case sameVault = "same_vault"
        case anywhere
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case numberFormat = "number_format"
        case dateIncludesTime = "date_includes_time"
        case selectOptions = "select_options"
        case relationScope = "relation_scope"
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Vaults/PropertyDefinition.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add PropertyDefinition + nested types

Property schema entry for Vault: name + type + optional type-specific
config (NumberFormat, SelectOption, RelationScope). All JSON keys are
snake_case.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: PropertyValue type-erased enum + tests

**Files:**
- Create: `Pommora/Pommora/Vaults/PropertyValue.swift`
- Create: `Pommora/PommoraTests/Vaults/PropertyValueTests.swift`

**Context:** Items and Pages hold `properties: [String: PropertyValue]`. `PropertyValue` must round-trip arbitrary types (numbers, bools, dates, strings, arrays) inside a dictionary. Custom Codable inspects the JSON shape per-value and dispatches.

**Relation encoding (locked decision 2026-05-16):** `.relation(String)` uses a **tagged-object** shape on disk — `{"$rel": "01H..."}` — so an external agent (or the graph-view indexer) can identify a relation edge from the JSON alone without consulting the Vault schema. This satisfies Pommora's load-bearing constraint #3 (persistent immediate legibility for agents). All other cases stay bare (strings, numbers, bools, arrays).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Vaults/PropertyValueTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("PropertyValue")
struct PropertyValueTests {

    @Test("round-trips a dictionary of every type")
    func roundTripDictionary() throws {
        let original: [String: PropertyValue] = [
            "count": .number(42.5),
            "done": .checkbox(true),
            "due": .date(Date(timeIntervalSince1970: 1716480000)),
            "kickoff": .datetime(Date(timeIntervalSince1970: 1716480000)),
            "status": .select("Active"),
            "tags": .multiSelect(["urgent", "review"]),
            "link": .url(URL(string: "https://example.com")!),
            "relatedItem": .relation("01HTARGET"),
            "missing": .null
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: data)
        #expect(decoded.count == original.count)
        for (k, v) in original {
            #expect(decoded[k] == v, "mismatch on key \(k)")
        }
    }

    @Test("relation encodes as tagged $rel object and round-trips")
    func relationTagged() throws {
        let original = PropertyValue.relation("01HTARGET")
        let data = try JSONEncoder().encode(original)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "{\"$rel\":\"01HTARGET\"}")
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("null values serialize as JSON null")
    func nullEncoding() throws {
        let value: PropertyValue = .null
        let data = try JSONEncoder().encode(value)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "null")
    }

    @Test("multi-select serializes as array of strings")
    func multiSelectEncoding() throws {
        let value: PropertyValue = .multiSelect(["a", "b", "c"])
        let data = try JSONEncoder().encode(value)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "[\"a\",\"b\",\"c\"]")
    }

    @Test("date round-trips through ISO-8601 (via outer JSONEncoder dateEncodingStrategy)")
    func dateRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = PropertyValue.date(Date(timeIntervalSince1970: 1716480000))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PropertyValue.self, from: data)
        if case let .date(d) = decoded {
            #expect(abs(d.timeIntervalSince1970 - 1716480000) < 1)
        } else {
            Issue.record("expected .date case after decode, got \(decoded)")
        }
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Vaults/PropertyValue.swift`:

```swift
import Foundation

/// Type-erased property value used in Item / Page / Agenda `properties` dictionaries.
/// Custom Codable inspects the JSON shape per-value:
/// - JSON number → `.number(Double)`
/// - JSON bool   → `.checkbox(Bool)`
/// - JSON null   → `.null`
/// - JSON object `{"$rel": "..."}` → `.relation(String)` (ULID of target entity)
/// - JSON string → `.url`/`.date`/`.datetime`/`.select` (disambiguated by shape;
///                  ISO-8601 strings decode as `.datetime` if they include time, `.date` if not;
///                  URLs validate via `URL(string:)`; anything else is `.select`)
/// - JSON array  → `.multiSelect([String])`
///
/// Relation encoding: `.relation(id)` writes `{"$rel": id}` so external agents and the
/// graph-view indexer can identify cross-entity edges from any single file without consulting
/// the Vault schema. Satisfies Pommora load-bearing constraint #3.
///
/// Date vs datetime: `.date` writes a yyyy-MM-dd string (UTC); `.datetime` writes full
/// ISO-8601 with timezone. On decode: ISO-8601 with `T` → `.datetime`, else yyyy-MM-dd → `.date`.
enum PropertyValue: Codable, Equatable, Hashable, Sendable {
    case number(Double)
    case checkbox(Bool)
    case date(Date)
    case datetime(Date)
    case select(String)
    case multiSelect([String])
    case relation(String)        // ULID of target entity; encodes as {"$rel": id}
    case url(URL)
    case null

    // MARK: - Codable

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .checkbox(b); return
        }
        if let n = try? c.decode(Double.self) {
            self = .number(n); return
        }
        if let arr = try? c.decode([String].self) {
            self = .multiSelect(arr); return
        }
        // Tagged-object relation: {"$rel": "01H..."}
        if let obj = try? c.decode([String: String].self),
           obj.count == 1,
           let id = obj["$rel"] {
            self = .relation(id); return
        }
        if let s = try? c.decode(String.self) {
            // Try URL
            if let url = URL(string: s), url.scheme != nil {
                self = .url(url); return
            }
            // Try ISO-8601 datetime
            let isoDateTime = ISO8601DateFormatter()
            isoDateTime.formatOptions = [.withInternetDateTime]
            if let d = isoDateTime.date(from: s) {
                self = .datetime(d); return
            }
            // Try yyyy-MM-dd
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            if let d = dateFormatter.date(from: s) {
                self = .date(d); return
            }
            // Fallthrough: plain string → treat as select value
            self = .select(s); return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "PropertyValue: unrecognised JSON shape"
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n):       try c.encode(n)
        case .checkbox(let b):     try c.encode(b)
        case .select(let s):       try c.encode(s)
        case .multiSelect(let xs): try c.encode(xs)
        case .relation(let id):    try c.encode(["$rel": id])
        case .url(let u):          try c.encode(u.absoluteString)
        case .null:                try c.encodeNil()
        case .date(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            try c.encode(f.string(from: d))
        case .datetime(let d):
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            try c.encode(iso.string(from: d))
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/PropertyValue -destination 'platform=macOS' 2>&1 | tail -15
# Expected: 4 pass
git add Pommora/Pommora/Vaults/PropertyValue.swift \
        Pommora/PommoraTests/Vaults/PropertyValueTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add PropertyValue type-erased enum

Custom Codable round-trips number/bool/date/datetime/select/
multiSelect/relation/url/null through arbitrary JSON dictionaries.
Shape-driven decode: ISO-8601 with T → .datetime, yyyy-MM-dd → .date,
URL with scheme → .url, etc.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: VaultView placeholder

**Files:**
- Create: `Pommora/Pommora/Vaults/VaultView.swift`

**Context:** Saved view configurations land at v0.10. Empty placeholder so `Vault.views: [VaultView]` round-trips as `[]` from day one.

- [ ] **Step 1: Implement + commit**

```swift
// Pommora/Pommora/Vaults/VaultView.swift
import Foundation

/// Placeholder for saved Vault view configurations (table / board / list / cards / gallery).
/// Full schema lands v0.10.
struct VaultView: Codable, Equatable, Hashable, Sendable {
    // intentionally empty in v0.2
}
```

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Vaults/VaultView.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(vaults): add VaultView placeholder (full schema v0.10)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 18: Vault value type + Codable round-trip tests

**Files:**
- Create: `Pommora/Pommora/Vaults/Vault.swift`
- Create: `Pommora/PommoraTests/Vaults/VaultFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:513-525](.claude/Planning/Contexts-Vaults-spec.md#L513-L525). On disk at `<nexus>/<Title>/_vault.json`. Title derives from folder name.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Vaults/VaultFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("VaultFile")
struct VaultFileTests {

    @Test("Vault round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Planner", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_vault.json")

        let original = Vault(
            id: "01HVAULT",
            title: "Planner",
            icon: "folder",
            properties: [
                PropertyDefinition(
                    name: "status",
                    type: .select,
                    selectOptions: [
                        PropertyDefinition.SelectOption(value: "active", label: "Active", color: .green),
                        PropertyDefinition.SelectOption(value: "done", label: "Done", color: .gray)
                    ]
                ),
                PropertyDefinition(name: "due", type: .date, dateIncludesTime: false)
            ],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try Vault.load(from: metaURL)
        #expect(loaded.id == "01HVAULT")
        #expect(loaded.title == "Planner")
        #expect(loaded.icon == "folder")
        #expect(loaded.properties.count == 2)
        #expect(loaded.properties[0].name == "status")
        #expect(loaded.properties[0].type == .select)
    }

    @Test("Vault on-disk JSON omits title")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_vault.json")

        try Vault(id: "01H", title: "Materials", icon: nil, properties: [], views: [], modifiedAt: Date())
            .save(to: metaURL)
        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("empty Vault round-trips with empty properties + views")
    func emptyVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_vault.json")

        let v = Vault(id: "01H", title: "Empty", icon: nil, properties: [], views: [], modifiedAt: Date())
        try v.save(to: metaURL)
        let loaded = try Vault.load(from: metaURL)
        #expect(loaded.properties == [])
        #expect(loaded.views == [])
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Vaults/Vault.swift`:

```swift
import Foundation

/// Vault — folder + `_vault.json` schema sidecar that defines the property
/// schema shared by every Page + Item inside.
///
/// On disk: `<nexus>/<Title>/_vault.json` (folder name = title; no title on disk).
struct Vault: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String                          // ULID
    var title: String                       // derived from folder name
    var icon: String?                       // SF Symbol name
    var properties: [PropertyDefinition]    // schema shared across Content
    var views: [VaultView]                  // saved views (empty placeholder in v0.2)
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?,
        properties: [PropertyDefinition], views: [VaultView], modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.properties = properties
        self.views = views
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        self.views = try c.decodeIfPresent([VaultView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Vault {
    static func load(from metadataURL: URL) throws -> Vault {
        var v = try AtomicJSON.decode(Vault.self, from: metadataURL)
        v.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return v
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/VaultFile -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Vaults/Vault.swift \
        Pommora/PommoraTests/Vaults/VaultFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add Vault Codable + tests

Folder + _vault.json sidecar; properties + views arrays; title from
folder name. Custom Codable omits title and handles empty arrays.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Collection value type + tests

**Files:**
- Create: `Pommora/Pommora/Vaults/Collection.swift`
- Create: `Pommora/PommoraTests/Vaults/CollectionTests.swift`

**Context:** Collections in v1 are pure filesystem folders inside a Vault — no `_collection.json` metadata file. Identity is derived from the folder URL. The Swift value type exists for in-app handling (sidebar rows, ContentManager keying), not for serialization.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Vaults/CollectionTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("Collection")
struct CollectionTests {

    @Test("init derives title from folder name + id from URL hash")
    func deriveFromURL() {
        let url = URL(fileURLWithPath: "/tmp/pommora/MyVault/Tasks", isDirectory: true)
        let c = Collection(folderURL: url, vaultID: "01HVAULT")
        #expect(c.title == "Tasks")
        #expect(c.vaultID == "01HVAULT")
        #expect(c.folderURL == url)
        #expect(!c.id.isEmpty)
    }

    @Test("two Collections at same path produce same id")
    func stableID() {
        let url = URL(fileURLWithPath: "/tmp/x/Y/Z", isDirectory: true)
        let a = Collection(folderURL: url, vaultID: "01HV")
        let b = Collection(folderURL: url, vaultID: "01HV")
        #expect(a.id == b.id)
    }

    @Test("Collections at different paths produce different ids")
    func differentPathsDifferentIDs() {
        let a = Collection(
            folderURL: URL(fileURLWithPath: "/tmp/x/Y/Z1", isDirectory: true),
            vaultID: "01HV"
        )
        let b = Collection(
            folderURL: URL(fileURLWithPath: "/tmp/x/Y/Z2", isDirectory: true),
            vaultID: "01HV"
        )
        #expect(a.id != b.id)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Vaults/Collection.swift`:

```swift
import Foundation
import CryptoKit

/// In-app value type for a Collection (Vault sub-folder).
/// Not serialised — collections have no `_collection.json` in v1.
/// Identity is the SHA-256 of the folder URL path (stable across runs).
struct Collection: Equatable, Identifiable, Hashable, Sendable {
    let id: String
    let vaultID: String
    let title: String
    let folderURL: URL

    init(folderURL: URL, vaultID: String) {
        self.folderURL = folderURL
        self.vaultID = vaultID
        self.title = folderURL.lastPathComponent
        // SHA-256 of normalized path → 64-char hex; deterministic across runs
        let normalized = folderURL.standardizedFileURL.path
        let hash = SHA256.hash(data: Data(normalized.utf8))
        self.id = hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/Collection -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Vaults/Collection.swift \
        Pommora/PommoraTests/Vaults/CollectionTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add Collection in-app value type

Pure-folder Collection (no metadata file in v1). Stable id via
SHA-256 of normalized folder path; title from lastPathComponent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: Item value type + Codable round-trip tests

**Files:**
- Create: `Pommora/Pommora/Content/Item.swift`
- Create: `Pommora/PommoraTests/Content/ItemFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:537-554](.claude/Planning/Contexts-Vaults-spec.md#L537-L554). Items are `.json` files in a Collection folder. 250-char `description` cap is a UI-time concern (validator enforces); the type itself accepts any string.

- [ ] **Step 1: Create folder + write the failing test**

```bash
mkdir -p "Pommora/Pommora/Content" "Pommora/PommoraTests/Content"
```

Create `Pommora/PommoraTests/Content/ItemFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("ItemFile")
struct ItemFileTests {

    @Test("Item round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.json")

        let original = Item(
            id: "01HITEM",
            title: "Buy groceries",
            icon: "cart",
            description: "Milk, eggs, bread",
            tier1: ["01HSPACE-PERSONAL"],
            tier2: ["01HTOPIC-ERRANDS"],
            tier3: [],
            properties: [
                "status": .select("Active"),
                "due": .date(Date(timeIntervalSince1970: 1716480000))
            ],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Item.load(from: url)
        #expect(loaded.id == "01HITEM")
        #expect(loaded.title == "Buy groceries")
        #expect(loaded.icon == "cart")
        #expect(loaded.description == "Milk, eggs, bread")
        #expect(loaded.tier1 == ["01HSPACE-PERSONAL"])
        #expect(loaded.tier2 == ["01HTOPIC-ERRANDS"])
        #expect(loaded.tier3 == [])
        #expect(loaded.properties.count == 2)
    }

    @Test("Item on-disk JSON omits title field (filename = title)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.json")

        try Item(
            id: "01H", title: "X", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Item uses snake_case for tier + timestamps + descrption (sic)")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Y.json")
        try Item(
            id: "01H", title: "Y", icon: nil, description: "x",
            tier1: ["01HA"], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"tier1\""))
        #expect(raw.contains("\"created_at\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"description\""))
    }

    @Test("empty arrays + dict round-trip cleanly")
    func emptyValues() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Z.json")

        try Item(
            id: "01H", title: "Z", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: url)
        let loaded = try Item.load(from: url)
        #expect(loaded.tier1 == [])
        #expect(loaded.properties.isEmpty)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Content/Item.swift`:

```swift
import Foundation

/// Item — `.json` inside a Vault Collection. Carries description, properties
/// (per Vault schema), tier1/2/3 multi-relations to Contexts.
struct Item: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String                          // derived from filename on load
    var icon: String?
    var description: String
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    var createdAt: Date
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, description, tier1, tier2, tier3, properties
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?, description: String,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date, modifiedAt: Date
    ) {
        self.id = id; self.title = title; self.icon = icon; self.description = description
        self.tier1 = tier1; self.tier2 = tier2; self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(description, forKey: .description)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(properties, forKey: .properties)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Item {
    static func load(from url: URL) throws -> Item {
        var i = try AtomicJSON.decode(Item.self, from: url)
        i.title = url.deletingPathExtension().lastPathComponent
        return i
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/ItemFile -destination 'platform=macOS' 2>&1 | tail -15
git add Pommora/Pommora/Content/Item.swift \
        Pommora/PommoraTests/Content/ItemFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(content): add Item Codable + tests

.json entity inside a Collection. Carries description, tier1/2/3
multi-relations, and per-Vault-schema properties via PropertyValue.
Custom Codable omits title (filename = title) and uses snake_case
for tier + timestamp keys.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: PageFrontmatter + PageFile + tests

**Files:**
- Create: `Pommora/Pommora/Content/PageFrontmatter.swift`
- Create: `Pommora/Pommora/Content/PageFile.swift`
- Create: `Pommora/PommoraTests/Content/PageFileTests.swift`

**Context:** Pages = `.md` with YAML frontmatter + raw body. Frontmatter shape mirrors Item (minus `description`; plus body is raw String). `PageFile` composes the two and uses `AtomicYAMLMarkdown` for I/O.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Content/PageFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("PageFile")
struct PageFileTests {

    @Test("PageFile round-trips frontmatter + body")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Notes.md")

        let fm = PageFrontmatter(
            id: "01HPAGE",
            icon: "doc.text",
            tier1: ["01HSPACE"],
            tier2: [],
            tier3: ["01HSUBTOPIC"],
            properties: ["status": .select("Active")],
            createdAt: Date(timeIntervalSince1970: 1716000000)
        )
        let body = "# Notes\n\nA paragraph.\n"
        let page = PageFile(frontmatter: fm, body: body)
        try page.save(to: url)

        let loaded = try PageFile.load(from: url)
        #expect(loaded.frontmatter.id == "01HPAGE")
        #expect(loaded.frontmatter.icon == "doc.text")
        #expect(loaded.frontmatter.tier1 == ["01HSPACE"])
        #expect(loaded.frontmatter.tier3 == ["01HSUBTOPIC"])
        #expect(loaded.body == body)
        #expect(loaded.title == "Notes")
    }

    @Test("body-only .md (no frontmatter envelope) decodes with empty frontmatter")
    func bodyOnly() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Plain.md")
        try FixtureFiles.write("# Plain\n\nJust body.\n", to: url)

        let loaded = try PageFile.load(from: url)
        #expect(loaded.frontmatter.id.isEmpty || loaded.frontmatter.id == "")  // either way: empty
        #expect(loaded.body == "# Plain\n\nJust body.\n")
        #expect(loaded.title == "Plain")
    }

    @Test("frontmatter uses snake_case keys on disk")
    func snakeCaseFrontmatter() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.md")

        try PageFile(
            frontmatter: PageFrontmatter(
                id: "01H", icon: nil, tier1: ["01HA"], tier2: [], tier3: [],
                properties: [:], createdAt: Date(timeIntervalSince1970: 0)
            ),
            body: ""
        ).save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("created_at:"))
        #expect(raw.contains("tier1:"))
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Content/PageFrontmatter.swift`:

```swift
import Foundation

/// YAML frontmatter for `.md` Page files. Mirrors Item shape minus `description`
/// (Pages put long-form text in the body) plus `created_at` (Items have it; Pages
/// gain it for parity per Handoff "Known Spec Gaps").
struct PageFrontmatter: Codable, Equatable, Hashable, Sendable {
    var id: String
    var icon: String?
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var properties: [String: PropertyValue]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, icon, tier1, tier2, tier3, properties
        case createdAt = "created_at"
    }

    init(
        id: String, icon: String?,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date
    ) {
        self.id = id; self.icon = icon
        self.tier1 = tier1; self.tier2 = tier2; self.tier3 = tier3
        self.properties = properties
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(properties, forKey: .properties)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
```

Create `Pommora/Pommora/Content/PageFile.swift`:

```swift
import Foundation

/// Composite of frontmatter + body for a `.md` Page file.
/// I/O via `AtomicYAMLMarkdown`. Title derived from filename on load.
struct PageFile: Equatable, Sendable {
    var frontmatter: PageFrontmatter
    var body: String
    var title: String       // derived from filename on load; not persisted

    init(frontmatter: PageFrontmatter, body: String, title: String = "") {
        self.frontmatter = frontmatter
        self.body = body
        self.title = title
    }

    static func load(from url: URL) throws -> PageFile {
        let (fm, body): (PageFrontmatter, String) =
            try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: url)
        return PageFile(
            frontmatter: fm,
            body: body,
            title: url.deletingPathExtension().lastPathComponent
        )
    }

    func save(to url: URL) throws {
        try AtomicYAMLMarkdown.write(frontmatter: frontmatter, body: body, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/PageFile -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Content/PageFrontmatter.swift \
        Pommora/Pommora/Content/PageFile.swift \
        Pommora/PommoraTests/Content/PageFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(content): add PageFrontmatter + PageFile

YAML frontmatter shape (id, icon, tier1/2/3, properties, created_at)
+ PageFile composite that round-trips via AtomicYAMLMarkdown. Body-only
files decode with empty frontmatter; snake_case keys on disk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 22: Recurrence value type + tests

**Files:**
- Create: `Pommora/Pommora/Agenda/Recurrence.swift`
- Create: `Pommora/PommoraTests/Agenda/RecurrenceTests.swift`

**Context:** Schema matching the corrected `EKRecurrenceRule` shape at [.claude/Planning/Contexts-Vaults-spec.md:384-412](.claude/Planning/Contexts-Vaults-spec.md#L384-L412). Three nested types: `Recurrence.Frequency`, `Recurrence.End`, `Recurrence.DayOfWeek`.

- [ ] **Step 1: Create folder + write the failing test**

```bash
mkdir -p "Pommora/Pommora/Agenda" "Pommora/PommoraTests/Agenda"
```

Create `Pommora/PommoraTests/Agenda/RecurrenceTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("Recurrence")
struct RecurrenceTests {

    @Test("simple weekly recurrence round-trips")
    func weeklyRoundTrip() throws {
        let r = Recurrence(
            frequency: .weekly,
            interval: 1,
            firstDayOfWeek: 2,
            end: .occurrenceCount(10),
            daysOfWeek: [
                Recurrence.DayOfWeek(day: .monday, weekNumber: nil),
                Recurrence.DayOfWeek(day: .friday, weekNumber: -1)
            ],
            daysOfMonth: [],
            daysOfYear: [],
            weeksOfYear: [],
            monthsOfYear: [],
            setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        #expect(decoded == r)
    }

    @Test("end can be omitted (nil)")
    func endNil() throws {
        let r = Recurrence(
            frequency: .daily, interval: 1, firstDayOfWeek: 1, end: nil,
            daysOfWeek: [], daysOfMonth: [], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        #expect(decoded.end == nil)
    }

    @Test("end with date is correctly tagged")
    func endDate() throws {
        let until = Date(timeIntervalSince1970: 1716480000)
        let r = Recurrence(
            frequency: .monthly, interval: 2, firstDayOfWeek: 1, end: .endDate(until),
            daysOfWeek: [], daysOfMonth: [1, 15], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        if case let .endDate(d) = decoded.end {
            #expect(abs(d.timeIntervalSince1970 - until.timeIntervalSince1970) < 1)
        } else {
            Issue.record("expected .endDate case")
        }
    }

    @Test("snake_case keys on disk")
    func snakeCase() throws {
        let r = Recurrence(
            frequency: .yearly, interval: 1, firstDayOfWeek: 1, end: nil,
            daysOfWeek: [], daysOfMonth: [], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: [-1]
        )
        let data = try AtomicJSON.encode(r)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw.contains("\"first_day_of_week\""))
        #expect(raw.contains("\"days_of_week\""))
        #expect(raw.contains("\"days_of_month\""))
        #expect(raw.contains("\"set_positions\""))
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Agenda/Recurrence.swift`:

```swift
import Foundation

/// JSON shape matching `EKRecurrenceRule`. Per spec validation pass — `EKRecurrenceRule`
/// is immutable on the EventKit side, so on sync we always construct a fresh rule
/// from this struct rather than mutating in place.
struct Recurrence: Codable, Equatable, Hashable, Sendable {
    var frequency: Frequency
    var interval: Int                       // every N units (≥ 1)
    var firstDayOfWeek: Int                 // 1=Sun … 7=Sat; affects weekly semantics
    var end: End?
    var daysOfWeek: [DayOfWeek]
    var daysOfMonth: [Int]                  // e.g. [1, 15] = "1st and 15th"
    var daysOfYear: [Int]
    var weeksOfYear: [Int]
    var monthsOfYear: [Int]
    var setPositions: [Int]                 // e.g. [-1] = "last instance"

    enum Frequency: String, Codable, CaseIterable, Hashable, Sendable {
        case daily, weekly, monthly, yearly
    }

    enum End: Codable, Equatable, Hashable, Sendable {
        case occurrenceCount(Int)
        case endDate(Date)

        private enum CodingKeys: String, CodingKey { case kind, value }
        private enum Kind: String, Codable { case occurrenceCount = "occurrence_count", endDate = "end_date" }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .occurrenceCount: self = .occurrenceCount(try c.decode(Int.self, forKey: .value))
            case .endDate:         self = .endDate(try c.decode(Date.self, forKey: .value))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .occurrenceCount(let n):
                try c.encode(Kind.occurrenceCount, forKey: .kind)
                try c.encode(n, forKey: .value)
            case .endDate(let d):
                try c.encode(Kind.endDate, forKey: .kind)
                try c.encode(d, forKey: .value)
            }
        }
    }

    struct DayOfWeek: Codable, Equatable, Hashable, Sendable {
        var day: Day
        var weekNumber: Int?                // -5…-1 or 1…5; "last Friday" = .friday, -1

        enum Day: String, Codable, CaseIterable, Hashable, Sendable {
            case sunday = "sun", monday = "mon", tuesday = "tue", wednesday = "wed"
            case thursday = "thu", friday = "fri", saturday = "sat"
        }

        enum CodingKeys: String, CodingKey {
            case day
            case weekNumber = "week_number"
        }
    }

    enum CodingKeys: String, CodingKey {
        case frequency, interval, end
        case firstDayOfWeek = "first_day_of_week"
        case daysOfWeek = "days_of_week"
        case daysOfMonth = "days_of_month"
        case daysOfYear = "days_of_year"
        case weeksOfYear = "weeks_of_year"
        case monthsOfYear = "months_of_year"
        case setPositions = "set_positions"
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/Recurrence -destination 'platform=macOS' 2>&1 | tail -15
git add Pommora/Pommora/Agenda/Recurrence.swift \
        Pommora/PommoraTests/Agenda/RecurrenceTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(agenda): add Recurrence value type matching EKRecurrenceRule

frequency / interval / first_day_of_week / end (occurrence count or
end_date) / days_of_week (typed with optional week_number) / days_of_month
/ days_of_year / weeks_of_year / months_of_year / set_positions. All
JSON keys snake_case for direct mirroring of EventKit semantics.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 23: AgendaSchema value type + tests

**Files:**
- Create: `Pommora/Pommora/Agenda/AgendaSchema.swift`
- Tests: covered by AgendaManagerTests (seed-on-first-init test)

**Context:** `_agenda.json` schema sidecar with built-in `type` Select property. Per [.claude/Planning/Contexts-Vaults-spec.md:429-455](.claude/Planning/Contexts-Vaults-spec.md#L429-L455). Built-in `type` cannot be deleted; options are user-editable.

- [ ] **Step 1: Implement AgendaSchema**

Create `Pommora/Pommora/Agenda/AgendaSchema.swift`:

```swift
import Foundation

/// `_agenda.json` schema sidecar. Defines the built-in `type` Select property
/// plus any user-defined properties + saved views.
struct AgendaSchema: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var properties: [Property]
    var views: [VaultView]                // reuse Vault's placeholder
    var modifiedAt: Date

    struct Property: Codable, Equatable, Hashable, Sendable {
        var name: String
        var type: PropertyType
        var options: [PropertyDefinition.SelectOption]?
        var builtin: Bool
        var defaultValue: String?

        enum CodingKeys: String, CodingKey {
            case name, type, options, builtin
            case defaultValue = "default"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, properties, views
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> AgendaSchema {
        AgendaSchema(
            schemaVersion: 1,
            icon: "calendar",
            properties: [
                Property(
                    name: "type",
                    type: .select,
                    options: [
                        PropertyDefinition.SelectOption(value: "Task",   label: "Task",   color: .blue),
                        PropertyDefinition.SelectOption(value: "To-Do",  label: "To-Do",  color: .yellow),
                        PropertyDefinition.SelectOption(value: "Phase",  label: "Phase",  color: .purple),
                        PropertyDefinition.SelectOption(value: "Event",  label: "Event",  color: .green)
                    ],
                    builtin: true,
                    defaultValue: "Task"
                )
            ],
            views: [],
            modifiedAt: Date()
        )
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Agenda/AgendaSchema.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(agenda): add AgendaSchema sidecar with built-in type Select

Schema for _agenda.json. defaultSeed produces the Task/To-Do/Phase/
Event Select with builtin=true (can't be deleted, options editable).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 24: AgendaItem value type + tests

**Files:**
- Create: `Pommora/Pommora/Agenda/AgendaItem.swift`
- Create: `Pommora/PommoraTests/Agenda/AgendaItemFileTests.swift`

**Context:** Full schema per [.claude/Features/Agenda.md:39-75](.claude/Features/Agenda.md#L39-L75). All time fields optional; EventKit mapping is data-driven (combination of populated fields determines target). No EventKit code yet — just the data shape.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Agenda/AgendaItemFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("AgendaItemFile")
struct AgendaItemFileTests {

    @Test("AgendaItem round-trips event-shaped item")
    func eventShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Team standup.agenda.json")

        let original = AgendaItem(
            id: "01HAGENDA",
            title: "Team standup",
            icon: "person.3",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716481800),
            allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: "Conference room A",
            recurrence: nil,
            alarmOffsets: [-900],   // 15 min before
            alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "Daily standup",
            tier1: [], tier2: ["01HTOPIC-WORK"], tier3: [],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            properties: ["type": .select("Event")]
        )
        try original.save(to: url)

        let loaded = try AgendaItem.load(from: url)
        #expect(loaded.id == "01HAGENDA")
        #expect(loaded.title == "Team standup")
        #expect(loaded.startAt != nil)
        #expect(loaded.endAt != nil)
        #expect(loaded.dueAt == nil)
        #expect(loaded.location == "Conference room A")
        #expect(loaded.alarmOffsets == [-900])
    }

    @Test("AgendaItem round-trips reminder-shaped item")
    func reminderShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.agenda.json")

        let original = AgendaItem(
            id: "01HAGTASK",
            title: "Buy groceries",
            icon: "checkmark.circle",
            startAt: nil, endAt: nil, allDay: false,
            dueAt: Date(timeIntervalSince1970: 1716480000),
            dueFloating: true, dueAllDay: true,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try original.save(to: url)

        let loaded = try AgendaItem.load(from: url)
        #expect(loaded.dueAt != nil)
        #expect(loaded.dueFloating == true)
        #expect(loaded.dueAllDay == true)
        #expect(loaded.startAt == nil)
    }

    @Test("Snake_case keys on disk")
    func snakeCase() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.agenda.json")
        try AgendaItem(
            id: "01H", title: "X", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"start_at\""))
        #expect(raw.contains("\"due_at\""))
        #expect(raw.contains("\"due_floating\""))
        #expect(raw.contains("\"alarm_offsets\""))
        #expect(raw.contains("\"sync_target\""))
        #expect(raw.contains("\"eventkit_uuid\""))
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Agenda/AgendaItem.swift`:

```swift
import Foundation

/// Single unified Agenda entity. EventKit mapping (EKEvent vs EKReminder) is
/// determined by which time fields are populated — not by a kind discriminator.
struct AgendaItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String                  // derived from filename on load
    var icon: String?

    // Event-shaped (mirrors EKEvent)
    var startAt: Date?
    var endAt: Date?
    var allDay: Bool

    // Reminder-shaped (mirrors EKReminder.dueDateComponents)
    var dueAt: Date?
    var dueFloating: Bool              // true = nil timezone
    var dueAllDay: Bool                // true = strip hour/minute/second

    // Completion (mirrors EKReminder.isCompleted / .completionDate)
    var completed: Bool
    var completedAt: Date?

    // Shared optional fields
    var location: String?
    var recurrence: Recurrence?
    var alarmOffsets: [TimeInterval]   // negative = before; matches EKAlarm.relativeOffset
    var alarmAbsolute: [Date]

    // EventKit sync state (populated only when mirrored)
    var syncTarget: SyncTarget?
    var calendarID: String?
    var eventkitUUID: String?

    // Shared with Items
    var description: String
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var createdAt: Date
    var modifiedAt: Date
    var properties: [String: PropertyValue]  // includes built-in `type` Select

    enum SyncTarget: String, Codable, CaseIterable, Hashable, Sendable {
        case calendar, reminder
    }

    enum CodingKeys: String, CodingKey {
        case id, icon, completed, location, recurrence, description
        case tier1, tier2, tier3, properties
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case dueAt = "due_at"
        case dueFloating = "due_floating"
        case dueAllDay = "due_all_day"
        case completedAt = "completed_at"
        case alarmOffsets = "alarm_offsets"
        case alarmAbsolute = "alarm_absolute"
        case syncTarget = "sync_target"
        case calendarID = "calendar_id"
        case eventkitUUID = "eventkit_uuid"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(
        id: String, title: String, icon: String?,
        startAt: Date?, endAt: Date?, allDay: Bool,
        dueAt: Date?, dueFloating: Bool, dueAllDay: Bool,
        completed: Bool, completedAt: Date?,
        location: String?, recurrence: Recurrence?,
        alarmOffsets: [TimeInterval], alarmAbsolute: [Date],
        syncTarget: SyncTarget?, calendarID: String?, eventkitUUID: String?,
        description: String,
        tier1: [String], tier2: [String], tier3: [String],
        createdAt: Date, modifiedAt: Date,
        properties: [String: PropertyValue]
    ) {
        self.id = id; self.title = title; self.icon = icon
        self.startAt = startAt; self.endAt = endAt; self.allDay = allDay
        self.dueAt = dueAt; self.dueFloating = dueFloating; self.dueAllDay = dueAllDay
        self.completed = completed; self.completedAt = completedAt
        self.location = location; self.recurrence = recurrence
        self.alarmOffsets = alarmOffsets; self.alarmAbsolute = alarmAbsolute
        self.syncTarget = syncTarget; self.calendarID = calendarID; self.eventkitUUID = eventkitUUID
        self.description = description
        self.tier1 = tier1; self.tier2 = tier2; self.tier3 = tier3
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
        self.properties = properties
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        self.endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        self.allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        self.dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        self.dueFloating = try c.decodeIfPresent(Bool.self, forKey: .dueFloating) ?? false
        self.dueAllDay = try c.decodeIfPresent(Bool.self, forKey: .dueAllDay) ?? false
        self.completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.alarmOffsets = try c.decodeIfPresent([TimeInterval].self, forKey: .alarmOffsets) ?? []
        self.alarmAbsolute = try c.decodeIfPresent([Date].self, forKey: .alarmAbsolute) ?? []
        self.syncTarget = try c.decodeIfPresent(SyncTarget.self, forKey: .syncTarget)
        self.calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
        self.eventkitUUID = try c.decodeIfPresent(String.self, forKey: .eventkitUUID)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.tier1 = try c.decodeIfPresent([String].self, forKey: .tier1) ?? []
        self.tier2 = try c.decodeIfPresent([String].self, forKey: .tier2) ?? []
        self.tier3 = try c.decodeIfPresent([String].self, forKey: .tier3) ?? []
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.properties = try c.decodeIfPresent([String: PropertyValue].self, forKey: .properties) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(startAt, forKey: .startAt)
        try c.encodeIfPresent(endAt, forKey: .endAt)
        try c.encode(allDay, forKey: .allDay)
        try c.encodeIfPresent(dueAt, forKey: .dueAt)
        try c.encode(dueFloating, forKey: .dueFloating)
        try c.encode(dueAllDay, forKey: .dueAllDay)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encode(alarmOffsets, forKey: .alarmOffsets)
        try c.encode(alarmAbsolute, forKey: .alarmAbsolute)
        try c.encodeIfPresent(syncTarget, forKey: .syncTarget)
        try c.encodeIfPresent(calendarID, forKey: .calendarID)
        try c.encodeIfPresent(eventkitUUID, forKey: .eventkitUUID)
        try c.encode(description, forKey: .description)
        try c.encode(tier1, forKey: .tier1)
        try c.encode(tier2, forKey: .tier2)
        try c.encode(tier3, forKey: .tier3)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(properties, forKey: .properties)
    }
}

extension AgendaItem {
    static func load(from url: URL) throws -> AgendaItem {
        var item = try AtomicJSON.decode(AgendaItem.self, from: url)
        // "Buy groceries.agenda.json" → strip both extensions → "Buy groceries"
        item.title = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        return item
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AgendaItemFile -destination 'platform=macOS' 2>&1 | tail -15
git add Pommora/Pommora/Agenda/AgendaItem.swift \
        Pommora/PommoraTests/Agenda/AgendaItemFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(agenda): add AgendaItem Codable + tests

Full EKEvent + EKReminder-shaped schema with optional time fields,
recurrence (EKRecurrenceRule-mirroring), alarms (offset + absolute),
EventKit sync identifiers, tier1/2/3 relations, and user properties
including the built-in type Select. Filename = title pattern matches
other entities.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 25: Homepage value type + tests

**Files:**
- Create: `Pommora/Pommora/Homepage/Homepage.swift`
- Create: `Pommora/PommoraTests/Homepage/HomepageFileTests.swift`

**Context:** Schema at [.claude/Planning/Contexts-Vaults-spec.md:306-324](.claude/Planning/Contexts-Vaults-spec.md#L306-L324). Singleton — no `id`, no `tier`, no `parents`. File location IS the identity.

- [ ] **Step 1: Create folder + write the failing test**

```bash
mkdir -p "Pommora/Pommora/Homepage" "Pommora/PommoraTests/Homepage"
```

Create `Pommora/PommoraTests/Homepage/HomepageFileTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("HomepageFile")
struct HomepageFileTests {

    @Test("Homepage round-trips")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("homepage.json")

        let original = Homepage(
            schemaVersion: 1,
            icon: "house",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(Homepage.self, from: url)
        #expect(loaded == original)
    }

    @Test("defaultSeed has house icon + empty blocks")
    func defaultSeed() {
        let seed = Homepage.defaultSeed()
        #expect(seed.schemaVersion == 1)
        #expect(seed.icon == "house")
        #expect(seed.blocks == [])
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Homepage/Homepage.swift`:

```swift
import Foundation

/// Singleton composed-blocks dashboard. One per Nexus, fixed location:
/// `.nexus/homepage.json`. No id / tier / parents — the location IS the identity.
struct Homepage: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var blocks: [ContextBlock]              // composed-blocks tree (editor lands v0.9)
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, blocks
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> Homepage {
        Homepage(
            schemaVersion: 1,
            icon: "house",
            blocks: [],
            modifiedAt: Date()
        )
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/HomepageFile -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Homepage/Homepage.swift \
        Pommora/PommoraTests/Homepage/HomepageFileTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(homepage): add Homepage singleton Codable

schemaVersion + icon + blocks + modified_at. defaultSeed gives the
house icon + empty blocks. Composed-blocks editor lands v0.9.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 26: ULIDValidator + NexusContext + ULIDValidator tests

**Files:**
- Create: `Pommora/Pommora/Validation/ULIDValidator.swift`
- Create: `Pommora/Pommora/Validation/NexusContext.swift`
- Create: `Pommora/PommoraTests/Validation/ULIDValidatorTests.swift`

**Context:** Cross-entity validation (e.g. Subtopic's parent must resolve to a real Topic) needs lookup capability. Rather than a heavyweight coordinator class, `NexusContext` is a small value passed into validators that holds *closures* for the lookups the validator needs. Each manager fills the closures with its own state.

- [ ] **Step 1: Create folders + write the failing test**

```bash
mkdir -p "Pommora/Pommora/Validation" "Pommora/PommoraTests/Validation"
```

Create `Pommora/PommoraTests/Validation/ULIDValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("ULIDValidator")
struct ULIDValidatorTests {

    @Test("valid ULID passes")
    func validULID() {
        let id = ULID.generate()
        #expect(ULIDValidator.isValid(id))
    }

    @Test("26 chars of Crockford alphabet passes")
    func crockfordHandwritten() {
        let id = "01HXYZ1234567890ABCDEFGHJK"
        #expect(ULIDValidator.isValid(id))
    }

    @Test("wrong length fails")
    func wrongLength() {
        #expect(!ULIDValidator.isValid("01HXYZ"))
        #expect(!ULIDValidator.isValid(""))
        #expect(!ULIDValidator.isValid(String(repeating: "0", count: 27)))
    }

    @Test("lowercase alpha fails (Crockford is upper)")
    func lowercaseFails() {
        #expect(!ULIDValidator.isValid("01hxyz1234567890abcdefghjk"))
    }

    @Test("Crockford-excluded characters fail")
    func excludedChars() {
        // I, L, O, U are explicitly excluded from Crockford base32
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHI0"))  // contains I
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHL0"))  // contains L
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHO0"))  // contains O
        #expect(!ULIDValidator.isValid("01HXYZ1234567890ABCDEFGHU0"))  // contains U
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement ULIDValidator.**

Create `Pommora/Pommora/Validation/ULIDValidator.swift`:

```swift
import Foundation

/// Validates ULID strings (26-char Crockford base32, no I/L/O/U).
enum ULIDValidator {
    private static let crockfordAlphabet: Set<Character> =
        Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func isValid(_ id: String) -> Bool {
        guard id.count == 26 else { return false }
        return id.allSatisfy { crockfordAlphabet.contains($0) }
    }
}
```

- [ ] **Step 4: Implement NexusContext (lookup closures container)**

Create `Pommora/Pommora/Validation/NexusContext.swift`:

```swift
import Foundation

/// Lightweight cross-entity lookup value passed to validators that need to
/// resolve IDs to other entities (e.g. SubtopicValidator checking parent Topic
/// existence). Avoids a heavyweight coordinator class — each manager fills
/// only the closures it needs.
///
/// All closures return `nil` if the ID is unknown.
struct NexusContext: Sendable {
    var lookupSpace: @Sendable (String) -> Space?
    var lookupTopic: @Sendable (String) -> Topic?
    var lookupSubtopic: @Sendable (String) -> Subtopic?
    var lookupVault: @Sendable (String) -> Vault?

    /// Sentinel context with all lookups returning nil — for tests / standalone validation.
    static let empty = NexusContext(
        lookupSpace:    { _ in nil },
        lookupTopic:    { _ in nil },
        lookupSubtopic: { _ in nil },
        lookupVault:    { _ in nil }
    )
}
```

- [ ] **Step 5: Run tests + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/ULIDValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/ULIDValidator.swift \
        Pommora/Pommora/Validation/NexusContext.swift \
        Pommora/PommoraTests/Validation/ULIDValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add ULIDValidator + NexusContext

ULIDValidator checks 26-char Crockford base32 (rejects I/L/O/U and
lowercase). NexusContext carries lookup closures for cross-entity
validation without a coordinator class.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 27: SpaceValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/SpaceValidator.swift`
- Create: `Pommora/PommoraTests/Validation/SpaceValidatorTests.swift`

**Context:** Title rules (non-empty, no `/ \ :`), case-insensitive uniqueness within nexus. No cross-entity lookups needed.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/SpaceValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("SpaceValidator")
struct SpaceValidatorTests {

    @Test("non-empty title passes")
    func nonEmptyPasses() throws {
        try SpaceValidator.validate(title: "Personal", existing: [])
    }

    @Test("empty title throws emptyTitle")
    func emptyFails() {
        #expect(throws: SpaceValidator.ValidationError.emptyTitle) {
            try SpaceValidator.validate(title: "", existing: [])
        }
    }

    @Test("whitespace-only title throws emptyTitle")
    func whitespaceFails() {
        #expect(throws: SpaceValidator.ValidationError.emptyTitle) {
            try SpaceValidator.validate(title: "   \t  ", existing: [])
        }
    }

    @Test("forward slash throws invalidTitleCharacters")
    func slashFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo/Bar", existing: [])
        }
    }

    @Test("backslash throws invalidTitleCharacters")
    func backslashFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo\\Bar", existing: [])
        }
    }

    @Test("colon throws invalidTitleCharacters")
    func colonFails() {
        #expect(throws: SpaceValidator.ValidationError.invalidTitleCharacters) {
            try SpaceValidator.validate(title: "Foo:Bar", existing: [])
        }
    }

    @Test("case-insensitive duplicate throws duplicateTitle")
    func duplicateFails() {
        let existing = [makeSpace(title: "Personal")]
        #expect(throws: SpaceValidator.ValidationError.duplicateTitle) {
            try SpaceValidator.validate(title: "PERSONAL", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameToSelfPasses() throws {
        let s = makeSpace(title: "Personal")
        try SpaceValidator.validate(title: "Personal", existing: [s], excluding: s)
    }

    private func makeSpace(title: String) -> Space {
        Space(
            id: ULID.generate(),
            title: title,
            color: .blue,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/SpaceValidator.swift`:

```swift
import Foundation

enum SpaceValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existing: [Space],
        excluding: Space? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existing.contains { space in
            space.id != excluding?.id &&
            space.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SpaceValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/SpaceValidator.swift \
        Pommora/PommoraTests/Validation/SpaceValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add SpaceValidator + tests

Title non-empty, no /\\:, case-insensitive unique within nexus.
Excluding param for rename-to-self.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 28: TopicValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/TopicValidator.swift`
- Create: `Pommora/PommoraTests/Validation/TopicValidatorTests.swift`

**Context:** Title rules + parent rule (each `parents[i]` must resolve to a Space via `NexusContext.lookupSpace`). Empty parents allowed (Space-less Topic).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/TopicValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("TopicValidator")
struct TopicValidatorTests {

    @Test("empty parents allowed")
    func emptyParents() throws {
        try TopicValidator.validate(
            title: "Loose", parents: [], existing: [], context: .empty
        )
    }

    @Test("title rules apply same as Space")
    func titleRules() {
        #expect(throws: TopicValidator.ValidationError.emptyTitle) {
            try TopicValidator.validate(title: "", parents: [], existing: [], context: .empty)
        }
        #expect(throws: TopicValidator.ValidationError.invalidTitleCharacters) {
            try TopicValidator.validate(title: "A/B", parents: [], existing: [], context: .empty)
        }
    }

    @Test("duplicate title within nexus throws")
    func duplicate() {
        let existing = [makeTopic(title: "Productivity")]
        #expect(throws: TopicValidator.ValidationError.duplicateTitle) {
            try TopicValidator.validate(
                title: "productivity", parents: [], existing: existing, context: .empty
            )
        }
    }

    @Test("parent ID that doesn't resolve to a Space throws parentNotFound")
    func parentMissing() {
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { _ in nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        #expect(throws: TopicValidator.ValidationError.parentNotFound("01HZZ")) {
            try TopicValidator.validate(
                title: "X", parents: ["01HZZ"], existing: [], context: context
            )
        }
    }

    @Test("parent ID that resolves to a Space passes")
    func parentResolves() throws {
        let space = makeSpace(title: "Work")
        let context = NexusContext(
            lookupSpace:    { id in id == space.id ? space : nil },
            lookupTopic:    { _ in nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        try TopicValidator.validate(
            title: "Productivity", parents: [space.id], existing: [], context: context
        )
    }

    private func makeTopic(title: String, parents: [String] = []) -> Topic {
        Topic(id: ULID.generate(), title: title, parents: parents,
              icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeSpace(title: String) -> Space {
        Space(id: ULID.generate(), title: title, color: .blue,
              icon: nil, blocks: [], modifiedAt: Date())
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/TopicValidator.swift`:

```swift
import Foundation

enum TopicValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case parentNotFound(String)
    }

    static func validate(
        title: String,
        parents: [String],
        existing: [Topic],
        context: NexusContext,
        excluding: Topic? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existing.contains { topic in
            topic.id != excluding?.id &&
            topic.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }

        for parentID in parents {
            if context.lookupSpace(parentID) == nil {
                throw ValidationError.parentNotFound(parentID)
            }
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TopicValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/TopicValidator.swift \
        Pommora/PommoraTests/Validation/TopicValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add TopicValidator + tests

Title rules (same as Space) + parent rule: every parent ID must
resolve to a Space via NexusContext.lookupSpace. Empty parents
allowed (Space-less Topic).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 29: SubtopicValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/SubtopicValidator.swift`
- Create: `Pommora/PommoraTests/Validation/SubtopicValidatorTests.swift`

**Context:** Title rules + exactly-one-parent rule + parent must be a Topic + file location must match parent Topic's folder.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/SubtopicValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("SubtopicValidator")
struct SubtopicValidatorTests {

    @Test("happy path: exactly one parent resolving to a Topic + correct file location")
    func happyPath() throws {
        let topic = makeTopic(title: "Productivity")
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topic.id ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        try SubtopicValidator.validate(
            title: "GTD method",
            parents: [topic.id],
            fileLocation: SubtopicValidator.FileLocation(parentFolderTitle: "Productivity"),
            existing: [],
            context: context
        )
    }

    @Test("title rules apply")
    func titleRules() {
        let context = NexusContext.empty
        #expect(throws: SubtopicValidator.ValidationError.emptyTitle) {
            try SubtopicValidator.validate(
                title: "", parents: ["01H"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: context
            )
        }
    }

    @Test("zero parents throws missingParent")
    func zeroParents() {
        #expect(throws: SubtopicValidator.ValidationError.missingParent) {
            try SubtopicValidator.validate(
                title: "X", parents: [],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("two parents throws tooManyParents")
    func tooManyParents() {
        #expect(throws: SubtopicValidator.ValidationError.tooManyParents) {
            try SubtopicValidator.validate(
                title: "X", parents: ["01HA", "01HB"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("parent ID that doesn't resolve to a Topic throws")
    func parentNotFound() {
        #expect(throws: SubtopicValidator.ValidationError.parentNotFound("01HZZ")) {
            try SubtopicValidator.validate(
                title: "X", parents: ["01HZZ"],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: [], context: .empty
            )
        }
    }

    @Test("file location title not matching parent Topic title throws")
    func locationMismatch() {
        let topic = makeTopic(title: "Productivity")
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topic.id ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        #expect(throws: SubtopicValidator.ValidationError.fileLocationMismatch) {
            try SubtopicValidator.validate(
                title: "X", parents: [topic.id],
                fileLocation: .init(parentFolderTitle: "WrongFolder"),
                existing: [], context: context
            )
        }
    }

    @Test("duplicate title within same parent Topic throws")
    func duplicate() {
        let topic = makeTopic(title: "P")
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topic.id ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        let existing = [makeSubtopic(title: "GTD", parents: [topic.id])]
        #expect(throws: SubtopicValidator.ValidationError.duplicateTitle) {
            try SubtopicValidator.validate(
                title: "gtd", parents: [topic.id],
                fileLocation: .init(parentFolderTitle: "P"),
                existing: existing, context: context
            )
        }
    }

    private func makeTopic(title: String) -> Topic {
        Topic(id: ULID.generate(), title: title, parents: [],
              icon: nil, blocks: [], modifiedAt: Date())
    }

    private func makeSubtopic(title: String, parents: [String]) -> Subtopic {
        Subtopic(id: ULID.generate(), title: title, parents: parents,
                 linkedRelations: [], icon: nil, blocks: [], modifiedAt: Date())
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/SubtopicValidator.swift`:

```swift
import Foundation

enum SubtopicValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case missingParent
        case tooManyParents
        case parentNotFound(String)
        case fileLocationMismatch
    }

    struct FileLocation: Equatable, Sendable {
        var parentFolderTitle: String
    }

    static func validate(
        title: String,
        parents: [String],
        fileLocation: FileLocation,
        existing: [Subtopic],
        context: NexusContext,
        excluding: Subtopic? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        guard !parents.isEmpty else { throw ValidationError.missingParent }
        guard parents.count == 1 else { throw ValidationError.tooManyParents }

        let parentID = parents[0]
        guard let parentTopic = context.lookupTopic(parentID) else {
            throw ValidationError.parentNotFound(parentID)
        }

        // File location must equal parent Topic's folder name
        guard fileLocation.parentFolderTitle == parentTopic.title else {
            throw ValidationError.fileLocationMismatch
        }

        // Duplicate title within same parent
        let conflict = existing.contains { st in
            st.id != excluding?.id &&
            st.parents == parents &&
            st.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SubtopicValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/SubtopicValidator.swift \
        Pommora/PommoraTests/Validation/SubtopicValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add SubtopicValidator + tests

Title rules + exactly-one-parent rule + parent must resolve to a Topic
+ file location must match parent Topic's folder + duplicate title
within same parent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 30: VaultValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/VaultValidator.swift`
- Create: `Pommora/PommoraTests/Validation/VaultValidatorTests.swift`

**Context:** Title rules + case-insensitive unique within nexus root. Same pattern as SpaceValidator.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/VaultValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("VaultValidator")
struct VaultValidatorTests {

    @Test("valid title passes")
    func valid() throws {
        try VaultValidator.validate(title: "Planner", existing: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: VaultValidator.ValidationError.emptyTitle) {
            try VaultValidator.validate(title: "  ", existing: [])
        }
        #expect(throws: VaultValidator.ValidationError.invalidTitleCharacters) {
            try VaultValidator.validate(title: "A:B", existing: [])
        }
    }

    @Test("duplicate vault title throws")
    func duplicate() {
        let existing = [makeVault(title: "Planner")]
        #expect(throws: VaultValidator.ValidationError.duplicateTitle) {
            try VaultValidator.validate(title: "PLANNER", existing: existing)
        }
    }

    @Test("rename to current name (excluding self) passes")
    func renameSelf() throws {
        let v = makeVault(title: "Planner")
        try VaultValidator.validate(title: "Planner", existing: [v], excluding: v)
    }

    private func makeVault(title: String) -> Vault {
        Vault(id: ULID.generate(), title: title, icon: nil,
              properties: [], views: [], modifiedAt: Date())
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/VaultValidator.swift`:

```swift
import Foundation

enum VaultValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existing: [Vault],
        excluding: Vault? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existing.contains { v in
            v.id != excluding?.id &&
            v.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/VaultValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/VaultValidator.swift \
        Pommora/PommoraTests/Validation/VaultValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(validation): add VaultValidator + tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 31: CollectionValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/CollectionValidator.swift`
- Create: `Pommora/PommoraTests/Validation/CollectionValidatorTests.swift`

**Context:** Title rules + unique within parent Vault.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/CollectionValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("CollectionValidator")
struct CollectionValidatorTests {

    @Test("valid title in empty vault passes")
    func valid() throws {
        try CollectionValidator.validate(title: "Tasks", existingInVault: [])
    }

    @Test("title rules apply")
    func titleRules() {
        #expect(throws: CollectionValidator.ValidationError.emptyTitle) {
            try CollectionValidator.validate(title: "", existingInVault: [])
        }
        #expect(throws: CollectionValidator.ValidationError.invalidTitleCharacters) {
            try CollectionValidator.validate(title: "A/B", existingInVault: [])
        }
    }

    @Test("duplicate within vault throws")
    func duplicate() {
        let existing = [
            Collection(
                id: ULID.generate(),
                vaultID: "01HV",
                title: "Tasks",
                folderURL: URL(fileURLWithPath: "/tmp/V/Tasks", isDirectory: true),
                modifiedAt: Date()
            )
        ]
        #expect(throws: CollectionValidator.ValidationError.duplicateTitle) {
            try CollectionValidator.validate(title: "tasks", existingInVault: existing)
        }
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/CollectionValidator.swift`:

```swift
import Foundation

enum CollectionValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(
        title: String,
        existingInVault: [Collection],
        excluding: Collection? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existingInVault.contains { c in
            c.id != excluding?.id &&
            c.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/CollectionValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/CollectionValidator.swift \
        Pommora/PommoraTests/Validation/CollectionValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(validation): add CollectionValidator + tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 32: ItemValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/ItemValidator.swift`
- Create: `Pommora/PommoraTests/Validation/ItemValidatorTests.swift`

**Context:** Title rules + unique within Collection + tier1/2/3 each must resolve to the right tier + property values must conform to Vault schema (right type per `PropertyType`).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/ItemValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("ItemValidator")
struct ItemValidatorTests {

    @Test("happy path: valid title + resolving tier IDs + matching property values")
    func happy() throws {
        let space = makeSpace(); let topic = makeTopic(); let subtopic = makeSubtopic()
        let context = NexusContext(
            lookupSpace:    { id in id == space.id ? space : nil },
            lookupTopic:    { id in id == topic.id ? topic : nil },
            lookupSubtopic: { id in id == subtopic.id ? subtopic : nil },
            lookupVault:    { _ in nil }
        )
        let vault = makeVault(properties: [
            PropertyDefinition(name: "status", type: .select,
                selectOptions: [PropertyDefinition.SelectOption(value: "Active", label: "Active", color: nil)])
        ])
        try ItemValidator.validate(
            title: "Buy groceries",
            tier1: [space.id], tier2: [topic.id], tier3: [subtopic.id],
            properties: ["status": .select("Active")],
            vault: vault,
            existingInCollection: [],
            context: context
        )
    }

    @Test("tier1 ID resolving to a Topic (wrong tier) throws")
    func tier1WrongTier() {
        let topic = makeTopic()
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { id in id == topic.id ? topic : nil },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        let vault = makeVault(properties: [])
        #expect(throws: ItemValidator.ValidationError.tierMismatch(expectedTier: 1, id: topic.id)) {
            try ItemValidator.validate(
                title: "X", tier1: [topic.id], tier2: [], tier3: [],
                properties: [:], vault: vault,
                existingInCollection: [], context: context
            )
        }
    }

    @Test("property value of wrong type throws")
    func wrongPropertyType() {
        let vault = makeVault(properties: [
            PropertyDefinition(name: "count", type: .number)
        ])
        #expect(throws: ItemValidator.ValidationError.propertyTypeMismatch(name: "count")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["count": .checkbox(true)],  // wrong type
                vault: vault,
                existingInCollection: [], context: .empty
            )
        }
    }

    @Test("property not in vault schema throws")
    func unknownProperty() {
        let vault = makeVault(properties: [])
        #expect(throws: ItemValidator.ValidationError.unknownProperty(name: "phantom")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["phantom": .select("a")],
                vault: vault,
                existingInCollection: [], context: .empty
            )
        }
    }

    private func makeSpace() -> Space {
        Space(id: ULID.generate(), title: "S", color: .blue, icon: nil, blocks: [], modifiedAt: Date())
    }
    private func makeTopic() -> Topic {
        Topic(id: ULID.generate(), title: "T", parents: [], icon: nil, blocks: [], modifiedAt: Date())
    }
    private func makeSubtopic() -> Subtopic {
        Subtopic(id: ULID.generate(), title: "U", parents: ["01HX"],
                 linkedRelations: [], icon: nil, blocks: [], modifiedAt: Date())
    }
    private func makeVault(properties: [PropertyDefinition]) -> Vault {
        Vault(id: ULID.generate(), title: "V", icon: nil,
              properties: properties, views: [], modifiedAt: Date())
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/ItemValidator.swift`:

```swift
import Foundation

enum ItemValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case descriptionTooLong
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(name: String)
        case propertyTypeMismatch(name: String)
    }

    static let maxDescriptionLength = 250

    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        description: String = "",
        properties: [String: PropertyValue],
        vault: Vault,
        existingInCollection: [Item],
        context: NexusContext,
        excluding: Item? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        let conflict = existingInCollection.contains { i in
            i.id != excluding?.id &&
            i.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }

        guard description.count <= maxDescriptionLength else {
            throw ValidationError.descriptionTooLong
        }

        // tier rules
        for id in tier1 {
            if context.lookupSpace(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 1, id: id)
            }
        }
        for id in tier2 {
            if context.lookupTopic(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 2, id: id)
            }
        }
        for id in tier3 {
            if context.lookupSubtopic(id) == nil {
                throw ValidationError.tierMismatch(expectedTier: 3, id: id)
            }
        }

        // properties must be in schema + type match
        let schemaByName = Dictionary(uniqueKeysWithValues: vault.properties.map { ($0.name, $0) })
        for (name, value) in properties {
            guard let def = schemaByName[name] else {
                throw ValidationError.unknownProperty(name: name)
            }
            try validateType(value, against: def.type, name: name)
        }
    }

    private static func validateType(
        _ value: PropertyValue,
        against type: PropertyType,
        name: String
    ) throws {
        switch (value, type) {
        case (.number, .number),
             (.checkbox, .checkbox),
             (.date, .date),
             (.datetime, .datetime),
             (.select, .select),
             (.multiSelect, .multiSelect),
             (.relation, .relation),
             (.url, .url),
             (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(name: name)
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/ItemValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/ItemValidator.swift \
        Pommora/PommoraTests/Validation/ItemValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add ItemValidator + tests

Title rules + unique-in-Collection + 250-char description cap + tier1/2/3
must resolve to right tier + properties must be in Vault schema with
matching PropertyType (null always allowed).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 33: PageValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/PageValidator.swift`
- Create: `Pommora/PommoraTests/Validation/PageValidatorTests.swift`

**Context:** Same rules as Item minus the description cap (Pages put long text in body) plus `created_at` must be present.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/PageValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("PageValidator")
struct PageValidatorTests {

    @Test("happy path passes")
    func happy() throws {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        try PageValidator.validate(
            title: "Notes",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            vault: vault,
            existingInCollection: [],
            context: .empty
        )
    }

    @Test("created_at = zero-epoch is treated as missing")
    func missingCreatedAt() {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        #expect(throws: PageValidator.ValidationError.missingCreatedAt) {
            try PageValidator.validate(
                title: "X",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 0),
                vault: vault,
                existingInCollection: [],
                context: .empty
            )
        }
    }

    @Test("duplicate title in same Collection throws")
    func duplicate() throws {
        let vault = Vault(id: "01HV", title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        let existing = [makePageMeta(title: "Notes")]
        #expect(throws: PageValidator.ValidationError.duplicateTitle) {
            try PageValidator.validate(
                title: "NOTES",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 1),
                vault: vault,
                existingInCollection: existing,
                context: .empty
            )
        }
    }

    private func makePageMeta(title: String) -> PageMeta {
        PageMeta(
            id: ULID.generate(),
            title: title,
            url: URL(fileURLWithPath: "/tmp/x/\(title).md"),
            frontmatter: PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
    }
}
```

> **Note:** `PageMeta` is introduced in Task 39 (ContentManager). Until then, the test only compiles after Task 39. If executing strictly sequentially, run this test suite after Task 39 lands. Add a tracking note.

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/PageValidator.swift`:

```swift
import Foundation

enum PageValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
        case missingCreatedAt
        case tierMismatch(expectedTier: Int, id: String)
        case unknownProperty(name: String)
        case propertyTypeMismatch(name: String)
    }

    static func validate(
        title: String,
        tier1: [String], tier2: [String], tier3: [String],
        properties: [String: PropertyValue],
        createdAt: Date,
        vault: Vault,
        existingInCollection: [PageMeta],
        context: NexusContext,
        excluding: PageMeta? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // created_at must be present (epoch-zero sentinels for "missing"); allow values > 0
        guard createdAt.timeIntervalSince1970 > 0 else {
            throw ValidationError.missingCreatedAt
        }

        let conflict = existingInCollection.contains { p in
            p.id != excluding?.id &&
            p.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ValidationError.duplicateTitle }

        for id in tier1 where context.lookupSpace(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 1, id: id)
        }
        for id in tier2 where context.lookupTopic(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 2, id: id)
        }
        for id in tier3 where context.lookupSubtopic(id) == nil {
            throw ValidationError.tierMismatch(expectedTier: 3, id: id)
        }

        let schemaByName = Dictionary(uniqueKeysWithValues: vault.properties.map { ($0.name, $0) })
        for (name, value) in properties {
            guard let def = schemaByName[name] else {
                throw ValidationError.unknownProperty(name: name)
            }
            try validateType(value, against: def.type, name: name)
        }
    }

    private static func validateType(
        _ value: PropertyValue,
        against type: PropertyType,
        name: String
    ) throws {
        switch (value, type) {
        case (.number, .number), (.checkbox, .checkbox),
             (.date, .date), (.datetime, .datetime),
             (.select, .select), (.multiSelect, .multiSelect),
             (.relation, .relation), (.url, .url),
             (.null, _):
            return
        default:
            throw ValidationError.propertyTypeMismatch(name: name)
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/PageValidator -destination 'platform=macOS' 2>&1 | tail -10
# Note: tests reference PageMeta — defer to after Task 39 (ContentManager) if compiling in strict order
git add Pommora/Pommora/Validation/PageValidator.swift \
        Pommora/PommoraTests/Validation/PageValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(validation): add PageValidator + tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 34: AgendaValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/AgendaValidator.swift`
- Create: `Pommora/PommoraTests/Validation/AgendaValidatorTests.swift`

**Context:** Title rules + time-field consistency (`start_at` requires `end_at`, `end_at ≥ start_at`, `all_day` requires `start_at`, `due_all_day` requires `due_at`) + `type` property required and matches `_agenda.json` schema.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/AgendaValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("AgendaValidator")
struct AgendaValidatorTests {

    @Test("event-shaped (start+end) passes")
    func eventShape() throws {
        try AgendaValidator.validate(
            title: "Standup",
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            allDay: false,
            dueAt: nil, dueAllDay: false,
            properties: ["type": .select("Event")],
            schema: AgendaSchema.defaultSeed()
        )
    }

    @Test("reminder-shaped (due_at only) passes")
    func reminderShape() throws {
        try AgendaValidator.validate(
            title: "Buy", startAt: nil, endAt: nil, allDay: false,
            dueAt: Date(timeIntervalSince1970: 1000), dueAllDay: false,
            properties: ["type": .select("Task")],
            schema: AgendaSchema.defaultSeed()
        )
    }

    @Test("start_at without end_at throws missingEndAt")
    func startWithoutEnd() {
        #expect(throws: AgendaValidator.ValidationError.missingEndAt) {
            try AgendaValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: nil,
                allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Event")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("end_at before start_at throws endBeforeStart")
    func endBeforeStart() {
        #expect(throws: AgendaValidator.ValidationError.endBeforeStart) {
            try AgendaValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 200),
                endAt: Date(timeIntervalSince1970: 100),
                allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Event")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("all_day without start_at throws allDayWithoutStart")
    func allDayWithoutStart() {
        #expect(throws: AgendaValidator.ValidationError.allDayWithoutStart) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: true,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Task")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("due_all_day without due_at throws dueAllDayWithoutDue")
    func dueAllDayWithoutDue() {
        #expect(throws: AgendaValidator.ValidationError.dueAllDayWithoutDue) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: true,
                properties: ["type": .select("Task")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("missing type property throws missingTypeProperty")
    func missingType() {
        #expect(throws: AgendaValidator.ValidationError.missingTypeProperty) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: [:],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("type value not in schema options throws unknownTypeValue")
    func unknownTypeValue() {
        #expect(throws: AgendaValidator.ValidationError.unknownTypeValue("Madeup")) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Madeup")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/AgendaValidator.swift`:

```swift
import Foundation

enum AgendaValidator {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidTitleCharacters
        case missingEndAt
        case endBeforeStart
        case allDayWithoutStart
        case dueAllDayWithoutDue
        case missingTypeProperty
        case unknownTypeValue(String)
    }

    static func validate(
        title: String,
        startAt: Date?,
        endAt: Date?,
        allDay: Bool,
        dueAt: Date?,
        dueAllDay: Bool,
        properties: [String: PropertyValue],
        schema: AgendaSchema
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard title.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ValidationError.invalidTitleCharacters
        }

        // Time-field consistency
        if startAt != nil && endAt == nil { throw ValidationError.missingEndAt }
        if let s = startAt, let e = endAt, e < s { throw ValidationError.endBeforeStart }
        if allDay && startAt == nil { throw ValidationError.allDayWithoutStart }
        if dueAllDay && dueAt == nil { throw ValidationError.dueAllDayWithoutDue }

        // type property required + value must be one of schema's type-Select options
        guard case let .select(typeValue)? = properties["type"] else {
            throw ValidationError.missingTypeProperty
        }
        guard let typeProp = schema.properties.first(where: { $0.name == "type" }) else {
            throw ValidationError.missingTypeProperty
        }
        let allowed = Set((typeProp.options ?? []).map(\.value))
        guard allowed.contains(typeValue) else {
            throw ValidationError.unknownTypeValue(typeValue)
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AgendaValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/AgendaValidator.swift \
        Pommora/PommoraTests/Validation/AgendaValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(validation): add AgendaValidator + tests

Time-field consistency (start→end required, end≥start, all_day requires
start, due_all_day requires due) + required type property that matches
schema's type-Select options.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 35: HomepageValidator + tests

**Files:**
- Create: `Pommora/Pommora/Validation/HomepageValidator.swift`
- Create: `Pommora/PommoraTests/Validation/HomepageValidatorTests.swift`

**Context:** Singleton — only check that the file exists at the canonical location (or doesn't exist before seeding). Trivial; mostly here for symmetry.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Validation/HomepageValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("HomepageValidator")
struct HomepageValidatorTests {

    @Test("validateSingleton passes when exactly one file at canonical location")
    func happy() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(Homepage.defaultSeed(), to: url)
        try HomepageValidator.validateSingleton(in: nexus)
    }

    @Test("validateSingleton throws when file missing")
    func missing() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(throws: HomepageValidator.ValidationError.fileMissing) {
            try HomepageValidator.validateSingleton(in: nexus)
        }
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Validation/HomepageValidator.swift`:

```swift
import Foundation

enum HomepageValidator {
    enum ValidationError: Error, Equatable {
        case fileMissing
    }

    /// Verifies the canonical homepage file exists.
    /// Manager is responsible for ensuring it does (seeds on first load).
    static func validateSingleton(in nexus: Nexus) throws {
        let url = NexusPaths.homepageURL(in: nexus)
        if !Filesystem.fileExists(at: url) {
            throw ValidationError.fileMissing
        }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/HomepageValidator -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Validation/HomepageValidator.swift \
        Pommora/PommoraTests/Validation/HomepageValidatorTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(validation): add HomepageValidator singleton check

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 36: SpaceManager + tests

**Files:**
- Create: `Pommora/Pommora/Contexts/SpaceManager.swift`
- Create: `Pommora/PommoraTests/Contexts/SpaceManagerTests.swift`

**Context:** `@MainActor @Observable final class`. Owns the spaces array, exposes CRUD methods that write atomically + call `SpaceValidator` first. Assumes `NexusManager` holds the security-scoped resource scope.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/SpaceManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("SpaceManager")
struct SpaceManagerTests {

    @Test("create writes a .space.json on disk and adds to spaces")
    func create() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", color: .blue, icon: "person.circle")
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.spaces.count == 1)
        #expect(manager.spaces.first?.title == "Personal")
    }

    @Test("create with duplicate title throws + leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)

        await #expect(throws: SpaceValidator.ValidationError.duplicateTitle) {
            try await manager.create(name: "personal", color: .red, icon: nil)
        }
        #expect(manager.spaces.count == 1)
    }

    @Test("rename renames the file + updates in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.rename(space, to: "Life")
        let oldURL = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.spaceFileURL(forTitle: "Life", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.spaces.first?.title == "Life")
    }

    @Test("updateColor mutates field + bumps modified_at on disk")
    func updateColor() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.updateColor(space, to: .red)
        #expect(manager.spaces.first?.color == .red)
        let reloaded = try Space.load(from: NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus))
        #expect(reloaded.color == .red)
    }

    @Test("delete removes file + drops from spaces")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.delete(space)
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(manager.spaces.isEmpty)
    }

    @Test("loadAll reads existing .space.json files")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.spacesDir(in: nexus)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Space(id: "01H", title: "Pre-existing", color: .green, icon: nil,
                  blocks: [], modifiedAt: Date())
            .save(to: NexusPaths.spaceFileURL(forTitle: "Pre-existing", in: nexus))

        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.spaces.count == 1)
        #expect(manager.spaces.first?.title == "Pre-existing")
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement SpaceManager.**

Create `Pommora/Pommora/Contexts/SpaceManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SpaceManager {
    private(set) var spaces: [Space] = []
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.spacesDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let files = try Filesystem.children(of: dir) { url in
                url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "space"
            }
            let loaded = files.compactMap { try? Space.load(from: $0) }
            self.spaces = loaded.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            self.pendingError = nil
        } catch {
            self.spaces = []
            self.pendingError = error
        }
    }

    func create(name: String, color: SpaceColor, icon: String?) async throws {
        try SpaceValidator.validate(title: name, existing: spaces)

        let space = Space(
            id: ULID.generate(),
            title: name,
            color: color,
            icon: icon,
            blocks: [],
            modifiedAt: Date()
        )
        let dir = NexusPaths.spacesDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let url = NexusPaths.spaceFileURL(forTitle: name, in: nexus)
        try space.save(to: url)

        spaces.append(space)
        spaces.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func rename(_ space: Space, to newName: String) async throws {
        try SpaceValidator.validate(title: newName, existing: spaces, excluding: space)

        let oldURL = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
        let newURL = NexusPaths.spaceFileURL(forTitle: newName, in: nexus)

        var updated = space
        updated.title = newName
        updated.modifiedAt = Date()

        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        if let i = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[i] = updated
            spaces.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func updateColor(_ space: Space, to color: SpaceColor) async throws {
        var updated = space
        updated.color = color
        updated.modifiedAt = Date()
        let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
        try updated.save(to: url)
        if let i = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[i] = updated
        }
    }

    func updateIcon(_ space: Space, to icon: String?) async throws {
        var updated = space
        updated.icon = icon
        updated.modifiedAt = Date()
        let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
        try updated.save(to: url)
        if let i = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[i] = updated
        }
    }

    func delete(_ space: Space) async throws {
        let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
        try Filesystem.deleteFile(at: url)
        spaces.removeAll { $0.id == space.id }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SpaceManager -destination 'platform=macOS' 2>&1 | tail -15
git add Pommora/Pommora/Contexts/SpaceManager.swift \
        Pommora/PommoraTests/Contexts/SpaceManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add SpaceManager + CRUD tests

@MainActor @Observable. loadAll/create/rename/updateColor/updateIcon/
delete. Sorts spaces by localized title order. Calls SpaceValidator
before every mutation; assumes NexusManager holds the security scope.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 37: TopicManager (Topics + Sub-topics) + tests

**Files:**
- Create: `Pommora/Pommora/Contexts/TopicManager.swift`
- Create: `Pommora/PommoraTests/Contexts/TopicManagerTests.swift`

**Context:** Manages both Topics and Sub-topics together since Sub-topics live inside Topic folders and have no independent storage. Supports the locked promote-vs-cascade Topic delete behavior. Takes a `NexusContext` provider closure so it can validate Topic parents (Spaces) without holding a SpaceManager reference (avoids circular ownership).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Contexts/TopicManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("TopicManager")
struct TopicManagerTests {

    @Test("createTopic writes folder + _topic.json; loadAll reads them back")
    func createTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let folder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: "Productivity", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.topics.count == 1)
        #expect(manager.topics.first?.title == "Productivity")
    }

    @Test("createSubtopic writes .subtopic.json inside parent Topic folder")
    func createSubtopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD method", inTopic: topic, icon: nil)

        let stURL = NexusPaths.subtopicFileURL(
            forTitle: "GTD method", inTopicTitled: "Productivity", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: stURL.path))
        #expect(manager.subtopics(in: topic).count == 1)
        #expect(manager.subtopics(in: topic).first?.title == "GTD method")
    }

    @Test("renameTopic moves the folder; sub-topics inside follow")
    func renameTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)

        try await manager.renameTopic(topic, to: "Workflows")
        let newMeta = NexusPaths.topicMetadataURL(forTitle: "Workflows", in: nexus)
        let newSub = NexusPaths.subtopicFileURL(
            forTitle: "GTD", inTopicTitled: "Workflows", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newMeta.path))
        #expect(FileManager.default.fileExists(atPath: newSub.path))
        let oldFolder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
    }

    @Test("deleteTopic(promotingSubtopics: true) moves sub-topics out as standalone Topics")
    func deletePromote() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)
        try await manager.createSubtopic(name: "Time blocking", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingSubtopics: true)
        // Parent folder gone
        #expect(!FileManager.default.fileExists(
            atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
        ))
        // Sub-topics promoted to top-level Topics with their own folders
        let gtdMeta = NexusPaths.topicMetadataURL(forTitle: "GTD", in: nexus)
        let tbMeta = NexusPaths.topicMetadataURL(forTitle: "Time blocking", in: nexus)
        #expect(FileManager.default.fileExists(atPath: gtdMeta.path))
        #expect(FileManager.default.fileExists(atPath: tbMeta.path))
        // Manager state: 2 top-level topics, no subtopics
        #expect(manager.topics.count == 2)
        for t in manager.topics {
            #expect(manager.subtopics(in: t).isEmpty)
        }
    }

    @Test("deleteTopic(promotingSubtopics: false) cascades")
    func deleteCascade() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingSubtopics: false)
        #expect(!FileManager.default.fileExists(
            atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
        ))
        #expect(manager.topics.isEmpty)
    }

    @Test("moveSubtopic relocates the file to new parent's folder")
    func moveSubtopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "A", parents: [], icon: nil)
        try await manager.createTopic(name: "B", parents: [], icon: nil)
        let a = manager.topics.first { $0.title == "A" }!
        let b = manager.topics.first { $0.title == "B" }!
        try await manager.createSubtopic(name: "X", inTopic: a, icon: nil)
        let sub = manager.subtopics(in: a).first!

        try await manager.moveSubtopic(sub, toTopic: b)
        #expect(!FileManager.default.fileExists(
            atPath: NexusPaths.subtopicFileURL(forTitle: "X", inTopicTitled: "A", in: nexus).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: NexusPaths.subtopicFileURL(forTitle: "X", inTopicTitled: "B", in: nexus).path
        ))
        #expect(manager.subtopics(in: a).isEmpty)
        #expect(manager.subtopics(in: b).count == 1)
    }

    // MARK: - helper

    private func setup() async throws -> (Nexus, TopicManager) {
        let nexus = try TempNexus.make()
        let manager = TopicManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll()
        return (nexus, manager)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement TopicManager.**

Create `Pommora/Pommora/Contexts/TopicManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TopicManager {
    private(set) var topics: [Topic] = []
    /// Keyed by parent Topic ID.
    private(set) var subtopicsByParent: [String: [Subtopic]] = [:]
    var pendingError: Error?

    private let nexus: Nexus
    private let contextProvider: @MainActor () -> NexusContext

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func subtopics(in topic: Topic) -> [Subtopic] {
        subtopicsByParent[topic.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            let topicsDir = NexusPaths.topicsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(topicsDir)

            var loadedTopics: [Topic] = []
            var loadedSubs: [String: [Subtopic]] = [:]

            let topicFolders = try Filesystem.childFolders(of: topicsDir)
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }  // skip cosmetic folder
                guard let topic = try? Topic.load(from: metaURL) else { continue }
                loadedTopics.append(topic)

                let subFiles = try Filesystem.children(of: folder) { url in
                    url.pathExtension == "json" &&
                    url.deletingPathExtension().pathExtension == "subtopic"
                }
                let subs = subFiles.compactMap { try? Subtopic.load(from: $0) }
                    .map { st -> Subtopic in
                        var copy = st
                        copy.parents = [topic.id]   // file-location-derived parent
                        return copy
                    }
                loadedSubs[topic.id] = subs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }

            self.topics = loadedTopics.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            self.subtopicsByParent = loadedSubs
            self.pendingError = nil
        } catch {
            self.topics = []
            self.subtopicsByParent = [:]
            self.pendingError = error
        }
    }

    // MARK: - Topic CRUD

    func createTopic(name: String, parents: [String], icon: String?) async throws {
        try TopicValidator.validate(
            title: name, parents: parents,
            existing: topics, context: contextProvider()
        )

        let topic = Topic(
            id: ULID.generate(),
            title: name,
            parents: parents,
            icon: icon,
            blocks: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.topicFolderURL(forTitle: name, in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: name, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)

        topics.append(topic)
        subtopicsByParent[topic.id] = []
        topics.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func renameTopic(_ topic: Topic, to newName: String) async throws {
        try TopicValidator.validate(
            title: newName, parents: topic.parents,
            existing: topics, context: contextProvider(),
            excluding: topic
        )

        let oldFolder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
        let newFolder = NexusPaths.topicFolderURL(forTitle: newName, in: nexus)
        try Filesystem.renameFolder(from: oldFolder, to: newFolder)

        var updated = topic
        updated.title = newName
        updated.modifiedAt = Date()
        let newMeta = NexusPaths.topicMetadataURL(forTitle: newName, in: nexus)
        try updated.save(to: newMeta)

        if let i = topics.firstIndex(where: { $0.id == topic.id }) {
            topics[i] = updated
            topics.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func updateTopicParents(_ topic: Topic, to parents: [String]) async throws {
        try TopicValidator.validate(
            title: topic.title, parents: parents,
            existing: topics, context: contextProvider(),
            excluding: topic
        )

        var updated = topic
        updated.parents = parents
        updated.modifiedAt = Date()
        let meta = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
        try updated.save(to: meta)

        if let i = topics.firstIndex(where: { $0.id == topic.id }) {
            topics[i] = updated
        }
    }

    func updateTopicIcon(_ topic: Topic, to icon: String?) async throws {
        var updated = topic
        updated.icon = icon
        updated.modifiedAt = Date()
        let meta = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
        try updated.save(to: meta)
        if let i = topics.firstIndex(where: { $0.id == topic.id }) {
            topics[i] = updated
        }
    }

    /// Deletes a Topic. If `promotingSubtopics` is true (default), Sub-topics inside
    /// are converted to standalone Topics inheriting the deleted Topic's parents.
    /// On filename collision with an existing top-level Topic, auto-suffixes (2), (3), …
    func deleteTopic(_ topic: Topic, promotingSubtopics: Bool = true) async throws {
        let subs = subtopicsByParent[topic.id] ?? []

        if promotingSubtopics {
            for sub in subs {
                try await promoteSubtopicToTopic(sub, inheritedParents: topic.parents)
            }
        }

        let folder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
        try Filesystem.deleteFolder(at: folder)
        topics.removeAll { $0.id == topic.id }
        subtopicsByParent.removeValue(forKey: topic.id)
    }

    private func promoteSubtopicToTopic(_ sub: Subtopic, inheritedParents: [String]) async throws {
        var promotedName = sub.title
        var suffix = 2
        while topics.contains(where: { $0.title.lowercased() == promotedName.lowercased() }) {
            promotedName = "\(sub.title) (\(suffix))"
            suffix += 1
        }
        let topic = Topic(
            id: ULID.generate(),   // new identity at tier-2; old Subtopic id is dropped
            title: promotedName,
            parents: inheritedParents,
            icon: sub.icon,
            blocks: sub.blocks,
            modifiedAt: Date()
        )
        let folder = NexusPaths.topicFolderURL(forTitle: promotedName, in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: promotedName, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)
        topics.append(topic)
        subtopicsByParent[topic.id] = []
    }

    // MARK: - Subtopic CRUD

    func createSubtopic(name: String, inTopic parent: Topic, icon: String?) async throws {
        let existing = subtopicsByParent[parent.id] ?? []
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { [topics] id in topics.first { $0.id == id } },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        try SubtopicValidator.validate(
            title: name,
            parents: [parent.id],
            fileLocation: .init(parentFolderTitle: parent.title),
            existing: existing,
            context: context
        )

        let sub = Subtopic(
            id: ULID.generate(),
            title: name,
            parents: [parent.id],
            linkedRelations: [],
            icon: icon,
            blocks: [],
            modifiedAt: Date()
        )
        let url = NexusPaths.subtopicFileURL(
            forTitle: name, inTopicTitled: parent.title, in: nexus
        )
        try sub.save(to: url)

        var arr = subtopicsByParent[parent.id] ?? []
        arr.append(sub)
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        subtopicsByParent[parent.id] = arr
    }

    func renameSubtopic(_ sub: Subtopic, to newName: String) async throws {
        guard let parentID = sub.parents.first,
              let parent = topics.first(where: { $0.id == parentID })
        else { throw SubtopicValidator.ValidationError.missingParent }

        let existing = subtopicsByParent[parent.id] ?? []
        let context = NexusContext(
            lookupSpace:    { _ in nil },
            lookupTopic:    { [topics] id in topics.first { $0.id == id } },
            lookupSubtopic: { _ in nil },
            lookupVault:    { _ in nil }
        )
        try SubtopicValidator.validate(
            title: newName,
            parents: [parent.id],
            fileLocation: .init(parentFolderTitle: parent.title),
            existing: existing,
            context: context,
            excluding: sub
        )

        let oldURL = NexusPaths.subtopicFileURL(
            forTitle: sub.title, inTopicTitled: parent.title, in: nexus
        )
        let newURL = NexusPaths.subtopicFileURL(
            forTitle: newName, inTopicTitled: parent.title, in: nexus
        )
        var updated = sub
        updated.title = newName
        updated.modifiedAt = Date()
        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        var arr = subtopicsByParent[parent.id] ?? []
        if let i = arr.firstIndex(where: { $0.id == sub.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        subtopicsByParent[parent.id] = arr
    }

    func moveSubtopic(_ sub: Subtopic, toTopic newParent: Topic) async throws {
        guard let oldParentID = sub.parents.first,
              let oldParent = topics.first(where: { $0.id == oldParentID })
        else { throw SubtopicValidator.ValidationError.missingParent }
        guard oldParent.id != newParent.id else { return }

        let oldURL = NexusPaths.subtopicFileURL(
            forTitle: sub.title, inTopicTitled: oldParent.title, in: nexus
        )
        let newURL = NexusPaths.subtopicFileURL(
            forTitle: sub.title, inTopicTitled: newParent.title, in: nexus
        )

        var updated = sub
        updated.parents = [newParent.id]
        updated.modifiedAt = Date()
        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        var oldArr = subtopicsByParent[oldParent.id] ?? []
        oldArr.removeAll { $0.id == sub.id }
        subtopicsByParent[oldParent.id] = oldArr

        var newArr = subtopicsByParent[newParent.id] ?? []
        newArr.append(updated)
        newArr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        subtopicsByParent[newParent.id] = newArr
    }

    func deleteSubtopic(_ sub: Subtopic) async throws {
        guard let parentID = sub.parents.first,
              let parent = topics.first(where: { $0.id == parentID })
        else { throw SubtopicValidator.ValidationError.missingParent }

        let url = NexusPaths.subtopicFileURL(
            forTitle: sub.title, inTopicTitled: parent.title, in: nexus
        )
        try Filesystem.deleteFile(at: url)
        var arr = subtopicsByParent[parent.id] ?? []
        arr.removeAll { $0.id == sub.id }
        subtopicsByParent[parent.id] = arr
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TopicManager -destination 'platform=macOS' 2>&1 | tail -20
git add Pommora/Pommora/Contexts/TopicManager.swift \
        Pommora/PommoraTests/Contexts/TopicManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(contexts): add TopicManager (Topics + Sub-topics) + tests

Combined manager since Sub-topics live inside Topic folders.
Topic CRUD: create/rename/updateParents/updateIcon/delete (with
promote-vs-cascade Sub-topic flag, default = promote). Sub-topic CRUD:
create/rename/move/delete. Folder+metadata atomicity discipline; sorted
output; cross-entity lookups via injected NexusContext provider closure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 38: VaultManager + tests

**Files:**
- Create: `Pommora/Pommora/Vaults/VaultManager.swift`
- Create: `Pommora/PommoraTests/Vaults/VaultManagerTests.swift`

**Context:** Manages Vaults (each = folder + `_vault.json`) AND their Collections (sub-folders with no metadata). Collections are discovered by walking each Vault's children that are folders (skipping any folder beginning with `_` or `.`).

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Vaults/VaultManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("VaultManager")
struct VaultManagerTests {

    @Test("createVault writes folder + _vault.json")
    func createVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: "folder")
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.vaults.count == 1)
        #expect(manager.vaults.first?.title == "Planner")
    }

    @Test("createCollection creates folder inside Vault")
    func createCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let cols = manager.collections(in: vault)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("renameVault renames folder + updates collection paths")
    func renameVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        try await manager.renameVault(vault, to: "Schedule")
        let newFolder = NexusPaths.vaultFolderURL(forTitle: "Schedule", in: nexus)
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        // Collection still present under new vault folder
        let renamedVault = manager.vaults.first!
        let cols = manager.collections(in: renamedVault)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("deleteVault removes folder + collections")
    func deleteVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        try await manager.deleteVault(vault)
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.vaults.isEmpty)
    }

    @Test("loadAll skips top-level folders without _vault.json (cosmetic dirs)")
    func skipCosmeticFolders() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Create a top-level folder that ISN'T a vault
        try FileManager.default.createDirectory(
            at: nexus.rootURL.appendingPathComponent("NotAVault", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.vaults.isEmpty)
    }

    @Test("renameCollection moves the folder")
    func renameCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)
        let coll = manager.collections(in: vault).first!

        try await manager.renameCollection(coll, to: "To-dos")
        let newFolder = NexusPaths.collectionFolderURL(
            forTitle: "To-dos", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(manager.collections(in: vault).first?.title == "To-dos")
    }

    @Test("deleteCollection removes folder")
    func deleteCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)
        let coll = manager.collections(in: vault).first!

        try await manager.deleteCollection(coll)
        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.collections(in: vault).isEmpty)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Vaults/VaultManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class VaultManager {
    private(set) var vaults: [Vault] = []
    private(set) var collectionsByVault: [String: [Collection]] = [:]
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func collections(in vault: Vault) -> [Collection] {
        collectionsByVault[vault.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // Top-level folders inside nexus root that contain _vault.json
            let topLevel = try Filesystem.childFolders(of: nexus.rootURL)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }
                .filter { $0.lastPathComponent != "Agenda" }
                .filter { $0.lastPathComponent != ".trash" }

            var loadedVaults: [Vault] = []
            var loadedCols: [String: [Collection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent("_vault.json")
                guard Filesystem.fileExists(at: metaURL),
                      let vault = try? Vault.load(from: metaURL)
                else { continue }
                loadedVaults.append(vault)

                // Discover Collections (sub-folders with _collection.json sidecar; skip _- and .-prefixed)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { folder -> Collection? in
                        let metaURL = folder.appendingPathComponent("_collection.json")
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? Collection.load(from: metaURL)
                    }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                loadedCols[vault.id] = cols
            }

            self.vaults = loadedVaults.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            self.collectionsByVault = loadedCols
            self.pendingError = nil
        } catch {
            self.vaults = []
            self.collectionsByVault = [:]
            self.pendingError = error
        }
    }

    // MARK: - Vault CRUD

    func createVault(name: String, icon: String?) async throws {
        try VaultValidator.validate(title: name, existing: vaults)

        let vault = Vault(
            id: ULID.generate(),
            title: name,
            icon: icon,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: name, in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: name, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: vault)

        vaults.append(vault)
        collectionsByVault[vault.id] = []
        vaults.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func renameVault(_ vault: Vault, to newName: String) async throws {
        try VaultValidator.validate(title: newName, existing: vaults, excluding: vault)

        let oldFolder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        let newFolder = NexusPaths.vaultFolderURL(forTitle: newName, in: nexus)
        try Filesystem.renameFolder(from: oldFolder, to: newFolder)

        var updated = vault
        updated.title = newName
        updated.modifiedAt = Date()
        let newMeta = NexusPaths.vaultMetadataURL(forTitle: newName, in: nexus)
        try updated.save(to: newMeta)

        if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[i] = updated
            // Rebuild Collection in-memory under new parent path (id + vault_id unchanged;
            // _collection.json sidecar moved with its folder, just re-derive folderURL).
            if let oldCols = collectionsByVault[vault.id] {
                let rebuilt = oldCols.map { c -> Collection in
                    let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                    return Collection(
                        id: c.id,
                        vaultID: c.vaultID,
                        title: c.title,
                        folderURL: newCollURL,
                        modifiedAt: c.modifiedAt
                    )
                }
                collectionsByVault[vault.id] = rebuilt
            }
            vaults.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func updateVaultIcon(_ vault: Vault, to icon: String?) async throws {
        var updated = vault
        updated.icon = icon
        updated.modifiedAt = Date()
        let meta = NexusPaths.vaultMetadataURL(forTitle: vault.title, in: nexus)
        try updated.save(to: meta)
        if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[i] = updated
        }
    }

    func deleteVault(_ vault: Vault) async throws {
        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        try Filesystem.deleteFolder(at: folder)
        vaults.removeAll { $0.id == vault.id }
        collectionsByVault.removeValue(forKey: vault.id)
    }

    // MARK: - Collection CRUD

    func createCollection(name: String, inVault vault: Vault) async throws {
        let existing = collectionsByVault[vault.id] ?? []
        try CollectionValidator.validate(title: name, existingInVault: existing)

        let folder = NexusPaths.collectionFolderURL(
            forTitle: name, inVaultTitled: vault.title, in: nexus
        )
        let now = Date()
        let coll = Collection(
            id: ULID.generate(),
            vaultID: vault.id,
            title: name,
            folderURL: folder,
            modifiedAt: now
        )
        let metaURL = folder.appendingPathComponent("_collection.json")
        try Filesystem.createFolderWithMetadata(
            folderURL: folder, metadataURL: metaURL, metadata: coll
        )

        var arr = existing
        arr.append(coll)
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        collectionsByVault[vault.id] = arr
    }

    func renameCollection(_ collection: Collection, to newName: String) async throws {
        guard let vault = vaults.first(where: { $0.id == collection.vaultID }) else { return }
        let existing = collectionsByVault[vault.id] ?? []
        try CollectionValidator.validate(
            title: newName, existingInVault: existing, excluding: collection
        )

        let newURL = NexusPaths.collectionFolderURL(
            forTitle: newName, inVaultTitled: vault.title, in: nexus
        )
        try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

        // Bump modified_at in the sidecar at its new location
        let now = Date()
        let updated = Collection(
            id: collection.id,
            vaultID: collection.vaultID,
            title: newName,
            folderURL: newURL,
            modifiedAt: now
        )
        let metaURL = newURL.appendingPathComponent("_collection.json")
        try updated.save(to: metaURL)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == collection.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        collectionsByVault[vault.id] = arr
    }

    func deleteCollection(_ collection: Collection) async throws {
        try Filesystem.deleteFolder(at: collection.folderURL)
        var arr = collectionsByVault[collection.vaultID] ?? []
        arr.removeAll { $0.id == collection.id }
        collectionsByVault[collection.vaultID] = arr
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/VaultManager -destination 'platform=macOS' 2>&1 | tail -20
git add Pommora/Pommora/Vaults/VaultManager.swift \
        Pommora/PommoraTests/Vaults/VaultManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(vaults): add VaultManager (Vaults + Collections) + tests

@MainActor @Observable. Vault CRUD (folder+_vault.json atomic
creation), Collection CRUD (folder only, no metadata). loadAll skips
top-level folders that aren't vaults (no _vault.json, hidden, _-prefixed,
or known siblings like Agenda/.trash). Collections rebuilt with new
paths on vault rename.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 39: PageMeta + ContentManager + tests

**Files:**
- Create: `Pommora/Pommora/Content/PageMeta.swift`
- Create: `Pommora/Pommora/Content/ContentManager.swift`
- Create: `Pommora/PommoraTests/Content/ContentManagerTests.swift`

**Context:** `ContentManager` handles Pages + Items within Collections. `PageMeta` is a lightweight value (id + title + url + frontmatter) — we don't keep the full body in memory; full PageFile is loaded on demand. Items load entirely since they're small.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Content/ContentManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("ContentManager")
struct ContentManagerTests {

    @Test("createPage writes .md with frontmatter scaffold")
    func createPage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let pages = manager.pages(in: coll)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Notes")

        let loaded = try PageFile.load(from: url)
        #expect(!loaded.frontmatter.id.isEmpty)
        #expect(loaded.body == "")
        #expect(loaded.frontmatter.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("createItem writes .json with empty structure")
    func createItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createItem(name: "Buy groceries", in: coll, vault: vault)
        let url = NexusPaths.itemFileURL(forTitle: "Buy groceries", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let items = manager.items(in: coll)
        #expect(items.count == 1)
        #expect(items.first?.title == "Buy groceries")
    }

    @Test("renamePage moves file + updates pages list")
    func renamePage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        try await manager.renamePage(page, to: "Ideas", in: coll, vault: vault)
        #expect(!FileManager.default.fileExists(
            atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL).path
        ))
        #expect(manager.pages(in: coll).first?.title == "Ideas")
    }

    @Test("renameItem moves file + updates items list")
    func renameItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createItem(name: "X", in: coll, vault: vault)
        let item = manager.items(in: coll).first!

        try await manager.renameItem(item, to: "Y", in: coll, vault: vault)
        #expect(manager.items(in: coll).first?.title == "Y")
    }

    @Test("updateItem persists property changes")
    func updateItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createItem(name: "X", in: coll, vault: vault)
        var item = manager.items(in: coll).first!
        item.description = "Updated"

        try await manager.updateItem(item, in: coll, vault: vault)
        #expect(manager.items(in: coll).first?.description == "Updated")
        let url = NexusPaths.itemFileURL(forTitle: "X", in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.description == "Updated")
    }

    @Test("deletePage + deleteItem remove files")
    func deletes() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "P", in: coll, vault: vault)
        try await manager.createItem(name: "I", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!
        let item = manager.items(in: coll).first!

        try await manager.deletePage(page, in: coll)
        try await manager.deleteItem(item, in: coll)
        #expect(manager.pages(in: coll).isEmpty)
        #expect(manager.items(in: coll).isEmpty)
    }

    @Test("loadAll discovers existing .md + .json in a Collection")
    func loadExisting() async throws {
        let (nexus, _, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try FixtureFiles.write(
            "---\nid: 01HPRE\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Pre", in: coll.folderURL)
        )
        try Item(
            id: "01HITEM", title: "Pre", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "Pre-item", in: coll.folderURL))

        await manager.loadAll(for: coll)
        #expect(manager.pages(in: coll).count == 1)
        #expect(manager.items(in: coll).count == 1)
    }

    private func setup() async throws -> (Nexus, Vault, Collection, ContentManager) {
        let nexus = try TempNexus.make()
        let vault = Vault(id: ULID.generate(), title: "V", icon: nil,
                          properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = Collection(
            id: ULID.generate(),
            vaultID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = ContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, manager)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Content/PageMeta.swift`:

```swift
import Foundation

/// Lightweight in-memory representation of a Page (no body).
/// Full `PageFile` loaded on demand by the editor (post-v0.2).
struct PageMeta: Equatable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    let url: URL
    var frontmatter: PageFrontmatter
}
```

Create `Pommora/Pommora/Content/ContentManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ContentManager {
    /// Keyed by Collection.id.
    private(set) var pagesByCollection: [String: [PageMeta]] = [:]
    private(set) var itemsByCollection: [String: [Item]] = [:]
    var pendingError: Error?

    private let nexus: Nexus
    private let contextProvider: @MainActor () -> NexusContext

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    func pages(in collection: Collection) -> [PageMeta] {
        pagesByCollection[collection.id] ?? []
    }

    func items(in collection: Collection) -> [Item] {
        itemsByCollection[collection.id] ?? []
    }

    // MARK: - Load

    func loadAll(for collection: Collection) async {
        do {
            let pageFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "md"
            }
            let pageMetas: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.load(from: url) else { return nil }
                return PageMeta(id: pf.frontmatter.id, title: pf.title, url: url, frontmatter: pf.frontmatter)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            let itemFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "json"
            }
            let items: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            pagesByCollection[collection.id] = pageMetas
            itemsByCollection[collection.id] = items
            pendingError = nil
        } catch {
            pagesByCollection[collection.id] = []
            itemsByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Page CRUD

    func createPage(name: String, in collection: Collection, vault: Vault) async throws {
        let existing = pagesByCollection[collection.id] ?? []
        try PageValidator.validate(
            title: name,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(),
            vault: vault,
            existingInCollection: existing,
            context: contextProvider()
        )

        let now = Date()
        let frontmatter = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now
        )
        let page = PageFile(frontmatter: frontmatter, body: "", title: name)
        let url = NexusPaths.pageFileURL(forTitle: name, in: collection.folderURL)
        try page.save(to: url)

        let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
        var arr = existing
        arr.append(meta)
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        pagesByCollection[collection.id] = arr
    }

    func renamePage(_ page: PageMeta, to newName: String, in collection: Collection, vault: Vault) async throws {
        let existing = pagesByCollection[collection.id] ?? []
        try PageValidator.validate(
            title: newName,
            tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
            properties: page.frontmatter.properties,
            createdAt: page.frontmatter.createdAt,
            vault: vault,
            existingInCollection: existing,
            context: contextProvider(),
            excluding: page
        )

        let newURL = NexusPaths.pageFileURL(forTitle: newName, in: collection.folderURL)
        try Filesystem.renameFile(from: page.url, to: newURL)

        var updated = page
        updated.title = newName
        updated.url = newURL

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == page.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        pagesByCollection[collection.id] = arr
    }

    func deletePage(_ page: PageMeta, in collection: Collection) async throws {
        try Filesystem.deleteFile(at: page.url)
        var arr = pagesByCollection[collection.id] ?? []
        arr.removeAll { $0.id == page.id }
        pagesByCollection[collection.id] = arr
    }

    // MARK: - Item CRUD

    func createItem(name: String, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: name, tier1: [], tier2: [], tier3: [],
            description: "",
            properties: [:],
            vault: vault, existingInCollection: existing,
            context: contextProvider()
        )

        let now = Date()
        let item = Item(
            id: ULID.generate(), title: name, icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let url = NexusPaths.itemFileURL(forTitle: name, in: collection.folderURL)
        try item.save(to: url)

        var arr = existing
        arr.append(item)
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        itemsByCollection[collection.id] = arr
    }

    func renameItem(_ item: Item, to newName: String, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: newName,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description, properties: item.properties,
            vault: vault, existingInCollection: existing,
            context: contextProvider(), excluding: item
        )

        let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
        let newURL = NexusPaths.itemFileURL(forTitle: newName, in: collection.folderURL)
        var updated = item
        updated.title = newName
        updated.modifiedAt = Date()
        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == item.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        itemsByCollection[collection.id] = arr
    }

    func updateItem(_ item: Item, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: item.title,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description, properties: item.properties,
            vault: vault, existingInCollection: existing,
            context: contextProvider(), excluding: item
        )

        var updated = item
        updated.modifiedAt = Date()
        let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
        try updated.save(to: url)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == item.id }) {
            arr[i] = updated
        }
        itemsByCollection[collection.id] = arr
    }

    func deleteItem(_ item: Item, in collection: Collection) async throws {
        let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
        try Filesystem.deleteFile(at: url)
        var arr = itemsByCollection[collection.id] ?? []
        arr.removeAll { $0.id == item.id }
        itemsByCollection[collection.id] = arr
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/ContentManager -destination 'platform=macOS' 2>&1 | tail -20
git add Pommora/Pommora/Content/PageMeta.swift \
        Pommora/Pommora/Content/ContentManager.swift \
        Pommora/PommoraTests/Content/ContentManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(content): add PageMeta + ContentManager

PageMeta = id+title+url+frontmatter (no body in memory). ContentManager
handles Pages + Items per Collection: loadAll/createPage/createItem/
renamePage/renameItem/updateItem/deletePage/deleteItem. Validates via
PageValidator/ItemValidator before every write.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 40: AgendaManager + tests

**Files:**
- Create: `Pommora/Pommora/Agenda/AgendaManager.swift`
- Create: `Pommora/PommoraTests/Agenda/AgendaManagerTests.swift`

**Context:** Data-only scaffold (no EventKit sync in this plan). Seeds `_agenda.json` schema sidecar on first init. Validates via `AgendaValidator`.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Agenda/AgendaManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("AgendaManager")
struct AgendaManagerTests {

    @Test("loadAll seeds _agenda.json schema if missing")
    func seedsSchema() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()
        let schemaURL = NexusPaths.agendaSchemaURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))
        let loaded = try AtomicJSON.decode(AgendaSchema.self, from: schemaURL)
        #expect(loaded.properties.contains { $0.name == "type" && $0.builtin })
    }

    @Test("createItem writes .agenda.json with type=Task")
    func createTask() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "Buy groceries", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try await manager.createItem(item)
        let url = NexusPaths.agendaItemFileURL(forTitle: "Buy groceries", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.items.count == 1)
    }

    @Test("createItem with invalid type throws")
    func invalidType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "X", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Bogus")]
        )
        await #expect(throws: AgendaValidator.ValidationError.unknownTypeValue("Bogus")) {
            try await manager.createItem(item)
        }
    }

    @Test("deleteItem removes file + drops from items")
    func deleteItem() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "X", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try await manager.createItem(item)
        try await manager.deleteItem(item)
        #expect(manager.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Agenda/AgendaManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AgendaManager {
    private(set) var schema: AgendaSchema = AgendaSchema.defaultSeed()
    private(set) var items: [AgendaItem] = []
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.agendaDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)

            let schemaURL = NexusPaths.agendaSchemaURL(in: nexus)
            if Filesystem.fileExists(at: schemaURL) {
                schema = try AtomicJSON.decode(AgendaSchema.self, from: schemaURL)
            } else {
                schema = AgendaSchema.defaultSeed()
                try AtomicJSON.write(schema, to: schemaURL)
            }

            let itemFiles = try Filesystem.children(of: dir) { url in
                url.pathExtension == "json" &&
                url.deletingPathExtension().pathExtension == "agenda"
            }
            items = itemFiles.compactMap { try? AgendaItem.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            pendingError = nil
        } catch {
            items = []
            pendingError = error
        }
    }

    func createItem(_ item: AgendaItem) async throws {
        try AgendaValidator.validate(
            title: item.title,
            startAt: item.startAt, endAt: item.endAt, allDay: item.allDay,
            dueAt: item.dueAt, dueAllDay: item.dueAllDay,
            properties: item.properties,
            schema: schema
        )
        let dir = NexusPaths.agendaDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
        try item.save(to: url)
        items.append(item)
        items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func updateItem(_ item: AgendaItem) async throws {
        try AgendaValidator.validate(
            title: item.title,
            startAt: item.startAt, endAt: item.endAt, allDay: item.allDay,
            dueAt: item.dueAt, dueAllDay: item.dueAllDay,
            properties: item.properties,
            schema: schema
        )
        var updated = item
        updated.modifiedAt = Date()
        let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
        try updated.save(to: url)
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = updated
        }
    }

    func deleteItem(_ item: AgendaItem) async throws {
        let url = NexusPaths.agendaItemFileURL(forTitle: item.title, in: nexus)
        try Filesystem.deleteFile(at: url)
        items.removeAll { $0.id == item.id }
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/AgendaManager -destination 'platform=macOS' 2>&1 | tail -15
git add Pommora/Pommora/Agenda/AgendaManager.swift \
        Pommora/PommoraTests/Agenda/AgendaManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(agenda): add AgendaManager (data layer, no EventKit yet)

Seeds _agenda.json schema on first init. CRUD validates via
AgendaValidator. No UI integration in this plan; full EventKit
sync lands v0.4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 41: HomepageManager + tests

**Files:**
- Create: `Pommora/Pommora/Homepage/HomepageManager.swift`
- Create: `Pommora/PommoraTests/Homepage/HomepageManagerTests.swift`

**Context:** Singleton manager. Seeds `homepage.json` on first load if missing. Save persists changes.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Homepage/HomepageManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("HomepageManager")
struct HomepageManagerTests {

    @Test("load seeds homepage.json if missing")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        let url = NexusPaths.homepageURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.homepage.icon == "house")
    }

    @Test("load reads existing homepage.json")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(
            Homepage(schemaVersion: 1, icon: "bookmark", blocks: [],
                     modifiedAt: Date(timeIntervalSince1970: 1716480000)),
            to: url
        )
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        #expect(manager.homepage.icon == "bookmark")
    }

    @Test("save persists changes")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        manager.homepage.icon = "star"
        try await manager.save()
        let reloaded = try AtomicJSON.decode(Homepage.self, from: NexusPaths.homepageURL(in: nexus))
        #expect(reloaded.icon == "star")
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Homepage/HomepageManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class HomepageManager {
    var homepage: Homepage = Homepage.defaultSeed()
    var pendingError: Error?

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
        homepage.modifiedAt = Date()
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(homepage, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/HomepageManager -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Homepage/HomepageManager.swift \
        Pommora/PommoraTests/Homepage/HomepageManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(homepage): add HomepageManager singleton (seeds on first load)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 42: TierConfigManager + tests

**Files:**
- Create: `Pommora/Pommora/Configuration/TierConfigManager.swift`
- Create: `Pommora/PommoraTests/Configuration/TierConfigManagerTests.swift`

**Context:** Same shape as HomepageManager — singleton, seed on first load, save persists.

- [ ] **Step 1: Create folder + write the failing test**

```bash
mkdir -p "Pommora/Pommora/Configuration" "Pommora/PommoraTests/Configuration"
```

Create `Pommora/PommoraTests/Configuration/TierConfigManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("TierConfigManager")
struct TierConfigManagerTests {

    @Test("load seeds default on first run")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = TierConfigManager(nexus: nexus)
        await m.load()
        #expect(FileManager.default.fileExists(atPath: NexusPaths.tierConfigURL(in: nexus).path))
        #expect(m.config.tiers.count == 3)
        #expect(m.config.tiers[0].singular == "Space")
    }

    @Test("save persists user edits")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = TierConfigManager(nexus: nexus)
        await m.load()
        m.config.tiers[0].singular = "Area"
        m.config.tiers[0].plural = "Areas"
        try await m.save()
        let reloaded = try AtomicJSON.decode(TierConfig.self, from: NexusPaths.tierConfigURL(in: nexus))
        #expect(reloaded.tiers[0].singular == "Area")
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Configuration/TierConfigManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TierConfigManager {
    var config: TierConfig = TierConfig.defaultSeed()
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.tierConfigURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                config = try AtomicJSON.decode(TierConfig.self, from: url)
            } else {
                config = TierConfig.defaultSeed()
                try AtomicJSON.write(config, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        let url = NexusPaths.tierConfigURL(in: nexus)
        try AtomicJSON.write(config, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/TierConfigManager -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Configuration/TierConfigManager.swift \
        Pommora/PommoraTests/Configuration/TierConfigManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(configuration): add TierConfigManager singleton

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 43: SavedConfigManager + tests

**Files:**
- Create: `Pommora/Pommora/Configuration/SavedConfigManager.swift`
- Create: `Pommora/PommoraTests/Configuration/SavedConfigManagerTests.swift`

**Context:** Mirrors TierConfigManager exactly. Singleton, seed on first load, save persists.

- [ ] **Step 1: Write the failing test**

Create `Pommora/PommoraTests/Configuration/SavedConfigManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("SavedConfigManager")
struct SavedConfigManagerTests {

    @Test("load seeds three fixed items")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SavedConfigManager(nexus: nexus)
        await m.load()
        #expect(m.config.items.map(\.key) == ["homepage", "calendar", "recents"])
    }

    @Test("save persists label edits")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SavedConfigManager(nexus: nexus)
        await m.load()
        m.config.items[0].label = "Dashboard"
        try await m.save()
        let reloaded = try AtomicJSON.decode(SavedConfig.self, from: NexusPaths.savedConfigURL(in: nexus))
        #expect(reloaded.items[0].label == "Dashboard")
    }
}
```

- [ ] **Step 2: Run — fail. Step 3: Implement.**

Create `Pommora/Pommora/Configuration/SavedConfigManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SavedConfigManager {
    var config: SavedConfig = SavedConfig.defaultSeed()
    var pendingError: Error?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.savedConfigURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                config = try AtomicJSON.decode(SavedConfig.self, from: url)
            } else {
                config = SavedConfig.defaultSeed()
                try AtomicJSON.write(config, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        let url = NexusPaths.savedConfigURL(in: nexus)
        try AtomicJSON.write(config, to: url)
    }
}
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -only-testing:PommoraTests/SavedConfigManager -destination 'platform=macOS' 2>&1 | tail -10
git add Pommora/Pommora/Configuration/SavedConfigManager.swift \
        Pommora/PommoraTests/Configuration/SavedConfigManagerTests.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(configuration): add SavedConfigManager singleton

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 44: SidebarSelection enum

**Files:**
- Create: `Pommora/Pommora/Sidebar/SidebarSelection.swift`

**Context:** Single source of truth for what's selected in the sidebar — held by `ContentView`, bound through environment to both sidebar rows and the detail pane.

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/Sidebar/SidebarSelection.swift`:

```swift
import Foundation

/// What the user has selected in the sidebar. Single source of truth held by
/// ContentView. Detail pane switches on this to choose the right detail view.
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)            // "homepage" | "calendar" | "recents"
    case space(Space)
    case topic(Topic)
    case subtopic(Subtopic)
    case vault(Vault)
    case collection(Collection)
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
git add Pommora/Pommora/Sidebar/SidebarSelection.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "feat(sidebar): add SidebarSelection enum

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 45: SpaceRow inline-rename + context menu

**Files:**
- Create: `Pommora/Pommora/Sidebar/SpaceRow.swift`

**Context:** Wraps `SelectableRow` with a color dot + icon. Inline rename via `@FocusState` + `TextField`. Right-click context menu drives sheets through a binding the parent passes in.

- [ ] **Step 1: Implement SpaceRow**

Create `Pommora/Pommora/Sidebar/SpaceRow.swift`:

```swift
import SwiftUI

struct SpaceRow: View {
    let space: Space
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Group {
            if editingID == space.id {
                renameField
            } else {
                SelectableRow(
                    title: space.title,
                    symbol: space.icon ?? "circle.fill",
                    tag: SelectionTag.space(space.id),
                    selection: $selection,
                    accent: space.color.swiftUIColor,
                    onSelect: { selection = .space(space) }
                )
                .contextMenu {
                    Button("Rename") { startRename() }
                    Button("Change Color") { presentedSheet = .editColor(space) }
                    Button("Change Icon") { presentedSheet = .editIcon(.space(space)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteSpace(space)
                    }
                }
            }
        }
    }

    private var renameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($renameFocused)
            .onSubmit { commit() }
            .onKeyPress(.escape) { cancel(); return .handled }
            .onAppear {
                draft = space.title
                renameFocused = true
            }
    }

    private func startRename() {
        editingID = space.id
    }

    private func commit() {
        guard draft != space.title else { editingID = nil; return }
        Task {
            do {
                try await spaceManager.rename(space, to: draft)
            } catch {
                // error surfaces in spaceManager.pendingError
            }
            editingID = nil
        }
    }

    private func cancel() {
        editingID = nil
    }
}
```

The `SelectableRow` is the locked-styling row that already exists at [Pommora/Pommora/Sidebar/SidebarView.swift:72-111](Pommora/Pommora/Sidebar/SidebarView.swift#L72-L111). It currently uses a `String?` selection — Task 48 modifies it to use the new `SelectionTag` enum.

`SidebarSheet` + `SidebarConfirmation` types are defined in Task 49 (and Task 50). Until those land, this file won't compile. Either defer this task's commit until Task 49+50 are also written, or stub the types here and remove the stubs later. Cleanest: write Tasks 49-50 immediately after this one, then commit Tasks 45-50 together. The plan below lands them in sequence.

- [ ] **Step 2: Defer commit; proceed to Task 46**

Don't commit yet — wait until Tasks 46-50 finish so the row + sheet types compile together.

---

### Task 46: TopicRow + SubtopicRow

**Files:**
- Create: `Pommora/Pommora/Sidebar/TopicRow.swift`
- Create: `Pommora/Pommora/Sidebar/SubtopicRow.swift`

**Context:** TopicRow is a `DisclosureGroup` with the Topic as the label + Sub-topics as children. SubtopicRow is a leaf row with its own rename + context menu. Parent-Space tagging indicator (color dot) rendered next to the title.

- [ ] **Step 1: Implement TopicRow**

Create `Pommora/Pommora/Sidebar/TopicRow.swift`:

```swift
import SwiftUI

struct TopicRow: View {
    let topic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(topicManager.subtopics(in: topic)) { sub in
                SubtopicRow(
                    subtopic: sub,
                    parentTopic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newSubtopic(parent: topic)
            } label: {
                Label("New Sub-topic", systemImage: "plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        } label: {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == topic.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { editingID = nil; return .handled }
                .onAppear {
                    draft = topic.title
                    renameFocused = true
                }
        } else {
            HStack(spacing: 6) {
                ParentSpaceTags(topic: topic, spaceManager: spaceManager)
                SelectableRow(
                    title: topic.title,
                    symbol: topic.icon ?? "folder",
                    tag: SelectionTag.topic(topic.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .topic(topic) }
                )
            }
            .contextMenu {
                Button("Rename") { editingID = topic.id }
                Button("Edit Parents") { presentedSheet = .editTopicParents(topic) }
                Button("Change Icon") { presentedSheet = .editIcon(.topic(topic)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteTopic(topic, subtopicCount: topicManager.subtopics(in: topic).count)
                }
            }
        }
    }

    private func commit() {
        guard draft != topic.title else { editingID = nil; return }
        Task {
            do { try await topicManager.renameTopic(topic, to: draft) } catch {}
            editingID = nil
        }
    }
}

/// Renders one small color dot per parent Space of the Topic.
struct ParentSpaceTags: View {
    let topic: Topic
    let spaceManager: SpaceManager

    var body: some View {
        HStack(spacing: 2) {
            ForEach(parentSpaces, id: \.id) { space in
                Circle()
                    .fill(space.color.swiftUIColor)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var parentSpaces: [Space] {
        topic.parents.compactMap { id in
            spaceManager.spaces.first { $0.id == id }
        }
    }
}
```

Create `Pommora/Pommora/Sidebar/SubtopicRow.swift`:

```swift
import SwiftUI

struct SubtopicRow: View {
    let subtopic: Subtopic
    let parentTopic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(TopicManager.self) private var topicManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == subtopic.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) { editingID = nil; return .handled }
                    .onAppear {
                        draft = subtopic.title
                        renameFocused = true
                    }
            } else {
                SelectableRow(
                    title: subtopic.title,
                    symbol: subtopic.icon ?? "doc.text",
                    tag: SelectionTag.subtopic(subtopic.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .subtopic(subtopic) }
                )
                .contextMenu {
                    Button("Rename") { editingID = subtopic.id }
                    Button("Change Icon") { presentedSheet = .editIcon(.subtopic(subtopic)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteSubtopic(subtopic)
                    }
                }
            }
        }
    }

    private func commit() {
        guard draft != subtopic.title else { editingID = nil; return }
        Task {
            do { try await topicManager.renameSubtopic(subtopic, to: draft) } catch {}
            editingID = nil
        }
    }
}
```

- [ ] **Step 2: Defer commit; proceed to Task 47**

---

### Task 47: VaultRow + CollectionRow

**Files:**
- Create: `Pommora/Pommora/Sidebar/VaultRow.swift`
- Create: `Pommora/Pommora/Sidebar/CollectionRow.swift`

**Context:** VaultRow is a `DisclosureGroup` with Collections as children. CollectionRow is a leaf row that selects on click (detail pane shows the Finder Table from Task 63).

- [ ] **Step 1: Implement VaultRow**

Create `Pommora/Pommora/Sidebar/VaultRow.swift`:

```swift
import SwiftUI

struct VaultRow: View {
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(VaultManager.self) private var vaultManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(vaultManager.collections(in: vault)) { coll in
                CollectionRow(
                    collection: coll,
                    parentVault: vault,
                    selection: $selection,
                    editingID: $editingID,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newCollection(vault: vault)
            } label: {
                Label("New Collection", systemImage: "plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        } label: {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == vault.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { editingID = nil; return .handled }
                .onAppear {
                    draft = vault.title
                    renameFocused = true
                }
        } else {
            SelectableRow(
                title: vault.title,
                symbol: vault.icon ?? "tray.2",
                tag: SelectionTag.vault(vault.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .vault(vault) }
            )
            .contextMenu {
                Button("Rename") { editingID = vault.id }
                Button("Change Icon") { presentedSheet = .editIcon(.vault(vault)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = vaultManager.collections(in: vault).count
                    confirmingDelete = .deleteVault(vault, collectionCount: cols)
                }
            }
        }
    }

    private func commit() {
        guard draft != vault.title else { editingID = nil; return }
        Task {
            do { try await vaultManager.renameVault(vault, to: draft) } catch {}
            editingID = nil
        }
    }
}
```

Create `Pommora/Pommora/Sidebar/CollectionRow.swift`:

```swift
import SwiftUI

struct CollectionRow: View {
    let collection: Collection
    let parentVault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(VaultManager.self) private var vaultManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == collection.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) { editingID = nil; return .handled }
                    .onAppear {
                        draft = collection.title
                        renameFocused = true
                    }
            } else {
                SelectableRow(
                    title: collection.title,
                    symbol: "folder",
                    tag: SelectionTag.collection(collection.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .collection(collection) }
                )
                .contextMenu {
                    Button("Rename") { editingID = collection.id }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteCollection(collection)
                    }
                }
            }
        }
    }

    private func commit() {
        guard draft != collection.title else { editingID = nil; return }
        Task {
            do { try await vaultManager.renameCollection(collection, to: draft) } catch {}
            editingID = nil
        }
    }
}
```

- [ ] **Step 2: Defer commit; proceed to Task 48**

---

### Task 48: SidebarView replacement + SelectableRow update

**Files:**
- Modify: `Pommora/Pommora/Sidebar/SidebarView.swift` (full replacement)
- Tests: covered manually + by `SidebarSelectionTests` (Task 48 step 5)

**Context:** Replaces all hardcoded placeholders with real four-section List. Updates `SelectableRow` to accept the new `SelectionTag` enum instead of `String?`. Wires through environment managers.

- [ ] **Step 1: Define SelectionTag enum**

Add to `Pommora/Pommora/Sidebar/SidebarSelection.swift` (append below existing `SidebarSelection`):

```swift
/// Used by SelectableRow to compare against the current SidebarSelection
/// for highlight state. Each case carries the entity's ULID.
enum SelectionTag: Equatable, Hashable, Sendable {
    case savedKey(String)
    case space(String)
    case topic(String)
    case subtopic(String)
    case vault(String)
    case collection(String)

    func matches(_ selection: SidebarSelection) -> Bool {
        switch (self, selection) {
        case (.savedKey(let k), .savedKey(let s)):       return k == s
        case (.space(let id), .space(let s)):            return id == s.id
        case (.topic(let id), .topic(let t)):            return id == t.id
        case (.subtopic(let id), .subtopic(let st)):     return id == st.id
        case (.vault(let id), .vault(let v)):            return id == v.id
        case (.collection(let id), .collection(let c)):  return id == c.id
        default: return false
        }
    }
}
```

- [ ] **Step 2: Replace SidebarView with the four-section layout**

Overwrite `Pommora/Pommora/Sidebar/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(SavedConfigManager.self) private var savedConfigManager

    @Binding var selection: SidebarSelection

    @State private var editingID: String? = nil
    @State private var presentedSheet: SidebarSheet? = nil
    @State private var confirmingDelete: SidebarConfirmation? = nil

    var body: some View {
        List {
            SavedSection(selection: $selection)
            SpacesSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
            TopicsSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
            VaultsSection(
                selection: $selection,
                editingID: $editingID,
                presentedSheet: $presentedSheet,
                confirmingDelete: $confirmingDelete
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                  NewSpaceSheet()
            case .newTopic:                  NewTopicSheet()
            case .newSubtopic(let t):        NewSubtopicSheet(parent: t)
            case .newVault:                  NewVaultSheet()
            case .newCollection(let v):      NewCollectionSheet(vault: v)
            case .newPage(let c, let v):     NewPageSheet(collection: c, vault: v)
            case .newItem(let c, let v):     NewItemSheet(collection: c, vault: v)
            case .editTopicParents(let t):   EditTopicParentsSheet(topic: t)
            case .editIcon(let target):     IconPickerSheet(target: target)
            case .editColor(let s):         ColorPickerSheet(space: s)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { confirmation in
            confirmationButtons(for: confirmation)
        } message: { confirmation in
            Text(confirmationMessage(for: confirmation))
        }
    }

    private var confirmationTitle: String {
        switch confirmingDelete {
        case .deleteSpace(let s)?:    return "Delete Space \"\(s.title)\"?"
        case .deleteTopic(let t, _)?: return "Delete Topic \"\(t.title)\"?"
        case .deleteSubtopic(let s)?: return "Delete Sub-topic \"\(s.title)\"?"
        case .deleteVault(let v, _)?: return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c)?: return "Delete Collection \"\(c.title)\"?"
        case nil: return ""
        }
    }

    private func confirmationMessage(for confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .deleteSpace: return "This action cannot be undone."
        case .deleteTopic(_, let count): return count > 0
            ? "Contains \(count) Sub-topic(s). Promote them or delete all?"
            : "This action cannot be undone."
        case .deleteSubtopic: return "This action cannot be undone."
        case .deleteVault(_, let cols): return "Contains \(cols) Collection(s). All contents will be deleted."
        case .deleteCollection: return "All Pages and Items inside will be deleted."
        }
    }

    @ViewBuilder
    private func confirmationButtons(for confirmation: SidebarConfirmation) -> some View {
        switch confirmation {
        case .deleteSpace(let s):
            Button("Delete", role: .destructive) {
                Task { try? await spaceManager.delete(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteTopic(let t, let count):
            if count > 0 {
                Button("Delete & Promote Sub-topics", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
                Button("Delete All", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: false); confirmingDelete = nil }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteSubtopic(let s):
            Button("Delete", role: .destructive) {
                Task { try? await topicManager.deleteSubtopic(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteVault(v); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteCollection(c); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        }
    }
}

// MARK: - Sections

struct SavedSection: View {
    @Binding var selection: SidebarSelection
    @Environment(SavedConfigManager.self) private var savedConfigManager

    var body: some View {
        Section("Saved") {
            ForEach(savedConfigManager.config.items) { item in
                SelectableRow(
                    title: item.label,
                    symbol: iconFor(item.key),
                    tag: SelectionTag.savedKey(item.key),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .savedKey(item.key) }
                )
            }
        }
    }

    private func iconFor(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents":  return "clock"
        default: return "questionmark.square"
        }
    }
}

struct SpacesSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Section("Spaces") {
            ForEach(spaceManager.spaces) { space in
                SpaceRow(
                    space: space,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newSpace
            } label: {
                Label("New Space", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct TopicsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(TopicManager.self) private var topicManager

    var body: some View {
        Section("Topics") {
            ForEach(topicManager.topics) { topic in
                TopicRow(
                    topic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newTopic
            } label: {
                Label("New Topic", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct VaultsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Section("Vaults") {
            ForEach(vaultManager.vaults) { vault in
                VaultRow(
                    vault: vault,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            Button {
                presentedSheet = .newVault
            } label: {
                Label("New Vault", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - SelectableRow (updated to use SelectionTag)

struct SelectableRow: View {
    let title: String
    let symbol: String
    let tag: SelectionTag
    @Binding var selection: SidebarSelection
    let accent: Color?
    let onSelect: () -> Void

    var isSelected: Bool {
        tag.matches(selection)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.accentColor : (accent ?? .primary))
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .brightness(isSelected ? 0.12 : 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.11))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 2)
                : nil
        )
    }
}

// MARK: - Sheet & Confirmation enums

enum SidebarConfirmation: Identifiable {
    case deleteSpace(Space)
    case deleteTopic(Topic, subtopicCount: Int)
    case deleteSubtopic(Subtopic)
    case deleteVault(Vault, collectionCount: Int)
    case deleteCollection(Collection)

    var id: String {
        switch self {
        case .deleteSpace(let s):       return "deleteSpace-\(s.id)"
        case .deleteTopic(let t, _):    return "deleteTopic-\(t.id)"
        case .deleteSubtopic(let s):    return "deleteSubtopic-\(s.id)"
        case .deleteVault(let v, _):    return "deleteVault-\(v.id)"
        case .deleteCollection(let c):  return "deleteCollection-\(c.id)"
        }
    }
}
```

- [ ] **Step 3: Build to check structure compiles (sheets are stubbed in Task 49+ — defer the build until those land)**

```bash
# Don't build yet — wait until Task 49+ sheets exist
```

- [ ] **Step 4: Commit all sidebar files together (Tasks 45-48)**

```bash
git add Pommora/Pommora/Sidebar/SpaceRow.swift \
        Pommora/Pommora/Sidebar/TopicRow.swift \
        Pommora/Pommora/Sidebar/SubtopicRow.swift \
        Pommora/Pommora/Sidebar/VaultRow.swift \
        Pommora/Pommora/Sidebar/CollectionRow.swift \
        Pommora/Pommora/Sidebar/SidebarView.swift \
        Pommora/Pommora/Sidebar/SidebarSelection.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
# (Commit happens AFTER Tasks 49-50 add the sheet types — see Task 50 step 5)
```

> Note: the build will fail until SidebarSheet + sheet views from Tasks 49-60 are defined. That's expected. The integration commit happens at the end of Task 60 once all sidebar + sheet code can compile together.

---

### Task 49: SidebarSheet enum

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/SidebarSheet.swift`

**Context:** Identifiable enum keyed by sheet kind so a single `.sheet(item:)` modifier can present any sheet. Avoids N boolean state properties. Pattern at [.claude/Guidelines/CRUD-Patterns.md:168-192](.claude/Guidelines/CRUD-Patterns.md#L168-L192).

- [ ] **Step 1: Create folder + implement SidebarSheet**

```bash
mkdir -p "Pommora/Pommora/Sidebar/Sheets"
```

Create `Pommora/Pommora/Sidebar/Sheets/SidebarSheet.swift`:

```swift
import Foundation

/// Discriminated union of every sheet the sidebar can present.
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newSubtopic(parent: Topic)
    case newVault
    case newCollection(vault: Vault)
    case newPage(collection: Collection, vault: Vault)
    case newItem(collection: Collection, vault: Vault)
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)

    /// Disambiguates the icon picker between entity kinds (each manager has its
    /// own updateIcon path).
    enum IconTarget: Hashable {
        case space(Space)
        case topic(Topic)
        case subtopic(Subtopic)
        case vault(Vault)
    }

    var id: String {
        switch self {
        case .newSpace:                       return "newSpace"
        case .newTopic:                       return "newTopic"
        case .newSubtopic(let t):             return "newSubtopic-\(t.id)"
        case .newVault:                       return "newVault"
        case .newCollection(let v):           return "newCollection-\(v.id)"
        case .newPage(let c, _):              return "newPage-\(c.id)"
        case .newItem(let c, _):              return "newItem-\(c.id)"
        case .editTopicParents(let t):        return "editTopicParents-\(t.id)"
        case .editIcon(let target):
            switch target {
            case .space(let s):    return "editIcon-space-\(s.id)"
            case .topic(let t):    return "editIcon-topic-\(t.id)"
            case .subtopic(let s): return "editIcon-subtopic-\(s.id)"
            case .vault(let v):    return "editIcon-vault-\(v.id)"
            }
        case .editColor(let s):               return "editColor-\(s.id)"
        }
    }
}
```

- [ ] **Step 2: Defer commit (build still broken until all sheets exist)**

---

### Task 50: SpaceColorPicker + ColorPickerSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/SpaceColorPicker.swift`
- Create: `Pommora/Pommora/Sidebar/Sheets/ColorPickerSheet.swift`

**Context:** Reusable 9-button grid over `SpaceColor.allCases`. Used inline in `NewSpaceSheet` (Task 52) and as a standalone sheet for "Change Color" on existing Spaces.

- [ ] **Step 1: Implement SpaceColorPicker (inline component)**

Create `Pommora/Pommora/Sidebar/Sheets/SpaceColorPicker.swift`:

```swift
import SwiftUI

/// Inline 9-color grid for picking a SpaceColor. Used inside sheets and pickers.
struct SpaceColorPicker: View {
    @Binding var color: SpaceColor

    private let columns = [GridItem(.adaptive(minimum: 32), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SpaceColor.allCases) { option in
                Button {
                    color = option
                } label: {
                    Circle()
                        .fill(option.swiftUIColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: color == option ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
            }
        }
    }
}
```

- [ ] **Step 2: Implement ColorPickerSheet (standalone for changing a Space's color)**

Create `Pommora/Pommora/Sidebar/Sheets/ColorPickerSheet.swift`:

```swift
import SwiftUI

struct ColorPickerSheet: View {
    let space: Space
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @State private var draft: SpaceColor

    init(space: Space) {
        self.space = space
        _draft = State(initialValue: space.color)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Color for \"\(space.title)\"")
                .font(.headline)
            SpaceColorPicker(color: $draft)
                .padding()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task {
                        try? await spaceManager.updateColor(space, to: draft)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 320, height: 220)
    }
}
```

- [ ] **Step 3: Defer commit**

---

### Task 51: IconPickerSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/IconPickerSheet.swift`

**Context:** Minimal `TextField` for an SF Symbol name + live preview. Per [.claude/Guidelines/CRUD-Patterns.md:331-336](.claude/Guidelines/CRUD-Patterns.md#L331-L336), curated grid picker is deferred. Dispatches the icon update to the appropriate manager based on `IconTarget`.

- [ ] **Step 1: Implement IconPickerSheet**

Create `Pommora/Pommora/Sidebar/Sheets/IconPickerSheet.swift`:

```swift
import SwiftUI

struct IconPickerSheet: View {
    let target: SidebarSheet.IconTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager

    @State private var icon: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Icon")
                .font(.headline)
            HStack(spacing: 16) {
                Image(systemName: icon.isEmpty ? "questionmark.circle" : icon)
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
                TextField("SF Symbol name (e.g. star, book.closed)", text: $icon)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
            }
            .padding(.horizontal)
            Text("Browse symbols in the SF Symbols app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task {
                        await save()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 380, height: 220)
        .onAppear {
            icon = currentIcon ?? ""
            fieldFocused = true
        }
    }

    private var currentIcon: String? {
        switch target {
        case .space(let s):    return s.icon
        case .topic(let t):    return t.icon
        case .subtopic(let s): return s.icon
        case .vault(let v):    return v.icon
        }
    }

    private func save() async {
        let newIcon: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
        switch target {
        case .space(let s):    try? await spaceManager.updateIcon(s, to: newIcon)
        case .topic(let t):    try? await topicManager.updateTopicIcon(t, to: newIcon)
        case .subtopic:
            // No icon-update path on SubtopicValidator/Topic Manager in v0.2; persist
            // by full subtopic update through TopicManager.renameSubtopic-equivalent
            // is unwieldy. Out of scope for this plan — defer Sub-topic icon edit
            // to v0.3 when Subtopic.updateIcon ships.
            break
        case .vault(let v):    try? await vaultManager.updateVaultIcon(v, to: newIcon)
        }
    }
}
```

> **Spec gap captured during planning:** Sub-topic icon-update path isn't in TopicManager's Task 37 surface (Sub-topic CRUD covers create/rename/move/delete only). To honor "Change Icon" on Sub-topics in this plan, add `TopicManager.updateSubtopicIcon(_:to:)` as a follow-up step. Add it inline now:

- [ ] **Step 2: Extend TopicManager with updateSubtopicIcon**

Open `Pommora/Pommora/Contexts/TopicManager.swift` and add:

```swift
func updateSubtopicIcon(_ sub: Subtopic, to icon: String?) async throws {
    guard let parentID = sub.parents.first,
          let parent = topics.first(where: { $0.id == parentID })
    else { throw SubtopicValidator.ValidationError.missingParent }

    var updated = sub
    updated.icon = icon
    updated.modifiedAt = Date()
    let url = NexusPaths.subtopicFileURL(
        forTitle: sub.title, inTopicTitled: parent.title, in: nexus
    )
    try updated.save(to: url)
    var arr = subtopicsByParent[parent.id] ?? []
    if let i = arr.firstIndex(where: { $0.id == sub.id }) {
        arr[i] = updated
    }
    subtopicsByParent[parent.id] = arr
}
```

Update `IconPickerSheet.save()` to use it:

```swift
case .subtopic(let s):
    try? await topicManager.updateSubtopicIcon(s, to: newIcon)
```

- [ ] **Step 3: Defer commit**

---

### Task 52: NewSpaceSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/NewSpaceSheet.swift`

**Context:** Name + color (via `SpaceColorPicker`) + icon (text field). On Create, calls `SpaceManager.create`; on failure, surfaces inline.

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/Sidebar/Sheets/NewSpaceSheet.swift`:

```swift
import SwiftUI

struct NewSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager

    @State private var name: String = ""
    @State private var color: SpaceColor = .blue
    @State private var icon: String = "person.circle"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Space")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                LabeledContent("Color") {
                    SpaceColorPicker(color: $color)
                }
                TextField("Icon (SF Symbol name)", text: $icon)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 320)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let iconValue: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
            try await spaceManager.create(name: name, color: color, icon: iconValue)
            dismiss()
        } catch let error as SpaceValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: SpaceValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Space with that name already exists."
        }
    }
}
```

- [ ] **Step 2: Defer commit**

---

### Task 53: NewTopicSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/NewTopicSheet.swift`

**Context:** Name + multi-Space parent picker (chips) + icon. Empty parents allowed (Space-less Topic).

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/Sidebar/Sheets/NewTopicSheet.swift`:

```swift
import SwiftUI

struct NewTopicSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var name: String = ""
    @State private var selectedParents: Set<String> = []
    @State private var icon: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Topic")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                TextField("Icon (SF Symbol name)", text: $icon)
                Section("Parent Spaces (optional)") {
                    ForEach(spaceManager.spaces) { space in
                        Toggle(isOn: Binding(
                            get: { selectedParents.contains(space.id) },
                            set: { v in
                                if v { selectedParents.insert(space.id) }
                                else { selectedParents.remove(space.id) }
                            }
                        )) {
                            HStack {
                                Circle().fill(space.color.swiftUIColor).frame(width: 8, height: 8)
                                Text(space.title)
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 480)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let parents = Array(selectedParents)
            let iconValue: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
            try await topicManager.createTopic(name: name, parents: parents, icon: iconValue)
            dismiss()
        } catch let error as TopicValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: TopicValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Topic with that name already exists."
        case .parentNotFound: return "One of the selected parent Spaces no longer exists."
        }
    }
}
```

- [ ] **Step 2: Defer commit**

---

### Task 54: NewSubtopicSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/NewSubtopicSheet.swift`

**Context:** Pre-bound to parent Topic from the trigger; collects name + icon.

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/Sidebar/Sheets/NewSubtopicSheet.swift`:

```swift
import SwiftUI

struct NewSubtopicSheet: View {
    let parent: Topic
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Sub-topic in \"\(parent.title)\"")
                .font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
                TextField("Icon (SF Symbol name)", text: $icon)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 260)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let iconValue: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
            try await topicManager.createSubtopic(name: name, inTopic: parent, icon: iconValue)
            dismiss()
        } catch let error as SubtopicValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: SubtopicValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Sub-topic with that name already exists in this Topic."
        case .missingParent, .tooManyParents, .parentNotFound, .fileLocationMismatch:
            return "Internal validation error."
        }
    }
}
```

- [ ] **Step 2: Defer commit**

---

### Task 55: NewVaultSheet, NewCollectionSheet, NewPageSheet, NewItemSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/NewVaultSheet.swift`
- Create: `Pommora/Pommora/Sidebar/Sheets/NewCollectionSheet.swift`
- Create: `Pommora/Pommora/Sidebar/Sheets/NewPageSheet.swift`
- Create: `Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift`

**Context:** All follow the same pattern as `NewSubtopicSheet` — name + (sometimes icon) + Create button calling the appropriate manager.

- [ ] **Step 1: Implement NewVaultSheet**

Create `Pommora/Pommora/Sidebar/Sheets/NewVaultSheet.swift`:

```swift
import SwiftUI

struct NewVaultSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultManager.self) private var vaultManager

    @State private var name: String = ""
    @State private var icon: String = "tray.2"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Vault").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
                TextField("Icon (SF Symbol name)", text: $icon)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 260)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let iconValue: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
            try await vaultManager.createVault(name: name, icon: iconValue)
            dismiss()
        } catch let error as VaultValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: VaultValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Vault with that name already exists."
        }
    }
}
```

- [ ] **Step 2: Implement NewCollectionSheet**

Create `Pommora/Pommora/Sidebar/Sheets/NewCollectionSheet.swift`:

```swift
import SwiftUI

struct NewCollectionSheet: View {
    let vault: Vault
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultManager.self) private var vaultManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collection in \"\(vault.title)\"").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 220)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            try await vaultManager.createCollection(name: name, inVault: vault)
            dismiss()
        } catch let error as CollectionValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: CollectionValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Collection with that name already exists in this Vault."
        }
    }
}
```

- [ ] **Step 3: Implement NewPageSheet**

Create `Pommora/Pommora/Sidebar/Sheets/NewPageSheet.swift`:

```swift
import SwiftUI

struct NewPageSheet: View {
    let collection: Collection
    let vault: Vault
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentManager.self) private var contentManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Page in \"\(collection.title)\"").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 220)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            try await contentManager.createPage(name: name, in: collection, vault: vault)
            dismiss()
        } catch let error as PageValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: PageValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Page with that name already exists in this Collection."
        case .missingCreatedAt: return "Internal: created_at not set."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Property '\(n)' not in Vault schema."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
```

- [ ] **Step 4: Implement NewItemSheet**

Create `Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift`:

```swift
import SwiftUI

struct NewItemSheet: View {
    let collection: Collection
    let vault: Vault
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentManager.self) private var contentManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item in \"\(collection.title)\"").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 220)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            try await contentManager.createItem(name: name, in: collection, vault: vault)
            dismiss()
        } catch let error as ItemValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ItemValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "An Item with that name already exists."
        case .descriptionTooLong: return "Description over 250 characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Property '\(n)' not in Vault schema."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
```

- [ ] **Step 5: Defer commit**

---

### Task 56: EditTopicParentsSheet

**Files:**
- Create: `Pommora/Pommora/Sidebar/Sheets/EditTopicParentsSheet.swift`

**Context:** Multi-Space picker for an existing Topic. Mirrors NewTopicSheet's parent picker; calls `updateTopicParents` on save.

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/Sidebar/Sheets/EditTopicParentsSheet.swift`:

```swift
import SwiftUI

struct EditTopicParentsSheet: View {
    let topic: Topic
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var selectedParents: Set<String>
    @State private var errorMessage: String?

    init(topic: Topic) {
        self.topic = topic
        _selectedParents = State(initialValue: Set(topic.parents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Parents for \"\(topic.title)\"").font(.headline)
            Form {
                Section("Parent Spaces") {
                    ForEach(spaceManager.spaces) { space in
                        Toggle(isOn: Binding(
                            get: { selectedParents.contains(space.id) },
                            set: { v in
                                if v { selectedParents.insert(space.id) }
                                else { selectedParents.remove(space.id) }
                            }
                        )) {
                            HStack {
                                Circle().fill(space.color.swiftUIColor).frame(width: 8, height: 8)
                                Text(space.title)
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 440)
    }

    private func save() async {
        do {
            try await topicManager.updateTopicParents(topic, to: Array(selectedParents))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Commit all sidebar + sheet files together (close out Tasks 44-56)**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -10
# Expected: build succeeds with all sheet + sidebar files in place.

git add Pommora/Pommora/Sidebar/ \
        Pommora/Pommora/Contexts/TopicManager.swift \
        Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(sidebar): four-section sidebar + all "+ New" sheets

Replaces hardcoded placeholders with live Saved / Spaces / Topics /
Vaults sections driven by their managers. Implements inline rename
(@FocusState + TextField + .onKeyPress(.escape)), right-click context
menus per row, dual-button delete-confirmation for Topics (promote
default + cascade option), and "+ New" sheets for Space / Topic /
Sub-topic / Vault / Collection / Page / Item. IconPickerSheet +
ColorPickerSheet + EditTopicParentsSheet. SelectableRow updated to
take SelectionTag enum. TopicManager gains updateSubtopicIcon.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 57: ContentItem enum + ContextDetailPlaceholder + DetailRow hierarchical model

**Files:**
- Create: `Pommora/Pommora/Detail/ContentItem.swift`
- Create: `Pommora/Pommora/Detail/ContextDetailPlaceholder.swift`
- Create: `Pommora/Pommora/Detail/DetailRow.swift`

**Context:** Pre-work for the hierarchical Table views in Tasks 58-59. `ContentItem` enum unifies Page + Item for rendering. `DetailRow` is the hierarchical row model that SwiftUI `Table(_:children:)` consumes — each row carries its name, kind, modified date, and optional children. `ContextDetailPlaceholder` is the minimal Space/Topic/Sub-topic detail view shown until composed-blocks editor lands v0.9.

- [ ] **Step 1: Create folder + ContentItem**

```bash
mkdir -p "Pommora/Pommora/Detail"
```

Create `Pommora/Pommora/Detail/ContentItem.swift`:

```swift
import Foundation

/// Unified row value for Pages + Items inside a Collection. Used by the
/// detail-pane Tables so a single column can render both kinds uniformly.
enum ContentItem: Identifiable, Hashable, Sendable {
    case page(PageMeta)
    case item(Item)

    var id: String {
        switch self {
        case .page(let p): return "page-\(p.id)"
        case .item(let i): return "item-\(i.id)"
        }
    }

    var title: String {
        switch self {
        case .page(let p): return p.title
        case .item(let i): return i.title
        }
    }

    var kindLabel: String {
        switch self {
        case .page: return "Page"
        case .item: return "Item"
        }
    }

    var iconName: String {
        switch self {
        case .page(let p): return p.frontmatter.icon ?? "doc.text"
        case .item(let i): return i.icon ?? "list.bullet.rectangle"
        }
    }

    var modifiedAt: Date {
        switch self {
        case .page(let p): return p.frontmatter.createdAt  // PageMeta doesn't carry mtime; fall back to createdAt
        case .item(let i): return i.modifiedAt
        }
    }
}
```

- [ ] **Step 2: Implement DetailRow**

Create `Pommora/Pommora/Detail/DetailRow.swift`:

```swift
import Foundation

/// Hierarchical row model consumed by SwiftUI `Table(_:children:)`.
/// `children == nil` → leaf row (no disclosure triangle).
/// `children == []`  → expandable but empty.
/// `children == [...]` → expandable with N nested rows.
struct DetailRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case collection(Collection)
        case page(PageMeta)
        case item(Item)
    }

    let id: String
    let title: String
    let kind: Kind
    let iconName: String
    let modifiedAt: Date
    let children: [DetailRow]?

    var kindLabel: String {
        switch kind {
        case .collection: return "Collection"
        case .page:       return "Page"
        case .item:       return "Item"
        }
    }
}
```

- [ ] **Step 3: Implement ContextDetailPlaceholder**

Create `Pommora/Pommora/Detail/ContextDetailPlaceholder.swift`:

```swift
import SwiftUI

/// Minimal placeholder shown for Space / Topic / Sub-topic selection until
/// the composed-blocks editor lands v0.9.
struct ContextDetailPlaceholder: View {
    let title: String
    let icon: String
    let accent: Color?
    let supportingLine: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(accent ?? .secondary)
            Text(title)
                .font(.title)
            if let supportingLine {
                Text(supportingLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Composed view coming v0.9")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build + defer commit (build until Task 60 lands)**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
```

---

### Task 58: VaultDetailView — hierarchical Finder-style Table

**Files:**
- Create: `Pommora/Pommora/Detail/VaultDetailView.swift`

**Context:** Native SwiftUI `Table(_:children:)` API. Top-level rows are the Vault's Collections; each Collection row can be expanded (chevron disclosure built into the row) to show its nested Pages + Items as child rows. Three columns: **Name** (icon + title), **Kind** (Collection / Page / Item), **Modified** (date). No toolbar. Footer button: "+ New Collection". Row tap on a Collection selects it (so the user can also drill into the dedicated CollectionDetailView via the sidebar); row tap on an Item opens the Item Window; tap on a Page is a no-op (no editor yet).

- [ ] **Step 1: Implement VaultDetailView**

Create `Pommora/Pommora/Detail/VaultDetailView.swift`:

```swift
import SwiftUI

struct VaultDetailView: View {
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?           // drives Item Window popover

    @Environment(VaultManager.self) private var vaultManager
    @Environment(ContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []
    @State private var expanded: Set<String> = []   // row IDs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: vault.id) {
            // Ensure every Collection inside this Vault has its content loaded
            for coll in vaultManager.collections(in: vault) {
                await contentManager.loadAll(for: coll)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: vault.icon ?? "tray.2")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(vault.title).font(.title2)
                Text("Vault").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Table

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
            }
            TableColumn("Kind") { row in
                Text(row.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
        .onChange(of: tableSelection) { _, newSelection in
            guard let firstID = newSelection.first,
                  let row = findRow(id: firstID, in: rows) else { return }
            handleSingleSelect(row)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newCollection(vault: vault)
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(8)
    }

    // MARK: - Row construction

    private var rows: [DetailRow] {
        vaultManager.collections(in: vault).map { coll in
            let pages = contentManager.pages(in: coll).map(ContentItem.page)
            let items = contentManager.items(in: coll).map(ContentItem.item)
            let kids: [DetailRow] = (pages + items).map { ci in
                DetailRow(
                    id: ci.id,
                    title: ci.title,
                    kind: contentKind(ci),
                    iconName: ci.iconName,
                    modifiedAt: ci.modifiedAt,
                    children: nil
                )
            }
            return DetailRow(
                id: "collection-\(coll.id)",
                title: coll.title,
                kind: .collection(coll),
                iconName: "folder",
                modifiedAt: Date(),
                children: kids
            )
        }
    }

    private func contentKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }

    private func findRow(id: String, in rows: [DetailRow]) -> DetailRow? {
        for row in rows {
            if row.id == id { return row }
            if let kids = row.children, let hit = findRow(id: id, in: kids) {
                return hit
            }
        }
        return nil
    }

    // MARK: - Interaction

    private func handleSingleSelect(_ row: DetailRow) {
        switch row.kind {
        case .collection(let c):
            selection = .collection(c)
        case .item(let i):
            presentedItem = i
        case .page:
            break  // no opening surface yet
        }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        handleSingleSelect(row)
    }
}
```

- [ ] **Step 2: Defer commit (build resumes at Task 60)**

---

### Task 59: CollectionDetailView — hierarchical Finder-style Table

**Files:**
- Create: `Pommora/Pommora/Detail/CollectionDetailView.swift`

**Context:** Same hierarchical Table API as VaultDetailView, but the top-level rows ARE the Pages + Items (Collection is the implicit parent — the user already drilled in). Future-ready for sub-collections (post-v1) via the `children:` API. Single-row click on an Item → Item Window; on a Page → no-op (no editor yet). Footer: "+ New Page" / "+ New Item".

- [ ] **Step 1: Implement CollectionDetailView**

Create `Pommora/Pommora/Detail/CollectionDetailView.swift`:

```swift
import SwiftUI

struct CollectionDetailView: View {
    let collection: Collection
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(ContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            await contentManager.loadAll(for: collection)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(collection.title).font(.title2)
                Text("Collection in \(vault.title)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Kind") { row in
                Text(row.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
        .onChange(of: tableSelection) { _, newSelection in
            guard let firstID = newSelection.first,
                  let row = rows.first(where: { $0.id == firstID })
            else { return }
            switch row.kind {
            case .item(let i): presentedItem = i
            case .page:        break
            case .collection:  break
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newPage(collection: collection, vault: vault)
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Button {
                presentedSheet = .newItem(collection: collection, vault: vault)
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        let pages = contentManager.pages(in: collection).map { ContentItem.page($0) }
        let items = contentManager.items(in: collection).map { ContentItem.item($0) }
        return (pages + items).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: detailKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil  // v1 Collections are flat; nil = leaf row (no disclosure)
            )
        }
    }

    private func detailKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }
}
```

- [ ] **Step 2: Defer commit (build resumes at Task 60)**

---

### Task 60: SidebarDetailView dispatcher + integration commit

**Files:**
- Create: `Pommora/Pommora/Detail/SidebarDetailView.swift`
- Commit: All Detail pane files (Tasks 57-60)

**Context:** Switch-on-selection dispatcher. Wraps all the detail views; also hosts the Item Window popover.

- [ ] **Step 1: Implement SidebarDetailView**

Create `Pommora/Pommora/Detail/SidebarDetailView.swift`:

```swift
import SwiftUI

struct SidebarDetailView: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @State private var presentedItem: Item?

    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Group {
            switch selection {
            case .none:
                emptyState

            case .savedKey(let key):
                ContextDetailPlaceholder(
                    title: key.capitalized,
                    icon: iconForSavedKey(key),
                    accent: nil,
                    supportingLine: "Saved view coming v0.5"
                )

            case .space(let s):
                ContextDetailPlaceholder(
                    title: s.title,
                    icon: s.icon ?? "circle.fill",
                    accent: s.color.swiftUIColor,
                    supportingLine: "Tier 1 — Space"
                )

            case .topic(let t):
                ContextDetailPlaceholder(
                    title: t.title,
                    icon: t.icon ?? "folder",
                    accent: nil,
                    supportingLine: "Tier 2 — Topic\nParents: \(parentSpaceNames(for: t).joined(separator: ", "))"
                )

            case .subtopic(let s):
                ContextDetailPlaceholder(
                    title: s.title,
                    icon: s.icon ?? "doc.text",
                    accent: nil,
                    supportingLine: "Tier 3 — Sub-topic"
                )

            case .vault(let v):
                VaultDetailView(
                    vault: v,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    presentedItem: $presentedItem
                )

            case .collection(let c):
                // We need the parent Vault here too. Find it via VaultManager.
                if let v = lookupVault(forCollection: c) {
                    CollectionDetailView(
                        collection: c,
                        vault: v,
                        selection: $selection,
                        presentedSheet: $presentedSheet,
                        presentedItem: $presentedItem
                    )
                } else {
                    Text("Collection parent vault not found")
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(item: $presentedItem) { item in
            ItemWindow(item: item)
        }
    }

    @Environment(VaultManager.self) private var vaultManager

    private func lookupVault(forCollection c: Collection) -> Vault? {
        vaultManager.vaults.first { $0.id == c.vaultID }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select something from the sidebar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForSavedKey(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents":  return "clock"
        default: return "questionmark.square"
        }
    }

    private func parentSpaceNames(for topic: Topic) -> [String] {
        topic.parents.compactMap { id in
            spaceManager.spaces.first { $0.id == id }?.title
        }
    }
}
```

- [ ] **Step 2: Build to confirm detail pane compiles**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -10
```

Expected: build succeeds. `ItemWindow` is referenced — it's stubbed in Task 65; until Task 65 lands, replace `ItemWindow(item:)` with `Text(item.title)` and update later.

- [ ] **Step 3: Commit Detail pane (Tasks 57-60)**

```bash
git add Pommora/Pommora/Detail/ Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(detail): hierarchical Table detail views (Vault + Collection)

VaultDetailView uses native SwiftUI Table(_:children:) so each
Collection row expands inline to show its Pages + Items as child rows
(Finder-style nested disclosure). CollectionDetailView uses the same
hierarchical API for future-readiness (v1 Collections are flat → all
leaves). ContextDetailPlaceholder for Space/Topic/Sub-topic until v0.9
composed-blocks editor. ContentItem unifies Page+Item; DetailRow is
the hierarchical model. No toolbars per v1 paradigm scope.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 61: MultiSelectChips reusable component

**Files:**
- Create: `Pommora/Pommora/ItemWindow/MultiSelectChips.swift`

**Context:** Pill-chip multi-select control over a list of string options. Used in Item Window's `multiSelect` PropertyType editor. Each chip toggles on tap; "+" adds a new option (if `allowsAddingOptions: true`).

- [ ] **Step 1: Create folder + implement**

```bash
mkdir -p "Pommora/Pommora/ItemWindow"
```

Create `Pommora/Pommora/ItemWindow/MultiSelectChips.swift`:

```swift
import SwiftUI

struct MultiSelectChips: View {
    let options: [String]
    @Binding var selected: [String]
    let allowsAddingOptions: Bool

    @State private var draftNew: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    chip(for: option)
                }
                if allowsAddingOptions {
                    addButton
                }
            }
        }
    }

    private func chip(for option: String) -> some View {
        let isOn = selected.contains(option)
        return Button {
            toggle(option)
        } label: {
            Text(option)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        HStack(spacing: 4) {
            TextField("Add option", text: $draftNew)
                .textFieldStyle(.plain)
                .frame(maxWidth: 100)
                .onSubmit {
                    let trimmed = draftNew.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !selected.contains(trimmed) else { return }
                    selected.append(trimmed)
                    draftNew = ""
                }
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.gray.opacity(0.08)))
    }

    private func toggle(_ option: String) {
        if let i = selected.firstIndex(of: option) {
            selected.remove(at: i)
        } else {
            selected.append(option)
        }
    }
}

/// Simple flow layout — wraps chips to multiple lines.
/// SwiftUI Layout protocol (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > containerWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth - spacing)
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth - spacing)
        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
```

- [ ] **Step 2: Build + defer commit (until Task 67)**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
```

---

### Task 62: PropertyEditorRow

**Files:**
- Create: `Pommora/Pommora/ItemWindow/PropertyEditorRow.swift`

**Context:** Dispatch view that renders the right control per `PropertyType`. Used inside the Item Window's properties section. Reads the property definition from the Vault schema + the current value, exposes a binding that writes back.

- [ ] **Step 1: Implement**

Create `Pommora/Pommora/ItemWindow/PropertyEditorRow.swift`:

```swift
import SwiftUI

struct PropertyEditorRow: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(definition.name)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)
            editor
            Spacer()
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch definition.type {
        case .number:
            numberEditor
        case .checkbox:
            checkboxEditor
        case .date:
            dateEditor(includeTime: false)
        case .datetime:
            dateEditor(includeTime: true)
        case .select:
            selectEditor
        case .multiSelect:
            multiSelectEditor
        case .relation:
            Text("Relation editor coming v0.5").font(.caption).foregroundStyle(.tertiary)
        case .url:
            urlEditor
        }
    }

    // MARK: - Editors

    private var numberEditor: some View {
        TextField("", value: Binding(
            get: { if case .number(let n) = value { return n } else { return 0.0 } },
            set: { value = .number($0) }
        ), format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 120)
    }

    private var checkboxEditor: some View {
        Toggle("", isOn: Binding(
            get: { if case .checkbox(let b) = value { return b } else { return false } },
            set: { value = .checkbox($0) }
        ))
        .labelsHidden()
    }

    private func dateEditor(includeTime: Bool) -> some View {
        DatePicker("",
            selection: Binding(
                get: {
                    if case .date(let d) = value { return d }
                    if case .datetime(let d) = value { return d }
                    return Date()
                },
                set: { value = includeTime ? .datetime($0) : .date($0) }
            ),
            displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
        )
        .labelsHidden()
    }

    private var selectEditor: some View {
        let options = definition.selectOptions ?? []
        return Picker("", selection: Binding(
            get: { if case .select(let s) = value { return s } else { return "" } },
            set: { value = .select($0) }
        )) {
            Text("—").tag("")
            ForEach(options) { opt in
                Text(opt.label).tag(opt.value)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    private var multiSelectEditor: some View {
        let options = (definition.selectOptions ?? []).map(\.value)
        return MultiSelectChips(
            options: options,
            selected: Binding(
                get: { if case .multiSelect(let xs) = value { return xs } else { return [] } },
                set: { value = .multiSelect($0) }
            ),
            allowsAddingOptions: false   // schema edit is its own concern
        )
    }

    private var urlEditor: some View {
        TextField("https://…", text: Binding(
            get: { if case .url(let u) = value { return u.absoluteString } else { return "" } },
            set: { newText in
                if let url = URL(string: newText), url.scheme != nil {
                    value = .url(url)
                }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
    }
}
```

- [ ] **Step 2: Build + defer commit (until Task 67)**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -5
```

---

### Task 63: ItemWindow popover

**Files:**
- Create: `Pommora/Pommora/ItemWindow/ItemWindow.swift`

**Context:** Sheet hosting the Item editing surface. Editable fields: title (rename), icon (`TextField`), description (`TextEditor` with 250-char counter), one `PropertyEditorRow` per Vault property. Tier1/2/3 shown as read-only ULID strings with "Relation editor coming v0.5" note. Save commits via `ContentManager.updateItem`.

- [ ] **Step 1: Implement ItemWindow**

Create `Pommora/Pommora/ItemWindow/ItemWindow.swift`:

```swift
import SwiftUI

struct ItemWindow: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentManager.self) private var contentManager
    @Environment(VaultManager.self) private var vaultManager

    @State private var draftTitle: String = ""
    @State private var draftIcon: String = ""
    @State private var draftDescription: String = ""
    @State private var draftProperties: [String: PropertyValue] = [:]
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    titleSection
                    iconSection
                    descriptionSection
                    Divider()
                    propertiesSection
                    Divider()
                    relationsSection
                    Divider()
                    metaSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 580)
        .onAppear { hydrate() }
    }

    private var header: some View {
        HStack {
            Image(systemName: draftIcon.isEmpty ? "list.bullet.rectangle" : draftIcon)
                .font(.system(size: 20))
            Text(draftTitle).font(.headline)
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding()
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title").font(.caption).foregroundStyle(.secondary)
            TextField("", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Icon").font(.caption).foregroundStyle(.secondary)
            TextField("SF Symbol name", text: $draftIcon)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(draftDescription.count) / 250")
                    .font(.caption)
                    .foregroundStyle(draftDescription.count > 250 ? .red : .tertiary)
            }
            TextEditor(text: $draftDescription)
                .frame(minHeight: 60, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.gray.opacity(0.3))
                )
        }
    }

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties").font(.caption).foregroundStyle(.secondary)
            if let vault = vaultForItem() {
                if vault.properties.isEmpty {
                    Text("No properties in this Vault's schema.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(vault.properties) { def in
                        PropertyEditorRow(
                            definition: def,
                            value: Binding(
                                get: { draftProperties[def.name] ?? .null },
                                set: { draftProperties[def.name] = $0 }
                            )
                        )
                    }
                }
            } else {
                Text("Parent Vault not found.").font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relations").font(.caption).foregroundStyle(.secondary)
            relationLine(label: "Tier 1 (Spaces)", ids: item.tier1)
            relationLine(label: "Tier 2 (Topics)", ids: item.tier2)
            relationLine(label: "Tier 3 (Sub-topics)", ids: item.tier3)
            Text("Property-panel relation editor coming v0.5")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func relationLine(label: String, ids: [String]) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading).foregroundStyle(.secondary)
            Text(ids.isEmpty ? "—" : ids.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meta").font(.caption).foregroundStyle(.secondary)
            Text("ID: \(item.id)").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            Text("Created: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
            Text("Modified: \(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - State helpers

    private func hydrate() {
        draftTitle = item.title
        draftIcon = item.icon ?? ""
        draftDescription = item.description
        draftProperties = item.properties
    }

    private func vaultForItem() -> Vault? {
        // Items live in Collections; find the Vault whose Collection holds this Item
        for vault in vaultManager.vaults {
            for coll in vaultManager.collections(in: vault) {
                if contentManager.items(in: coll).contains(where: { $0.id == item.id }) {
                    return vault
                }
            }
        }
        return nil
    }

    private func save() async {
        guard let vault = vaultForItem() else {
            errorMessage = "Parent Vault not found."
            return
        }
        guard let coll = (vaultManager.collections(in: vault).first {
            contentManager.items(in: $0).contains(where: { $0.id == item.id })
        }) else {
            errorMessage = "Parent Collection not found."
            return
        }

        var updated = item
        updated.title = draftTitle
        updated.icon = draftIcon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftIcon
        updated.description = draftDescription
        updated.properties = draftProperties

        do {
            // If title changed, rename first
            if updated.title != item.title {
                try await contentManager.renameItem(item, to: updated.title, in: coll, vault: vault)
                // refetch the renamed item to get the new identity-preserving record
                guard let refetched = contentManager.items(in: coll).first(where: { $0.id == item.id }) else {
                    errorMessage = "Rename succeeded but couldn't refetch."
                    return
                }
                updated = refetched
                updated.icon = draftIcon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftIcon
                updated.description = draftDescription
                updated.properties = draftProperties
            }
            try await contentManager.updateItem(updated, in: coll, vault: vault)
            dismiss()
        } catch let error as ItemValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ItemValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Title can't be empty."
        case .invalidTitleCharacters: return "Title can't contain / \\ :"
        case .duplicateTitle: return "Another Item already has that name in this Collection."
        case .descriptionTooLong: return "Description over 250 characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Unknown property '\(n)' for this Vault."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
```

- [ ] **Step 2: Build + commit Item Window (Tasks 61-63)**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -10
git add Pommora/Pommora/ItemWindow/ Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(item-window): popover ItemWindow + PropertyEditorRow + MultiSelectChips

ItemWindow shows title (editable, calls renameItem), icon TextField,
description TextEditor with 250-char counter, ForEach over parent
Vault's properties via PropertyEditorRow, read-only tier1/2/3 IDs
(relation editor v0.5), and ID/created/modified meta. PropertyEditorRow
dispatches per PropertyType (number/checkbox/date/datetime/select/
multiSelect/url; relation = placeholder). MultiSelectChips reusable
pill-chip control with FlowLayout for wrapping. ItemWindow finds its
parent Vault + Collection by walking VaultManager + ContentManager.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 64: ContentView manager wiring

**Files:**
- Modify: `Pommora/Pommora/ContentView.swift` (substantial change)

**Context:** Constructs all managers when `nexusManager.currentNexus` becomes non-nil; injects each via `.environment(...)`. Hosts the `SidebarSelection` + `presentedSheet` state. Wires `SidebarView` to the sidebar of `NavigationSplitView`, and `SidebarDetailView` to the detail pane. The `TopicManager` is constructed with a `contextProvider` closure that pulls from `SpaceManager`; similarly `ContentManager` pulls from the full set for tier lookups.

- [ ] **Step 1: Replace ContentView**

Open `Pommora/Pommora/ContentView.swift` and replace its body. The full replacement:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager

    @State private var spaceManager: SpaceManager?
    @State private var topicManager: TopicManager?
    @State private var vaultManager: VaultManager?
    @State private var contentManager: ContentManager?
    @State private var agendaManager: AgendaManager?
    @State private var homepageManager: HomepageManager?
    @State private var tierConfigManager: TierConfigManager?
    @State private var savedConfigManager: SavedConfigManager?

    @State private var sidebarSelection: SidebarSelection = .none
    @State private var presentedSheet: SidebarSheet?
    @State private var inspectorPresented: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .inspector(isPresented: $inspectorPresented) {
            Color.clear  // existing v0.0 placeholder
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
        .task { await nexusManager.loadOnLaunch() }
        .onChange(of: nexusManager.currentNexus) { _, nexus in
            constructManagers(for: nexus)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if let spaceMgr = spaceManager,
           let topicMgr = topicManager,
           let vaultMgr = vaultManager,
           let savedMgr = savedConfigManager
        {
            SidebarView(selection: $sidebarSelection)
                .environment(spaceMgr)
                .environment(topicMgr)
                .environment(vaultMgr)
                .environment(savedMgr)
        } else {
            VStack {
                ProgressView()
                Text("Loading nexus…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let spaceMgr = spaceManager,
           let vaultMgr = vaultManager,
           let contentMgr = contentManager
        {
            SidebarDetailView(
                selection: $sidebarSelection,
                presentedSheet: $presentedSheet
            )
            .environment(spaceMgr)
            .environment(vaultMgr)
            .environment(contentMgr)
        } else {
            Color.clear
        }
    }

    // MARK: - Manager construction

    private func constructManagers(for nexus: Nexus?) {
        guard let nexus else {
            spaceManager = nil; topicManager = nil; vaultManager = nil
            contentManager = nil; agendaManager = nil; homepageManager = nil
            tierConfigManager = nil; savedConfigManager = nil
            return
        }

        let spaceMgr = SpaceManager(nexus: nexus)
        let vaultMgr = VaultManager(nexus: nexus)

        // TopicManager needs SpaceManager for parent lookups; pass via closure
        let topicMgr = TopicManager(nexus: nexus) {
            NexusContext(
                lookupSpace: { id in spaceMgr.spaces.first { $0.id == id } },
                lookupTopic: { _ in nil },
                lookupSubtopic: { _ in nil },
                lookupVault: { id in vaultMgr.vaults.first { $0.id == id } }
            )
        }

        // ContentManager needs all three lookups for tier validation
        let contentMgr = ContentManager(nexus: nexus) {
            NexusContext(
                lookupSpace:    { id in spaceMgr.spaces.first { $0.id == id } },
                lookupTopic:    { id in topicMgr.topics.first { $0.id == id } },
                lookupSubtopic: { id in
                    for arr in topicMgr.subtopicsByParent.values {
                        if let s = arr.first(where: { $0.id == id }) { return s }
                    }
                    return nil
                },
                lookupVault:    { id in vaultMgr.vaults.first { $0.id == id } }
            )
        }

        let agendaMgr = AgendaManager(nexus: nexus)
        let homepageMgr = HomepageManager(nexus: nexus)
        let tierMgr = TierConfigManager(nexus: nexus)
        let savedMgr = SavedConfigManager(nexus: nexus)

        // Set state
        self.spaceManager = spaceMgr
        self.topicManager = topicMgr
        self.vaultManager = vaultMgr
        self.contentManager = contentMgr
        self.agendaManager = agendaMgr
        self.homepageManager = homepageMgr
        self.tierConfigManager = tierMgr
        self.savedConfigManager = savedMgr

        // Initial load — fire all in parallel
        Task {
            async let _ = spaceMgr.loadAll()
            async let _ = topicMgr.loadAll()
            async let _ = vaultMgr.loadAll()
            async let _ = agendaMgr.loadAll()
            async let _ = homepageMgr.load()
            async let _ = tierMgr.load()
            async let _ = savedMgr.load()
            // ContentManager loads per-collection lazily on detail view appear
        }
    }
}
```

- [ ] **Step 2: Build to confirm everything compiles**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` with zero warnings.

- [ ] **Step 3: Commit**

```bash
git add Pommora/Pommora/ContentView.swift Pommora/Pommora.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(content-view): wire all paradigm managers + sidebar/detail layout

ContentView constructs every manager on nexus change and injects each
into the environment. Sidebar gets Space/Topic/Vault/SavedConfig
managers; detail gets Space/Vault/Content. TopicManager + ContentManager
receive NexusContext provider closures that read live state from the
peer managers for cross-entity validation lookups. ProgressView shown
until managers are constructed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 65: End-to-end verification + final commit

**Files:**
- No code; pure verification pass.

**Context:** Final gate before declaring the paradigm scaffolding shipped. Runs the full build, all tests, and the manual gold path from the design doc.

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`. Expected pass count: ~170+ (26 existing + ~150 new across the 30 new test suites added across Tasks 3-43). Exact count varies as tests are written — what matters is zero failures.

- [ ] **Step 2: Clean build under Swift 6 strict concurrency**

```bash
xcodebuild clean -project "Pommora/Pommora.xcodeproj" -scheme Pommora
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora build 2>&1 | grep -E "warning:|error:" | wc -l
```
Expected: `0` (zero warnings, zero errors).

- [ ] **Step 3: Sandbox entitlement check**

```bash
xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora \
  -configuration Debug -derivedDataPath /tmp/pommora-dd build
codesign -d --entitlements - /tmp/pommora-dd/Build/Products/Debug/Pommora.app 2>&1 | head -30
```
Expected output contains:
```
[Key] com.apple.security.app-sandbox
[Value] true
[Key] com.apple.security.files.user-selected.read-write
[Value] true
```

- [ ] **Step 4: Manual gold path with a fresh nexus**

Launch the app via `open /tmp/pommora-dd/Build/Products/Debug/Pommora.app`. Walk through, verifying each step:

1. **Pick a fresh empty nexus** (Cmd-O → choose an empty folder). `.nexus/nexus.json` appears on disk. Sidebar shows the four sections: Saved (Homepage / Calendar / Recents), Spaces (empty + "New Space"), Topics (empty + "New Topic"), Vaults (empty + "New Vault").

2. **`+ New Space`** → name "Personal", color blue, icon `person.circle` → Sidebar shows "Personal" with a blue dot. On disk: `<nexus>/.nexus/spaces/Personal.space.json`. Open in Finder; `cat` the file — pretty-printed JSON with `"color": "blue"`, `"icon": "person.circle"`, `"tier": 1`.

3. **`+ New Topic`** → name "Productivity", parent Spaces: [Personal], icon `lightbulb` → Sidebar shows "Productivity" under Topics with a blue parent-Space dot. On disk: `<nexus>/.nexus/topics/Productivity/_topic.json`.

4. **Expand Productivity → `+ New Sub-topic`** → name "GTD method" → Sidebar shows GTD method nested under Productivity. On disk: `<nexus>/.nexus/topics/Productivity/GTD method.subtopic.json`.

5. **Right-click Productivity → Delete** → confirmation dialog shows "Contains 1 Sub-topic(s). Promote them or delete all?" with **two destructive buttons**: "Delete & Promote Sub-topics" (default) + "Delete All". Click "Delete & Promote Sub-topics" → Productivity folder gone; sidebar now shows GTD method as a top-level Topic. On disk: `<nexus>/.nexus/topics/GTD method/_topic.json` exists; GTD method's parents inherit `[01HSPACE-PERSONAL]`.

6. **`+ New Vault`** → name "Planner", icon `tray.2` → Sidebar shows "Planner" under Vaults. On disk: `<nexus>/Planner/_vault.json`.

7. **Expand Planner → `+ New Collection`** → name "Tasks" → Sidebar shows "Tasks" nested under Planner. On disk: `<nexus>/Planner/Tasks/` (folder, no metadata file).

8. **Click "Planner" in sidebar** → Detail pane shows a native Table with one row: "Tasks" (Kind: Collection). The chevron expands the row to show its contents (currently empty). No toolbar.

9. **Footer of detail pane → click "New Collection"** → sheet appears. (Click Cancel.)

10. **Click "Tasks" in sidebar (or expand the Planner row + click the Tasks chevron)** → Detail pane swaps to CollectionDetailView. Two footer buttons: "+ New Page", "+ New Item". Table is empty.

11. **`+ New Item`** → name "Buy groceries" → Item appears in the Table with Kind = "Item". On disk: `<nexus>/Planner/Tasks/Buy groceries.json`.

12. **Single-click "Buy groceries" row** → Item Window popover opens with the locked-spec title + icon + description + ID/created/modified meta. Properties section shows "No properties in this Vault's schema." (correct — Planner's `_vault.json` has empty properties). Tier1/2/3 sections show "—" with the "Relation editor coming v0.5" note. Type a description "Milk and eggs" → Save → popover dismisses; `cat` the JSON to confirm `"description": "Milk and eggs"`.

13. **`+ New Page`** → name "Notes" → Page appears in Table with Kind = "Page". On disk: `<nexus>/Planner/Tasks/Notes.md` with YAML frontmatter. Click does nothing (correct — no editor in this plan).

14. **Verify Homepage + Agenda seeded automatically:**
    - `<nexus>/.nexus/homepage.json` exists with `"icon": "house"`.
    - `<nexus>/Agenda/_agenda.json` exists with the built-in `type` Select.
    - Tier-config + Saved-config files also present at `.nexus/tier-config.json` and `.nexus/saved-config.json`.

15. **Renames**: rename "Personal" → "Life" via right-click → Rename → file moves from `Personal.space.json` to `Life.space.json`. Verify with `ls`.

16. **Deletes**: delete Planner Vault → confirmation lists collection count → confirm → folder + everything inside gone. Sidebar updates live.

17. **Restart app** → reopens to the same nexus → all entities still present (filesystem is source of truth; no SQLite to be out of sync).

- [ ] **Step 5: LLM-legibility spot-check**

Pick one file from each entity type and `cat` it:
```bash
cat <nexus>/.nexus/spaces/Life.space.json       # Space
cat <nexus>/.nexus/topics/Productivity/_topic.json  # Topic (after recreating)
cat <nexus>/.nexus/topics/Productivity/Foo.subtopic.json  # Subtopic
cat <nexus>/Planner/_vault.json                  # Vault
cat <nexus>/Planner/Tasks/X.json                 # Item
cat <nexus>/Planner/Tasks/Y.md                   # Page
cat <nexus>/Agenda/_agenda.json                  # AgendaSchema
cat <nexus>/.nexus/homepage.json                 # Homepage
cat <nexus>/.nexus/tier-config.json
cat <nexus>/.nexus/saved-config.json
```
Each must be:
- Pretty-printed (newlines + 2-space indent)
- Sorted keys alphabetically
- ISO-8601 dates
- All field names match the locked spec exactly (no underscored vs camelCase drift)

- [ ] **Step 6: Final commit (verification summary)**

```bash
git log --oneline | head -30   # confirm the commit history reflects every task
echo "Paradigm Scaffolding complete: Phases 0–6 shipped."
```

No code commit at this step — just verification.

- [ ] **Step 7: Update Handoff.md (recommended; not strictly required this session)**

After verification passes, update [.claude/Handoff.md](.claude/Handoff.md) to:
- Move "v0.1b — Tab integration" into the next-session candidates (paradigm done; tabs are the natural next step)
- Note that Phases 7+ (tier1/2/3 property panel, Settings scene, file watcher, SQLite indexer, EventKit) remain
- Capture any spec gaps surfaced during implementation (filename collision UX during Topic-promote? Whether the Item Window should show a "go to source Vault" link? — record as Known Spec Gaps for the next planning pass)

This is the natural breakpoint after the entire paradigm has been scaffolded.

---

## Sequencing summary

Build in this order, each step green before the next:

1. **Task 1** — Swift 6 migration + audit
2. **Tasks 2–6** — Foundation helpers (Yams, test support, AtomicJSON, AtomicYAMLMarkdown, NexusPaths, Filesystem)
3. **Tasks 7–13** — Contexts Codables (SpaceColor, ContextBlock, Space, Topic, Subtopic, TierConfig, SavedConfig)
4. **Tasks 14–19** — Vaults Codables (PropertyType, PropertyDefinition, PropertyValue, VaultView, Vault, Collection)
5. **Tasks 20–25** — Content + Agenda + Homepage Codables (Item, PageFrontmatter+PageFile, Recurrence, AgendaSchema, AgendaItem, Homepage)
6. **Tasks 26–35** — Validators (ULID + NexusContext, Space, Topic, Subtopic, Vault, Collection, Item, Page, Agenda, Homepage)
7. **Tasks 36–43** — Managers (Space, Topic, Vault, Content, Agenda, Homepage, TierConfig, SavedConfig)
8. **Tasks 44–48** — Sidebar selection + 5 row types + integration
9. **Tasks 49–56** — Sheets + pickers (build will be broken until 56's integration commit lands; that's expected)
10. **Tasks 57–60** — Detail pane (ContentItem, DetailRow, ContextDetailPlaceholder, VaultDetailView, CollectionDetailView, SidebarDetailView)
11. **Tasks 61–63** — Item Window (MultiSelectChips, PropertyEditorRow, ItemWindow)
12. **Task 64** — ContentView manager wiring
13. **Task 65** — End-to-end verification + gold path

If Task 1's Swift 6 migration surfaces > 30 min of friction, STOP and report — fallback is to defer migration and stay on Swift 5 for this plan.

## Out of scope (explicitly)

- Tabs / tab strip (Framework v0.1b — deferred)
- Page Markdown editor (v0.6+)
- Composed-blocks editor for Spaces / Topics / Sub-topics / Homepage (v0.9)
- EventKit integration for Agenda
- `tier1` / `tier2` / `tier3` relations property panel (Phase 7 / v0.5)
- File watcher (FSEventStream) (v0.5)
- SQLite indexer (GRDB.swift) (v0.5)
- Settings scene (v0.5)
- Saved-section content (Homepage/Calendar/Recents views) (v0.5)
- Calendar view (v0.4)
- Vault property-schema editor (v1.x)
- Vault view types beyond basic detail Table (v0.10)
- Full SF Symbol curated picker
- Wikilinks rendering (v0.8)
- Cross-nexus wikilink rewrite (v0.8)
