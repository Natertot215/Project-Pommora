## Headless Data Layer — Design

The complete write/mutation side of the Pommora React rebuild, built and verified **before any real UIX exists**. The read engine (`readNexus`/`readPage`) already exists; this adds atomic I/O, sidecar persistence, full CRUD, properties, connections, and the SQLite index. Grounded in a 20-agent dual research pass (Swift bloat analysis × TS-native recreation) whose load-bearing claims were verified against the real Swift source.

### Governing principles

- **Catch up to Swift, don't go ahead.** Build only what Swift has actually shipped at the data level. Net-new subsystems Swift hasn't built are out of scope — no exceptions. (File-version history was considered and **rejected**: Swift delegates versioning to the OS; "history" here means **Recents**, a `state.json` field Swift already has.)
- **Less code, less complexity, more capability, fewer constraints.** Research projects ~15.6k Swift LOC → ~6.6k TS (a directional ~55–60% cut). The real win is the *categorical deletion* of Swift-forced layers (actor/`Sendable`/`@MainActor`, the DI graph, `Codable`+`CodingKeys`, the `PropertyValue` codec, the Yams `Node` merge, GRDB snapshot-mirrors, security-scoped bookmarks) — not the line count.
- **Byte-compatible on-disk format.** Same bytes as Swift (conceptual-portability constraint #1); read/written natively in TS with **no codec**. Every existing nexus works unchanged. Two additive, ratified improvements only: foreign JSON keys (`z.looseObject`) and foreign-frontmatter comments (yaml Document API) now **survive** a rewrite (Swift silently dropped them) — which advances cross-sync + agent-legibility.
- **One process owns I/O.** All fs lives in the Electron **main** process. The renderer is sandboxed and calls a narrow `contextBridge` bridge → typed `ipcRenderer.invoke` channels. Every handler returns the never-throws envelope `{ ok: true, … } | { ok: false, error }`. Reactivity = the renderer re-reads the changed subtree after each mutation (no in-memory `@Observable` mirror).
- **Don't add complexity that wasn't asked for.** Simplest dependable design wins.

### Ratified decisions

- **SQLite** → `better-sqlite3`, isolated behind `db.ts` (synchronous, prepared statements, `db.transaction()` auto-rollback). It's a native module: adds an `electron-rebuild` + `asarUnpack` step; the index is regeneratable, so a load failure **degrades to file-only reads, never blocks the app**. Swap to built-in `node:sqlite` later = one-file change.
- **Adoption** → mirror Swift, kept minimal. A mutation targeting a raw (un-adopted) folder lazily mints real ULID sidecars along the touched ancestor chain. Not optimized for the "don't stamp my Obsidian vault" case — **we build and test against `~/test` only**.
- **History** → **Recents only.** Navigation history (`state.json` `recents: [{kind,id}]` + `pinned`), maintained by the state layer (prepend on open, dedupe, cap). No versioning, no git, no new dependency, no new phase.
- **Scope (build-now, full CRUD):** Pages · Contexts (3 tiers) · Agenda (Tasks + Events) · Properties (value + schema) · Connections + tier relations · SQLite index.
- **Reserved / read-only (Swift hasn't built these — round-trip but no editing):** `blocks: []` on Homepage + context sidecars (kept empty, preserved by value) · Homepage composition · Settings-editing UI (storage + migration + read **are** built).

#### Smaller defaults (recommended; flagged for your review)

- Foreign-key preservation on sidecar rewrite via `z.looseObject` (additive vs Swift; closes a sync/legibility gap).
- `[[ ]]` title-resolution uniqueness is **nexus-wide** (duplicate title → ambiguous/inert), matching the connection model.
- Post-mutation, main returns the **full re-read `NexusTree`** (optimize to scoped patches only if profiling demands).
- Delete = move to an **in-nexus `.trash/`** with timestamp de-collision (recoverable, relative-path preserved), not OS trash.
- Widen the IPC error envelope to `{ ok: false, error: { code, message } }` so typed/retryable errors survive the boundary.

### What TS sheds — the categorical deletions

| Swift-forced layer | Why it disappears in TS |
| --- | --- |
| `@MainActor` / `Sendable` / `actor` isolation, `any Decoder` ceremony | Single-threaded main process; fs I/O is plain `async`. No isolation model. |
| `NexusEnvironment` DI graph + 19-call injection modifier (built to dodge a SwiftUI `_TaskValueModifier` SIGTRAP) | One `NexusSession` value object `{rootPath,id,index}`. A missing field is `undefined`, not a crash. |
| ~21 custom `Codable` + 35 `CodingKeys` enums + `LenientFrontmatterShape` duplicate | One `zod` schema per entity = the codec. `z.infer` derives the type (no drift). |
| `PropertyValue` shape-sniffing codec (~117 LOC) | Native YAML values on read; a ~10-LOC `encodeValue` on write. Type is *declared by the schema*, not re-sniffed. |
| Yams `Node` graph merge for foreign-key preservation (~70 LOC) | `yaml` Document API round-trips unknown keys + order + comments natively. |
| GRDB `*Snapshot` mirror structs + `String`-overload workarounds + two-phase MainActor walk | `better-sqlite3` + hand-written parametrized SQL. No ORM. |
| Security-scoped bookmarks, `NSOpenPanel` retry loop, XCTest launch-modal guard | `dialog.showOpenDialog`; no macOS sandbox layer exists here. |

Per-concern LOC (Swift → TS est): page I/O 726→410 · sidecars 1442→400 · managers/CRUD 4323→1130 · properties 1100→520 · connections 940→192 · SQLite 1742→1200 · ordering/IDs 1130→355 · validation 1850→1010 · contexts+non-page 2354→920. **Treat ~55–60% as the honest band**, not a precise figure (per-concern counts overlap).

### Modernized on-disk format

Canonical reference for every writer. Snake_case keys, sorted keys, 2-space JSON, ISO-8601 dates, atomic temp+rename. Filename = title everywhere (no `title` key). **Kind authority is path-based**: a folder's kind = which `_*.json` sidecar it carries; a `.md` file's kind = its parent folder's sidecar. Extension and frontmatter are non-authoritative.

#### Page `.md`

Exact bytes: `---\n<yaml>---\n\n<body>` — one opening + one closing fence, YAML ends in a single `\n`, exactly one blank line before the body (stripped on read). Modeled keys:

- `id` — ULID string, **required** (strict read throws; lenient/adoption read synthesizes `adopted-<sha256(nexus-relative-path)[:16]>`).
- `icon?` — symbol name.
- `tier1` / `tier2` / `tier3` — **bare ULID string arrays at the root** (always written, even empty).
- `properties` — map of `propertyID → value` (see shapes below).
- `created_at` — ISO-8601 (epoch-0 default; file ctime on lenient adoption).
- `modified_at?` — ISO-8601 (backfilled from mtime, then persisted).
- `folded_headings?` — array of heading source lines, UI-only, **omitted when empty**.
- `cover?` — nexus-relative POSIX path.
- Any other key is **foreign** — preserved verbatim by value + position + comments.

> ⚠ **Doc-bug caught during verification:** the Swift project's `CLAUDE.md` states tier links are stored as `[{"$rel":"<ULID>"}]`. **That is wrong.** [`PageFrontmatter.swift:13-15`] declares `tier1/2/3` as **`[String]`** — bare ULID arrays at the root. The `$rel`-tagged shape applies **only** to user relation *properties* inside `properties` (and Agenda properties). Encode tiers bare; verify both the page and agenda writers against the Swift model. (Surface this back to the Swift project to correct its doc.)

#### PropertyValue on-disk shapes

The declared type lives in the schema, not the value. Shapes: `number` = bare number · `checkbox` = bare bool · `url` = bare string · `select` = bare string · `multi_select` = bare `[string]` · `status` = `{"$status":"<value>"}` · `relation` = `[{"$rel":"<ULID>"}]` (always an array; legacy single `{"$rel":id}` tolerated → `[id]`) · `date` = `"yyyy-MM-dd"` (UTC) · `datetime` = full ISO-8601 with TZ · `file` = `[{path, original_name, added_at, mime_type}]`. `lastEditedTime` is **virtual** — never persisted (encode throws; derived from `modified_at`). User relations inside `properties[id]` **omit the key when empty**; tiers always write their (possibly empty) array.

> ⚠ **Load-bearing & silent on failure:** the read decode **precedence** must match Swift exactly — `null → bool → number → non-empty [{$rel}] → [FileRef] → [string] → empty []→file([]) → single {$rel}/{$status} → string(url→iso-datetime→yyyy-MM-dd→select)`. One reordering mis-types relations/files/multiselect with **no error**. Pin with a table-driven round-trip fixture over every variant + the legacy single-`$rel` and empty-array edges. (Verified against [`PropertyValue.swift:50-131`].) Note relations are *"retired from user creation"* in Swift — they exist only as the built-in tiers.

#### Folder sidecars

- `_pagetype.json` (flat at nexus root): `{ id, icon?, schema_version (seed 2), collection_order?, page_order?, views?, banner?, modified_at, property_definitions[] }`.
- `_pagecollection.json` (in a Type folder): `{ id, type_id (legacy fallback vault_id), icon?, schema_version (1), set_order?, page_order?, views?, banner?, modified_at }`.
- `_pageset.json` (in a Collection folder): `{ id, collection_id, icon?, schema_version (1), page_order?, modified_at }`.
- Contexts — `.nexus/{areas,topics,projects}/<Title>/_area.json|_topic.json|_project.json`: `{ id, tier (constant 1|2|3, always re-written so external edits self-heal), icon?, blocks [] (reserved, always []), modified_at }`; `_area.json` adds `color?` (AreaColor 10-case). Tiers are **decoupled** — no parents, no containment.
- `property_definitions[]` entry: `{ id (prop_<ULID> user / _id,_status,_tierN reserved), name, type, icon?, number_format?, date_includes_time?, select_options?[{value,label,color}], status_groups?[{id,label,color,options[…]}] (3 fixed EventKit slots), relation_target?{kind:"context_tier",tier} (legacy fallback relation_scope), reverse_name?, reverse_icon?, accept?[], display_as?, date_format?, time_format? }`; `.date` normalizes to `.datetime` on read; plus top-level `default_sort?{property_id,direction}`.

#### Agenda (EventKit-shaped JSON at the nexus root)

Discovered by sidecar presence (Finder-renameable; default folders `Tasks`/`Events`). `_taskconfig.json` + `<title>.task.json`; `_eventconfig.json` + `<title>.event.json`. Config sidecar = a property schema (`property_definitions[]` seeded with a built-in `_status`, `views[]`, `default_sort?`).

- **AgendaTask** (EKReminder): `{ id, icon?, description?, tier1/2/3 (bare ULID arrays), properties (incl `_status`), created_at, modified_at, due_at?, due_floating?, due_all_day? (requires due_at), start_at?, completed?, completed_at?, priority (0-9), recurrence?, alarm_offsets?[], calendar_id?, eventkit_uuid? }`.
- **AgendaEvent** (EKEvent): `{ id, icon?, description?, tier1/2/3, properties, created_at, modified_at, start_at (required), end_at (required, ≥ start_at), all_day?, location?, recurrence?, alarm_offsets?[], alarm_absolute?[], calendar_id?, eventkit_uuid? }`.
- **Recurrence** (EKRecurrenceRule mirror): `{ frequency, interval, first_day_of_week?, end?{kind:"occurrence_count"|"end_date", value}, days_of_week?[{day,week_number?}], days_of_month?[], days_of_year?[], weeks_of_year?[], months_of_year?[], set_positions?[] }`.

#### `.nexus/*` singletons (fixed location = identity, no `id` field except identity)

- `nexus.json` — `{ id (portable ULID), created_at }`.
- `settings.json` — `{ version, defaults_version (4, forward-only step-migration of fields still at the old default), accent_color (SettingsAccentColor 8-case — **distinct palette** from AreaColor), labels {sidebar_sections + Vault/Collection/Set/Project/Task/Event LabelPairs}, show_page_icon, excluded_folders[], modified_at }`.
- `state.json` — `{ vault_order?, area_order?, topic_order?, project_order?, active_views?{}, recents[{kind,id}], pinned[ULID] (legacy fallback favorites), cursor, sidebar order }` — `*_order` omitted when empty; written **read-modify-atomic** so sibling writers aren't clobbered. **Recents lives here.**
- `saved-config.json` — renameable labels for the fixed Homepage/Calendar/Recents pins (key fixed in code).
- `sidebar-sections.json` — user vault groupings (Swift's lone camelCase outlier `vaultIDs` → read with `vaultIDs`/`vault_ids` fallback, normalized to `vault_ids` on next write).
- `tier-config.json` — per-tier `{ singular, plural, exposed:bool }`. Tier numbers are fixed code constants; only labels editable.
- `homepage.json` — `{ schema_version, icon?, blocks [] (reserved, always []), modified_at }`.

#### Connections (no on-disk store)

Live **only** as title-only `[[Title]]` text in a Page's Markdown body (page→page). No frontmatter mirror, no id/pipe/alias; `![[ ]]` and `{{ }}` are not connections. Resolution = normalized (trim+lowercase) body-title → the unique page holding it → its ULID, computed at read time. The id never touches disk. Obsidian/GitHub-compatible.

#### SQLite index (`.nexus/index.db`)

Regeneratable accelerator, **off the read path**, no body column. **11 tables** — `page_types, page_collections, page_sets, pages, agenda_tasks, agenda_events, contexts, context_links` (tiers), `connections` (body links, page-only), `property_definitions`, `meta` — + ~14 indexes; properties as TEXT JSON queried via `json_extract`/`json_each`; `idx_pages_title COLLATE NOCASE`; all ids TEXT ULIDs. `schema_version` mismatch → drop + rebuild. DDL copied byte-for-byte so Swift- and React-built indexes are interchangeable.

### Module architecture

`src/shared/` (types + zod + Result; importable by renderer — no fs, no React):

```
types.ts          — EXTEND: NexusTree shapes (exist) + mutation request/result envelopes
schemas.ts        — ALL zod entity schemas (snake_case = codec); z.looseObject for foreign keys; z.infer types
propertyValue.ts  — PropertyValue union + parse/encode (LOCKED precedence; lastEditedTime throws)
properties.ts     — PropertyType union, PropertyDefinition + config types, FileRef, reserved-ID catalog
connections.ts    — LinkStatus (resolved/phantom/ambiguous), ScannedConnection, ConnectionEdge, LinkIndex
indexTypes.ts     — EntityRef/EntityKind, FilterCriterion tree, SortDirection, GroupedEntities, reports (DTOs)
result.ts         — Result<T,E> + PommoraError {code,message,scope}
```

`src/main/`:

```
io/atomicWrite.ts     — atomicWriteFile (temp+fsync+rename via write-file-atomic), writeJson, mutateJson, trashWithTimestamp
io/schemaTransaction.ts — two-phase multi-file commit (stage .txn → rename-with-backup → rollback → sweep stale)
io/pageFile.ts        — split/assemble the envelope; write via yaml Document API (set/delete modeled keys, foreign preserved)
ids.ts                — ulidx monotonic newId() + isUlid() + adopted-<sha256> (shared by reader & writer)
kind.ts               — SIDECAR_FILENAME map + resolveKind(folderPath) + agenda-by-sidecar discovery
sidecarIO.ts          — readSidecar/writeSidecar (schema parse → inject title from basename → strip runtime fields on write)
singletons.ts         — named load/save per .nexus singleton + Settings.migrate()
validation/validators.ts — pure Result-returning: nameCollision, pageValidator, propertyDefinition rules
crud/folderEntity.ts  — ONE generic create/rename/delete/reorder/updateIcon for the 6 folder-shaped entities
crud/page.ts          — page create/rename/delete/updateBody/updateProperty/move (+ no-overwrite guard)
crud/agenda.ts        — agendaEntity factory (CRUD + schema CRUD), reuses encodeValue + folderEntity primitives
crud/cascade.ts       — connection rename cascade (rewrite inbound bodies, revert on fail) + unlinkTier
crud/reorder.ts       — pure id-space reorder + persist ID list to state.json
properties/schema.ts  — parse PropertyDefinition[] + normalize() (legacy migrations) + droppingUserRelations
properties/tiers.ts   — BuiltInContextLinkProperties merge (_tier1/2/3 synthesis)
connections/{normalize,scan,resolve,edges,rewrite}.ts — pure Map-based engine (no SQLite on read path)
index/{schema,db,upsert,build,query}.ts — better-sqlite3 wrapper + version handshake + shared upsert + cold build + parametrized SQL
session.ts            — NexusSession {rootPath,id,index}; open/pick (dialog), best-effort index open/rebuild, lazy adoption
index.ts              — EXTEND IPC host: mutate:* / index:* handlers, path-guarded under root, return envelopes
```

`src/preload/index.ts` — extend the `nexus` bridge with narrow mutate methods (createEntity/renameEntity/movePage/deletePage/updatePageBody/updatePageProperty/reorder). No fs leaked.

**IPC seating:** renderer → `preload.nexus.<verb>(args)` → `invoke('mutate:<verb>')` → main handler validates → resolves path under `session.rootPath` (existing traversal guard) → `crud/*` (→ `io/*` + `validation/*` + `schemas`) → best-effort index upsert (swallowed) → returns `{ok,…}`. SQLite lives only in main; `query.ts` becomes `index:*` handlers returning plain DTOs. `readNexus`/`readPage` stay the only content path; the index answers only cross-cutting queries.

### Build phasing (headless, dependency-ordered — no dates)

- **Phase 0 — Shared contracts & atomic I/O.** `result.ts`, `propertyValue.ts`, `properties.ts`; `ids.ts`; `io/atomicWrite.ts` + `io/schemaTransaction.ts`. Unit-test the PropertyValue codec per-branch + atomic-write crash safety. *(deps: none)*
- **Phase 1 — Page file engine (write).** `io/pageFile.ts` via the yaml Document API. Acceptance = port Swift `FrontmatterPreservationTests` + `AtomicYAMLMarkdownTests` verbatim as vitest specs (byte-stability is the contract). *(deps: 0)*
- **Phase 2 — Sidecars, kind authority & singletons.** `schemas.ts`, `kind.ts`, `sidecarIO.ts`, `singletons.ts` + `Settings.migrate()`. Refactor `readNexus` to call them (net LOC removal). *(deps: 0)*
- **Phase 3 — Validation + CRUD lifecycle.** `validators.ts`, `session.ts` (open/pick + lazy adoption), `crud/{folderEntity,page,reorder}.ts`. Wire `mutate:*` IPC + preload. Validate → atomic write → re-read model. Rename-rollback + no-overwrite tested. *(deps: 1, 2)*
- **Phase 4 — Properties write path.** `properties/{schema,tiers}.ts` + `encodeValue` into page/agenda writes + `saveValue`/`commitSchema` IPC (schema-mutation atomicity via `schemaTransaction`). *(deps: 1, 3)*
- **Phase 5 — Connections & tier relations.** `connections/*` (pure, Map-based) + `crud/cascade.ts`. Extend the `readNexus` walk to collect `linkIndex.byTitle` + `contextsById`. No persistent table on the read path. *(deps: 1, 3)*
- **Phase 6 — SQLite index.** `index/*` with verbatim DDL + `better-sqlite3` wrapper + version handshake + `electron-rebuild`/`asarUnpack` pipeline. Best-effort upserts wired into `crud/*` (swallowed). Port `loadAll-sync-parents`. *(deps: 2, 4, 5)*
- **Agenda CRUD** folds into Phases 3–4 via the `agendaEntity` factory (reuses `folderEntity` + `encodeValue`).

#### Verification — tests only, no UI

This phase wires **nothing** to the renderer. Every phase is proven by headless `vitest` specs against the modules and the IPC handlers directly (call the handler, assert the `{ ok, … }` envelope + the on-disk result). Renderer touch-points stay typed **stubs** in the preload bridge — never wired surfaces. The real UI is rebuilt later from the Figma Component Library. Per-phase acceptance: typecheck + build + the phase's vitest suite green.

### Library stack

No hard lock-in — each dependency sits behind a thin seam (the SQLite driver behind `db.ts`, the YAML engine behind `pageFile.ts`, ID minting behind `ids.ts`) and is swappable without touching callers. Version constraints are compatibility pins, not endorsements. The editor (a later phase) is **not** mandated to any library.

- **`yaml` ^2.9** (installed) — frontmatter; use the **Document API** (`parseDocument`/`set`/`delete`/`toString`) on write to preserve foreign keys, order, comments. JSON sidecars use native `JSON`.
- **`zod` v4** — one schema per entity = the codec (`.default()`/`.catch()` lenient backfills, `z.looseObject` foreign-key retention, `.partial()` lenient adoption, `z.discriminatedUnion` for Recurrence.end). `z.infer` is the single source of truth for types.
- **`ulidx` ^2.4** — ULIDs via `monotonicFactory()` (strict same-ms ordering) + `ulidToUUID` for a future cloud key map. One shared `ids.ts`.
- **`write-file-atomic` ^8** — single-file temp+fsync+rename; also the per-temp primitive inside `schemaTransaction` (which is hand-rolled — no library covers multi-file commits).
- **`better-sqlite3` ^12** (Phase 6) — synchronous driver behind `db.ts`. No ORM (queries are dynamic json-path/filter-tree/IN-list). Needs `electron-rebuild` + `asarUnpack`.
- **Node built-ins** — `statSync().ino` for the rename clobber-guard; `crypto` for adopted-id sha256.
- **Declined:** `gray-matter` (re-stringifies YAML, loses key order — breaks foreign-frontmatter preservation); a date library (native `toISOString()` + `.slice(0,10)` suffice); the original `ulid` (unmaintained → `ulidx`); **`isomorphic-git`** (history-as-versioning is out of scope).

### Risks & invariants

- **PropertyValue precedence is load-bearing & silent on failure** — table-driven round-trip fixture over every variant (above).
- **Tier storage asymmetry** — tiers are bare ULID arrays at root; `$rel`-tagged is only for user/agenda properties. Verify both writers.
- **Foreign-key preservation must spread from the ORIGINAL on-disk object**, not the zod-parsed value (zod may coerce/strip). Re-read raw frontmatter/JSON at write time.
- **yaml first-write styling** may differ byte-for-byte from Yams on a fresh modeled-key write (untouched foreign nodes are safe). Assert *value + envelope-frame* equality, not serializer quoting; pin `lineWidth:0`; test re-save idempotence.
- **Atomicity is same-volume** — stage temps as siblings of the target. Multi-file `schemaTransaction` rollback is best-effort (no fs transaction exists); the stale-sweep on next commit handles a crash mid-commit (same surface as Swift).
- **`better-sqlite3` is native** — must be ABI-rebuilt + asar-unpacked or it throws in a packaged build. A load failure **must degrade to file-only reads**.
- **Connection cascade** depends on the link index; in degraded/empty-index mode a rename rewrites nothing. Rename the target's own file **last**; the index self-heals on next load.
- **Stale index / external edits** — index re-syncs only on CRUD or rebuild (a Finder/Obsidian edit is invisible until next open). Port `loadAll-sync-parents` so a write into an externally-created vault doesn't FK-fault. A filesystem watcher is a deliberate v1 non-goal.
- **Factory consolidation concentrates correctness** — the context-tier + agenda factories are the big LOC win; cover each tier/entity path with its own round-trip + rename-rollback + cascade test, not the factory once.

### Reserved / out of scope (the catching-up boundary)

Round-tripped but not built (Swift hasn't shipped them): `blocks: []` editing (Homepage + contexts) · Homepage composition · Settings-editing UI. Not built at all: file-version history (OS's job), a filesystem watcher, real-nexus adoption optimization. Connection autocomplete, the page editor (CodeMirror), and view renderers (Table/Gallery) are separate core-7 phases after the data layer.
