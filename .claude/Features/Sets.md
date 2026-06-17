### Sets

The third operational tier on the Pages side: **Vault → Collection → Set (optional) → Pages**. A Page Set is a lightweight folder inside a Page Collection carrying identity and an icon — nothing else. No schema, no views, no open-in, no settings: everything inherits from the parent Collection (and transitively the Vault). UI label **"Set"** by default — a `SettingsLabels` pair, user-renameable per Nexus like Vault / Collection.

---

#### Entity + sidecar

A Set is its own entity carrying only identity, parent reference, icon, and page order — deliberately no views / open-in / properties, so Sets never grow Collection behavior (a distinct entity, not a recursive Collection).

`_pageset.json` holds the Set's ULID id, its parent collection id, an icon, and the page order. Title = folder name (no title field). Default icon: SF Symbol `folder`, overridable per Set. Set titles are unique per Collection (folder constraint); Sets are never connection or relation targets.

Ordering is parent-holds-children throughout: the Collection's sidecar carries `set_order`; the Set's own `page_order` orders its pages; the Collection's `page_order` covers collection-root pages only.

---

#### Three-tier rule + roll-up

Strict three levels, decided by depth: depth-0 folder = Vault, depth-1 = Collection, depth-2 = Set. Sets exist only inside Collections — never at vault root — and cannot contain Sets. Depth-3+ folders are sidecar-less; their pages roll up into the nearest Set.

---

#### Manager + index

A dedicated Set manager, owned + injected by `NexusEnvironment`; loads after vaults (needs Collections). CRUD mirrors the Collection method shapes — atomic folder-rename with rollback, trash-on-delete, index upsert after every write, defensive `loadAll` index sync.

The index carries a sets table (cascade-deleting from its parent collection) plus a nullable set reference on each page (nulled when its Set is deleted). Pages in Sets are ordinary page rows — search, autocomplete, relations, and connections include them inherently. The container shape carries the Set id + title; wikilink opening folds Vault / Collection / Set / Page paths.

---

#### Sidebar + navigation

- **Set rows are expandable, never selectable** — no `SelectionTag`, no selection chrome; clicking toggles the disclosure. Sets have no detail view and never appear in Recents or selection.
- **Two-zone reorder** inside a Collection's disclosure: sets zone / pages zone; cross-zone drags rejected.
- **Context menu:** New Page / Rename / Change Icon / Move to… / Delete.
- **Breadcrumb:** `Vault › Collection › Set › Page` — the Set segment is plain text, non-clickable.
- **Collection detail view** shows root pages plus each Set's pages under its own scrolling disclosure group header (structural grouping); collection-scope Sets render as group rows, with the loose root pages in a headerless band. The footer add menu offers New Page + New Set.
- **PagePreview** opens set pages — a page reference carries an optional set id (legacy refs decode); editor / preview / inspector write paths are set-aware (a save never re-points a page's set).

---

#### Delete — two modes

Deleting a Set prompts a choice:

- **Delete Set Only** — pages move up into the Collection (collision-checked).
- **Delete Set and Pages** — the folder moves to `.trash/` whole, recoverable.

---

#### Moves

- **All in-vault page moves are strip-free** (Set ↔ Collection root ↔ Vault root ↔ other Set) — Sets carry no schema, so within a Vault every move is a pure filesystem move. Cross-vault moves strip by name, as always.
- **Whole-Set moves between Collections:** same-vault carries pages untouched; cross-vault strips per page with one batched carried-values count confirmation. The Set assumes the destination's inherited settings automatically — it never carried its own.

---

#### Adoption + healing

Adoption auto-tags sidecar-less depth-2 folders with `_pageset.json` — idempotent, honors `excluded_folders`; the preview labels them Sets. Depth-3+ folders get no sidecar (roll-up rule above).

Container-ID healing (general hardening, not Set-specific): Finder-duplicating a container folder clones its sidecar ULID — on load, the first-discovered folder keeps the id and every later duplicate mints a fresh ULID and re-saves its sidecar (Collections and Sets alike).
