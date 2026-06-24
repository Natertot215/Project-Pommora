### Architecture — Data Layer + Nexus

The dynamics of Pommora's data layer — the on-disk Nexus, the manager + cache surface, the SQLite index, the atomic-write contract, the adopter, and the external-edit watcher. PRD carries the high-altitude storage model + SQLite DDL.

---

#### Two load-bearing principles

Every architectural choice below traces back to one of these.

1. **Files are canonical (≠ everything is Markdown).** Only Pages are Markdown; Tasks, Events, sidecars, Contexts, Homepage, and Settings stay JSON. On-disk layout + per-kind sidecars below. SQLite is regeneratable scaffolding, never source of truth — no user data is trapped in it.

2. **Agent legibility.** External agents (Claude via MCP, any filesystem tool, vim, Obsidian) read Pommora's entire structured graph — Pages, schemas, relations, properties — directly from files without tool-call round-trips. This differentiates from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Any choice that trades file-canonical legibility for app-internal convenience violates this principle.

---

#### Nexus layout

A Nexus is a single folder. Pommora opens it via picker (security-scoped bookmark) and treats it as canonical content. The Nexus can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync.

```
<picked nexus folder>/                  ← canonical content; syncs with cloud
  <Collection>/                         ← Page Collection (top folder, identified by sidecar)
    _pagecollection.json                ← shared property schema (Collection)
    <Set>/                              ← Page Set (depth-1; carries its own views[])
      _pageset.json                     ← set metadata + views[] + set_order (depth-1 Set)
      <SubSet>/                         ← Sub-Set (deeper; plain, recursive — any depth)
        _pageset.json                   ← set metadata (id + parent_id + icon + page_order)
        <Page>.md                       ← Page nested in a Sub-Set
      <Page>.md                         ← Page at the Set root
    <Page>.md                           ← Page directly in the Collection root

  <Tasks>/                              ← Tasks singleton (folder + _taskconfig.json)
    _taskconfig.json
    <title>.task.json

  <Events>/                             ← Events singleton (folder + _eventconfig.json)
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

**Classification by sidecar + folder position.** A root folder carrying a Pages sidecar IS a Page Collection — regardless of folder name; folders rename freely via Finder. The per-kind sidecar filenames (`_pagecollection.json` / `_pageset.json` / `_taskconfig.json` / `_eventconfig.json`) are the kind discriminators (the retired `_pagetype.json` is converted to `_pagecollection.json` by a one-shot migration on first open → [[PageCollections]]). A Collection nests Page Sets to **any depth** — every sidecar-bearing sub-folder is a Set (tier = folder depth, not filename); there is no depth cap and no roll-up (→ `// Features//PageSets.md`).

**No wrapper folders.** Page Collections and the Tasks / Events singletons all live as siblings at the nexus root — there is no `Pages/` or `Agenda/` container folder.

**Hidden + private.** `.nexus/` and `.trash/` are hidden from the sidebar and from non-Pommora tools by convention (matches `.obsidian/`).

**User folder exclusion.** Beyond the built-in skips (dot/underscore-prefixed + `node_modules`), the user can exclude arbitrary folders via `excluded_folders` on `settings.json` — anchored, nexus-relative paths Pommora ignores *completely* at any depth: never adopted, shown, indexed, walked, or auto-tagged. One subtractive filter (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected) loads directly from disk — so it works in the index-rebuild pass that runs before the per-Nexus environment exists. Internal `.nexus/` Context reads never consult it. Editing UI is deferred to Settings.

---

#### Manager + cache layer

One per-entity manager per kind owns the in-memory cache for that kind: it loads files at app start, mirrors to the SQLite index, and writes atomically on every mutation. There is a manager for each operational + organization kind (Page Collections, Page Sets, Page content, Tasks, Events, the three Context tiers) plus the Homepage and Settings singletons; each is sourced from its corresponding files/sidecars on disk.

Managers are `@MainActor` `@Observable`; SwiftUI views observe them directly via `@Environment`. Heavy services (the SQLite index, parsers) stay in DI to avoid re-init on view rebuild. Manager ownership + injection is centralized — see CLAUDE.md branch quirk #15.

**Full load mirrors parents to the SQLite index.** Invariant: after a full disk-load, every in-memory parent (Page Collection / Page Set) is also present in its SQLite table. The manager defensively re-upserts parents after load (idempotent; failures swallowed since the index is regeneratable). Without this, page CRUD into a Collection that arrived outside CRUD (adoption / external Finder folders) triggers an FK-constraint failure.

---

#### SQLite index — regeneratable scaffolding

The index lives at `<nexus>/.nexus/index.db`, travelling with the Nexus so a moved or renamed Nexus keeps it without re-pathing. It holds titles / properties / links / relations — **never** Page bodies; full-text search reads files directly. DDL is canonical in PRD § SQLite Schema. Tier relations live in the `context_links` table (no separate tier table); body connections in a page-only `connections` table.

**Fully regeneratable.** The index is stamped with a `schema_version`; on open a mismatch force-deletes + rebuilds the whole DB — no per-user data migration. Losing the file just means a rebuild on next open.

**Launch-tail indexing contract.** On launch the index rebuilds **only** when the schema-version mismatch flags it — there is no unconditional launch scan. The version is stamped only *after* a rebuild succeeds, so a failed rebuild retries next launch instead of locking in an empty index. Consequence: a page Finder-dropped after the index is current-stamped enters via CRUD upserts (or a forced rebuild), not via the launch path.

