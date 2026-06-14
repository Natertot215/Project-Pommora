### Architecture — Data Layer + Nexus

How Pommora's data layer works: the on-disk Nexus, the manager + cache surface, the SQLite index, the atomic-write contract, the adopter that opens any folder as a Nexus, and the file-watcher for external edits.

PRD carries the high-altitude storage model + SQLite DDL; this doc covers the **dynamics** — how the layers cooperate and what invariants hold.

---

#### Two load-bearing principles

These principles hold the data layer together. Every architectural choice below traces back to one of them.

1. **Files are canonical (≠ everything is Markdown).** Pages = `.md` (YAML frontmatter + body), Areas = folder + `_area.json`, Topics = folder + `_topic.json`, Projects = folder + `_project.json`, Agenda Tasks = `.task.json`, Agenda Events = `.event.json`, Homepage = `.nexus/homepage.json`, Settings = `.nexus/settings.json`. Among operational content, only Pages are Markdown — Agenda, sidecars, Contexts, Homepage, and Settings stay JSON. Per-Type schemas live in per-kind sidecars at the relevant folder (`_pagetype.json` / `_pagecollection.json` / `_pageset.json` / `_taskconfig.json` / `_eventconfig.json`). SQLite is performance scaffolding, never source of truth. No user data is trapped in the DB.

2. **Agent legibility.** External agents (Claude via MCP, any filesystem tool, vim, Obsidian) can read Pommora's entire structured graph — Pages, schemas, relations, properties — directly from files without tool-call round-trips. This is the differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Any choice that trades file-canonical legibility for app-internal convenience violates this principle.

---

#### Nexus layout

A Nexus is a single folder. Pommora opens it via picker (security-scoped bookmark) and treats it as canonical content. The Nexus can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync.

```
<picked nexus folder>/                  ← canonical content; syncs with cloud
  Assignments/                          ← Page Type (root folder, identified by sidecar)
    _pagetype.json                      ← shared property schema
    Spring-2026/                        ← Page Collection (sub-folder)
      _pagecollection.json              ← collection metadata + per-Collection views[] + set_order
      Midterm-Prep/                     ← Page Set (optional schema-less sub-folder)
        _pageset.json                   ← set metadata (id + collection_id + icon + page_order)
        Exam-Review.md                  ← Page inside a Page Set
      Essay-1.md                        ← Page at Collection root
    Final-Project.md                    ← Page directly in Page Type

  Tasks/                                ← AgendaTask singleton (folder + _taskconfig.json)
    _taskconfig.json
    Submit-grant-proposal.task.json

  Events/                               ← AgendaEvent singleton (folder + _eventconfig.json)
    _eventconfig.json
    Team-standup.event.json

  .nexus/                               ← app-internal config + index (nexus-portable; syncs)
    nexus.json                          ← ULID + createdAt
    state.json                          ← session state (open tabs, sidebar UI, Recents)
    settings.json                       ← per-Nexus UI labels + accent color + excluded_folders
    tier-config.json                    ← Contexts tier labels (singular + plural)
    saved-config.json                   ← Saved-section entry labels
    homepage.json                       ← singleton Homepage entity (composed blocks)
    index.db                            ← SQLite index (regeneratable, schema-versioned)
    areas/<Title>/_area.json            ← tier-1 Contexts (free-standing folder + sidecar)
    topics/<Title>/_topic.json          ← tier-2 Contexts (free-standing folder + sidecar)
    projects/<Title>/_project.json      ← tier-3 Contexts (free-standing folder + sidecar)
    attachments/<entity-id>/            ← copy-on-attach files (file/attachment properties)

  .trash/                               ← deleted entities (nexus-local trash; v1+ surface)
    Assignments/Old-essay.md            ← preserves original relative path under the source Type

~/Library/Application Support/com.nathantaichman.Pommora/   ← machine-specific; never syncs
  state.json                            ← security-scoped bookmark + recent-nexuses
```

**Classification by sidecar filename alone.** A root folder containing `_pagetype.json` IS a Page Type — regardless of folder name. Folders renameable via Finder; the sidecar identifies kind. The five per-kind sidecar filenames (`_pagetype.json` / `_pagecollection.json` / `_pageset.json` / `_taskconfig.json` / `_eventconfig.json`) are the discriminators. Container depth is strictly three levels — depth-2 folders inside a Collection are Page Sets; deeper folders are sidecar-less and their pages roll up into the nearest Set (→ `// Features//Sets.md`).

**No wrapper folders.** Page Types, Tasks singleton, Events singleton all live as siblings at the nexus root. The legacy `Pages/` / `Agenda/` wrappers (paradigmV2-era) are unwrapped by the adopter and disappear from the on-disk shape.

