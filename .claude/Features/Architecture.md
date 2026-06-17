### Architecture — Data Layer + Nexus

The dynamics of Pommora's data layer — the on-disk Nexus, the manager + cache surface, the SQLite index, the atomic-write contract, the adopter, and the external-edit watcher. PRD carries the high-altitude storage model + SQLite DDL.

---

#### Two load-bearing principles

Every architectural choice below traces back to one of these.

1. **Files are canonical (≠ everything is Markdown).** Only Pages are Markdown; Agenda, sidecars, Contexts, Homepage, and Settings stay JSON. On-disk layout + per-kind sidecars below. SQLite is regeneratable scaffolding, never source of truth — no user data is trapped in it.

2. **Agent legibility.** External agents (Claude via MCP, any filesystem tool, vim, Obsidian) read Pommora's entire structured graph — Pages, schemas, relations, properties — directly from files without tool-call round-trips. This differentiates from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Any choice that trades file-canonical legibility for app-internal convenience violates this principle.

---

#### Nexus layout

A Nexus is a single folder. Pommora opens it via picker (security-scoped bookmark) and treats it as canonical content. The Nexus can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync.

```
<picked nexus folder>/                  ← canonical content; syncs with cloud
  <Type>/                               ← Page Type (root folder, identified by sidecar)
    _pagetype.json                      ← shared property schema
    <Collection>/                       ← Page Collection (sub-folder)
      _pagecollection.json              ← collection metadata + per-Collection views[] + set_order
      <Set>/                            ← Page Set (optional schema-less sub-folder)
        _pageset.json                   ← set metadata (id + collection_id + icon + page_order)
        <Page>.md                       ← Page inside a Page Set
      <Page>.md                         ← Page at Collection root
    <Page>.md                           ← Page directly in Page Type

  <Tasks>/                              ← AgendaTask singleton (folder + _taskconfig.json)
    _taskconfig.json
    <title>.task.json

  <Events>/                             ← AgendaEvent singleton (folder + _eventconfig.json)
    _eventconfig.json
    <title>.event.json

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
    <Type>/<Page>.md                    ← preserves original relative path under the source Type

<app-support>/                          ← machine-specific; never syncs
  state.json                            ← security-scoped bookmark + recent-nexuses
```

**Classification by sidecar filename alone.** A root folder containing `_pagetype.json` IS a Page Type — regardless of folder name; folders rename freely via Finder. The five per-kind sidecar filenames (`_pagetype.json` / `_pagecollection.json` / `_pageset.json` / `_taskconfig.json` / `_eventconfig.json`) are the kind discriminators. Container depth is strictly three levels — depth-2 folders inside a Collection are Page Sets; deeper folders are sidecar-less and roll up into the nearest Set (→ `// Features//Sets.md`).

**No wrapper folders.** Page Types and the Tasks / Events singletons all live as siblings at the nexus root — there is no `Pages/` or `Agenda/` container folder.

**Hidden + private.** `.nexus/` and `.trash/` are hidden from the sidebar and from non-Pommora tools by convention (matches `.obsidian/`).

**User folder exclusion.** Beyond the built-in skips (dot/underscore-prefixed + `node_modules`), the user can exclude arbitrary folders via `excluded_folders` on `settings.json` — anchored, vault-relative paths Pommora ignores *completely* at any depth: never adopted, shown, indexed, walked, or auto-tagged. One subtractive filter (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected) loads directly from disk — so it works in the index-rebuild pass that runs before the per-Nexus environment exists. Internal `.nexus/` Context reads never consult it. Editing UI is deferred to Settings.

---

#### Manager + cache layer

One per-entity manager per kind owns the in-memory cache for that kind: it loads files at app start, mirrors to the SQLite index, and writes atomically on every mutation. There is a manager for each operational + organization kind (Page Types + Collections, Page Sets, Page content, Agenda Tasks, Agenda Events, the three Context tiers) plus the Homepage and Settings singletons; each is sourced from its corresponding files/sidecars on disk.