**Query surface.** The query facade composes Notion-style filter/sort/group/broken-links SQL — reaching the `properties` JSON column via JSON1, and `context_links` for tier lookups. Embedded views in Contexts / Homepage flow through it. The UI is therefore one hop removed from the canonical file (file → index → query → view); a wrong, empty, or `(missing)` surface localizes to the query/render hop, not by itself to the file — see CLAUDE.md branch quirk #17.

**Reverse query (Context Linked-from).** Reads `context_links` for every row whose `target_id` equals a Context ID, resolving each source's current title from its owning table — powering a Context's Linked-from surface. Each `tier1` / `tier2` / `tier3` value emits one row (`target_kind` = `area` / `topic` / `project`).

**Update path.** Every manager mutation upserts to the DB immediately after its atomic file write succeeds — mid-session changes never wait for a restart.

**Delete behavior.** Deleting a parent cascades its descendants in the index, except that deleting a Collection or Set does **not** delete its child Pages — they move up a level until the next full reconcile.

---

#### Atomic-write contract

Every file write goes through one of three atomic paths, all via temp-file + rename (POSIX rename is atomic on the same filesystem, so a crash mid-write leaves either the whole old file or the whole new file — never a half-written one):

- **YAML+Markdown write** — Pages. Composes `---\n<yaml>\n---\n\n<body>`, re-serializing only modeled keys and preserving every foreign frontmatter key by value. The preserving-merge mechanics are canonical in `// Guidelines//CRUD-Patterns.md` § "YAML frontmatter + body".
- **JSON write** — sidecars, Tasks / Events, Contexts, Settings, Homepage.
- **Schema transaction** — multi-file commits that must succeed-or-fail as a unit (e.g. a move that strips properties across types). Validates the full set, then applies in dependency order with rollback on failure.

**Page save contract.** The editor binds only to `body`; frontmatter is held as a typed struct and re-serialized on save, so the editor can't destroy frontmatter. Edits debounce then write atomically and update the index, flushing on context loss. Full pipeline → `// Features//PageEditor.md` § "Save pipeline".

---

#### File-watcher

External + out-of-band on-disk changes (Obsidian / vim / Finder / cloud-sync) propagate to the index + in-memory caches + sidebar without a restart, via a recursive FSEvents watch on the Nexus root. **Authority is recency and origin-blind** — the newest write wins; internal-vs-external is irrelevant. Reconcile is surgical for the safe common case (existing-Page edits/creates reindex only their scope) and a coarse atomic rebuild for anything that could orphan a link or misclassify a move (rename / move / delete / non-Page / dropped events). The index database is excluded at intake so reconciles can't self-feed; a last-seen-`mtime` gate drops duplicate events + self-write echoes. Identity survives an external rename because every Page is stamped a stable ULID on first sight; the open editor live-reloads on an external edit while protecting unflushed edits. Full design → `History.md`.

---

#### Adoption — opening any folder as a Nexus

When a folder is first opened as a Nexus, the adopter classifies each root folder independently: fresh (no recognized sidecar → content-sniff picks a Page Collection), unrecognized sidecar (auto-tagged as a Page Collection, the foreign sidecar staying **inert on disk**), or already flat (no-op). Idempotent, per-folder atomic, safe to re-run on partial state; hidden folders skipped. Preview-before-commit shows per-Collection counts + warnings; fully-flat Nexuses skip the sheet silently. Full per-shape detail → `// Features//PageCollections.md` § "Adopting existing folders".

**Kind authority = the folder sidecar, not the extension.** A `.md` file's kind comes from its parent folder's sidecar (`_pagetype.json` → Page), never from frontmatter. Any kind-like frontmatter key is treated as preserved foreign frontmatter — carried by value, never written by Pommora.

---

#### Migration — schema versioning + property-ID rewrites

**Index-side** — covered above: a version mismatch deletes + rebuilds the index, no per-user migration.

**File-side** — each Pommora-written Type sidecar carries a `schema_version` (missing = 0). A property migration runs on every Nexus open: mints stable ULID `id`s for name-keyed properties, normalizes relation shapes, and rewrites entity files to reference properties by ID. Two-phase (scan / apply), idempotent, lossless.

**Settings** — carry a `defaultsVersion` + step-function migrate scaffold, applied after decode and re-persisted only on change. Bump the version + add a step when defaults change.

---

#### What this data layer leaves to the OS

Deliberately *not* built:

- **Versioning / file history / backup** — left to Time Machine, `git` on the Nexus, filesystem snapshots. No internal version store; in-session undo is free from the editor.
- **Cross-device sync (v1)** — placing the Nexus in a synced folder gives device-to-device sync. Real cloud sync is a long-term Prospect.

---

#### Reference

- `PommoraPRD.md` — high-altitude product spec; storage model; SQLite DDL.
- `// Features//Domain-Model.md` — 2-layer model + PARA mapping + linking model.
- `// Features//Properties.md` — property catalog; tier-relation properties; move-strip semantics.
- `// Guidelines//CRUD-Patterns.md` — per-entity CRUD UI patterns.
- `// rules//MarkdownPM.md` — editor architecture + save pipeline.