**Hidden + private.** `.nexus/` and `.trash/` (leading dot) are hidden from the sidebar and from non-Pommora tools by convention (matches `.obsidian/`). Pommora's own writes to `.nexus/` don't surface in the user-facing tree.

**User folder exclusion.** Beyond the built-in convention skips (dot/underscore-prefixed + `node_modules`), the user can exclude arbitrary folders via `excluded_folders` on `settings.json` — anchored, vault-relative paths (`Archive`, `Projects/Old`) that Pommora ignores *completely*: never adopted, shown in the sidebar, indexed, walked for content, or touched by the launch auto-tag pass, at any depth. The single rule is `FolderFilter` (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected), loaded from disk via `FolderFilter.load(for:)` — so it works in the index-rebuild pass that runs before `NexusEnvironment` exists — and applied as a subtractive veto *in front of* every user-content discovery site through a defaulted `folderFilter:` parameter on `Filesystem.childFolders` / `descendantFiles`. The per-kind positive discovery (each kind finds its own sidecar) is unchanged; the `.nexus/` internal Context reads (Areas / Topics / Projects) never consult the filter. Stale entries are inert (git semantics); editing UI is deferred to the Settings panel.

---

#### Manager + cache layer

Per-entity managers own the in-memory cache for their kind. They load files at app start, mirror to the SQLite index, and write atomically on every mutation.

| Manager | Owns | Source |
|---|---|---|
| `PageTypeManager` | In-memory list of Page Types + their Collections | `_pagetype.json` + `_pagecollection.json` files at nexus root |
| `PageSetManager` | In-memory Page Sets per Collection (loads after vaults — needs Collections) | `_pageset.json` files inside Page Collections |
| `PageContentManager` | Per-Page bodies + frontmatter | `.md` files inside Page Types |
| `AgendaTaskManager` | Tasks + schema | `.task.json` files + `_taskconfig.json` |
| `AgendaEventManager` | Events + schema | `.event.json` files + `_eventconfig.json` |
| `AreaManager` / `TopicManager` / `ProjectManager` | Contexts (tier-1 / tier-2 / tier-3) | `_area.json` / `_topic.json` / `_project.json` under `.nexus/areas/` / `.nexus/topics/` / `.nexus/projects/` |
| `HomepageManager` | Singleton dashboard | `.nexus/homepage.json` |
| `SettingsManager` | UI labels + accent color | `.nexus/settings.json` |

Managers are `@MainActor` `@Observable` classes. SwiftUI views observe them directly via `@Environment(...)`. Heavy services (the SQLite index, parsers) stay in DI to avoid re-init on view rebuild.

**`loadAll` mirrors parents to the SQLite index.** Established invariant: after `loadAll`, every in-memory parent (PageType / PageCollection) is also present in the corresponding SQLite table. `PageTypeManager.loadAll` defensively `INSERT OR REPLACE`s after disk-load (idempotent; `try?` swallows failures since the index is regeneratable). Without this, any page CRUD into a non-CRUD-created vault (adoption / external Finder folders / post-adoption state) triggers SQLite error 19 (FK constraint failed). Regression-tested in `LoadAllIndexSyncTests.swift`.

---

#### SQLite index — regeneratable scaffolding

The index lives at `<nexus>/.nexus/index.db`. It travels with the Nexus, so a moved or renamed Nexus keeps its index without re-pathing. It holds titles / properties / links / relations — **never** Page bodies (the `pages` table has no body column; full-text search reads files directly).

**Fully regeneratable.** `PommoraIndex.open` stamps the file with a `schema_version` and force-deletes + rebuilds via `IndexBuilder` whenever that version differs from the code's `currentSchemaVersion` (currently **14**; a bump marks every pre-v14 DB stale so it deletes + recreates on open — no data migration). No user data is trapped — losing the index file just means a rebuild on next open.

**Launch-tail indexing contract.** On launch, the index rebuilds **only** when the schema-version mismatch flags `needsRebuild` — there is no unconditional launch scan. The version is stamped only *after* `IndexBuilder.populate` succeeds, so a failed rebuild retries next launch instead of locking in an empty index. Consequence: a page Finder-dropped *after* the index is current-stamped enters the index via CRUD upserts (or a forced rebuild), **not** via the launch path.

**Ten data tables** (DDL canonical in PRD § SQLite Schema): `page_types`, `page_collections`, `page_sets`, `pages`, `agenda_tasks`, `agenda_events`, `contexts`, `context_links`, `connections`, `property_definitions`. Tier relations use the `context_links` table — there is no separate tier table; body connections use the `connections` table (page-only — `source_kind` / `target_kind` are always `"page"`). Plus an internal `meta(key, value)` table holding the `schema_version` itself.

