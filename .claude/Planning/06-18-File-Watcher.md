## File Watcher — Design Spec (V4)

> **Status:** V4 — written, pending a final verification round. Review history: **V1** failed (content-diff echo filter unrunnable for closed-page bodies; "newest mtime wins" never implemented; non-reusable rename path). **V2** failed (prior-state and identity for Pages live in the index, not memory; path-derived ids defeat rename-tracking; open editor goes stale on rename). **V3** failed (the index database lives *inside* the watched root → self-churn; stamping/loader gaps under-counted; startup ordering has no handle). **V4** folds those and the two ratified product decisions — **all entity kinds in scope** and **stamp a stable ULID on first sight**. Not ratified until a verification round comes back clean; implementation plan follows ratification.

### Purpose

Internal and external file changes propagate into the running app immediately, with authority decided by **recency** — a newer on-disk write wins regardless of origin (Pommora, Obsidian, vim, Finder, cloud sync). Covers content edits, **renames/moves**, creates, and deletes across **every** on-disk entity under the Nexus root — Pages, Tasks, Events, Areas/Topics/Projects, and routable `.nexus` config. Native FSEvents; no third-party dependency.

### Ratified Decisions

- **Scope — all entity kinds** in the first version, every change type (edit, rename, move, create, delete).
- **Stamp-on-first-sight** *(paradigm — log to `History.md` on ratification)*: when Pommora first encounters an entity lacking a Pommora id, it mints and **persists a real ULID** into the Page's own frontmatter or the sidecar JSON, additively (foreign keys preserved). Every entity thereby carries a stable, path-independent identity, so a rename is always recognized as the same entity. This replaces the prior path-derived `adopted-<hash>` synthesis (which changed on rename and broke tracking). First launch over an existing external vault performs a one-time bulk stamp of un-stamped files.

### Core Principle

- **The filesystem is canonical.** A write whose modification time is newer than the app's last-known time for that path triggers a re-read into memory + index. Authority is recency, and it is **origin-blind**.
- **One exception — protect live edits.** A Page open in the editor with **unflushed edits** holds the most-recent edit; its buffer wins until it flushes.
- **Identity is the stamped ULID**, now guaranteed on every entity. A rename/move is the same ULID at a new path — never delete-plus-create.
- **Reuse, with named exceptions.** The watcher triggers existing per-scope loads, CRUD, and connection reconcile. New code is small and enumerated (*Net-New vs Reused*).

### Watch Scope

The watcher watches the Nexus root recursively, but reconciles only what it should:

- **Excluded at intake:** the index database and its sidecars (`index.db`, `index.db-journal`, `index.db-wal`, `index.db-shm`) — the app's own high-churn private state, never user content. Every reconcile writes the index, so failing to exclude these would make the watcher feed itself. Obvious temp/lock files are likewise dropped at intake.
- **Watched as user content — including paths under `.nexus/`:** Pages (`.md`) and their structure sidecars, **Contexts** (`.nexus/areas|topics|projects/.../_*.json`), Agenda (`.task.json` / `.event.json`), and the routable config files (`.nexus/homepage.json`, `.nexus/settings.json`, tier/label config). `.nexus/` is *not* excluded wholesale — only the index database within it is.
- **Classifier allow-list:** the reconciler acts only on recognized entity + routable-config paths. Anything unrecognized (e.g. `nexus.json`, `state.json`) no-ops; `nexus.json` (identity) is deliberately ignored.

(`FolderFilter` is user-content-only and does not exclude the index database — this intake rule is net-new path logic.)

### The Last-Seen Map (The Gate)

A single watcher-owned in-memory map, `[path: mtime]`, is the uniform recency-and-echo gate for **all** kinds:

- **Seeded** by the watcher's **own scan** at start (independent of the initial load, which runs as a detached task with no completion handle). The seed scan and the initial load both read disk; any overlap reconciles by recency.
- **Updated only by the watcher**, on every reconcile. Nothing else touches it — **no write-path instrumentation**.
- **On an event:** file `mtime` > last-seen → real change → reconcile, then update the map. Equal/older → duplicate event, temp churn, or a stale write → skip.
- Stores the **raw** observed `mtime`, so comparison is exact — no timestamp string round-trip, no precision hazard. (A change landing in the brief seed window, or between a stat and its map write, is caught on the next event.)

This is preferred over the index `modified_at` column because that column carries a file `mtime` only for Pages (Contexts have no such column; Agenda stores a logical timestamp). The all-kinds scope makes one watcher map the clean, schema-free, uniform choice.

**No write-tracking is needed.** Pommora's own writes settle without being recognized as echoes: an open Page's body lives in the editor, so a self-save reconciles to an identical buffer (no-op via body-equality); a closed entity's self-write reconciles to an identical re-read (idempotent — and a re-read writes nothing, so no event, no loop). The cost is at most one redundant idempotent reconcile per self-write — accepted in exchange for zero instrumentation. (The index-database exclusion above is what keeps this budget true: without it, every reconcile's index write would re-trigger the watcher.)

