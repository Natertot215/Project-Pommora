### Architecture — Data Layer + Nexus

How Pommora's data layer works: the on-disk Nexus, the manager + cache surface, the SQLite index, the atomic-write contract, the adopter that opens any folder as a Nexus, and the file-watcher for external edits.

PRD carries the high-altitude storage model + SQLite DDL; this doc covers the **dynamics** — how the layers cooperate and what invariants hold.

---

#### Two load-bearing principles

These principles hold the data layer together. Every architectural choice below traces back to one of them.

1. **Files are canonical (≠ everything is Markdown).** Pages = `.md`, **Items = `.md`** (YAML frontmatter + body; the capped description IS the body — Shape A, single source of truth), Spaces = `.space.json`, Topics = folder + `_topic.json`, Projects = `.project.json`, Agenda Tasks = `.task.json`, Agenda Events = `.event.json`, Homepage = `.nexus/homepage.json`, Settings = `.nexus/settings.json`. Among operational content, only Items are Markdown — Agenda, sidecars, Contexts, Homepage, and Settings stay JSON. Per-Type schemas live in per-kind sidecars at the relevant folder (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). SQLite is performance scaffolding, never source of truth. No user data is trapped in the DB.

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
    _itemtype.json                      ← sidecar stays JSON (kind authority)
    Tech/                               ← Item Collection ("Set")
      _itemcollection.json
      Swift-evolution.md                ← Item (frontmatter + capped body)
    Hacker-News.md                      ← Item directly in Item Type

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

**User folder exclusion.** Beyond the built-in convention skips (dot/underscore-prefixed + `node_modules`), the user can exclude arbitrary folders via `excluded_folders` on `settings.json` — anchored, vault-relative paths (`Archive`, `Projects/Old`) that Pommora ignores *completely*: never adopted, shown in the sidebar, indexed, walked for content, or touched by the launch auto-tag pass, at any depth. The single rule is `FolderFilter` (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected), loaded from disk via `FolderFilter.load(for:)` — so it works in the index-rebuild pass that runs before `NexusEnvironment` exists — and applied as a subtractive veto *in front of* every user-content discovery site through a defaulted `folderFilter:` parameter on `Filesystem.childFolders` / `descendantFiles`. The per-kind positive discovery (each kind finds its own sidecar) is unchanged; the `.nexus/` internal Context reads (Spaces / Topics) never consult the filter. Stale entries are inert (git semantics); editing UI ships with the v0.6.0 Settings panel. Spec → `Planning/2026-06-03-Folder-Exclusion-Plan.md`.

---

#### Manager + cache layer

Per-entity managers own the in-memory cache for their kind. They load files at app start, mirror to the SQLite index, and write atomically on every mutation.

| Manager | Owns | Source |
|---|---|---|
| `PageTypeManager` | In-memory list of Page Types + their Collections | `_pagetype.json` + `_pagecollection.json` files at nexus root |
| `ItemTypeManager` | In-memory list of Item Types + their Item Collections | `_itemtype.json` + `_itemcollection.json` files at nexus root |
| `PageContentManager` | Per-Page bodies + frontmatter | `.md` files inside Page Types |
| `ItemContentManager` | Per-Item bodies (capped description) + frontmatter | `.md` files inside Item Types |
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

**Query surface.** `IndexQuery` (`Index/IndexQuery.swift`) is a Notion-style filter/sort/group/broken-links facade — it composes parameterized SQL using SQLite's JSON1 extension to reach into the `properties` JSON column, and reads the `relations` table for relation lookups. Embedded views in Contexts / Homepage flow through this surface. So the UI is one hop removed from the canonical file: it renders what the **store → query → render** chain hands it (file → index → `IndexQuery` → view), never the file directly. A wrong, empty, or `(missing)` surface therefore localizes to the query/render hop — stale or unbuilt index rows, a load-timing or layout fault in the view — and is not by itself evidence that the canonical file is wrong; confirm the data at the relevant hop (read the file, run the query) before attributing a fault to the store.