**Query surface.** `IndexQuery` (`Index/IndexQuery.swift`) is a Notion-style filter/sort/group/broken-links facade — it composes parameterized SQL using SQLite's JSON1 extension to reach into the `properties` JSON column, and reads the `context_links` table for tier-relation lookups. Embedded views in Contexts / Homepage flow through this surface. So the UI is one hop removed from the canonical file: it renders what the **store → query → render** chain hands it (file → index → `IndexQuery` → view), never the file directly. A wrong, empty, or `(missing)` surface therefore localizes to the query/render hop — stale or unbuilt index rows, a load-timing or layout fault in the view — and is not by itself evidence that the canonical file is wrong; confirm the data at the relevant hop (read the file, run the query) before attributing a fault to the store.

**Reverse-view query (Context-side Linked-from).** `IndexQuery.incomingContextLinks(targetID:)` reads the `context_links` table for every row whose `target_id` equals a given ID, returning one `EntityRef` per row built from `source_id` + `source_kind`, with each source's current title resolved by joining `source_id` to its source-kind table. It powers a Context's Linked-from surface — every operational entity that links to that Context via a tier relation. Each `tier1` / `tier2` / `tier3` value emits one row into `context_links` (`property_id` = the reserved tier ID `_tier1` / `_tier2` / `_tier3`, `target_kind` = the coarse `area` / `topic` / `project`). The `target_kind` string is derived by `RelationTargetKind.string(from:)`, shared between the full rebuild and incremental upsert paths.

**Update path: `IndexUpdater`.** Wired into the per-entity content + type managers (Pages, Page Types, Agenda Tasks, Agenda Events) plus Contexts and property definitions; mid-session mutations propagate to the DB without waiting for a restart. Pattern: every manager mutation method (`upsertX`, `deleteX`) runs after the atomic file write succeeds.

**FK constraint shape.** Most relationships cascade-delete in SQLite (`ON DELETE CASCADE` on `page_type_id`; `page_sets.page_collection_id` cascades with its Collection). The `page_collection_id` and `page_set_id` fields on `pages` are `ON DELETE SET NULL` so deleting a Collection or Set doesn't cascade-delete its child Pages — they move up a level in the index until the next `loadAll` reconciles.

---

#### Atomic-write contract

Every file write goes through one of three atomic-write helpers:

- **`AtomicYAMLMarkdown.write(frontmatter:body:to:)`** — Pages. Composes `---\n<yaml>\n---\n\n<body>` then writes via temp-file + rename. The preserving overload (`write(...preservingFrom:modeledKeys:)`) re-reads the file it's overwriting and merges by value: it re-serializes only the type's own *modeled* keys and **preserves every foreign frontmatter key by value** (plugin / Obsidian / external keys are never culled — including an on-disk `Class` key, which Pommora neither models nor writes). Yams round-trips by value — flow style reflows to block style and comments/anchors are dropped — but no key/value is lost. Each frontmatter declares `static modeledKeys` so the merge knows which keys it owns; everything else passes through.
- **`AtomicJSON.write(value, to:)`** — sidecars, Agenda Tasks / Events, Contexts, Settings, Homepage. Encodes via `JSONEncoder` then writes via temp-file + rename.
- **`SchemaTransaction`** — multi-file commits for schema operations that must succeed-or-fail as a unit (e.g. move-strip touches the moved entity across multiple types). Composes a transaction shape (`writes: [FileWrite]` + `schemaWrites: [SchemaWrite]`), validates, then applies temp-files + rename in dependency order with rollback on failure.

**Why temp-file + rename, not in-place write.** POSIX rename is atomic on the same filesystem. A crash mid-write leaves either the old file (rename never happened) or the new file (rename completed) — never a half-written file. macOS / APFS preserves this guarantee.

**The save pipeline shape** (Pages): keystroke → `viewModel.body didSet` → `scheduleSave()` 300ms debounce → `PageContentManager.updatePage` → `AtomicYAMLMarkdown.write` (temp-file + rename) → `IndexUpdater.updatePage`. Flush triggers on context loss (page-switch, window-close, app resignActive / willTerminate, `⌘S`). The editor binds ONLY to `body` — frontmatter is held as a typed struct and re-serialized on save; the user can't destroy frontmatter via the editor. Full editor-side detail → `// Features//PageEditor.md` § "Save pipeline".

---

#### File-watcher contract (deferred)