### Identity, Stamping, And Classification

- **Stamping is fully net-new and gates rename-as-move.** A Page lacking a Pommora id is minted a ULID written into **its own frontmatter** (today the lenient loader synthesizes a path-derived id and never writes it back — so an un-stamped Page's id *changes on rename*, which would misread a move as delete+create). A Context/Agenda sidecar lacking an id is stamped in the **sidecar JSON**. Stamping is done by the reconciler's first-sight/create path, not the existing root-only adopter (which skips `.nexus/` and so never heals Contexts). The stamp write is gated away by the map; the re-read finds the id present, so it never re-stamps — no loop.
- **Prior-state authority per kind:** for **Pages**, the SQLite index is authoritative (in-memory page buckets load lazily and are often empty); for **Contexts and Agenda**, the eager in-memory collections are authoritative (fully loaded at launch).
- **Per-path classification:** read the file's ULID; if that ULID is already known at a *different* path → **move/rename** (re-point, never delete); if a known ULID's file is gone from disk → **delete**; an unknown ULID → **create** (stamp if needed, adopt).

### Behavior Matrix

| Situation | Behavior |
|---|---|
| External edit, entity **not open** | Gate passes → reconcile; sidebar, title, properties update live. |
| External edit, Page **open, no unflushed edits** | Editor reloads buffer from disk in place (a self-save echo no-ops via body-equality). |
| External edit, Page **open, unflushed edits** | Buffer wins; external change held until the editor flushes. Typing never clobbered. |
| External **rename / move** (file or folder) | ULID-matched → same entity; re-point path/parent/children; reconcile inbound links; connections preserved. |
| External **create** | Coarse reload of the scope adopts it (stamps id, indexes it); appears in sidebar live. |
| External **delete** | Remove from memory + index; deactivate inbound links. **Suppressed** if the Page is open with unflushed edits. |
| **Folder cascade delete** (Type/Collection) | DB cascades child rows; reconciler also clears the children's in-memory buckets. |
| External rename **creating a title collision** | Accepted (filesystem canonical); links to the ambiguous title fall to unresolved until disambiguated. |
| Config-file edit (`homepage.json`, `settings.json`, tier/label config) | Reload the owning manager (echo no-ops via the map). `nexus.json` and the index database are ignored. |
| **Pommora's own save** | Gate + body-equality + idempotent re-read settle it; no loop. |

Contexts and Agenda follow the same rows via their eager in-memory collections; only Pages have the open-editor sub-cases.

### Conflict Policy — Protect Live Edits

The open editor is a continuously most-recent edit while it holds **unflushed edits** (exposed as the editor's pending-save state):

- **Closed, or open with no unflushed edits:** disk wins → reconcile / reload.
- **Open with unflushed edits:** external change to that file is held; the editor's flush re-asserts the in-app version.
- **External delete while unflushed edits pending:** the delete is *suppressed* (coalesced away), not applied-then-undone — so inbound links are never orphaned. *(User-visible consequence: deleting an open, edited file in Finder makes it reappear — the intended protect-live-edits tradeoff.)*

### Architecture

Two new types (the split is kept — it lets the reconciler be unit-tested with injected synthetic events while the FSEvents binding stays a thin, hand-verified shim), plus a small editor addition.

- **`NexusFileWatcher`** — native FSEvents recursive watch on the Nexus root, file-level events, stream latency (~0.1s) coalescing temp churn and bursts; the intake filter (above) drops the index database and temp/lock files. Emits changed-path batches on a background queue, hops to the main actor. Owns the last-seen map and start/stop.
- **`ExternalChangeReconciler`** (`@MainActor`) — the brain: (1) gate each path against the last-seen map; (2) classify per path by ULID against the authoritative prior-state for that kind; (3) apply — coarse per-scope reload for membership/metadata, targeted re-point + index + connection ops for identity, surgical refresh for the open editor.
- **Editor addition** — the editor view model exposes its pending-edit (dirty) state, gains a `reloadFromDisk()` that replaces the buffer **without scheduling a save** (it must bypass the `body` setter's auto-save), and a **meta-refresh** entry point that updates its captured `PageMeta` (url/title) so an external rename of the open Page can't make it re-save to the old path. The open-editor registry is matched by entity id (iterating the existing weak set).

**Data flow:** FSEvents (background) → intake filter → batch → main actor → last-seen gate → ULID classification → apply (coarse reload + targeted identity/connection ops + open-editor refresh) → `@Observable` managers refresh the UI.

### Reconcile Strategy — Coarse Per Scope, Surgical For The Open Editor

- **Membership / metadata:** re-run the affected scope's existing load — `loadAll(for: collection)` for Pages and `loadAll()` for the relevant Context/Agenda manager. **The Page loaders and both Agenda loaders are extended to upsert what they load into the index** (the defensive sync the Type/Collection and Context loaders already perform; this also fixes a standing bug where externally-added Pages and Agenda items were never indexed).
- **Identity (move/rename):** ULID-matched → update path, parent, derived child paths; re-key the index row; run the connection cascade for any title change; connections **preserved**. A **folder rename** is a two-level reconcile — re-derive the container from the renamed folder via its stable sidecar id (existing folder-changed hook), then its children, re-pointing any open child editor's url. Agenda renames refresh via coarse `loadAll()` (a fresh re-read), not `updateTask`/`updateEvent` (which throw on a title change).
- **Open editor (surgical):** refresh the open Page's captured meta and reload its body, gated on pending-edit state.

### Creates And Adoption

No separate single-file adopter. An external create is handled by the same coarse reload once the loaders gain the index-upsert loop above; stamping (frontmatter or sidecar) rides the first-sight reconcile. New folders lean on the existing scan plus sidecar stamping.

### Connections Consistency

- **Move/rename:** identity preserved → inbound links stay resolved; the title cascade updates link text.
- **True delete:** deactivate inbound links (matching in-app delete).
- **Dirty-delete suppression:** the delete is never applied, so links are never orphaned.
- **Title collision:** accepted; the resolver leaves the ambiguous title unresolved (uniqueness is app-policy, not a DB constraint).

### Lifecycle

- **Start:** after Nexus security-scoped access is granted and `currentNexus` is set — owned on `NexusEnvironment` (the manager-injection single source, which already anticipates an FSEvents watcher). The watcher seeds its last-seen map from its own scan at start rather than waiting on the detached initial-load task.
- **Stop:** on nexus switch and app terminate.
- **XCTest guard:** the watcher (and any first-sight stamping it drives) does not run under the test host — same guard as `loadOnLaunch` — so `xcodebuild test` never trips a permission modal or writes to a fixture.
- **Dropped events:** on the FSEvents must-scan-subdirs signal, re-run the coarse reload for the affected subtree (the same path as ordinary reconcile), avoiding a full-nexus rebuild.

### Error Handling

- **Watcher fails to start** → app runs degraded (no live sync; the launch scan remains authoritative). Logged, never fatal.
- **Partial / non-atomic external write** read mid-flight → best-effort; a parse failure skips and retries on the next event.
- **Index write failure** → non-fatal; the index is regeneratable and self-heals on the next launch scan.
- **Folder cascade delete** → clear child in-memory buckets explicitly (the DB cascades; memory does not).

### Net-New vs Reused

| New code (named, bounded) | Reused as-is |
|---|---|
| `NexusFileWatcher` FSEvents binding + intake filter + last-seen map | Per-scope loads (`loadAll(for:)`, Context/Agenda `loadAll()`) |
| Per-path ULID classification in `ExternalChangeReconciler` | Connection cascade (standalone, already callable) |
| Stamp-on-first-sight write-back — Page frontmatter id **and** sidecar id | `IndexUpdater` upsert/delete per entity kind |
| Index-upsert loop added to the **Page loaders and both Agenda loaders** | Context loaders (already upsert on load); per-entity `delete*` |
| Editor: pending-edit state + `reloadFromDisk()` + meta-refresh + by-id registry match | `@Observable` UI refresh; atomic preserving-write; XCTest guard |
| Folder-cascade child-bucket clear; Context/Agenda reconcile wiring | Existing folder-changed hook |

### Out Of Scope (Deliberately Cut)

- **Content-diff echo filter** — replaced by the last-seen map.
- **Write-path instrumentation / outbound ledger** — unneeded (self-writes settle via body-equality + idempotent reconcile, given the index-database exclusion).
- **Custom debounce layer** — native FSEvents latency.
- **`modified_at` write-back** — the field exists; the only concern is not gratuitously bumping it during reconcile.
- **Conflict-copy / "keep both"**, **sync toast** — not in this design.
- **Broken-link / duplicate-title warning UI and FTS5 search** — separate features in the same roadmap phase; the watcher keeps the index correct and degrades gracefully, but ships no new UI.

### Testing

- **Unit, via injected synthetic events:** the last-seen gate (echo + stale-write + temp-churn no-op); the intake filter (index-database events dropped); per-path ULID classification (move vs delete-plus-create); stamp-on-first-sight persists a ULID (frontmatter + sidecar) and suppresses its own echo; coarse reload refreshes a list and indexes new items without disturbing an open editor; each matrix row, across kinds.
- **Behavior guarantees:** external rename of an **open** Page refreshes its identity (no resurrection of the old file); dirty editor survives an external edit and suppresses an external delete (inbound links stay resolved); clean open editor reloads; true delete deactivates links; folder rename re-points children; title collision degrades, not crashes; the app's own index churn produces no reconcile.
- The thin FSEvents binding is hand-verified; the XCTest-host guard is respected.

### Deferred / Edges

- Live handling of the Nexus *root* being moved/renamed (the bookmark re-resolves on next launch).
- Context↔context relations follow the same reconcile path once that relation design lands.
