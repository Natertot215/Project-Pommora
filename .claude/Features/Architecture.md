### Architecture — Data Layer + Nexus

How Pommora's data layer actually works: the on-disk Nexus, the manager + cache surface, the SQLite index that stays in sync with it, the atomic-write contract that makes saves crash-safe, the adopter that opens any folder as a Nexus, and the file-watcher that keeps everything in sync with external edits.

PRD carries the high-altitude storage model + SQLite DDL. This doc covers the **dynamics** — how the layers cooperate, what invariants hold, and the rules that keep the whole thing legible to external agents.

---

#### Two load-bearing principles

These principles hold the data layer together. Every architectural choice below traces back to one of them.

1. **Files are canonical.** Pages = `.md`, Items = `.json`, Spaces = `.space.json`, Topics = folder + `_topic.json`, Projects = `.project.json`, Agenda Tasks = `.task.json`, Agenda Events = `.event.json`, Homepage = `.nexus/homepage.json`, Settings = `.nexus/settings.json`. Per-Type schemas live in per-kind sidecars at the relevant folder (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). SQLite is performance scaffolding, never source of truth. No user data is trapped in the DB.

2. **Agent legibility.** External agents (Claude via MCP, any filesystem tool, vim, Obsidian) can read Pommora's entire structured graph — Pages, Items, schemas, relations, properties — directly from files without tool-call round-trips. This is the differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Any choice that trades file-canonical legibility for app-internal convenience violates this principle.

---

#### Nexus layout

A Nexus is a single folder. Pommora opens it via picker (security-scoped bookmark) and treats it as canonical content. The Nexus can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync.

```
<picked nexus folder>/                  ← canonical content; syncs with cloud
  Assignments/                          ← Page Type (root folder, identified by sidecar)
    _pagetype.json                      ← shared property schema
    Spring-2026/                        ← Page Collection (sub-folder)
      _pagecollection.json              ← collection metadata + per-Collection views[]
      Essay-1.md                        ← Page
    Final-Project.md                    ← Page directly in Page Type

  Bookmarks/                            ← Item Type
    _itemtype.json
    Tech/                               ← Item Collection ("Set")
      _itemcollection.json
      Swift-evolution.json              ← Item
    Hacker-News.json                    ← Item directly in Item Type

  Tasks/                                ← AgendaTask singleton (folder + _taskconfig.json)
    _taskconfig.json
    Submit-grant-proposal.task.json

  Events/                               ← AgendaEvent singleton (folder + _eventconfig.json)
    _eventconfig.json
    Team-standup.event.json

  .nexus/                               ← app-internal config + index (nexus-portable; syncs)
    nexus.json                          ← ULID + createdAt
    state.json                          ← session state (open tabs, sidebar UI, Recents)
    settings.json                       ← per-Nexus UI labels + accent color
    tier-config.json                    ← Contexts tier labels (singular + plural)
    saved-config.json                   ← Saved-section item labels
    homepage.json                       ← singleton Homepage entity (composed blocks)
    index.db                            ← SQLite index (regeneratable, schema-versioned)
    spaces/                             ← tier-1 Contexts (flat files)
    topics/                             ← tier-2 Contexts (folders) + tier-3 Projects (files inside)
    attachments/<entity-id>/            ← copy-on-attach files (file/attachment properties)

  .trash/                               ← deleted entities (nexus-local trash; v1+ surface)
    Assignments/Old-essay.md            ← preserves original relative path under the source Type

~/Library/Application Support/com.nathantaichman.Pommora/   ← machine-specific; never syncs
  state.json                            ← security-scoped bookmark + recent-nexuses
```

