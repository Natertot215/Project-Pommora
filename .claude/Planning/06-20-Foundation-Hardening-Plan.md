# Foundation Hardening Implementation Plan

> **For agentic workers:** execute task-by-task as a **sequential pipeline** — each task ends in a green commit before the next begins. Steps use checkbox (`- [ ]`) syntax. Verify every claim against real code; a finding is a hypothesis until the code proves it.

**Goal:** Land the audit's correctness fixes + safe cleanup as a series of green commits, before any structural refactor.

**Architecture:** Phase 1 of the [codebase audit](06-20-Codebase-Audit-And-Reorg.md). Five correctness bug-fixes (A1–A5), two dead-code removals, two zero-behavior-change DRY hoists, and a stale-comment correction pass — 10 tasks, each a green commit. Nothing here touches the per-type managers (kept separate, ratified), the folder reorg, or `Codable` — those are later, separately-planned phases.

**Tech Stack:** Swift 6 (strict concurrency, ExistentialAny), SwiftUI/AppKit, GRDB (SQLite), Swift Testing (`@Suite`/`@Test`/`#expect`). Xcode project at `Pommora/Pommora.xcodeproj`.

## Global Constraints

- Each task ships as **one green commit**; verify with `xcodebuild test -scheme Pommora -only-testing:PommoraTests -destination 'platform=macOS'` and **confirm a non-zero executed test count** (a 0-count "succeeded" is a false pass — quirk #1).
- Run builds via a **background builder agent** (no window focus — quirk #13).
- **Trust `xcodebuild`, not SourceKit** (stale "cannot find type" squiggles are normal — quirk #3).
- New Swift files auto-include via `PBXFileSystemSynchronizedRootGroup` — no pbxproj edit needed (quirk #2). Revert any incidental SPM-reorder churn before commit (quirk #6).
- Custom Codable signatures: `init(from decoder: any Decoder)` / `encode(to encoder: any Encoder)`; errors typed `(any Error)?` (quirk #5).
- Branch: create `foundation-hardening` off the current `audit-comment-cleanup` HEAD (carries the committed comment-cleanup + audit doc).

---

## Phase A — Correctness fixes (confirmed against code)

### Task A1: PageCollection index writes the real schema_version

**Why:** `upsertPageType` (`:70`) and `upsertPageSet` (`:126`) bind the entity's `schemaVersion`; `upsertPageCollection` (`:98`) hardcodes `1`. A migrated collection is indexed at the wrong version.

**Files:**
- Modify: `Pommora/Pommora/Index/IndexUpdater.swift:98`
- Test: `Pommora/PommoraTests/Index/` (new `@Test` in the existing index-update suite, or a new file `PageCollectionSchemaVersionTests.swift`)

- [ ] **Step 1 — Failing test.** Using the existing index fixtures (`makeIndex(at:)` + `makePageCollection`), upsert a `PageCollection` whose `schemaVersion` is **not** 1, then read the indexed row and assert it round-trips:

```swift
@Test func upsertPageCollection_persists_entity_schemaVersion() throws {
    let nexus = try TempNexus.make()
    defer { TempNexus.cleanup(nexus) }
    let index = try makeIndex(at: nexus)
    let updater = IndexUpdater(index: index)
    let pc = makePageCollection(schemaVersion: 7)           // a value ≠ the hardcoded 1
    try updater.upsertPageType(makePageType(id: pc.typeID))  // satisfy the FK parent
    try updater.upsertPageCollection(pc)

    let stored = try index.dbQueue.read { db in
        try Int.fetchOne(db, sql: "SELECT schema_version FROM page_collections WHERE id = ?", arguments: [pc.id])
    }
    #expect(stored == 7)
}
```
> If `makePageCollection`/`makePageType` don't take those exact params, match the real fixture signatures in the suite — the assertion is what matters.

- [ ] **Step 2 — Run, verify it FAILS** (`stored == 1`, expected 7).
- [ ] **Step 3 — Fix.** `IndexUpdater.swift:98`, change the last argument from `1` to `pc.schemaVersion`:

```swift
arguments: [pc.id, pc.typeID, pc.title, pc.icon, iso(pc.modifiedAt), pc.schemaVersion]
```

- [ ] **Step 4 — Run, verify PASS** + full `-only-testing:PommoraTests` green (non-zero count).
- [ ] **Step 5 — Commit:** `fix(index): page_collection upsert writes the entity schema_version, not literal 1`

---

### Task A2: One shared ISO-8601 formatter for the index (fixes datetime-filter drift)

**Why:** the index **write** paths use `[.withInternetDateTime, .withFractionalSeconds]` (`IndexUpdater.swift:33`, `IndexBuilder.swift:708`), but the datetime **filter** value at `IndexQuery.swift:546` uses `[.withInternetDateTime]` only. A datetime filter string can't match the stored fractional-second timestamps. Consolidating to one formatter fixes the drift and prevents recurrence.

**Files:**
- Create: `Pommora/Pommora/Index/IndexDateFormat.swift`
- Modify: `Pommora/Pommora/Index/IndexUpdater.swift:31-39` · `Pommora/Pommora/Index/IndexBuilder.swift:706-714` · `Pommora/Pommora/Index/IndexQuery.swift:544-547`
- Test: `Pommora/PommoraTests/Index/IndexDateFormatTests.swift`

- [ ] **Step 1 — Failing test.** Assert the filter formatting equals the write formatting for the same instant (currently differs by fractional seconds):

```swift
@Test func index_datetime_format_is_consistent_across_read_and_write() {
    let d = Date(timeIntervalSince1970: 1_700_000_000.123)
    // Both must include fractional seconds so a datetime filter matches a stored timestamp.
    #expect(IndexDateFormat.iso8601.string(from: d).contains("."))
}
```

- [ ] **Step 2 — Run, verify it FAILS** (`IndexDateFormat` doesn't exist yet).
- [ ] **Step 3 — Implement the shared formatter:**

```swift
import Foundation

/// Single source for the index's ISO-8601 timestamp encoding. Read (filter) and
/// write (upsert/rebuild) paths MUST share this, or a datetime filter string fails
/// to match a stored fractional-second timestamp.
enum IndexDateFormat {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
```

- [ ] **Step 4 — Route all three sites through it.** Replace the private `iso8601`/`isoFormatter` statics in `IndexUpdater` and `IndexBuilder` with `IndexDateFormat.iso8601`, and change `IndexQuery.swift:545-546` from a local formatter to:

```swift
case .datetime(let d):
    return ("?", [IndexDateFormat.iso8601.string(from: d)])
```

- [ ] **Step 5 — Run, verify PASS** + full suite green (non-zero count).
- [ ] **Step 6 — Commit:** `fix(index): single shared ISO-8601 formatter so datetime filters match stored timestamps`

---

### Task A3: Corrupt state.json fails loud instead of silently wiping it

**Why:** `OrderPersister.swift:97` does `(try? AtomicJSON.decode(...)) ?? NexusState()` — when the file **exists but won't parse**, it silently replaces it with an empty state and writes back, dropping all pins / recents / active-views / order. `NexusState`'s decoder already handles legacy formats, so a decode failure means genuine corruption, which must not destroy data.

**Files:**
- Modify: `Pommora/Pommora/Ordering/OrderPersister.swift:96-97`
- Test: `Pommora/PommoraTests/` (the suite covering `OrderPersister` / state.json)

- [ ] **Step 1 — Failing test.** Write a corrupt `state.json`, trigger an order write, assert it **throws** and leaves the file **unchanged**:

```swift
@Test func order_write_on_corrupt_state_throws_and_preserves_file() throws {
    let nexus = try TempNexus.make()
    defer { TempNexus.cleanup(nexus) }
    let url = NexusPaths.nexusStateURL(in: nexus)
    try FileManager.default.createDirectory(at: NexusPaths.nexusConfigDir(in: nexus), withIntermediateDirectories: true)
    try "{ not valid json".data(using: .utf8)!.write(to: url)

    #expect(throws: (any Error).self) {
        try OrderPersister.persistPageTypeOrder(["a", "b"], in: nexus)  // any public order-write entry
    }
    let after = try String(contentsOf: url, encoding: .utf8)
    #expect(after == "{ not valid json")   // untouched, not wiped
}
```
> Use whichever public `OrderPersister` order-write method the suite already exercises; the point is the corrupt-file path.

- [ ] **Step 2 — Run, verify it FAILS** (today it swallows the corruption, overwrites, does not throw).
- [ ] **Step 3 — Fix.** `OrderPersister.swift`, inside the `fileExists` branch, propagate the decode error instead of substituting a fresh state:

```swift
if FileManager.default.fileExists(atPath: url.path) {
    state = try AtomicJSON.decode(NexusState.self, from: url)   // was: (try? …) ?? NexusState()
} else {
    state = NexusState()
}
```

- [ ] **Step 4 — Run, verify PASS** + full suite green. Managers already catch order-write errors into `pendingError` (toast), so a corrupt file now surfaces instead of losing data.
- [ ] **Step 5 — Commit:** `fix(ordering): corrupt state.json surfaces an error instead of silently wiping pins/recents/order`

---

### Task A4: A page missing `created_at` falls back to `modified_at` (not the 1970 epoch)

**Why:** `PageFrontmatter.swift:80` defaults a missing `created_at` to `Date(timeIntervalSince1970: 0)`, so the page sorts/shows as 1970-01-01. Fall back to `modified_at` (a far better estimate); the current date only if both are absent. *(Ratified: fall back to modified.)*

**Files:** Modify `Pommora/Pommora/Content/PageFrontmatter.swift:80-81` · Test: the existing `PageFrontmatter`/`PageFile` suite.

- [ ] **Step 1 — Failing test.** Decode frontmatter with `modified_at` but no `created_at`; assert they're equal:

```swift
@Test func missing_createdAt_falls_back_to_modifiedAt() throws {
    let json = #"{"id":"p1","modified_at":"2026-06-20T12:00:00Z"}"#.data(using: .utf8)!
    let fm = try JSONDecoder().decode(PageFrontmatter.self, from: json)  // match the suite's decode helper
    #expect(fm.createdAt == fm.modifiedAt)
    #expect(fm.createdAt != Date(timeIntervalSince1970: 0))
}
```

- [ ] **Step 2 — Run, verify it FAILS** (`createdAt` is the 1970 epoch).
- [ ] **Step 3 — Fix.** Decode `modifiedAt` **first**, then chain the fallback (order matters — it's used as the fallback):

```swift
self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? self.modifiedAt ?? Date()
```

- [ ] **Step 4 — Run, verify PASS** + full suite green.
- [ ] **Step 5 — Commit:** `fix(pages): missing created_at falls back to modified_at, not the 1970 epoch`

---

### Task A5: Remove the bucket-decode fabrication (no wrong `.select` write)

**Why:** `BucketValueDecoder.propertyValue` (`GroupDropPlanner.swift:112`) `default`-returns `.select(bucket)` for **any** non-select/status/checkbox property — fabricating a select value if a property-group drop ever lands on a date/number property. Per Nathan: **remove the mechanism**, no guard — an unsupported type yields no value.

**Files:** Modify `Pommora/Pommora/Detail/ViewPipeline/GroupDropPlanner.swift:108-113` · Test: `Pommora/PommoraTests/Detail/`

- [ ] **Step 1 — Failing test.** For a non-groupable type, assert nil (today it returns `.select`):

```swift
@Test func bucketDecoder_returns_nil_for_non_groupable_type() {
    let schema = [PropertyDefinition(id: "p", name: "N", type: .number)]  // match the real init
    #expect(BucketValueDecoder.propertyValue(bucket: "5", propertyID: "p", schema: schema) == nil)
}
```

- [ ] **Step 2 — Run, verify it FAILS** (returns `.select("5")`).
- [ ] **Step 3 — Fix.** Replace the fabricating default with nil:

```swift
case .select: return .select(bucket)
default: return nil
```

- [ ] **Step 4 — Run, verify PASS** + the existing select/status/checkbox decode tests stay green.
- [ ] **Step 5 — Commit:** `fix(views): bucket decoder yields nil for non-groupable types instead of fabricating a select`

---

## Phase B — Dead-code removal (verified zero/single use)

### Task B1: Delete the dead IconPickerField

**Why:** `Sidebar/Sheets/IconPickerField.swift` has **zero** references (its own header says it was for the retired Create sheets; grep confirms no call sites).

**Files:** Delete `Pommora/Pommora/Sidebar/Sheets/IconPickerField.swift`

- [ ] **Step 1 — Re-confirm zero references:** `grep -rn "IconPickerField" Pommora/Pommora --include="*.swift" | grep -v "IconPickerField.swift:"` → no output.
- [ ] **Step 2 — Delete the file:** `git rm "Pommora/Pommora/Sidebar/Sheets/IconPickerField.swift"`
- [ ] **Step 3 — Build + full suite green** (non-zero count) — nothing referenced it, so nothing breaks.
- [ ] **Step 4 — Commit:** `chore(sidebar): delete dead IconPickerField (zero call sites)`

---

### Task B2: Remove the dead "add option by typing" path from MultiSelectChips

**Why:** `MultiSelectChips.allowsAddingOptions` has exactly one caller — `PropertyEditorRow.swift:190` — which passes `false`. The Properties spec forbids creating options by typing into a value picker, so the `addButton` + `draftNew` are dead in production.

**Files:**
- Modify: `Pommora/Pommora/Properties/Chips/MultiSelectChips.swift` (remove `:6`, `:8`, `:16-18`, `:40-56`)
- Modify: `Pommora/Pommora/Properties/PropertyEditorRow.swift:190`

- [ ] **Step 1 — Re-confirm single caller:** `grep -rn "allowsAddingOptions" Pommora/Pommora --include="*.swift"` → only the definition + `PropertyEditorRow.swift:190`.
- [ ] **Step 2 — Edit `MultiSelectChips`:** delete `let allowsAddingOptions: Bool` (`:6`), `@State private var draftNew` (`:8`), the `if allowsAddingOptions { addButton }` block (`:16-18`), and the entire `addButton` computed (`:40-56`). `FlowLayout`, `chip(for:)`, and `toggle(_:)` stay.
- [ ] **Step 3 — Update the caller** at `PropertyEditorRow.swift:190`: remove the `allowsAddingOptions: false` argument from the `MultiSelectChips(...)` initializer.
- [ ] **Step 4 — Build + full suite green** (non-zero count).
- [ ] **Step 5 — Commit:** `chore(properties): remove dead add-option-by-typing path from MultiSelectChips`

---

## Phase C — Safe DRY hoists (zero behavior change; descopable)

> These two collapse purely mechanical duplication and touch **no** kept-separate manager. Approve or descope independently of Phases A/B.

### Task C1: Single filename-safety rule for the 9 entity validators

**Why:** the trim → empty-guard → invalid-character-guard block is copy-pasted across 9 validators, and the invalid-char set (`["/", "\\", ":"]`) is hardcoded 8×. One source removes the divergence risk (a validator silently missing a forbidden char).

**Files:**
- Create: `Pommora/Pommora/Validation/FilenameSafety.swift`
- Modify (each: replace the trim+two-guards block with one call): `Validation/AreaValidator.swift`, `TopicValidator.swift`, `ProjectValidator.swift`, `PageTypeValidator.swift`, `PageCollectionValidator.swift`, `PageSetValidator.swift`, `PageValidator.swift`, `AgendaTaskValidator.swift`, `AgendaEventValidator.swift`
- Test: `Pommora/PommoraTests/Validation/FilenameSafetyTests.swift`

- [ ] **Step 1 — Failing test** for the new shared rule:

```swift
@Test func filenameSafety_trims_and_enforces_both_rules() throws {
    enum E: Error { case empty, bad }
    #expect(try FilenameSafety.validatedTitle("  Hi  ", empty: E.empty, invalidCharacters: E.bad) == "Hi")
    #expect(throws: E.empty) { _ = try FilenameSafety.validatedTitle("   ", empty: E.empty, invalidCharacters: E.bad) }
    #expect(throws: E.bad)   { _ = try FilenameSafety.validatedTitle("a/b", empty: E.empty, invalidCharacters: E.bad) }
}
```

- [ ] **Step 2 — Run, verify it FAILS** (`FilenameSafety` doesn't exist).
- [ ] **Step 3 — Implement the shared rule** (autoclosure errors preserve each validator's contract, matching the existing `NameCollisionValidator(else:)` pattern):

```swift
import Foundation

enum FilenameSafety {
    static let invalidCharacters: Set<Character> = ["/", "\\", ":"]

    /// Trims `raw`, then enforces the two filename-safety rules every entity validator
    /// shares. The caller supplies its own error type so the public contract is unchanged.
    static func validatedTitle(
        _ raw: String,
        empty: @autoclosure () -> any Error,
        invalidCharacters: @autoclosure () -> any Error
    ) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw empty() }
        guard trimmed.allSatisfy({ !Self.invalidCharacters.contains($0) }) else { throw invalidCharacters() }
        return trimmed
    }
}
```

- [ ] **Step 4 — Route each validator.** Replace its trim+two-guards block with one call, keeping its own error cases. Example (`AreaValidator.swift:15-21` → ):

```swift
let trimmed = try FilenameSafety.validatedTitle(
    title,
    empty: ValidationError.emptyTitle,
    invalidCharacters: ValidationError.invalidTitleCharacters)
```
Apply the identical transform to the other 8 files listed above, each passing **its own** `ValidationError.emptyTitle` / `.invalidTitleCharacters`. Leave every duplicate-title check exactly as-is (`ProjectValidator` keeps its hand-rolled variant).

- [ ] **Step 5 — Run the full suite** — all existing validator tests + the new `FilenameSafetyTests` green (non-zero count). The existing validator tests are the behavior net.
- [ ] **Step 6 — Commit:** `refactor(validation): single FilenameSafety rule for the 9 entity validators`

---

### Task C2: One context-index emitter (collapse the 3 identical upserts)

**Why:** `upsertContext(_ area:)`, `(_ topic:)`, `(_ project:)` (`IndexUpdater.swift:317-354`) are the same `INSERT OR REPLACE INTO contexts` differing only by the tier literal + bindings. One parameterized writer removes the SQL duplication — **no entity or manager is merged** (the typed overloads stay; callers are unchanged).

**Files:** Modify `Pommora/Pommora/Index/IndexUpdater.swift:317-354` · Test: `Pommora/PommoraTests/Index/`

- [ ] **Step 1 — Failing test** for the new generic writer:

```swift
@Test func upsertContext_generic_writes_row() throws {
    let nexus = try TempNexus.make(); defer { TempNexus.cleanup(nexus) }
    let index = try makeIndex(at: nexus)
    let updater = IndexUpdater(index: index)
    try updater.upsertContext(id: "ctx-1", tier: 2, title: "Topic A", icon: nil)
    let row = try index.dbQueue.read { db in
        try Row.fetchOne(db, sql: "SELECT tier, title FROM contexts WHERE id = ?", arguments: ["ctx-1"])
    }
    #expect(row?["tier"] == 2)
    #expect(row?["title"] == "Topic A")
}
```

- [ ] **Step 2 — Run, verify it FAILS** (no `upsertContext(id:tier:title:icon:)` yet).
- [ ] **Step 3 — Implement** one generic writer + thin typed forwarders (binds the entity's own `tier`, so even the tier literal stops being duplicated):

```swift
func upsertContext(id: String, tier: Int, title: String, icon: String?) throws {
    try index.dbQueue.write { db in
        try db.execute(
            sql: "INSERT OR REPLACE INTO contexts (id, tier, title, icon) VALUES (?, ?, ?, ?)",
            arguments: [id, tier, title, icon])
    }
}
func upsertContext(_ area: Area)       throws { try upsertContext(id: area.id,    tier: area.tier,    title: area.title,    icon: area.icon) }
func upsertContext(_ topic: Topic)     throws { try upsertContext(id: topic.id,   tier: topic.tier,   title: topic.title,   icon: topic.icon) }
func upsertContext(_ project: Project) throws { try upsertContext(id: project.id, tier: project.tier, title: project.title, icon: project.icon) }
```
> If `Area/Topic/Project` don't expose a `tier` property, bind the literal `1`/`2`/`3` in the respective forwarder instead — the SQL body is still single-sourced.

- [ ] **Step 4 — Run, verify PASS** + the existing context-index tests stay green (behavior identical; callers untouched).
- [ ] **Step 5 — Commit:** `refactor(index): single parameterized context upsert; typed overloads forward to it`

---

## Phase D — Stale-status comment correction

### Task D1: Correct comments that claim shipped features are missing/unwired

**Why:** some comments assert a capability is absent, unwired, or "lands in vX" when it has since shipped — actively misleading (a reader can believe connections aren't wired when they are). The earlier how/why cleanup *kept* these (they read as status "why" notes), so they need a dedicated **verify-then-correct** pass. This is comment-only; no code changes.

**Scope:** `Pommora/Pommora/**` + `External/MarkdownPM/Sources/**` (Swift comments only).

**Rule (per candidate — bias to keep):**
- For each comment claiming a feature is missing/unwired/deferred, grep + read the code to verify whether that capability now exists/is wired.
- It **exists** → comment is stale → delete it, or rewrite to present-tense fact if the rest of the comment is load-bearing.
- It's a **version stamp** on a planned feature ("lands in v0.6.0") → drop the version (Versioning HARD RULE); keep the deferral fact **only** if the feature genuinely isn't built.
- Feature genuinely **doesn't exist yet** → KEEP (accurate TODO).
- Comment describes a **runtime condition** ("returns `[]` if the folder doesn't exist") → KEEP (not a status claim).
- Unsure → KEEP + report.

**Candidates to start from (verify each — do not bulk-delete):**
- `ViewSettings/GroupingOptionsList.swift:8` — "drag events are not wired".
- `ViewSettings/ViewSettingsButton.swift:38` — ".page scope's settings pane (not built…)".
- `Properties/Chips/ContextChip.swift:10` + `Properties/PropertiesPulldown.swift:91` — "PropertiesPulldown (planned… not yet wired)".
- Version stamps (drop the version): `PommoraApp.swift:67` ("v0.6.0"), `Settings/SettingsScene.swift:7` ("ships in v0.6.0"), `Contexts/ContextBlock.swift:4` ("composed-blocks editor lands in v0.9").

**Steps:**
- [ ] **Step 1 — Gather candidates:** `grep -rniE '//.*((not (yet|wired|implemented|built|hooked))|lands in v|ships in v|once .* (lands|ships)|planned|not yet wired|deferred)' Pommora/Pommora External/MarkdownPM/Sources --include="*.swift"`
- [ ] **Step 2 — Verify each** against the code (grep the named type/feature; read its call sites).
- [ ] **Step 3 — Edit only** the confirmed-false / version-stamped comments per the rule. Comments only — never code.
- [ ] **Step 4 — Build + full suite green** (comments don't compile, but a malformed edit could).
- [ ] **Step 5 — Report** deleted/corrected vs kept, with the per-change verification evidence.
- [ ] **Step 6 — Commit:** `chore(comments): correct stale not-wired/not-built status comments that misstate shipped features`

> **Leave the Swift MarkdownPM connection comments** — they correctly state MarkdownPM delegates connection-wiring to the host (which the app wired). The genuinely-stale "deferred, as in Swift" wiki-link-resolver claim is in the **React** doc `React/.claude/Planning/MarkdownPM.md:193,232` (out of this Swift plan's scope; Swift wired both via `WikiLinkPageOpener` + `ConnectionCascade`) — flag for the React session.

---

## Decisions — resolved

Both former open questions are ratified and folded into Phase A: `created_at` → fall back to `modified_at` (Task A4); the bucket-decoder → remove the fabrication mechanism, yielding nil for non-groupable types (Task A5).

## Dropped (audit claims that did NOT verify)

- `NexusAdopter` "dead `skipped`/`contentSniff` scaffolding" — `skipped`/`skippedTopLevel` is a **live** field (collected `:297`, stored `:328`, compared in `Equatable` `:208`). Not dead.
- `OrderResolver.titleKeyPath` "vestigial" — it **is** used for the alphabetic-tail fallback. Removing it changes sort behavior; it's a refactor, not dead code. Deferred.
- `PropertiesPulldown` unused VM — ambiguous (delete the VM vs wire the View to it); touches tests. Deferred to the DRY phase.

---

## Execution (via workflow)

Run as a **sequential pipeline**, stop-on-red, on branch `foundation-hardening`:

1. Each task = one agent that implements the change + writes/updates the test.
2. A **background builder agent** runs `xcodebuild test -scheme Pommora -only-testing:PommoraTests -destination 'platform=macOS'` and reports pass/fail + **executed count**.
3. Green (non-zero count) → the task agent commits with the message above → next task. Red → halt, surface the failure, do not proceed.

Phases A and B tasks are mutually independent (distinct files) and could run in parallel worktrees, but the SQLite/Xcode build is shared — sequential is simpler and keeps a clean bisectable history. C1/C2 run last (C1 touches 9 files).

## Roadmap — subsequent phases (each gets its own concrete plan when reached)

Per the audit backlog, planned **separately** because their exact tasks emerge during the refactor (pre-specifying them would be guesswork):

- **Reorg → Components vs Features** + the `Row` primitive (the React lesson) — a move-heavy plan; build-verify per move.
- **Manual `Codable` → synthesized + minimal-custom** — TDD the legacy-key + foreign-frontmatter preservation first.
- **SavedView pane scaffold + Page-CRUD scope path** — the remaining "still collapse" DRY.
- **Concurrency/`FormatStyle`/typed-throws modernization**, **`PUI` enforcement**, **`PommoraTestSupport` + coverage**.

> Per-type **Context + Agenda managers stay separate** across all phases (ratified — headroom for divergent features).

---

## Self-Review

- **Spec coverage:** Phase 1 of the audit backlog ("quick-win sweep" + the two safest hoists) is fully covered; later backlog items are explicitly roadmapped, not dropped.
- **Placeholder scan:** every code step shows the actual change; tests show real assertions (fixture calls flagged where the executing agent confirms a signature).
- **Type consistency:** `FilenameSafety.validatedTitle(_:empty:invalidCharacters:)` and `upsertContext(id:tier:title:icon:)` are named identically wherever referenced.
- **Honesty:** 2 unverified audit claims dropped; 2 real-but-paradigm fixes held for Nathan's decision.
