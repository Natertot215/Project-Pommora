## Sets — Third Operational Tier (Spec)

**Status:** Design ratified 2026-06-11, open questions resolved same day. "Set" is the code-level and default UI name; like Vault and Collection, the UI label is user-renameable per Nexus via the Settings labels scaffold. Ships as v0.4.1.

A Set is a lightweight organizational folder inside a Page Collection. It carries identity and an icon — nothing else. No schema, no views, no open-in, no settings; all behavior inherits from the parent Collection (and transitively the Vault). The operational hierarchy becomes **Vault → Collection → Set (optional) → Pages**, with pages still allowed at every level above Set.

This supersedes two prior positions, deliberately:

- The "Folders" third tier tried and reverted 2026-05-27 (`History.md`) — reverted because it duplicated Collections' role and conflicted with the then-unspecified view-organization system. Sets differ on both counts: they are non-navigable settings-inheriting folders (not a second Collection), and the grouping interplay is specified below.
- The adoption lock "2-level structural depth preserved" (`History.md`) — becomes "3-level structural depth; deeper folders roll up."

### Ratified decisions

- **Distinct entity**, not a recursive Collection. The type has no fields for views/settings/navigation, so the compiler enforces that Sets never grow Collection behavior.
- **Sidebar: expandable, not selectable.** A Set row discloses its pages; clicking the row itself selects nothing and opens no view.
- **Strict three levels.** Sets cannot contain Sets. Externally created folders at deeper levels get no sidecar; their pages flatten up into the nearest Set.
- **Sets exist only inside Collections** — never at vault root. Depth is the rule: depth-1 folder = Collection, depth-2 folder = Set, always.
- **Delete is a choice.** Deleting a Set prompts: delete the Set only (pages move up into the Collection) or delete the Set and its pages (folder trashed whole, recoverable).
- **Default icon: folder** (SF Symbol `folder`), overridable per Set like Collections.
- **Free movement within the Vault.** Because Sets carry no schema, pages move freely between Sets, their parent Collection, and the Vault root — no property strip, no dialog. Property stripping remains exclusive to cross-Vault moves (name-matched, as today).
- **First-class identification.** Sets are indexed in SQLite, join container identification for connections (see below), and are never excluded from mechanisms pages-in-Collections participate in.

### On-disk model

```
<nexus>/Assignments/                 _pagetype.json
         Spring-2026/                _pagecollection.json
           Midterm-Prep/             _pageset.json          ← new
             Exam-Review.md
           Essay-1.md                (page at Collection root)
```

`_pageset.json` holds `id` (ULID), `collection_id`, `icon`, `page_order`, `modified_at`, `schema_version`. Title is the folder name (filename = title, no title field). Kind authority is the sidecar, per the existing classification rule. Ordering follows the parent-holds-children pattern throughout: `PageCollection` gains optional `set_order` (mirroring `collection_order` on `_pagetype.json`), and the Set's own `page_order` orders its pages — after Sets, a Collection's `page_order` covers collection-root pages only, no longer rolled-up descendants.

Set titles are unique per Collection (a folder constraint). Sets are not connection targets, so set titles need no nexus-wide uniqueness; page titles stay nexus-wide unique (Connections invariant), so same-named pages across Sets are already impossible.

### Domain model + managers

`PageSet` struct: `id`, `collectionID`, `title` (derived), `folderURL` (runtime), `icon`, `modifiedAt`, `schemaVersion`. Deliberately no `views` / `openIn` / `properties` fields.

CRUD follows the Collection method shapes exactly: atomic folder-rename with rollback, trash-on-delete, index upsert after every write, auto-heal of missing/drifted sidecars on load, defensive index sync in `loadAll`. New surface: create / rename / delete (two-mode, per above) / updateIcon / reorder, plus a `pageSetsByCollection` cache and Set-scoped page load + page-CRUD overloads in `PageContentManager`.

`PageParent` gains `.set(PageSet, collection:, vault:)` — the switch forces every page-CRUD call site to handle the third location.

**Manager ownership (decided):** a dedicated `PageSetManager`, owned and injected by `NexusEnvironment` like every other manager. Chosen for future-proofing over folding into `PageTypeManager`; the cost is explicit coordination — a Collection rename or move must notify `PageSetManager` to rebuild its Sets' (and their pages') runtime folder URLs.