**Classification by sidecar filename alone.** A root folder containing `_pagetype.json` IS a Page Type — regardless of folder name. Folders renameable via Finder; the sidecar identifies kind. The six per-kind sidecar filenames (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`) are the discriminators.

**No wrapper folders.** Page Types, Item Types, Tasks singleton, Events singleton all live as siblings at the nexus root. The legacy `Pages/` / `Items/` / `Agenda/` wrappers (paradigmV2-era) are unwrapped by the adopter and disappear from the on-disk shape.

**Hidden + private.** `.nexus/` and `.trash/` (leading dot) are hidden from the sidebar and from non-Pommora tools by convention (matches `.obsidian/`). Pommora's own writes to `.nexus/` don't surface in the user-facing tree.

---

#### Manager + cache layer

Per-entity managers own the in-memory cache for their kind. They load files at app start, mirror to the SQLite index, and write atomically on every mutation.

| Manager | Owns | Source |
|---|---|---|
| `PageTypeManager` | In-memory list of Page Types + their Collections | `_pagetype.json` + `_pagecollection.json` files at nexus root |
| `ItemTypeManager` | In-memory list of Item Types + their Item Collections | `_itemtype.json` + `_itemcollection.json` files at nexus root |
| `PageContentManager` | Per-Page bodies + frontmatter | `.md` files inside Page Types |
| `ItemContentManager` | Per-Item JSON content | `.json` files inside Item Types |
| `AgendaTaskManager` | Tasks + schema | `.task.json` files + `_taskconfig.json` |
| `AgendaEventManager` | Events + schema | `.event.json` files + `_eventconfig.json` |
| `SpaceManager` / `TopicManager` | Contexts (tier-1 / tier-2 + tier-3) | `.space.json` / `_topic.json` / `.project.json` under `.nexus/` |
| `HomepageManager` | Singleton dashboard | `.nexus/homepage.json` |
| `SettingsManager` | UI labels + accent color | `.nexus/settings.json` |

Managers are `@MainActor` `@Observable` classes. SwiftUI views observe them directly via `@Environment(...)`. Heavy services (the SQLite index, parsers) stay in DI to avoid re-init on view rebuild.

**`loadAll` mirrors parents to the SQLite index.** Established invariant: after `loadAll`, every in-memory parent (PageType / PageCollection / ItemType / ItemCollection) is also present in the corresponding SQLite table. `PageTypeManager.loadAll` + `ItemTypeManager.loadAll` defensively `INSERT OR REPLACE` after disk-load (idempotent; `try?` swallows failures since the index is regeneratable). Without this, any page/item CRUD into a non-CRUD-created folder (adoption / external Finder folders / post-adoption state) triggers SQLite error 19 (FK constraint failed). Regression-tested in `LoadAllIndexSyncTests.swift`.

---

#### SQLite index — regeneratable scaffolding

The index lives at `<nexus>/.nexus/index.db`. It travels with the Nexus, so a moved or renamed Nexus keeps its index without re-pathing. It holds titles / properties / links / relations — **never** Page bodies (the `pages` table has no body column; full-text search reads files directly).

**Fully regeneratable.** `PommoraIndex.open` stamps the file with a `schema_version` and force-deletes + rebuilds via `IndexBuilder` whenever that version differs from the code's `currentSchemaVersion`. No user data is trapped — losing the index file just means a rebuild on next open.

**Eleven data tables** (DDL canonical in PRD § SQLite Schema): `page_types`, `item_types`, `page_collections`, `item_collections`, `pages`, `items`, `agenda_tasks`, `agenda_events`, `contexts`, `relations`, `property_definitions`. Tier relations share the `relations` table — there is no separate tier table. Plus an internal `meta(key, value)` table holding the `schema_version` itself.

**Query surface.** `IndexQuery` (`Index/IndexQuery.swift`) is a Notion-style filter/sort/group/broken-links facade — it composes parameterized SQL using SQLite's JSON1 extension to reach into the `properties` JSON column, and reads the `relations` table for relation lookups. Embedded views in Contexts / Homepage flow through this surface.

**Reverse-view query (Context-side Linked-from).** `IndexQuery.incomingRelations(targetID:)` reads the `relations` table for every row whose `target_id` equals a given ID, returning one `EntityRef` per row built from `source_id` + `source_kind`, with each source's current title resolved by joining `source_id` to its owning-kind table. It powers a Context's Linked-from surface — every operational entity that links to that Context. **Tier relations route through the same query.** Each `tier1` / `tier2` / `tier3` value emits one row into `relations` (`property_id` = the reserved tier ID, `target_kind` = `contextTier`), so tier-tagged entities and user-defined Relation-property values both surface from a single `relations` read — no separate per-tier table to join.

**Update path: `IndexUpdater`.** Wired into all six entity managers; mid-session mutations propagate to the DB without waiting for a restart. Pattern: every manager mutation method (`createX`, `updateX`, `deleteX`, `renameX`) calls the corresponding `IndexUpdater.x` after the atomic file write succeeds.

**FK constraint shape.** Most relationships cascade-delete in SQLite (`ON DELETE CASCADE` on `page_type_id` / `item_type_id` / etc.). The `page_collection_id` and `item_collection_id` fields on `pages` and `items` are `ON DELETE SET NULL` so deleting a Collection doesn't cascade-delete its child Pages / Items — they move back to the Type root in the index until the next `loadAll` reconciles.

---

#### Atomic-write contract

Every file write goes through one of three atomic-write helpers:

- **`AtomicYAMLMarkdown.write(frontmatter:body:to:)`** — Pages. Composes `---\n<yaml>\n---\n\n<body>` then writes via temp-file + rename.
- **`AtomicJSON.write(value, to:)`** — Items, sidecars, Agenda Tasks / Events, Contexts, Settings, Homepage. Encodes via `JSONEncoder` then writes via temp-file + rename.
- **`SchemaTransaction`** — multi-file commits for schema operations that must succeed-or-fail as a unit (e.g. paired-relation create touches two sidecars; move-strip touches the moved entity + paired-relation reverse refs across multiple types). Composes a transaction shape (`writes: [FileWrite]` + `schemaWrites: [SchemaWrite]`), validates, then applies temp-files + rename in dependency order with rollback on failure.

**Why temp-file + rename, not in-place write.** POSIX rename is atomic on the same filesystem. A crash mid-write leaves either the old file (rename never happened) or the new file (rename completed) — never a half-written file. macOS / APFS preserves this guarantee.

**The save pipeline shape** (Pages, as the most complex example): keystroke → `viewModel.body didSet` → `scheduleSave()` 300ms debounce → `PageContentManager.updatePage` → `AtomicYAMLMarkdown.write` (temp-file + rename) → `IndexUpdater.updatePage`. Flush triggers on context loss (page-switch, window-close, app resignActive / willTerminate, `⌘S`). The editor binds ONLY to `body` — frontmatter is held as a typed struct and re-serialized on save; the user can't destroy frontmatter via the editor. Item save pipeline mirrors this via `ItemContentManager.updateItem` + `AtomicJSON.write`. Full editor-side detail → `// Features//PageEditor.md` § "Save pipeline".

---

#### File-watcher contract (deferred; v0.3.3)

External edits — files changed by Obsidian / vim / Finder rename / cloud-sync mtime drift — need to propagate to the SQLite index + the in-memory caches + the sidebar UI without restarting Pommora.

**Tool choice: FSEventStream.** `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong shape. FSEventStream via Swift wrapper (`EonilFSEvents` or hand-rolled `FSEventStreamCreate`) gives recursive watch on the Nexus root with a per-event payload.

**APFS atomic-rename gotchas.** Editor save = `.tmp` write + rename emits create+delete events for the temp. Debounce 50–100ms by path; track outbound mtimes to ignore Pommora's own writes (otherwise every save round-trips through the watcher).

**Lost-update protection.** On Page / Item / AgendaTask / AgendaEvent save, compare on-disk mtime to the version Pommora last loaded. If external mtime drifted, prompt the user to reload before overwriting.

Roadmap entry: `Framework.md` v0.3.3 (FSEventStream + FTS5 + external-edit detection). The data layer's atomic-write discipline + IndexUpdater shape was designed to support this — adding the watcher is a wiring task, not an architectural change.

---

#### Adoption — opening any folder as a Nexus

`NexusAdopter` classifies each root folder independently when a folder is first opened as a Nexus — fresh (content-sniff `.md` vs `.json`), legacy Vault sidecar (rename to `_pagetype.json`), legacy wrapper layout (unwrap + rename), or already flat (no-op). Idempotent; per-folder atomicity (no two-phase transaction across folders); safe to re-run on partial state. Hidden folders (leading `.` or `_`) skipped. Preview-before-commit via `AdoptionPreviewView` shows per-Type counts + warnings; fully-flat Nexuses skip the sheet silently. Full per-shape detail → `// Features//PageTypes.md` § "Adopting existing folders" + `// Features//Items.md` § (parallel rule on the Items side).

---

#### Migration — schema versioning + property-ID rewrites

Pommora carries two migration mechanisms:

**1. Index-side schema version.** The SQLite index file stamps a `meta.schema_version`. On open, `PommoraIndex.open` compares against the code's `currentSchemaVersion`; mismatch deletes the file and rebuilds from disk via `IndexBuilder`. Adding a new index column / table is a `currentSchemaVersion += 1` + one new DDL — no per-user migration.

**2. File-side schema version + property migration.** Each Pommora-written Type sidecar carries a `schema_version` (Page/Item Types at 2). Legacy decode with no version reads as 0; any sidecar below the current version is migrated. `PropertyIDMigration` runs on every Nexus open: it mints stable ULID `id`s for name-keyed properties, normalizes relation shapes (array-wrapped values, the `relation_target` key, Collection targets rewritten to their parent Type), and rewrites entity files to reference properties by ID. Two-phase (scan / apply). Lossless normalization applies silently; the one lossy change — dropping a relation property that targets a context tier — surfaces in the preview sheet behind an explicit acknowledgment. Idempotent.

**Settings auto-migration.** `Settings.defaultsVersion: Int` + `Settings.migrate(_:)` step-function scaffold. `SettingsManager.loadOrSeed` calls `migrate` after decode + re-persists only when changed (mtime stays stable on no-op launches). Bump the constant + add a migration step when defaults change.

---

#### What this data layer enables — and what it leaves to the OS

**Enabled by file-canonicality:**

- **External editor compatibility.** Files open cleanly in Obsidian / Bear / pandoc / iA Writer / GitHub / vim — Pages are standard CommonMark, sidecars are plain JSON, frontmatter is YAML.
- **External agent legibility.** Claude via MCP, any filesystem tool, any future agent reads the entire graph directly. No tool-call round-trips to Pommora.
- **Cloud sync for free.** The Nexus folder can sit in iCloud Drive / Dropbox / any synced folder; per-file conflict resolution is the syncer's job. Real cloud sync (Supabase, etc.) arrives as additive translation — the on-disk model maps cleanly to a cloud DB.

**Deliberately left to OS-level tools:**

- **Versioning / file history / backup.** Time Machine, `git` on the Nexus, filesystem snapshots. No internal version store, no auto-commit. In-session undo is free from the editor.
- **Cross-device sync (v1).** User picks the Nexus location; placing it in a synced folder gives device-to-device sync. Real cloud sync is a long-term Prospect.

---

#### Discipline (not enforcement)

No enforced layer separation. Patterns that keep the data layer tractable:

- **Frontmatter + per-Type schemas live in JSON sidecars** (canonical), not code.
- **Item entries are individual `.json` files**, not SQLite-only — agents read them directly.
- **View specs are data** (filter / sort / group / shown-properties on each storage container's `views[]`).
- **File renames + wikilink resolution as algorithm.** Wikilinks resolve by ID at render time; renames are pure filesystem renames; no body-scan rewrite needed.
- **Agent-legibility check per decision** — would an external file-only agent still see this? If no, revisit.
- **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for module name, app branding, documentation; not allowed in JSON field names (`pommora_*`) or as a Swift type discriminator (`Pommora.X`). Side-prefixed names are canonical when collisions arise (`AgendaTask` not `Pommora.Task`).

---

#### Reference

- `PommoraPRD.md` — high-altitude product spec; storage model overview; SQLite DDL.
- `// Features//Domain-Model.md` — 2-layer model + PARA mapping + linking model.
- `// Features//Properties.md` — per-Type property catalog; relation lifecycle; move-strip semantics.
- `// Guidelines//CRUD-Patterns.md` — per-entity CRUD UI patterns + atomic-write discipline.
- `// Guidelines//Markdown.md` — editor architecture (dynamic-syntax, anti-patterns, save pipeline).