**Reverse-view query (Context-side Linked-from).** `IndexQuery.incomingRelations(targetID:)` reads the `relations` table for every row whose `target_id` equals a given ID, returning one `EntityRef` per row built from `source_id` + `source_kind`, with each source's current title resolved by joining `source_id` to its source-kind table. It powers a Context's Linked-from surface — every operational entity that links to that Context. **Tier relations route through the same query.** Each `tier1` / `tier2` / `tier3` value emits one row into `relations` (`property_id` = the reserved tier ID `_tier1` / `_tier2` / `_tier3`, `target_kind` = the coarse `space` / `topic` / `project`), so tier-tagged entities and user-defined Relation-property values both surface from a single `relations` read — no separate per-tier table to join. The `target_kind` string is derived by `RelationTargetKind.string(from:)`, shared between the full rebuild and incremental upsert paths.

**Update path: `IndexUpdater`.** Wired into the per-entity content + type managers (Pages, Items, Page/Item Types, Agenda Tasks, Agenda Events) plus Contexts and property definitions; mid-session mutations propagate to the DB without waiting for a restart. Pattern: every manager mutation method (`upsertX`, `deleteX`) runs after the atomic file write succeeds.

**FK constraint shape.** Most relationships cascade-delete in SQLite (`ON DELETE CASCADE` on `page_type_id` / `item_type_id` / etc.). The `page_collection_id` and `item_collection_id` fields on `pages` and `items` are `ON DELETE SET NULL` so deleting a Collection doesn't cascade-delete its child Pages / Items — they move back to the Type root in the index until the next `loadAll` reconciles.

---

#### Atomic-write contract

Every file write goes through one of three atomic-write helpers:

- **`AtomicYAMLMarkdown.write(frontmatter:body:to:)`** — **Pages AND Items** (one shared codec). Composes `---\n<yaml>\n---\n\n<body>` then writes via temp-file + rename. The preserving overload (`write(...preservingFrom:modeledKeys:)`) re-reads the file it's overwriting and merges by value: it re-serializes only the type's own *modeled* keys and **preserves every foreign frontmatter key by value** (plugin / Obsidian / external keys are never culled). Yams round-trips by value — flow style reflows to block style and comments/anchors are dropped — but no key/value is lost. Each frontmatter declares `static modeledKeys` so the merge knows which keys it owns; everything else passes through.
- **`AtomicJSON.write(value, to:)`** — sidecars, Agenda Tasks / Events, Contexts, Settings, Homepage. Encodes via `JSONEncoder` then writes via temp-file + rename.
- **`SchemaTransaction`** — multi-file commits for schema operations that must succeed-or-fail as a unit (e.g. paired-relation create touches two sidecars; move-strip touches the moved entity + paired-relation reverse refs across multiple types). Composes a transaction shape (`writes: [FileWrite]` + `schemaWrites: [SchemaWrite]`), validates, then applies temp-files + rename in dependency order with rollback on failure.

**Why temp-file + rename, not in-place write.** POSIX rename is atomic on the same filesystem. A crash mid-write leaves either the old file (rename never happened) or the new file (rename completed) — never a half-written file. macOS / APFS preserves this guarantee.

**The save pipeline shape** (Pages, as the most complex example): keystroke → `viewModel.body didSet` → `scheduleSave()` 300ms debounce → `PageContentManager.updatePage` → `AtomicYAMLMarkdown.write` (temp-file + rename) → `IndexUpdater.updatePage`. Flush triggers on context loss (page-switch, window-close, app resignActive / willTerminate, `⌘S`). The editor binds ONLY to `body` — frontmatter is held as a typed struct and re-serialized on save; the user can't destroy frontmatter via the editor. Item save pipeline mirrors this via `ItemContentManager.updateItem` + the same `AtomicYAMLMarkdown.write` (preserving overload) — the Item's capped description is its body, structured fields are its frontmatter, and foreign keys ride through untouched. Full editor-side detail → `// Features//PageEditor.md` § "Save pipeline".

---

#### File-watcher contract (deferred — `Framework.md` v0.4.0)

External edits (Obsidian / vim / Finder rename / cloud-sync mtime drift) must propagate to the SQLite index + in-memory caches + sidebar without a restart. Planned shape:

- **FSEventStream** — recursive watch on the Nexus root with a per-event payload (`DispatchSource.makeFileSystemObjectSource` is per-fd, no recursion).
- **Self-write filtering** — debounce 50–100ms by path; track outbound mtimes so Pommora's own `.tmp` + rename writes don't round-trip through the watcher.
- **Lost-update protection** — on entity save, compare on-disk mtime to the last-loaded version; prompt to reload before overwriting if it drifted.

The atomic-write discipline + IndexUpdater shape already support this — the watcher is a wiring task, not an architectural change.

---

#### Adoption — opening any folder as a Nexus