External edits (Obsidian / vim / Finder rename / cloud-sync mtime drift) must propagate to the SQLite index + in-memory caches + sidebar without a restart. Uses `FSEventStream` (recursive watch on the Nexus root) with self-write filtering (debounce by path + outbound mtime tracking) and lost-update protection (mtime compare before overwriting). The atomic-write discipline + `IndexUpdater` shape already support this — the watcher is a wiring task, not an architectural change.

---

#### Adoption — opening any folder as a Nexus

`NexusAdopter` classifies each root folder independently when a folder is first opened as a Nexus — fresh (no recognized sidecar → content-sniff always picks a Page Type), legacy Vault sidecar (rename to `_pagetype.json`), legacy wrapper layout (unwrap + rename), or already flat (no-op). Idempotent; per-folder atomicity (no two-phase transaction across folders); safe to re-run on partial state. Hidden folders (leading `.` or `_`) skipped. Preview-before-commit via `AdoptionPreviewView` shows per-Type counts + warnings; fully-flat Nexuses skip the sheet silently. Full per-shape detail → `// Features//PageTypes.md` § "Adopting existing folders".

**Legacy `_itemtype.json` folders.** A pre-collapse sidecar is not a recognized per-kind sidecar, so the folder classifies as **sidecar-less** — adoption auto-tags it with a fresh `_pagetype.json`, the stale legacy sidecar stays **inert on disk** (it is not a recognized cleanup orphan), and the folder's members index as pages. Pinned by `LegacyItemTypeSidecarAdoptionTests`.

**Kind authority = the folder sidecar, not the extension.** A `.md` file's kind comes from its parent folder's sidecar (`_pagetype.json` → Page), never from a frontmatter field. There is no kind stamp in frontmatter — an on-disk `Class` key is treated as preserved foreign frontmatter (carried by value, never written by Pommora).

---

#### Migration — schema versioning + property-ID rewrites

Pommora carries two migration mechanisms:

**1. Index-side schema version** — covered above (the code's `PommoraIndex.currentSchemaVersion`; a mismatch deletes + rebuilds, no per-user migration).

**2. File-side schema version + property migration.** Each Pommora-written Type sidecar carries a `schema_version` (Page Types at 2; legacy decode with no version reads as 0). `PropertyIDMigration` runs on every Nexus open: it mints stable ULID `id`s for name-keyed properties, normalizes relation shapes (array-wrapped values, the `relation_target` key), and rewrites entity files to reference properties by ID. Two-phase (scan / apply), idempotent. Lossless normalization applies silently. User-relation definitions are stripped at decode time (via `droppingUserRelations()`) before the migration scan runs; orphaned `$rel` member values are cleared opportunistically during the migration's member-walk.

**Settings auto-migration.** `Settings.defaultsVersion: Int` + `Settings.migrate(_:)` step-function scaffold. `SettingsManager.loadOrSeed` calls `migrate` after decode + re-persists only when changed (mtime stays stable on no-op launches). Bump the constant + add a migration step when defaults change.

---

#### What this data layer leaves to the OS

File-canonicality's payoffs (external-editor compatibility, agent legibility, cloud-sync-for-free) are the two load-bearing principles above. What's deliberately *not* built:

- **Versioning / file history / backup** — Time Machine, `git` on the Nexus, filesystem snapshots. No internal version store, no auto-commit; in-session undo is free from the editor.
- **Cross-device sync (v1)** — user picks the Nexus location; placing it in a synced folder gives device-to-device sync. Real cloud sync is a long-term Prospect.

---

#### Discipline (not enforcement)

No enforced layer separation. Patterns that keep the data layer tractable:

- **Per-Type schemas live in JSON sidecars** (canonical), not code; Page frontmatter lives inline in each `.md` file.
- **Foreign frontmatter is preserved by value** on every Page write path — an external tool's frontmatter keys survive Pommora's saves (mechanism detailed at `AtomicYAMLMarkdown` above).
- **View specs are data** (filter / sort / group / shown-properties on each storage container's `views[]`).
- **File renames + connection resolution as algorithm.** Connections resolve by title at render time (backed by index-based ID lookup); renames are pure filesystem renames followed by a cascade body-rewrite of all referencing files.
- **Agent-legibility check per decision** — would an external file-only agent still see this? If no, revisit.

---

#### Reference

- `PommoraPRD.md` — high-altitude product spec; storage model overview; SQLite DDL.
- `// Features//Domain-Model.md` — 2-layer model + PARA mapping + linking model.
- `// Features//Properties.md` — per-Type property catalog; tier-relation (context-link) properties; move-strip semantics.
- `// Guidelines//CRUD-Patterns.md` — per-entity CRUD UI patterns + atomic-write discipline.
- `// rules//MarkdownPM.md` — editor architecture (dynamic-syntax, anti-patterns, save pipeline).
