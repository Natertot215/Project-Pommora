## Connections v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task ships as one green commit (paradigm decision #4: stub-and-progressively-replace; never batch-commit at branch end).

**Goal:** Ship working inline Connections — `[[Title]]`→Page and `{{Title}}`→Item — that parse, resolve by title, index into SQLite, navigate, and cascade on rename; `{{ }}` renders as a plain styled link placeholder, with the Item-Chip / dropdown / item-mechanics scaffolded for a later Figma-driven pass.

**Architecture:** Bodies are canonical (`[[ ]]` / `{{ }}` live in the Markdown body, title-only, no frontmatter mirror). A new derived `connections` SQLite table (one directed edge per link, nullable `target_id` for phantoms) is rebuilt by scanning bodies — cold-start in `IndexBuilder`, incrementally on every body-write CRUD call, immediately (no relaunch). Resolution is title-keyed; global per-kind title uniqueness (enforced in-app via an index query) keeps a bare title unambiguous. Rename cascades through `SchemaTransaction` (atomic, foreign-frontmatter-preserving). The MarkdownPM editor is render+input only — Pommora owns grammar, resolver, index, navigation, cascade.

**Tech Stack:** Swift 6 (strict concurrency, ExistentialAny), SwiftUI + AppKit, GRDB (SQLite), TextKit 2, the in-tree `MarkdownPM` package, Swift Testing (`@Suite`/`@Test`).

**Canonical "What":** `.claude/Features/Connections.md`. **Recon:** four source-verified agents (2026-06-05) — findings folded into the task notes below.

---

### Ground rules carried from the codebase