Managers are `@MainActor` `@Observable`; SwiftUI views observe them directly via `@Environment`. Heavy services (the SQLite index, parsers) stay in DI to avoid re-init on view rebuild. Manager ownership + injection is centralized — see CLAUDE.md branch quirk #15.

**Full load mirrors parents to the SQLite index.** Invariant: after a full disk-load, every in-memory parent (Page Type / Page Collection) is also present in its SQLite table. The manager defensively re-upserts parents after load (idempotent; failures swallowed since the index is regeneratable). Without this, page CRUD into a vault that arrived outside CRUD (adoption / external Finder folders) triggers an FK-constraint failure.

---

#### SQLite index — regeneratable scaffolding

The index lives at `<nexus>/.nexus/index.db`. It travels with the Nexus, so a moved or renamed Nexus keeps its index without re-pathing. It holds titles / properties / links / relations — **never** Page bodies (the `pages` table has no body column; full-text search reads files directly).

**Fully regeneratable.** The index file is stamped with a `schema_version`; on open, a mismatch against the code's current version force-deletes + rebuilds the whole DB — no per-user data migration. No user data is trapped — losing the index file just means a rebuild on next open.

**Launch-tail indexing contract.** On launch, the index rebuilds **only** when the schema-version mismatch flags a rebuild — there is no unconditional launch scan. The version is stamped only *after* the rebuild succeeds, so a failed rebuild retries next launch instead of locking in an empty index. Consequence: a page Finder-dropped *after* the index is current-stamped enters the index via CRUD upserts (or a forced rebuild), **not** via the launch path.

**Data tables** (DDL canonical in PRD § SQLite Schema): `page_types`, `page_collections`, `page_sets`, `pages`, `agenda_tasks`, `agenda_events`, `contexts`, `context_links`, `connections`, `property_definitions`, plus an internal `meta(key, value)` table holding the `schema_version`. Tier relations use the `context_links` table — there is no separate tier table; body connections use the `connections` table (page-only).

**Query surface.** The query facade composes Notion-style filter/sort/group/broken-links SQL — reaching into the `properties` JSON column via SQLite's JSON1 extension, and reading the `context_links` table for tier-relation lookups. Embedded views in Contexts / Homepage flow through it. So the UI is one hop removed from the canonical file: it renders what the **store → query → render** chain hands it (file → index → query → view), never the file directly. A wrong, empty, or `(missing)` surface therefore localizes to the query/render hop — stale or unbuilt index rows, a load-timing or layout fault in the view — and is not by itself evidence that the canonical file is wrong; confirm the data at the relevant hop (read the file, run the query) before attributing a fault to the store.

**Reverse-view query (Context-side Linked-from).** A reverse query reads the `context_links` table for every row whose `target_id` equals a given Context ID, resolving each source's current title from its owning kind table. It powers a Context's Linked-from surface — every operational entity that tags that Context. Each `tier1` / `tier2` / `tier3` value emits one row into `context_links` (`property_id` = the reserved tier ID, `target_kind` = the coarse `area` / `topic` / `project`).

**Update path.** Per-entity content + type managers (Pages, Page Types, Agenda Tasks, Agenda Events) plus Contexts and property definitions propagate mid-session mutations to the DB without waiting for a restart. Pattern: every manager mutation runs after the atomic file write succeeds.

**Delete behavior.** Deleting a parent cascades its descendants in the index, except that deleting a Collection or Set does **not** delete its child Pages — they move up a level in the index until the next full reconcile.

---

#### Atomic-write contract

Every file write goes through one of three atomic-write paths:

- **YAML+Markdown write** — Pages. Composes `---\n<yaml>\n---\n\n<body>` via temp-file + rename. The preserving path re-reads the file it's overwriting and merges by value: it re-serializes only the type's own *modeled* keys and **preserves every foreign frontmatter key by value** (plugin / Obsidian / external keys are never culled). YAML round-trips by value — flow style reflows to block style and comments/anchors are dropped — but no key/value is lost. Each frontmatter type declares which keys it owns; everything else passes through.
- **JSON write** — sidecars, Agenda Tasks / Events, Contexts, Settings, Homepage. Encodes then writes via temp-file + rename.
- **Schema transaction** — multi-file commits for schema operations that must succeed-or-fail as a unit (e.g. a move that strips properties across types). Validates the full set, then applies temp-file + rename in dependency order with rollback on failure.