**Move semantics:** moves within the same Vault (Set ↔ Collection root ↔ Vault root, or between Sets) never strip properties; cross-Vault moves strip by name, as today.

**Whole-Set moves are allowed.** A Set can move between Collections: same-Vault moves carry pages untouched; cross-Vault moves strip each page by name (one batched confirmation, reusing the move-strip primitive). The Set assumes the destination Collection's inherited settings automatically — it never carried its own.

**Rename cascades:** renaming a Collection must rebuild the runtime `folderURL` of its Sets *and* their pages (one level deeper than today's rebuild); renaming a Set rebuilds its pages' URLs. Every cached `folderURL` is depth-sensitive — `ConnectionFileLocator` folds paths from container titles, so stale set titles break wikilink opening. Page renames cascade title-keyed connections exactly as today (set membership is title-irrelevant).

### SQLite index

One new table and one new column; index schema version bump, no data migration (index is regeneratable):

- `page_sets`: `id`, `page_collection_id` (FK, `ON DELETE CASCADE`), `title`, `icon`, `modified_at`, `schema_version`.
- `pages.page_set_id`: nullable, `ON DELETE SET NULL` — mirrors `page_collection_id`.

Pages in Sets are ordinary `pages` rows, so search, autocomplete candidates, wikilink resolution, tier relations, property indexing, and filtering include them with no changes. `IndexBuilder` walks one level deeper, with `page_sets` slotted between `page_collections` and `pages` in both the clear-tables and insert order; `IndexUpdater` upserts parents-first; the FK-failure fallback chain on page upsert retries without set, then without collection.

### Connections + identification

`EntityContainer` gains a set segment (ID + title). This is a hard correctness requirement: `ConnectionFileLocator` folds a page's on-disk path from container titles, so a wikilinked page inside a Set is unreachable without it. The same container identification is the hook for future title-duplication scoping and alias features — Sets identify pages exactly as Vaults and Collections do. Sets themselves are not link targets and not relation targets (unchanged: relations are context-tier-only; connections are page-only).

### Adoption

`autoTagMissingSidecars` gains a depth-2 rung: sidecar-less folders inside Collections get `_pageset.json`, exactly as depth-1 folders get `_pagecollection.json`. Depth 3+ folders get no sidecar; their pages flatten into the nearest Set. Adoption preview labels third-level folders as Sets. The depth-2 walk takes the same `FolderFilter` parameter as depths 0/1 (`excluded_folders` subtree matching is already depth-agnostic).

**Forward compatibility:** a pre-Sets build opening a Sets nexus never walks depth 2, so `_pageset.json` is untouched and set pages temporarily roll up into their Collection — display-only degradation, no data risk; Sets reappear on next open in a current build.

### UI surfaces

- **Sidebar:** `PageCollectionRow`'s disclosure body becomes Sets + Pages — the same mixed pattern `PageTypeRow` uses for Collections + Pages (homogeneity quirk #8 is safe; the shape already exists one level up). Set rows are disclosure rows with no `SelectionTag`. Reordering uses the existing two-zone pattern (sets zone / pages zone, cross-zone drags rejected), persisting to `set_order`.
- **Breadcrumb:** `Vault › Collection › Set › Page`; the Set segment is a `FooterCrumb` with nil action (plain text, non-navigable — already supported).
- **Recents / back-forward / `SidebarSelection`:** untouched. Sets never enter them.
- **Open-in + settings inheritance:** a page in a Set routes by its Collection's (then Vault's) settings; Sets contribute nothing.
- **Collection detail view:** pages in Sets surface here — the Set has no view of its own. "New Set" lives on the Collection (context menu + detail view); "New Page" additionally on the Set row's context menu.
- **Collection footer:** the footer add control (`FooterAddMenuButton`, already array-based) gains a "New Set" item beside "New Page".
- **Settings labels:** "Set" joins Vault/Collection in the renameable-labels scaffold (`.nexus/settings.json`), pending the naming review.

### Views + grouping (future Views work — recorded here, built with Views)