- **Build verification:** dispatch a background builder Agent running `xcodebuild test ... -only-testing:PommoraTests` (quirk #13 — no window-focus grab). ALWAYS confirm a non-zero executed test count (quirk #1: a filter that matches no `@Suite` no-ops to SUCCEEDED/0). Trust `xcodebuild`, not SourceKit squiggles (quirk #3).
- **Schema bump = full rebuild.** `PommoraIndex` has no `ALTER TABLE` path; bumping `currentSchemaVersion` deletes + recreates the DB and re-runs `IndexBuilder.populate`. Safe — the index holds no user data.
- **FK tolerance.** The index FK model is lenient (`context_links` has no FKs; `upsertPage`/`upsertItem` already swallow `SQLITE_CONSTRAINT`). The `connections` table carries NO FK on `source_id`/`target_id`, so a nullable/dangling `target_id` is structurally safe (no SQLite error-19 path).
- **One shared title normalization** (`ConnectionTitle.normalize` = trimmed + lowercased) backs uniqueness, phantom keys, and resolution so they never disagree.
- **Parallel-session caveat** (quirk #10): the working tree may carry unattributed changes — never revert them; surface and proceed on non-overlapping files.

### File Structure

**New files (Pommora app):**
- `Pommora/Pommora/Connections/ConnectionTitle.swift` — the single title-normalization function.
- `Pommora/Pommora/Connections/ConnectionScanner.swift` — pure body→`[ScannedConnection]` scan (`[[ ]]` + `{{ }}`).
- `Pommora/Pommora/Connections/ConnectionResolver.swift` — `PommoraConnectionResolver` (the injected `WikiLinkResolver` hitting the index by title), for both page and item links.
- `Pommora/Pommora/Connections/ConnectionCascade.swift` — rename-cascade service (rewrite referencing bodies atomically).

**New files (MarkdownPM package):**
- `External/MarkdownPM/Sources/MarkdownPM/Styling/MarkdownPMStyler+ItemLinks.swift` — `{{ }}` styler (plain-link placeholder).

**New files (Component Library / stubs):**
- `Pommora/Pommora/Properties/Chips/ItemChip.swift` — Item-Chip primitive stub (mirrors `ContextChip`).

**Modified (Pommora app):**
- `Index/IndexSchema.swift` — `connections` DDL + indexes + `pages`/`items` title indexes.
- `Index/PommoraIndex.swift` — `currentSchemaVersion` 7→8.
- `Index/IndexBuilder.swift` — `clearAllTables` + cold-start connection scan + `body` on `PageSnapshot`.
- `Index/IndexUpdater.swift` — `reconcileConnections` / `activateConnections` / `deactivateConnections`.
- `Index/IndexQuery.swift` — connection read queries + nexus-wide `titleExists` + `titleCandidates`.
- `Content/PageContentManager+CRUD.swift`, `Items/ItemContentManager+CRUD.swift` — nexus-wide uniqueness; body-write reconcile hooks; rename cascade hook; activate/deactivate.
- `Vaults/ReservedPropertyID.swift`, `ViewSettings/PropertyVisibilityPane.swift` — retire `_wikilinks`.
- `Pages/MarkdownEditorConfig.swift`, `Pages/PageEditorView.swift` — inject the resolver; wire click callbacks.
- `Pages/AppGlobals.swift` (read-only ref) — the `{{ }}`→Item-Window bridge target.

**Modified (MarkdownPM package):**
- `Services/WikiLinkService.swift` — LD-28: never emit `[[Name|id]]` on disk.
- `Parser/MarkdownToken.swift`, `Parser/MarkdownTokenizer.swift` — `.itemLink` token + `{{ }}` regex.
- `Styling/MarkdownPMStyler.swift` — call the new item-link styler.
- `Services/MarkdownPMServices.swift` — add `itemLinks` resolver slot.
- `TextView/NativeTextViewWrapper.swift`, `TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift` — `onItemLinkClick` callback + click routing by token kind.

---

## Phase A — Prerequisites (clear the runway)

### Task A1: Retire the dead `_wikilinks` reserved ID

**Files:**
- Modify: `Pommora/Pommora/Vaults/ReservedPropertyID.swift:24,34`
- Modify: `Pommora/Pommora/ViewSettings/PropertyVisibilityPane.swift:183` (comment only)
- Test: `Pommora/PommoraTests/Vaults/ReservedPropertyIDTests.swift`, `Pommora/PommoraTests/.../PropertiesPulldownTests.swift`

> Filter note (A1): the suite in `PropertiesPulldownTests.swift` is named `PropertiesPulldownTests` (WITH the `Tests` suffix) — use `-only-testing:PommoraTests/PropertiesPulldownTests`.

Recon (Agent 3): `_wikilinks` is purely subtractive — zero production read/write/decode. Removing it touches the constant, the `all` set, one stale comment, and three test assertions.

- [ ] **Step 1: Update the failing test first.** In `ReservedPropertyIDTests.swift`, change any assertion that `ReservedPropertyID.all` contains `_wikilinks` (or `.isReserved("_wikilinks")`) to assert it is ABSENT:

```swift
@Test func wikilinksIDIsRetired() {
    #expect(ReservedPropertyID.isReserved("_wikilinks") == false)
    #expect(ReservedPropertyID.all.contains("_wikilinks") == false)
}
```
Also delete the lines in `ReservedPropertyIDTests.swift:49-50` that reference `ReservedPropertyID.wikilinks` (compile error after the constant is removed), and remove the `_wikilinks` fixture row + fix the count assertion in `PropertiesPulldownTests.swift:101,108,114`.

- [ ] **Step 2: Run to verify fail.** Background builder: `-only-testing:PommoraTests/ReservedPropertyID` (the `@Suite` is named `"ReservedPropertyID"`, NOT the filename). Expected: FAIL (the constant still exists).
- [ ] **Step 3: Remove the constant + catalog entry.** In `ReservedPropertyID.swift` delete line 24 (`nonisolated static let wikilinks = "_wikilinks"`) and remove `wikilinks,` from the `all` set (line 34).
- [ ] **Step 4: Fix the stale comment.** In `PropertyVisibilityPane.swift:183` remove `_wikilinks` from the example list in the doc comment (leave `_status` etc.).
- [ ] **Step 5: Run to verify pass.** Background builder: full `-only-testing:PommoraTests`. Expected: PASS, non-zero count.
- [ ] **Step 6: Commit.** `refactor(connections): retire dead _wikilinks reserved ID`

> Filter note: use `-only-testing:PommoraTests/ReservedPropertyID` (matches the `@Suite("ReservedPropertyID")` name) for targeted runs on this task.

### Task A2: LD-28 — strip the id from on-disk wikilink storage

**Files:**
- Modify: `External/MarkdownPM/Sources/MarkdownPM/Services/WikiLinkService.swift:146-151`
- Test: `Pommora/PommoraTests/Pages/WikiLinkOnDiskGuardTests.swift` (currently `.disabled`)

Recon (all four agents): `makeStorageState` emits `[[Name|id]]` when the text storage carries `.wikiLinkID`. The spec mandates title-only on disk. Without this strip, wiring a real resolver corrupts every saved body. This is the DEC-1 target.

- [ ] **Step 1: Enable the existing guard test.** The test `dec1TargetNoIdOnDisk` already exists in `WikiLinkOnDiskGuardTests.swift:46` with a `.disabled(...)` trait (it was written speculatively and left disabled). Remove ONLY the `.disabled(...)` trait — do NOT add a new test. The test body already asserts the disk form is title-only.

- [ ] **Step 2: Run to verify fail.** Builder: `-only-testing:PommoraTests/WikiLinkOnDiskGuard` (the `@Suite` is named `"WikiLinkOnDiskGuard"`, NOT the filename). Expected: FAIL (`out == "[[Alpha|01HZ...]]"`).
- [ ] **Step 3: Strip the id branch.** In `makeStorageState`, replace the id-bearing branch (lines 146-151) so it ALWAYS writes the bare form:

```swift
// LD-28: Pommora stores wiki-links title-only on disk ([[Name]]). The opaque
// id is never persisted — resolution is title-keyed via the index. We keep
// reading `.wikiLinkID` above only to preserve in-session metadata; it never
// reaches storage.
let storageFragment = "[[\(name)]]"
```
Delete the `if let linkID, !linkID.isEmpty { ... }` branch entirely; `linkID` may still populate the returned `metadata` map (in-memory only).

- [ ] **Step 4: Run to verify pass.** Builder: full `-only-testing:PommoraTests`. Expected: PASS, non-zero count.
- [ ] **Step 5: Commit.** `fix(connections): strip embedded id from on-disk wikilink storage (LD-28/DEC-1)`

> Filter note: use `-only-testing:PommoraTests/WikiLinkOnDiskGuard` (matches `@Suite("WikiLinkOnDiskGuard")`) for targeted runs on this task.

---

## Phase B — Connections index (graph-ready data foundation)

> **Test fixtures (shared pattern — B3/B4/B5/B6/C1/D1):** Build the index via the PROVEN existing pattern: `TempNexus.make()` → `PommoraIndex.open(at: nexus.rootURL)` → `IndexUpdater(index)` / `IndexQuery(index)` (used by `IndexUpdaterTests`/`LoadAllIndexSyncTests`). RESOLUTION tests MUST pre-register the target row (`updater.upsertPage`/`upsertItem`) BEFORE asserting resolution — otherwise every connection comes back phantom. D1 cascade tests MUST use a real on-disk nexus (TempNexus + real `.md` files) because `ConnectionCascade.run` reads/writes files via `entityContainer`→URL.

### Task B1: `connections` table, indexes, schema bump

**Files:**
- Modify: `Pommora/Pommora/Index/IndexSchema.swift`
- Modify: `Pommora/Pommora/Index/PommoraIndex.swift:63`
- Modify: `Pommora/Pommora/Index/IndexBuilder.swift:479-491`
- Test: `Pommora/PommoraTests/Index/ConnectionSchemaTests.swift` (new)

- [ ] **Step 1: Write the failing schema test.**

```swift
import GRDB
import Testing
@testable import Pommora

@Suite struct ConnectionSchemaTests {
    @Test func connectionsTableAndIndexesExist() throws {
        let q = try DatabaseQueue()
        try q.write { try IndexSchema.apply(to: $0) }
        try q.read { db in
            #expect(try db.tableExists("connections"))
            // Use pragma_table_info (SQLite-guaranteed; db.columns(in:) not proven in this GRDB build).
            let cols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('connections')")
            for c in ["id","source_id","source_kind","target_id","target_kind",
                      "target_title","surface","multiplicity","weight","resolved","modified_at"] {
                #expect(cols.contains(c))
            }
        }
    }
    @Test func schemaVersionIsEight() { #expect(PommoraIndex.currentSchemaVersion == 8) }
}
```

- [ ] **Step 2: Run to verify fail.** Builder: `-only-testing:PommoraTests/ConnectionSchemaTests`. Expected: FAIL (no table / version 7).
- [ ] **Step 3: Add the DDL.** In `IndexSchema.swift` add to `apply(to:)` (after `contextLinksDDL`): `try db.execute(sql: connectionsDDL)`. Add the table + index DDL:

```swift
private static let connectionsDDL = """
    CREATE TABLE IF NOT EXISTS connections (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_kind TEXT NOT NULL,          -- "page" | "item"
        target_id TEXT,                     -- NULL while phantom (unresolved)
        target_kind TEXT NOT NULL,          -- "page" (from [[ ]]) | "item" (from {{ }})
        target_title TEXT NOT NULL,         -- normalized (trimmed+lowercased) — resolution key
        surface TEXT NOT NULL,              -- "page_body" | "item_body"
        multiplicity INTEGER NOT NULL DEFAULT 1,
        weight REAL NOT NULL DEFAULT 1.0,
        resolved INTEGER NOT NULL DEFAULT 0,
        modified_at TEXT NOT NULL
    );
    """
```
Append to `indexesDDL`:
```sql
CREATE INDEX IF NOT EXISTS idx_connections_source_id ON connections(source_id);
CREATE INDEX IF NOT EXISTS idx_connections_target_id ON connections(target_id);
CREATE INDEX IF NOT EXISTS idx_connections_target_title ON connections(target_kind, target_title);
CREATE INDEX IF NOT EXISTS idx_pages_title ON pages(title COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_items_title ON items(title COLLATE NOCASE);
```

- [ ] **Step 4: Bump the schema version.** In `PommoraIndex.swift:63` set `currentSchemaVersion = 8` and add the version-history comment block (match the v2–v7 style):

```swift
// v8 (2026-06-05): add the `connections` table (inline-link edges scanned from
// Page/Item bodies — [[ ]]/{{ }}) + idx_connections_* + title indexes on
// pages/items. Net-new derived data; bumping 7 → 8 forces one rebuild so
// existing DBs gain the table and IndexBuilder backfills connections from
// on-disk bodies. No user data at risk (regeneratable index).
```

- [ ] **Step 5: Add to `clearAllTables`.** In `IndexBuilder.swift:479` add as the first statement: `try db.execute(sql: "DELETE FROM connections")`.
- [ ] **Step 6: Run to verify pass.** Builder: `-only-testing:PommoraTests/ConnectionSchemaTests`. Expected: PASS.
- [ ] **Step 7: Commit.** `feat(connections): add connections table + indexes (schema v8)`

### Task B2: `ConnectionTitle` + `ConnectionScanner`

**Files:**
- Create: `Pommora/Pommora/Connections/ConnectionTitle.swift`
- Create: `Pommora/Pommora/Connections/ConnectionScanner.swift`
- Test: `Pommora/PommoraTests/Connections/ConnectionScannerTests.swift` (new)

- [ ] **Step 1: Write the failing test.**

```swift
import Testing
@testable import Pommora

@Suite struct ConnectionScannerTests {
    @Test func scansBothSyntaxesNormalizedAndCounted() {
        let body = "See [[ Alpha ]] and {{Beta}}, again [[alpha]]. Image ![[pic]] ignored. `[[code]]` skipped not-required-v1."
        let found = ConnectionScanner.scan(body: body)
        // [[Alpha]] appears twice (normalized "alpha") → multiplicity 2, page kind.
        let alpha = found.first { $0.normalizedTitle == "alpha" && $0.syntax == .page }
        #expect(alpha?.multiplicity == 2)
        // {{Beta}} → item kind, multiplicity 1.
        #expect(found.contains { $0.normalizedTitle == "beta" && $0.syntax == .item })
        // ![[pic]] image embed is NOT a connection.
        #expect(found.contains { $0.normalizedTitle == "pic" } == false)
    }
    @Test func normalizeTrimsAndLowercases() {
        #expect(ConnectionTitle.normalize("  Foo Bar ") == "foo bar")
    }
}
```

- [ ] **Step 2: Run to verify fail.** Expected: FAIL (types undefined).
- [ ] **Step 3: Implement `ConnectionTitle`.**

```swift
import Foundation

/// The single normalization for connection titles — used by the scanner, the
/// phantom key, resolution, and uniqueness so they never disagree (spec:
/// "one shared normalization"). Trimmed + case-folded.
enum ConnectionTitle {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum ConnectionSyntax: String, Sendable, Equatable {
    case page   // [[ ]]
    case item   // {{ }}
    /// The target entity kind this syntax resolves to, as stored in `target_kind`.
    var targetKind: String { self == .page ? "page" : "item" }
}

struct ScannedConnection: Sendable, Equatable {
    let normalizedTitle: String
    let syntax: ConnectionSyntax
    let multiplicity: Int
}
```

- [ ] **Step 4: Implement `ConnectionScanner`.**

```swift
import Foundation

/// Pure body scanner: extracts `[[Title]]` (Page) and `{{Title}}` (Item)
/// connections from a Markdown body. Title-only; a legacy `[[Name|id]]` pipe
/// (pre-LD-28 bodies) is tolerated — the id segment is dropped. `![[ ]]` image
/// embeds are excluded. Repeats to the same (syntax,title) aggregate into
/// `multiplicity`. No deps — runs off-actor in index write closures.
enum ConnectionScanner {
    // `(?<!!)` excludes image embeds `![[ ]]`. Title = up to `|` or close.
    // `internal` (not private) so ConnectionRewriter (D1) can reuse them — no regex duplication.
    internal static let pageRegex = try! NSRegularExpression(
        pattern: #"(?<!!)\[\[([^\[\]\r\n|]+)(?:\|[^\]\r\n]*)?\]\]"#)
    internal static let itemRegex = try! NSRegularExpression(
        pattern: #"\{\{([^{}\r\n|]+)(?:\|[^}\r\n]*)?\}\}"#)

    static func scan(body: String) -> [ScannedConnection] {
        var counts: [ConnectionSyntax: [String: Int]] = [.page: [:], .item: [:]]
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        func collect(_ regex: NSRegularExpression, _ syntax: ConnectionSyntax) {
            for m in regex.matches(in: body, options: [], range: full) {
                let raw = ns.substring(with: m.range(at: 1))
                let key = ConnectionTitle.normalize(raw)
                guard !key.isEmpty else { continue }
                counts[syntax, default: [:]][key, default: 0] += 1
            }
        }
        collect(pageRegex, .page)
        collect(itemRegex, .item)
        return counts.flatMap { syntax, m in
            m.map { ScannedConnection(normalizedTitle: $0.key, syntax: syntax, multiplicity: $0.value) }
        }
    }
}
```

- [ ] **Step 5: Run to verify pass.** Expected: PASS. (Note: code-block exclusion — `` `[[code]]` `` — is NOT required for v1 per spec scope; the test asserts only image-embed exclusion.)
- [ ] **Step 6: Commit.** `feat(connections): body scanner + shared title normalization`

### Task B3: `IndexUpdater.reconcileConnections` + activate/deactivate

**Files:**
- Modify: `Pommora/Pommora/Index/IndexUpdater.swift`
- Test: `Pommora/PommoraTests/Index/ConnectionReconcileTests.swift` (new)

Mirrors the proven `reconcileContextLinks` shape (delete-by-source, re-insert). Resolution within the same write closure: a title resolves only if EXACTLY one entity of the target kind holds it (0 or >1 → phantom, honoring "duplicates stay unresolved").

> **Swift 6 statics note:** any new date/encoder statics added for connection methods must be `nonisolated(unsafe)` to match `IndexBuilder.isoFormatter` (`IndexBuilder.swift:772`). The existing `nowISO()` and `ULID` helpers are already in scope and safe — GRDB serializes writes so `@Sendable` write-closure calls are fine without additional isolation.

- [ ] **Step 1: Write the failing test** (resolved + phantom + self-skip + multiplicity):

```swift
@Suite struct ConnectionReconcileTests {
    // helper builds an index with a page "Target" present
    @Test func resolvesExistingAndPhantomsMissing() throws { /* … insert page Target;
        reconcileConnections(source S, body "[[Target]] [[Ghost]] [[Target]]");
        expect 2 rows: Target resolved (target_id set, multiplicity 2),
        Ghost phantom (target_id NULL, resolved 0). */ }
    @Test func skipsSelfConnection() throws { /* page "Self" body "[[Self]]" → 0 rows. */ }
}
```

- [ ] **Step 2: Run to verify fail.** Expected: FAIL (method undefined).
- [ ] **Step 3: Implement the three methods** on `IndexUpdater`:

```swift
// MARK: - Connections (body-scanned inline links)

/// Re-index every `[[ ]]`/`{{ }}` in `body` for `sourceID`. Delete-then-insert
/// (mirrors reconcileContextLinks). A target resolves only when EXACTLY one
/// entity of its kind holds the title (0 / >1 → phantom). Self-links skipped.
func reconcileConnections(sourceID: String, sourceKind: String, sourceTitle: String, body: String) throws {
    let scanned = ConnectionScanner.scan(body: body)
    let selfKey = ConnectionTitle.normalize(sourceTitle)
    let surface = sourceKind == "page" ? "page_body" : "item_body"
    try index.dbQueue.write { db in
        try db.execute(sql: "DELETE FROM connections WHERE source_id = ?", arguments: [sourceID])
        for c in scanned {
            // Self-connection guard: same kind + same title = the source itself.
            if c.syntax.targetKind == sourceKind && c.normalizedTitle == selfKey { continue }
            let table = c.syntax == .page ? "pages" : "items"
            let matches = try String.fetchAll(
                db, sql: "SELECT id FROM \(table) WHERE title = ? COLLATE NOCASE", arguments: [c.normalizedTitle])
            let targetID: String? = matches.count == 1 ? matches[0] : nil
            try db.execute(
                sql: """
                    INSERT INTO connections
                        (id, source_id, source_kind, target_id, target_kind, target_title,
                         surface, multiplicity, weight, resolved, modified_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1.0, ?, ?)
                    """,
                arguments: [ULID.generate(), sourceID, sourceKind, targetID, c.syntax.targetKind,
                            c.normalizedTitle, surface, c.multiplicity, targetID != nil ? 1 : 0, nowISO()])
        }
    }
}

/// A new/renamed entity's title appeared → activate matching phantom edges.
/// Guards against adopted-duplicate titles: only activates when EXACTLY ONE
/// entity of `targetKind` currently holds `targetTitle` in the DB (0 or >1 →
/// phantom stays phantom, so an adopted dup never wrongly lights edges meant
/// for a deleted dup). `targetKind` selects the pages vs items table.
func activateConnections(targetID: String, targetKind: String, targetTitle: String) throws {
    let table = targetKind == "page" ? "pages" : "items"
    let normalized = ConnectionTitle.normalize(targetTitle)
    try index.dbQueue.write { db in
        let count = try Int.fetchOne(
            db,
            sql: "SELECT count(*) FROM \(table) WHERE title = ? COLLATE NOCASE",
            arguments: [normalized]) ?? 0
        guard count == 1 else { return }   // 0 or >1 holders → leave phantoms alone
        try db.execute(
            sql: """
                UPDATE connections SET target_id = ?, resolved = 1, modified_at = ?
                WHERE target_kind = ? AND target_title = ? COLLATE NOCASE AND target_id IS NULL
                """,
            arguments: [targetID, nowISO(), targetKind, normalized])
    }
}

/// A permanently-deleted target → revert its inbound edges to phantom (inert).
func deactivateConnections(targetID: String) throws {
    try index.dbQueue.write { db in
        try db.execute(
            sql: "UPDATE connections SET target_id = NULL, resolved = 0, modified_at = ? WHERE target_id = ?",
            arguments: [nowISO(), targetID])
    }
}
```
(`nowISO()` and `ULID` are already in scope in this file.)

- [ ] **Step 4: Run to verify pass.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(connections): reconcile/activate/deactivate index writes`

### Task B4: `IndexQuery` read surface

**Files:**
- Modify: `Pommora/Pommora/Index/IndexQuery.swift`
- Test: `Pommora/PommoraTests/Index/ConnectionQueryTests.swift` (new)

- [ ] **Step 1: Write the failing test** — assert `outgoingConnections`, `incomingConnections` (backlinks), `titleExists(kind:excludingID:)` (nexus-wide), and `titleCandidates` (lists ALL matches for the dup-tolerant picker).
- [ ] **Step 2: Run to verify fail.** Expected: FAIL.
- [ ] **Step 3: Implement** (mirrors `incomingContextLinks`'s reverse-join + the `EntityKind` string map):

```swift
// MARK: - Connections

struct ConnectionEdge: Sendable, Equatable {
    let id: String
    let sourceID: String; let sourceKind: EntityKind
    let targetID: String?; let targetKind: EntityKind
    let targetTitle: String
    let multiplicity: Int
    let resolved: Bool
}

/// Outgoing edges authored in `sourceID`'s body.
func outgoingConnections(sourceID: String) async throws -> [ConnectionEdge] { /* SELECT … WHERE source_id = ? */ }

/// Inbound edges (backlinks) targeting `targetID` — the same rows queried in
/// reverse. Powers the future connections panel; reads straight from the index.
func incomingConnections(targetID: String) async throws -> [ConnectionEdge] { /* SELECT … WHERE target_id = ? */ }

/// Nexus-wide per-kind title existence — the uniqueness check (excludes the
/// entity being renamed). `kind` is .page or .item.
///
/// Invariant: titles are stored normalized (trimmed+lowercased via
/// `ConnectionTitle.normalize`) and queried with `COLLATE NOCASE` indexes —
/// this is the SINGLE normalization used everywhere (scanner, phantom key,
/// resolution). `titleExists` uses the same normalize call so the needle
/// always matches the stored form.
func titleExists(_ title: String, kind: EntityKind, excludingID: String? = nil) async throws -> Bool {
    let table = kind == .page ? "pages" : "items"
    return try await index.dbQueue.read { db in
        let needle = ConnectionTitle.normalize(title)
        let rows = try String.fetchAll(
            db, sql: "SELECT id FROM \(table) WHERE title = ? COLLATE NOCASE", arguments: [needle])
        return rows.contains { $0 != excludingID }
    }
}

/// All entities of `kind` whose title matches `query` (prefix, case-insensitive)
/// — autocomplete + the dup-tolerant "choose either" picker. Returns every
/// match (so two same-titled adopted entities both surface).
func titleCandidates(matching query: String, kind: EntityKind, limit: Int = 20) async throws -> [EntityRef] { /* SELECT id,title,icon … WHERE title LIKE ?||'%' COLLATE NOCASE LIMIT ? */ }
```
(Write the full bodies following the `incomingContextLinks` pattern: a `read` closure, `Row.fetchAll`, the inline `kindFromString` map for `source_kind`/`target_kind`.)

- [ ] **Step 4: Run to verify pass.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(connections): index read queries (outgoing/incoming/titleExists/candidates)`

### Task B5: Cold-start body scan in `IndexBuilder`

**Files:**
- Modify: `Pommora/Pommora/Index/IndexBuilder.swift`
- Test: extend `ConnectionSchemaTests` / new `ConnectionRebuildTests.swift`

A full rebuild must backfill connections from on-disk bodies — both Pages and Items (item bodies are scanned even though they're not yet in-app editable, so the graph data stays complete). `ItemSnapshot.description` already exists; `PageSnapshot` needs a `body`.

> **Cold-start resolution quality (quirk #14):** on a freshly-adopted nexus, type/collection rows for non-CRUD vaults may not be indexed at cold-start scan time, so some links resolve as phantom; they self-heal on the next CRUD body-write or after `loadAll` syncs the DB. `insertConnections` is best-effort resolution — acceptable, since the index is regeneratable.

- [ ] **Step 1: Write the failing test** — populate a nexus with a page whose body is `[[Other]]`, rebuild, assert a `connections` row exists.
- [ ] **Step 2: Run to verify fail.** Expected: FAIL (no connection rows after rebuild).
- [ ] **Step 3: Add `body` to `PageSnapshot`.** Add `let body: String` (line ~28) and populate in `collectPagesInFolder` from `pf.body` (PageFile carries the body).
- [ ] **Step 4: Add an `insertConnections` pass.** Mirror `insertTierContextLinks` — a new pass iterating page/item snapshots, calling a shared row-insert that uses `ConnectionScanner.scan` + the same single-match resolution as `reconcileConnections`. Call it from `populate`'s write closure (after `insertContexts`/`insertTierContextLinks`, so target entity rows already exist for resolution):

```swift
try clearAllTables(db)
insertPageTypes(db, snapshot: snapshot)
insertItemTypes(db, snapshot: snapshot)
insertAgendaTasks(db, snapshot: snapshot)
insertAgendaEvents(db, snapshot: snapshot)
insertContexts(db, snapshot: snapshot)
insertTierContextLinks(db, snapshot: snapshot)
insertConnections(db, snapshot: snapshot)   // ← new; resolves against rows inserted above
```
`insertConnections` wraps each row in `attemptInsert` (resilient — one bad row never aborts the rebuild).

- [ ] **Step 5: Run to verify pass.** Expected: PASS.
- [ ] **Step 6: Commit.** `feat(connections): cold-start body scan in IndexBuilder rebuild`

### Task B6: Wire reconcile into body-write CRUD + activate/deactivate

**Files:**
- Modify: `Pommora/Pommora/Content/PageContentManager+CRUD.swift`
- Modify: `Pommora/Pommora/Items/ItemContentManager+CRUD.swift`
- Test: `Pommora/PommoraTests/Content/ConnectionLiveUpdateTests.swift` (new)

This is the live-visibility hook: every in-app body write updates the index in the same operation (no relaunch). Page bodies flow through `updatePage(body:)`; item bodies through the item description-update path (`ItemContentManager+CRUD.swift:378` region) and `item.description`.

- [ ] **Step 1: Write the failing test** — create page A and target page T; edit A's body to `[[T]]`; assert `outgoingConnections(A)` immediately returns a resolved edge (no rebuild). Then create a new page "Ghost-Target" matching a prior phantom and assert it activates; delete it and assert inbound edges deactivate.
- [ ] **Step 2: Run to verify fail.** Expected: FAIL.
> **Both `updatePage` overloads:** BOTH `updatePage` overloads need the `reconcileConnections` hook — the collection-scoped overload (~L169) AND the type-root overload (~L328). Both write the body; both must update the connection index.

- [ ] **Step 3: Reconcile on page body write.** In `updatePage(_:body:in:vault:)`, after the successful `pageFile.save` + `upsertPage`, add:

```swift
if let updater = indexUpdater {
    do { try updater.reconcileConnections(sourceID: page.id, sourceKind: "page",
                                          sourceTitle: page.title, body: body) }
    catch { self.pendingError = error }
}
```
In `createPage`, BOTH `reconcileConnections(sourceID:sourceKind:sourceTitle:body:"")` AND `activateConnections(targetID: meta.id, targetKind: "page", targetTitle: name)` are MANDATORY — both are required for live-visibility (the first clears any stale outgoing edges from the slot; the second makes any pre-existing phantom `[[name]]` go live immediately). Do NOT skip either.

> Non-atomicity note: `upsertPage` + `reconcileConnections` are two separate `dbQueue.write` calls (not wrapped in a single transaction). This is acceptable — the index is regeneratable and a mid-flight crash leaves a briefly stale connection count, not lost user data.

- [ ] **Step 4: Reconcile on item body write + activate.** The item reconcile hook indexes item bodies wherever they are written — adoption, migration, external reconcile — NOT an in-app authoring path (item bodies stay display-only in v1; there is no in-app item-body editor). In practice this means the hook fires via `ItemContentManager+CRUD.swift`'s description-update path, which is called from adoption/reconcile flows. In the item description-update method, after persisting `item.description`, call `reconcileConnections(sourceID: item.id, sourceKind: "item", sourceTitle: item.title, body: item.description)`. In `createItem`, `activateConnections(targetID:targetKind:"item",targetTitle:)` is also MANDATORY.
- [ ] **Step 5: Deactivate on permanent delete, clean outgoing edges, and re-activate if the deleted title now has a unique survivor.** In `deletePage`/`deleteItem` (which already call `deletePage`/`deleteItem` on the index), add three operations co-located in the same delete path:
  1. `try updater.deactivateConnections(targetID: id)` — reverts inbound edges to phantom (NULLs `target_id`).
  2. `try db.execute(sql: "DELETE FROM connections WHERE source_id = ?", arguments: [id])` — cleans outgoing edges authored by the deleted entity. Co-locate alongside the existing `DELETE FROM context_links WHERE source_id = ?` in `IndexUpdater.deletePage`/`deleteItem` (same transaction).
  3. **`try updater.reactivateIfNowUnique(targetKind:title:)`** — after deactivation, if the deleted entity's title now has EXACTLY ONE remaining holder, activate that survivor's inbound phantoms (spec: activation is automatic the moment a matching entity exists; this resolves previously-ambiguous adopted duplicates). Add this `IndexUpdater` helper:

```swift
/// After a delete, if the deleted title now has exactly ONE holder, activate
/// that survivor's inbound phantoms (spec: activation is automatic the moment
/// a matching entity exists — covers resolving a previously-ambiguous adopted dup).
func reactivateIfNowUnique(targetKind: String, title: String) throws {
    try index.dbQueue.write { db in
        let table = targetKind == "page" ? "pages" : "items"
        let ids = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE title = ? COLLATE NOCASE",
                                      arguments: [ConnectionTitle.normalize(title)])
        guard ids.count == 1 else { return }
        try db.execute(sql: """
            UPDATE connections SET target_id = ?, resolved = 1, modified_at = ?
            WHERE target_kind = ? AND target_title = ? COLLATE NOCASE AND target_id IS NULL
            """, arguments: [ids[0], nowISO(), targetKind, ConnectionTitle.normalize(title)])
    }
}
```

Call in `deletePage` as `try updater.reactivateIfNowUnique(targetKind: "page", title: page.title)` and in `deleteItem` as `try updater.reactivateIfNowUnique(targetKind: "item", title: item.title)`.

Add a test covering the full adoption-dup lifecycle: create two items both titled "Dup", a body with `{{Dup}}` (phantom — two holders), delete one → assert the survivor's inbound phantom activates (resolved edge with the survivor's id).

  (`Filesystem.moveToTrash` is a permanent removal from the live nexus for v1 — restore-reactivation is deferred, Task F-note.)
- [ ] **Step 6: Run to verify pass.** Expected: PASS.
- [ ] **Step 7: Commit.** `feat(connections): live index updates on body write + activate/deactivate`

---

## Phase C — Nexus-wide per-kind title uniqueness

### Task C1: Enforce nexus-wide uniqueness on create/rename

**Files:**
- Modify: `Pommora/Pommora/Content/PageContentManager+CRUD.swift:64,111` (+ create/rename for items at `ItemContentManager+CRUD.swift:85,126,182,234,273,326`)
- Test: `Pommora/PommoraTests/Content/NexusWideUniquenessTests.swift` (new)

Recon (Agents 1/3/4): `NameCollisionValidator` stays for container-scoped checks (Vaults/Types/Collections). The new nexus-wide check is index-backed (`titleExists`) so it works without all vaults loaded. In-app create/rename to a duplicate is rejected; adoption is NOT guarded (duplicates tolerated, per Nathan) — the picker surfaces both (Task E5).

- [ ] **Step 1: Write the failing test** — create page "X" in vault V1; attempt to create page "X" in a DIFFERENT vault V2 → expect `PageCRUDError.duplicateTitle`. Same for Items. Assert a Page and an Item MAY share a title (no error).
- [ ] **Step 2: Run to verify fail.** Expected: FAIL (per-collection check lets cross-vault dup through).
- [ ] **Step 3: Add the nexus-wide guard helper** on each manager.

> IMPORTANT: `indexQuery` does NOT exist as a stored property on `PageContentManager`/`ItemContentManager` — they hold only `indexUpdater: IndexUpdater?`, and `IndexUpdater` has `let index: PommoraIndex`. Derive the query inline from `indexUpdater.index`; do NOT add a new stored property.

```swift
/// Nexus-wide per-kind uniqueness (Connections invariant). Index-backed so it
/// sees every vault, loaded or not. Container-scoped NameCollisionValidator
/// still runs for the in-memory sibling fast-path; this is the authority.
private func enforceNexusWideTitleUniqueness(_ title: String, excludingID: String?) async throws {
    guard let updater = indexUpdater else { return }   // index optional in some test harnesses
    let query = IndexQuery(updater.index)
    if try await query.titleExists(title, kind: .page, excludingID: excludingID) {
        throw PageCRUDError.duplicateTitle
    }
}
```
(Item side: `kind: .item`, `ItemCRUDError.duplicateTitle`.)

> TOCTOU note: `await titleExists` opens a suspension gap before the write — two concurrent creates with the same title could both pass the check before either write commits. Acceptable for single-user / single-`@MainActor` v1. Do NOT add locking.

- [ ] **Step 4: Call it in create + rename.** In `createPage` after the existing `enforceTitleUniqueness(name, among: existing)` add `try await enforceNexusWideTitleUniqueness(name, excludingID: nil)`. In `renamePage` add `try await enforceNexusWideTitleUniqueness(newName, excludingID: page.id)`. Mirror in the six Item call sites.
- [ ] **Step 5: Run to verify pass.** Expected: PASS.
- [ ] **Step 6: Commit.** `feat(connections): nexus-wide per-kind title uniqueness on create/rename`

---

## Phase D — Rename cascade

### Task D1: `ConnectionCascade` — rewrite referencing bodies atomically

**Files:**
- Create: `Pommora/Pommora/Connections/ConnectionCascade.swift`
- Modify: `Pommora/Pommora/Content/PageContentManager+CRUD.swift` (`renamePage`), `Items/ItemContentManager+CRUD.swift` (rename)
- Test: `Pommora/PommoraTests/Connections/ConnectionCascadeTests.swift` (new)

When a target is renamed, every body that references its old title is rewritten (`[[Old]]`→`[[New]]`, `{{Old}}`→`{{New}}`) via `SchemaTransaction` (atomic — all-or-nothing; on failure the file rename is reverted). Foreign frontmatter is preserved because each body is re-encoded through the same `PageFile`/`Item` save path. The cascade is targeted (driven by `incomingConnections`), not a full scan.

- [ ] **Step 1: Write the failing test** — page A body `[[Target]]`, item B body `[[Target]]`; rename page "Target"→"Renamed"; assert both bodies now read `[[Renamed]]` on disk and the index edges still resolve. Add a failure-injection case asserting the file rename is reverted if a body rewrite fails.
- [ ] **Step 2: Run to verify fail.** Expected: FAIL.
- [ ] **Step 3: Implement `ConnectionRewriter` + `ConnectionCascade`.**

> FILE LOCATION: `ConnectionCascade` is self-contained. Construct it with the nexus `rootURL` + `IndexQuery(indexUpdater.index)` (derived inline, no stored property). Resolve each source's file URL via the public `IndexQuery.entityContainer(id:kind:)` → `NexusPaths` (the EntityContainer titles derive the folder URL).

> REGEXES: `ConnectionScanner.pageRegex`/`itemRegex` are already `internal static let` (shipped that way in B2) — `ConnectionRewriter` reuses them directly; no visibility change needed here.

Add `ConnectionRewriter` to `ConnectionCascade.swift` (same file is fine, or split — implementer's choice):

```swift
enum ConnectionRewriter {
    /// Replace every [[oldTitle]] / {{oldTitle}} (case-insensitive, exact
    /// normalized-title match; legacy [[oldTitle|id]] tolerated) with newTitle.
    /// Only the matching syntax is touched.
    static func rewrite(body: String, oldTitle: String, newTitle: String, syntax: ConnectionSyntax) -> String {
        let oldKey = ConnectionTitle.normalize(oldTitle)
        let (open, close) = syntax == .page ? ("[[", "]]") : ("{{", "}}")
        let regex = syntax == .page ? ConnectionScanner.pageRegex : ConnectionScanner.itemRegex
        let ns = body as NSString
        let result = NSMutableString(string: body)
        for m in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).reversed() {
            let title = ns.substring(with: m.range(at: 1))
            guard ConnectionTitle.normalize(title) == oldKey else { continue }
            result.replaceCharacters(in: m.range, with: "\(open)\(newTitle)\(close)")
        }
        return result as String
    }
}
```

`ConnectionCascade` sketch:

```swift
/// Rewrites every body that links a renamed target. Atomic via SchemaTransaction;
/// the caller reverts the target's own file-rename if this throws.
struct ConnectionCascade {
    let rootURL: URL
    let indexQuery: IndexQuery
    /// Returns the set of source ids whose bodies changed (so the caller can
    /// reconcile their connection rows + refresh in-memory caches).
    func run(targetID: String, oldTitle: String, newTitle: String,
             targetSyntax: ConnectionSyntax) async throws -> [String] {
        let inbound = try await indexQuery.incomingConnections(targetID: targetID)
        guard !inbound.isEmpty else { return [] }
        let txn = SchemaTransaction()
        var touched: [String] = []
        for edge in inbound {
            // 1. Resolve source file URL via IndexQuery.entityContainer(id:kind:) → NexusPaths.
            // 2. Load PageFile/Item (preserving foreign frontmatter).
            // 3. ConnectionRewriter.rewrite(body:oldTitle:newTitle:syntax:).
            // 4. Re-encode through AtomicYAMLMarkdown.encode(... preservingFrom:).
            // 5. txn.stage(payload:to:url).
            touched.append(edge.sourceID)
        }
        try txn.commit()    // throws → caller reverts the rename; index untouched
        return touched      // caller calls reconcileConnections for each touched source
    }
}
```

Per-source `entityContainer` is one async read each (N reads for N inbound) — accepted; mirrors `unlinkTier`.

- [ ] **Step 4: Hook into ALL FOUR rename overloads.** There are TWO `renamePage` overloads in `PageContentManager+CRUD.swift` (the `in: collection` overload and the vault-root variant ~line 258) and TWO `renameItem` overloads in `ItemContentManager+CRUD.swift`. The cascade MUST be patched into ALL FOUR.

> ORDERING (critical): the cascade runs AFTER `Filesystem.renameFile` succeeds but BEFORE `indexUpdater.upsertPage` (which runs at `PageContentManager+CRUD.swift:123`). On cascade failure: revert the file rename (index is untouched since `upsertPage` hasn't run yet) and rethrow the cascade error directly. `RenameAtomicityError` is a STRUCT `{ saveError, revertError }` with NO `.cascadeFailed` case — do NOT use it here. If the revert also throws, surface both errors via a new `PageCRUDError.cascadeFailed(underlying:)` case (mirror: `ItemCRUDError.cascadeFailed(underlying:)`). Do NOT use `try?` to silence the revert; it must be a hard throw.

> **Rename phantom-window (critical):** per-source `reconcileConnections` in the cascade runs BEFORE `upsertPage` re-indexes the renamed entity's new title, so just-rewritten `[[NewName]]`/`{{NewName}}` edges briefly resolve to 0 rows (phantom window). Fix: in ALL FOUR rename overloads, AFTER `upsertPage` runs (entity now indexed under the new title), call `activateConnections(targetID: <entityID>, targetKind: "page"/"item", targetTitle: newName)` to resolve the phantom rows the cascade just created.

```swift
// After Filesystem.renameFile succeeds, BEFORE upsertPage:
if let updater = indexUpdater {
    let cascade = ConnectionCascade(rootURL: nexusRootURL, indexQuery: IndexQuery(updater.index))
    do {
        let touched = try await cascade
            .run(targetID: page.id, oldTitle: page.title, newTitle: newName, targetSyntax: .page)
        for sid in touched { /* reconcileConnections for each touched source */ }
    } catch let cascadeError {
        do {
            try Filesystem.renameFile(from: newURL, to: page.url)   // revert (NOT try?)
            throw cascadeError   // revert succeeded — rethrow cascade error directly
        } catch {
            // Revert also failed — surface both via cascadeFailed
            throw PageCRUDError.cascadeFailed(underlying: cascadeError)
        }
    }
}
// upsertPage runs here (after cascade succeeds)
// AFTER upsertPage — resolve the phantom window the cascade created:
try updater.activateConnections(targetID: page.id, targetKind: "page", targetTitle: newName)
```
Mirror in both Item rename overloads with `targetSyntax: .item` and `targetKind: "item"`.

- [ ] **Step 5: Run to verify pass.** Expected: PASS.
- [ ] **Step 6: Commit.** `feat(connections): mandatory atomic rename cascade`

> **Accepted (Nathan, 2026-06-05):** cascade need not be instantaneous — no coordination primitive against the editor's ~300ms debounced save; a rare sub-second overlap is acceptable. Do NOT build locking here.

### Task D2: Refresh pinned/recents titles on rename

**Files:**
- Modify: `renamePage` / item rename; `Pommora/Pommora/NavDropdown/PinnedManager.swift`, `RecentsManager`
- Test: `Pommora/PommoraTests/NavDropdown/RenamePinRefreshTests.swift` (new)

Recon (Agent 4): `PinnedManager`/`RecentsManager` store a denormalized `EntityStateRef.title`; rename never updates it (a known stale-title bug). The cascade work touches the same rename path — fix it here.

- [ ] **Step 1: Write the failing test** — pin page "Old"; rename to "New"; assert the pinned entry's title is "New".
- [ ] **Step 2: Run to verify fail.** Expected: FAIL.
- [ ] **Step 3: Add `updateTitle(for:id:to:)` on both managers.** `PinnedManager.entries` is `private(set)` and `EntityStateRef.==` is `(kind,id)` only (title is a denormalized cache, NOT part of equality). Add a dedicated mutating method on BOTH `PinnedManager` and `RecentsManager`:

```swift
// NOTE: EntityStateRef.kind is a String (not EntityKind) — compare with == directly.
// Callers pass "page" or "item" (or entityKind.rawValue).
func updateTitle(for kind: String, id: String, to newTitle: String) {
    // Find by (kind,id) — NOT by title — and replace in place.
    // Do NOT remove+append (that changes order/recency).
    // EntityStateRef.title is `let`; no `withTitle` helper exists — construct a
    // fresh value copying kind and id, supplying the new title.
    if let idx = entries.firstIndex(where: { $0.kind == kind && $0.id == id }) {
        entries[idx] = EntityStateRef(kind: entries[idx].kind, id: entries[idx].id, title: newTitle)
    }
}
```

Call `pinnedManager.updateTitle(for:id:to:)` and `recentsManager.updateTitle(for:id:to:)` from ALL FOUR rename overloads (both `renamePage` overloads + both `renameItem` overloads), after cascade + `upsertPage`/`upsertItem` succeed.
- [ ] **Step 4: Run to verify pass.** Expected: PASS.
- [ ] **Step 5: Commit.** `fix(connections): refresh pinned/recents titles on rename`

---

## Phase E — Editor: resolve, render, navigate (in-app surface)

> Phases E–F are precise, source-anchored specs; the stress-test round (then revision) hardens each to full code before execution. Every file:line below is recon-verified.

### Task E1: Inject the connection resolver (`[[ ]]` resolves live)

**Files:**
- Create: `Pommora/Pommora/Connections/ConnectionResolver.swift`
- Modify: `Pommora/Pommora/Pages/MarkdownEditorConfig.swift`, `Nexus/NexusEnvironment.swift`, `Pages/PageEditorView.swift:227`
- Modify: `External/MarkdownPM/Sources/MarkdownPM/Services/MarkdownPMServices.swift` (add `itemLinks` slot)
- Test: `Pommora/PommoraTests/Connections/ConnectionResolverTests.swift`

Recon (Agents 1/2): production uses `NoOpWikiLinkResolver` (`MarkdownEditorConfig.swift:26` → `MarkdownPMConfiguration.default`), so today every `[[ ]]` renders inert regardless of existence. The resolver must be built where the managers/index live (`NexusEnvironment`) and injected via `MarkdownPMServices.wikiLinks`. Add a parallel `itemLinks` slot for `{{ }}`.

- [ ] **Step 1:** Add `itemLinks: any WikiLinkResolver = NoOpWikiLinkResolver()` to `MarkdownPMServices` (container + init). The `WikiLinkResolution` shape (`id`, `exists`) fits both kinds.
- [ ] **Step 2:** Write `PommoraConnectionResolver` conforming to `WikiLinkResolver`, parameterized by kind, resolving `displayName` via the index `titleCandidates`/exact-title lookup → `WikiLinkResolution(id: <ulid-or-name>, exists: count==1)`. (Resolver returns an id only for in-memory metadata; LD-28 keeps it off disk.)
- [ ] **Step 3:** Change `MarkdownEditorConfig.pommora` to accept injected resolvers with DEFAULT values so existing call sites that don't pass resolvers compile unchanged:

```swift
// pommora(verticalInset:pageResolver:itemResolver:) — resolvers default to
// NoOpWikiLinkResolver() so ItemWindowRenderer.stubBody (ItemWindowRenderer.swift:241,
// pommora(verticalInset: 0)) compiles unchanged. The display-only Item Window
// keeps NoOp → item-body links render inert in v1 (item mechanics deferred).
static func pommora(
    verticalInset: CGFloat,
    pageResolver: any WikiLinkResolver = NoOpWikiLinkResolver(),
    itemResolver: any WikiLinkResolver = NoOpWikiLinkResolver()
) -> MarkdownEditorConfig { ... }
```

Construct ONE stable `PommoraConnectionResolver` (page kind) + one (item kind) as stored properties on `NexusEnvironment` (per quirk #15 — centralised injection). `PageEditorView` reads them via `@Environment` and builds the config per-render, but the RESOLVER INSTANCES are stable stored properties (not re-instantiated per-keystroke) → no `NSViewRepresentable` churn from per-render config construction.

Replace the static `Self.pommoraEditorConfiguration` at `PageEditorView.swift:227` with a config built from the injected resolvers (computed but backed by stable resolver references).

- [ ] **Step 4 (LIVE REFRESH):** A phantom won't light up when its target is created in another window because the styler only re-runs on edits. Add a `connectionsChanged: Notification.Name?` field to `MarkdownPMBus` and observe it via the existing bus-subscription pattern (like `appearanceDidChange`/`subscribeToBusNotifications` — NOT an ad-hoc global `NotificationCenter` name, so a config swap doesn't double-register). The `@MainActor` manager posts the signal on entity create / rename / delete; the coordinator restyles on main (re-queries the resolver → phantom resolves). This is the editor-surface half of the live-visibility non-negotiable; the index half is already live via reconcile.

- [ ] **Step 5:** Test the resolver against an index fixture (exists vs missing vs duplicate→not-exists). Commit: `feat(connections): inject title-keyed resolver; [[ ]] resolves live`.

### Task E2: Wire `onLinkClick` → navigate to the page

**Files:**
- Modify: `Pommora/Pommora/Pages/PageEditorView.swift:224-236`
- Test: contract test asserting the closure routes through `MainWindowRouter.requestOpen(to:)`

Recon (Agents 2/4): `onLinkClick` exists on `MarkdownPMEditor` (`NativeTextViewWrapper.swift:67`) and fires (`…+TextDelegate.swift:423`) but `PageEditorView` passes no handler — page-link navigation is a dead wire.

- [ ] **Step 1:** Add `onLinkClick: { title in mainWindowRouter.requestOpen(to: .page(<resolved PageMeta>)) }` to the `MarkdownPMEditor(...)` call. Resolve title→PageMeta via the page manager/index. Navigation-first (detail pane); page preview deferred.
- [ ] **Step 2:** Contract-test the routing; commit: `feat(connections): [[ ]] click navigates to page`.

### Task E3: `{{ }}` tokenizer + styler (plain-link placeholder)

**Files:**
- Modify: `External/MarkdownPM/Sources/MarkdownPM/Parser/MarkdownToken.swift:18-30`, `Parser/MarkdownTokenizer.swift`
- Create: `External/MarkdownPM/Sources/MarkdownPM/Styling/MarkdownPMStyler+ItemLinks.swift`
- Modify: `Styling/MarkdownPMStyler.swift` (invoke the new styler)
- Test: `External/MarkdownPM/Tests/MarkdownPMTests/ItemLinkTokenizerTests.swift`

Add `.itemLink` to `MarkdownTokenKind`; add an `itemLinkRegex` (`\{\{([^{}\r\n|]+)(?:\|[^}\r\n]*)?\}\}`) emitting `.itemLink` tokens (parallel to the `.wikiLink` block at `MarkdownTokenizer.swift:104-116`, with the same code-overlap skip). Clone `styleWikiLinks`→`styleItemLinks` (reads `ctx.services.itemLinks.resolve`), rendering resolved item links as a **plain styled link** (same visual as `[[ ]]`: `.link` + theme color) — the placeholder for the future Item Chip.

> SPEC FIX (unresolved rendering): unresolved connections MUST render as **plain prose** with brackets visible — NO muted/disabled styling (Connections.md:73 spec: "No muted styling"). Change BOTH the existing `styleWikiLinks` unresolved branch (currently `disabledText` at `MarkdownPMStyler+Links.swift:68`) AND the new `styleItemLinks` unresolved branch to plain body-text color (NOT `disabledText`). NOTE: this changes existing `[[ ]]` unresolved appearance (grey → plain text) to match the ratified spec.

> SWITCH-SITES: Adding `.itemLink` to `MarkdownTokenKind` requires updating every kind-switch/filter in MarkdownPM. Required edits:
> - `MarkdownPMStyler.swift` `shrinkInactiveMarkers` (~L488): this is an `||` GUARD CHAIN (not a switch) — add `.itemLink` to the chain (e.g. `token.kind == .wikiLink || token.kind == .itemLink || ...`).
> - `MarkdownPMStyler+TextStyling.swift:64-65` `literalTargetTokens` (~L485): also an `||` GUARD CHAIN — add `.itemLink` to the chain so emphasis inside `{{ }}` is suppressed the same way `[[ ]]` is.
> - `ParsedDocument`: add an `itemLinkTokens` array (parallel to `wikiLinkTokens`).
> - `NativeTextViewCoordinator` `InlineTokenContext` enum: add `.itemLink` case + its `inlineTokenContext(...)` walker in `+Services.swift`.
> - `NativeTextViewCoordinator+Services.swift` spellcheck-suppression guards (~lines 169, 206, 216): these are `||` chains checking `token.kind == .wikiLink || .link || .imageEmbed` — add `.itemLink` so spellcheck stays suppressed inside `{{ }}` tokens.
> - `NativeTextViewCoordinator+Restyling.swift` `parsedDocument(for:)` switch (~lines 206-221): must route `.itemLink` tokens into the new `itemLinkTokens` array on `ParsedDocument` — without this, the `default: break` arm silently drops them and they never get styled.

> ITEM WINDOW NOTE: `[[Page]]`/`{{Item}}` clicks INSIDE an item body (display-only Item Window) are inert in v1 — `ItemWindowRenderer` passes `NoOpWikiLinkResolver` and no click handler. Deferred with item mechanics.

- [ ] Steps: failing tokenizer test → add kind+regex+emit → failing styler test → add `MarkdownPMStyler+ItemLinks` + call it from `MarkdownPMStyler.swift` + fix unresolved render in both stylers + patch all switch sites → pass → commit `feat(markdownpm): {{ }} item-link tokenizer + plain-link placeholder styler`.

### Task E4: `{{ }}` click → open the Item Window

**Files:**
- Modify: `External/MarkdownPM/.../NativeTextViewWrapper.swift` (+`onItemLinkClick`), `Coordinator/NativeTextViewCoordinator+TextDelegate.swift:423` (route by token kind)
- Modify: `Pommora/Pommora/Pages/PageEditorView.swift`
- Test: contract test for the routing bridge

Recon (Agents 2/4): the editor (an `NSViewRepresentable`) can't reach `openWindow`; `AppGlobals.presentItemAction: ((Item) -> Void)?` (`AppGlobals.swift:70`) is the existing bridge (resolves Item→Type+Set → `openWindow(value: ItemRef)`). Add a sibling `onItemLinkClick: ((String) -> Void)?`.

> CLICK DISCRIMINATION (BLOCKER): the `clickedOnLink` handler (`NativeTextViewCoordinator+TextDelegate.swift:423`) must discriminate between `[[ ]]` and `{{ }}` clicks by attributed-string key, NOT by token kind lookup (which requires a range scan). Define:

```swift
// In MarkdownToken.swift, alongside the existing `.wikiLinkID` key:
public nonisolated static let itemLinkTitle = NSAttributedString.Key("ItemLinkTitle")
```

`styleItemLinks` writes `.itemLinkTitle` on the content ranges of every resolved `{{ }}` token (the displayed title text). In `clickedOnLink`:
```swift
// Probe .itemLinkTitle FIRST; fall through to [[ ]] path if absent.
if let title = attrs[.itemLinkTitle] as? String {
    onItemLinkClick?(title)
    return
}
// else: existing [[ ]] → onLinkClick path
```

This avoids the `.wikiLinkID` / `.itemLinkTitle` ambiguity on overlapping ranges and gives O(1) discrimination.

> RESOLUTION CHAIN (E4): `onItemLinkClick(title)` → `IndexQuery.titleCandidates(matching: title, kind: .item)` (exact-title lookup — `limit: 1`) → item `id` → load the full `Item` via `AppGlobals.itemContentManager?.loadItem(id:)` (name the load-by-id method) → `AppGlobals.presentItemAction?(item)` → `openWindow(value: ItemRef)`. If `titleCandidates` returns 0 or >1 matches, no-op (phantom or ambiguous dup — deferred to the picker).

- [ ] Steps: failing routing test → add callback + kind-based routing → wire the bridge in `PageEditorView` → pass → commit `feat(connections): {{ }} click opens the Item Window (navigation-first placeholder)`.

### Task E5: Autocomplete popup (`[[` / `{{`), dup-tolerant

**Resolved design (Nathan, 2026-06-06) — replaces the original "reuse the existing popup" sketch.** Recon CORRECTION: there is NO existing image-embed completion popup to extend (no app-side code sets `pendingInlineReplacement`); the engine's *consumer* side (`InlineReplacementRequest` → `pendingInlineReplacement` → `applyInlineReplacement`, caret restored) IS built and is the commit path. `ChipDropdownPanel` is NOT reused (it's chip-property selection). Build via the `swiftui-expert-skill`.

**Files:**
- Create: `Pommora/Pommora/.../AutoCompleteWindow.swift` — the new Component-Library component (grouped beside `ItemChip`; showcased in `ComponentLibraryView`'s ChipsGallery).
- Modify: `External/MarkdownPM/.../NativeTextViewSelectionTypes.swift` — add `.itemLink` to `InlineSelectionKind`; `Coordinator/NativeTextViewCoordinator+TextDelegate.swift` — fire `onInlineSelectionChange` for `{{ }}` tokens too; expose a caret/anchor rect (NSTextView `firstRect(forCharacterRange:)`) up through `NativeTextViewWrapper`.
- Modify: `Pommora/Pommora/Index/IndexQuery.swift` — `titleCandidates` keeps PREFIX match (`LIKE 'prefix%'`), change `ORDER BY title` → exact-match-first, then shortest title, then A–Z.
- Modify: `Pommora/Pommora/Pages/PageEditorView.swift` — observe `onInlineSelectionChange`, present the window, push the `InlineReplacementRequest` on select.
- Test: ranking-query test; component contract test; trigger/insert contract test.

**Behavior (locked):**
- **Trigger:** the window appears ONLY once a character is typed *inside* an open `[[`/`{{` pair — NOT on pair creation. Anchored inline at the bracket, mid-line, from the caret rect.
- **Candidates:** `titleCandidates(matching: typedText, kind:)` (Pages for `[[`, Items for `{{`), nexus-wide, **prefix (starts-with)**, case-insensitive. Lists ALL matches (two same-titled adopted entities both surface — "choose either"). Re-queried live as the user types; filters dynamically.
- **Ranking:** exact title → shortest title → A–Z.
- **Rows:** the entity **icon + title label**, body font; title in **label-secondary**, the matched leading-prefix span promoted to **label-primary**.
- **Sizing:** height grows with match count, capped at **4 rows**; scroll enabled for the full list beyond 4.
- **Surface:** Liquid Glass.
- **Selection:** click a row OR ↑/↓ + Enter; Esc dismisses. Selecting dismisses the window and inserts the finished **title-only** link (`[[Title]]` / `{{Title}}`, LD-28) via `InlineReplacementRequest` → `pendingInlineReplacement` (replacing the in-progress token).
- A bare typed title still resolves identically — the window is a convenience.

> AUTO-PAIR (shipped `195ef80`): `{` → `}}` and `[` → `]]` are in `MarkdownInputHandler.handleCharacterPairAutoPair`. The window's trigger gates on a char typed *inside* the pair, not the pair itself.

> NOT in this task (next session, gated on Item Windows): the item-body **dropdown** (single-click `{{Item}}` preview showing the item's body-text) — Nathan's separate design. Do NOT build it here.

> INERT IN ITEM WINDOW NOTE: `[[Page]]`/`{{Item}}` clicks inside an item body (display-only Item Window) stay inert in v1.

- [ ] Sub-tasks (each a green commit, verified): **(A)** engine — `.itemLink` selection kind + `{{ }}` selection-change firing + caret-rect exposure; **(B)** `titleCandidates` ranking (exact→shortest→A–Z) + test; **(C)** `AutoCompleteWindow` component (Liquid Glass, icon+title rows, secondary/primary highlight, dynamic height max-4 + scroll, click + ↑↓/Enter/Esc) via `swiftui-expert-skill` + Component-Library showcase; **(D)** wire into `PageEditorView` (trigger-on-char-inside, anchor at caret, push replacement on select). Final commit msg base: `feat(connections): [[ / {{ autocomplete window (dup-tolerant)`.

---

## Phase F — Framework stubs for deferred item-mechanics

### Task F1: `ItemChip` primitive stub + chip-render seam

**Files:**
- Create: `Pommora/Pommora/Properties/Chips/ItemChip.swift`
- Test: snapshot/contract test that `ItemChip` mirrors `ContextChip`'s `(icon, title)` shape

Per Nathan: `{{ }}` ships rendering as a plain link; the proper Item Chip (icon+title), single-click dropdown, double-click→window, and right-click "Open '<title>'" come later when the Figma designs are coded. This task lays the seam so that swap is additive.

- [ ] **Step 1:** Create `ItemChip` mirroring `ContextChip.swift:29` exactly (`let icon: String; let title: String`; the `.quinary` rounded-rect visual) so the later render path has a ready primitive. Mark it `// Placeholder render is plain-link (Task E3); this chip swaps in with the Figma item-mechanics.`
- [ ] **Step 2:** In `MarkdownPMStyler+ItemLinks`, leave a single documented extension point (the kern-trick / `NSTextAttachment` inline-element hook the recon identified — the LaTeX/image-embed render via `MarkdownTextLayoutFragment` is the precedent) where the chip render replaces the plain-link styling. Do NOT implement the attachment now.
- [ ] **Step 3:** Commit: `feat(connections): ItemChip primitive stub + chip-render extension point`.

**Deferred (framework-ready, NOT in this plan):**

*Rendering-table deferrals (explicit — not just "item mechanics"):*
- **Item-Chip inline render** (kern-trick/`NSTextAttachment`; the chip seam is laid in F1 but not activated).
- **`{{ }}` single-click dropdown preview** (the current plan ships single-click → Item Window directly; this maps double-click behavior onto a single click as a **placeholder** — it is NOT the final interaction model, just the simplest unambiguous v1 behavior. The final model requires Figma-driven design work and the full rendering table).
- **Single-vs-double-click distinction** for `{{ }}` (interim: single-click → Item Window; final: single-click → dropdown, double-click → Item Window; change is additive when the Figma pass lands).
- **Right-click "Open '`<title>`'" context-menu entry** for `{{ }}`.

*Other deferrals:*
- Editable item body (item bodies stay display-only — scanned from disk by adoption/migration/reconcile flows; there is no in-app item-body editor in v1).
- **Trash-restore reactivation** — deactivate-on-trash ships in this plan (B6 Step 5); reactivate-on-restore is deferred with the Trash UI. Trash is effectively permanent for v1 (no restore UI exists). The deactivation is correct and intentional.
- Connections/backlinks panel; graph view (this plan lays the graph-ready edge data).
- File-watcher / external reconcile (external renames orphan inbound links until the next full rebuild — accepted for v1).
- Aliases / id-scoping for duplicate titles.

---

## Self-Review (run after the stress-test, before execution)

1. **Spec coverage** — map each `Connections.md` section to a task: scope/identity → B; no-mirror → B (body+index only); rename cascade → D; resolution+lifecycle (activate/deactivate/self-skip) → B3/B6; rendering ([[ ]] live, {{ }} plain-link) → E1/E3; autocomplete → E5; index+graph data → B1–B5; Obsidian compat (LD-28 title-only) → A2; editor → E3/E4; deferred → F.
2. **Placeholder scan** — no "TODO"/"TBD"; Phases E–F carry precise specs + code sketches, to be expanded to full code in revision.
3. **Type consistency** — `ConnectionTitle.normalize`, `ConnectionSyntax`, `ScannedConnection`, `ConnectionEdge`, `reconcileConnections`/`activateConnections`/`deactivateConnections`, `titleExists`/`titleCandidates`, `ConnectionCascade.run` are named identically across tasks.
4. **Green-commit order** — A (independent) → B (foundation) → C (needs B's `titleExists`) → D (needs B's `incomingConnections` + `reconcileConnections`) → E (needs B's resolver/queries) → F (stubs). No task references a type built later. B2 ships `pageRegex`/`itemRegex` as `internal` → D1's `ConnectionRewriter` reuses them directly (no forward-reference violation).

Stress-test round 1 applied (blockers: indexQuery derivation, cascade ordering+overloads, config call-site, click discrimination, unresolved-render spec fix).

Round-3 fixes applied (phantom re-activation spec fix, EntityStateRef.kind String, rename phantom-window activate, regex visibility in B2, pragma_table_info, test-fixture notes, bus-routed live refresh, accepted v1 limitations).

---

## Accepted v1 Limitations

*Document these explicitly so future agents don't treat them as bugs to fix.*

**(a) COLD-START SCALE —** `insertConnections` runs a resolution SELECT per link inside one write transaction → O((P+I)×L) where P+I = total entities and L = links per body. This is measurable as launch latency on large nexuses. Log timing at the start and end of the `insertConnections` pass so regressions are visible. Optimization (batch resolution, covering index) is deferred.

**(b) NON-ASCII TITLES —** `ConnectionTitle.normalize` uses Swift Unicode `.lowercased()` but SQLite `COLLATE NOCASE` folds ASCII only, so a non-ASCII title ("Über") stored normalized as "über" may not match a SQLite NOCASE needle when the needle comes from a different casing path. This is a latent resolution miss for non-ASCII titles; v1 is ASCII-correct. The proper fix is a stored `title_normalized` column (written at insert time via Swift `.lowercased()`); deferred.