**Why temp-file + rename, not in-place write.** POSIX rename is atomic on the same filesystem. A crash mid-write leaves either the old file (rename never happened) or the new file (rename completed) — never a half-written file. macOS / APFS preserves this guarantee.

**Page save contract.** The editor binds only to `body`; frontmatter is held as a typed struct and re-serialized on save, so the user can't destroy frontmatter via the editor. Edits debounce, then write atomically and update the index; a flush forces on context loss (page-switch, window-close, app background/terminate, `⌘S`). Full pipeline → `// Features//PageEditor.md` § "Save pipeline".

---

#### File-watcher contract (deferred)

External edits (Obsidian / vim / Finder rename / cloud-sync mtime drift) must propagate to the SQLite index + in-memory caches + sidebar without a restart. A recursive filesystem watch on the Nexus root, with self-write filtering (debounce by path + outbound mtime tracking) and lost-update protection (mtime compare before overwriting). The atomic-write discipline + index-update path already support this — the watcher is a wiring task, not an architectural change.

---

#### Adoption — opening any folder as a Nexus

When a folder is first opened as a Nexus, the adopter classifies each root folder independently: fresh (no recognized sidecar → content-sniff always picks a Page Type), an unrecognized sidecar (auto-tagged as a Page Type), or already flat (no-op). Idempotent; per-folder atomicity (no two-phase transaction across folders); safe to re-run on partial state. Hidden folders (leading `.` or `_`) skipped. Preview-before-commit shows per-Type counts + warnings; fully-flat Nexuses skip the sheet silently. Full per-shape detail → `// Features//PageTypes.md` § "Adopting existing folders".

An unrecognized sidecar (a name Pommora doesn't own) classifies the folder as **sidecar-less** — adoption auto-tags it with a fresh `_pagetype.json`, the foreign sidecar stays **inert on disk**, and the folder's members index as pages.

**Kind authority = the folder sidecar, not the extension.** A `.md` file's kind comes from its parent folder's sidecar (`_pagetype.json` → Page), never from a frontmatter field. There is no kind stamp in frontmatter — any kind-like frontmatter key is treated as preserved foreign frontmatter (carried by value, never written by Pommora).

---

#### Migration — schema versioning + property-ID rewrites

Pommora carries two migration mechanisms:

**1. Index-side schema version** — covered above (a version mismatch deletes + rebuilds the index, no per-user migration).

**2. File-side schema version + property migration.** Each Pommora-written Type sidecar carries a `schema_version`; a missing version decodes as 0. A property migration runs on every Nexus open: it mints stable ULID `id`s for name-keyed properties, normalizes relation shapes, and rewrites entity files to reference properties by ID. Two-phase (scan / apply), idempotent, lossless. User-relation definitions are stripped at decode time before the scan runs; orphaned relation member values are cleared opportunistically during the migration.

**Settings auto-migration.** Settings carry a `defaultsVersion` and a step-function migrate scaffold, applied after decode and re-persisted only when something changed (mtime stays stable on no-op launches). Bump the version + add a step when defaults change.

---

#### What this data layer leaves to the OS

File-canonicality's payoffs (external-editor compatibility, agent legibility, cloud-sync-for-free) are the two load-bearing principles above. What's deliberately *not* built:

- **Versioning / file history / backup** — Time Machine, `git` on the Nexus, filesystem snapshots. No internal version store, no auto-commit; in-session undo is free from the editor.
- **Cross-device sync (v1)** — user picks the Nexus location; placing it in a synced folder gives device-to-device sync. Real cloud sync is a long-term Prospect.

---

#### Discipline (not enforcement)

No enforced layer separation. Patterns that keep the data layer tractable:

- **Per-Type schemas live in JSON sidecars** (canonical), not code; Page frontmatter lives inline in each `.md` file.
- **Foreign frontmatter is preserved by value** on every Page write path — an external tool's frontmatter keys survive Pommora's saves (mechanism in the atomic-write contract above).
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