- Vault views default to **group by Collection**, with each Collection's Sets rendered nested inside its disclosure.
- Collection views default to **group by Set**; collection-root pages render as an ungrouped band.
- Grouping by any property replaces and flattens the structural grouping.
- Sort applies within each disclosure group.
- **`GroupConfig` must become a discriminated value.** The reserved `SavedView.group` stub (`GroupConfig.propertyID`, unconsumed today) can only express property grouping; structural grouping (by Collection / by Set) is not a property. The Views work designs `GroupConfig` as property-or-container from the start — changing the stub now costs nothing; retrofitting after Views ship is a migration. Container grouping is also what embedded collection-views in Context block-pages render, so it must live in `SavedView`, not in view-local state.
- The per-view **reorder engine** writes manual order to the grouped row's owning container sidecar (a Set's rows → that Set's `page_order`).
- **Board stays property-driven** in the base design (kanban columns = property options, not Sets). A "columns = Sets" Board variant is a clean later option — dragging a card between Set columns is just a free in-Vault move — but is not required by this spec.

### Future interactions (one line each; the design must not foreclose these)

- **Trash (future):** restoring a page whose Set was deleted falls back to the Collection root (mirrors the FK `ON DELETE SET NULL`); cascade-delete reporting gains a Sets count.
- **FSEvents watcher (future):** the per-file reconcile classifies depth-2 folders/sidecars; a Set created in Finder mid-session appears live. Rule-driven depth walking makes this mechanical.
- **Global search / FTS (future):** pages in Sets are FTS rows like any page; result breadcrumbs come from the extended `EntityContainer`. Sets themselves are searchable results (identifiable containers whose child pages surface), same as Vaults and Collections.
- **Quick Capture (future):** capture defaults to an inbox Vault and is unaffected; any future destination picker treats a Set as a valid leaf destination (no schema means capturing into a Set is just capturing into the Vault's schema, placed deeper).
- **Property automations / if-then (undescribed):** set membership is queryable via `page_set_id` (triggers like "page enters Set X" are cheap) but is never itself a property — keeping the no-schema rule intact. Free in-Vault movement makes "move page to Set Y" a safe automation action; cross-Vault moves would not be (strip).
- **Sync / cloud mapping:** `page_sets` + `page_set_id` translate 1:1 to cloud tables — the additive-translation constraint holds.
- **Aliases / duplicate-title scoping (post-v1 wishlist):** container identification (Vault › Collection › Set) is the disambiguation key those features will scope by; the `EntityContainer` extension is the future-proofing.
- **Agent legibility:** set membership is path-derived — an external agent reads it from file location with zero tool calls, and creates a Set by writing a folder (adoption tags it) or the sidecar directly.

### SwiftUI platform notes

Verified against current Apple docs: arbitrary-depth disclosure is native (`List(_:children:)` / `OutlineGroup`; the hand-rolled nested `DisclosureGroup` pattern extends one level without platform risk — the Set+Page mixed-row shape inside a disclosure already ships at the Vault level); `dropDestination(for:)` exists on List and Table rows, so drag-page-onto-Set is platform-supported when wanted; hierarchical `Table(_:children:)` + `DisclosureTableRow` exist for the future grouped views — the known macOS limitation remains combining collapsible grouping with reliable nested reorder (already recorded in the roadmap's display-only fallback).

### Docs impact (final implementation task, not before)

Two-level assertions rewritten as fact — no "amended"/"superseded" language anywhere: `CLAUDE.md`, `PommoraPRD.md`, `Framework.md`, `Features/Domain-Model.md`, `Features/PageTypes.md`, `Features/Sidebar.md`, `Features/Pages.md`. A brief note in `History.md` and the relevant Collection/Set feature docs records that the third layer shipped at v0.4.1; new paradigm-decision entry records why Sets supersede the Folders revert and the 2-level adoption lock. Documentation stays minimal and precise.

### Bundled hardening (not Set-specific)

**Sidecar ULID-collision healing:** duplicating a container folder in Finder duplicates its sidecar ULID; Collections share this exposure today with no heal. Ships with this work as a general fix — on load, a duplicate container ID mints a fresh ULID for the later-discovered folder and re-saves its sidecar (covering Collections and Sets alike).