`NexusAdopter` classifies each root folder independently when a folder is first opened as a Nexus — fresh (content-sniff finds Markdown → defaults to a Page Type), legacy Vault sidecar (rename to `_pagetype.json`), legacy wrapper layout (unwrap + rename), or already flat (no-op). Idempotent; per-folder atomicity (no two-phase transaction across folders); safe to re-run on partial state. Hidden folders (leading `.` or `_`) skipped. Preview-before-commit via `AdoptionPreviewView` shows per-Type counts + warnings; fully-flat Nexuses skip the sheet silently. Full per-shape detail → `// Features//PageTypes.md` § "Adopting existing folders" + `// Features//Items.md` § (parallel rule on the Items side).

**Kind authority = the folder sidecar, not the extension.** Now that both Pages and Items are `.md`, the file extension no longer discriminates form — the parent Type folder's sidecar (`_itemtype.json` / `_pagetype.json`) is authoritative. Each content file also carries a reserved, UI-hidden, **non-authoritative** `Class` frontmatter stamp (`item` | `page`) recording its form; on a clean nexus it agrees with the folder. A stamp/folder disagreement — or a homeless file with no Type-folder context up the chain — routes the file to a hidden `.unsorted` inbox (sibling of `.trash`; future-UI-surfaced) rather than being silently re-stamped. A content-sniff'd `.md` folder *without* a sidecar adopts as a Page Type; hand-adding Items to a Finder-built folder requires writing the `_itemtype.json` sidecar.

---

#### Migration — schema versioning + property-ID rewrites

Pommora carries two migration mechanisms:

**1. Index-side schema version** — covered above (the code's `PommoraIndex.currentSchemaVersion`; a mismatch deletes + rebuilds, no per-user migration).

**2. File-side schema version + property migration.** Each Pommora-written Type sidecar carries a `schema_version` (Page/Item Types at 2; legacy decode with no version reads as 0). `PropertyIDMigration` runs on every Nexus open: it mints stable ULID `id`s for name-keyed properties, normalizes relation shapes (array-wrapped values, the `relation_target` key, Collection targets rewritten to their parent Type), and rewrites entity files to reference properties by ID. Two-phase (scan / apply), idempotent. Lossless normalization applies silently; the one lossy change — dropping a relation property that targets a context tier — surfaces in the preview sheet behind an explicit acknowledgment.

**3. Item `.json`→`.md` format migration.** `ItemFormatMigration` normalizes legacy whole-`.json` Items into the `.md` form (frontmatter + body). It **auto-runs once at launch** (mandatory one-time normalization, mirroring `PropertyIDMigration`'s invocation) — **not a declinable consent-gate**, because the transitional dual-format read/write code is retired once no `.json` Items remain, so a declined migration would hide the un-normalized Items. Per Item it stages the new `.md` plus the old `.json` → `.trash` in one `SchemaTransaction`; idempotent on the file transition and resumable after an interrupt (re-running only touches Items still in `.json`); failures are reported, not thrown. Subject to the XCTest launch-modal guard (CLAUDE.md quirk #16).

**Settings auto-migration.** `Settings.defaultsVersion: Int` + `Settings.migrate(_:)` step-function scaffold. `SettingsManager.loadOrSeed` calls `migrate` after decode + re-persists only when changed (mtime stays stable on no-op launches). Bump the constant + add a migration step when defaults change.

---

#### What this data layer leaves to the OS

File-canonicality's payoffs (external-editor compatibility, agent legibility, cloud-sync-for-free) are the two load-bearing principles above. What's deliberately *not* built:

- **Versioning / file history / backup** — Time Machine, `git` on the Nexus, filesystem snapshots. No internal version store, no auto-commit; in-session undo is free from the editor.
- **Cross-device sync (v1)** — user picks the Nexus location; placing it in a synced folder gives device-to-device sync. Real cloud sync is a long-term Prospect.

---

#### Discipline (not enforcement)

No enforced layer separation. Patterns that keep the data layer tractable:

- **Per-Type schemas live in JSON sidecars** (canonical), not code; Page and Item frontmatter lives inline in each `.md` file.
- **Item entries are individual `.md` files** (frontmatter + capped body), not SQLite-only — agents read them directly, same as Pages.
- **Foreign frontmatter is preserved by value** on every Page AND Item write path — an external tool's frontmatter keys survive Pommora's saves (mechanism detailed at `AtomicYAMLMarkdown` above).
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
