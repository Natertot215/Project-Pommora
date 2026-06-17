### Sets

The third operational tier on the Pages side: **Vault → Collection → Set (optional) → Pages**. A Page Set is a lightweight folder inside a Collection carrying only identity and an icon. No schema, views, open-in, or settings — everything inherits from the parent Collection (and transitively the Vault). UI label **"Set"** by default, user-renameable per Nexus like Vault / Collection.

---

#### Entity + sidecar

`_pageset.json` holds the Set's ULID, parent collection id, icon, and page order — deliberately nothing else, so Sets never grow Collection behavior (a distinct entity, not a recursive Collection). Title = folder name. Default icon `folder`, overridable. Set titles are unique per Collection (folder constraint); Sets are never connection or relation targets.

Ordering is parent-holds-children: the Collection's sidecar carries `set_order` and its own root `page_order`; each Set's `page_order` orders its own pages.

---

#### Three-tier rule + roll-up

Strict three levels by depth: depth-0 = Vault, depth-1 = Collection, depth-2 = Set. Sets exist only inside Collections, never at vault root, and cannot contain Sets. Depth-3+ folders are sidecar-less; their pages roll up into the nearest Set.

---

#### Manager + index

A dedicated Set manager, owned + injected by `NexusEnvironment`, loading after vaults (needs Collections). CRUD mirrors Collection shapes — atomic folder-rename with rollback, trash-on-delete, index upsert per write, defensive `loadAll` sync.

The index carries a sets table (cascade-deleting from its parent collection) plus a nullable set reference on each page (nulled when its Set is deleted). Pages in Sets are ordinary page rows, so search, autocomplete, relations, and connections include them inherently; wikilink opening folds Vault / Collection / Set / Page paths.

---

#### Sidebar + navigation

- **Set rows are expandable, never selectable** — no `SelectionTag`, no chrome; clicking toggles the disclosure. Sets have no detail view and never appear in Recents or selection.
- **Two-zone reorder** in a Collection's disclosure: sets zone / pages zone; cross-zone drags rejected.
- **Context menu:** New Page / Rename / Change Icon / Move to… / Delete.
- **Breadcrumb:** `Vault › Collection › Set › Page`; the Set segment is plain, non-clickable.
- **Collection detail view** groups each Set's pages under its own disclosure header, with loose root pages in a headerless band. Footer add menu: New Page + New Set.
- **PagePreview** opens set pages — a page reference carries an optional set id (legacy refs decode); editor / preview / inspector write paths are set-aware (a save never re-points a page's set).

---

#### Delete — two modes

- **Delete Set Only** — pages move up into the Collection (collision-checked).
- **Delete Set and Pages** — the folder moves to `.trash/` whole, recoverable.

---

#### Moves

- **In-vault moves are strip-free** (Set ↔ Collection root ↔ Vault root ↔ other Set) — Sets carry no schema, so within a Vault every move is a pure filesystem move.
- **Whole-Set moves between Collections:** same-vault carries pages untouched; cross-vault strips per page with one batched carried-values confirmation. The Set assumes the destination's inherited settings — it never carried its own.

---

#### Adoption + healing

Adoption auto-tags sidecar-less depth-2 folders with `_pageset.json` — idempotent, honors `excluded_folders`, preview-labeled Sets. Depth-3+ folders get no sidecar (roll-up rule above).

Container-ID healing (general, not Set-specific): Finder-duplicating a container folder clones its sidecar ULID — on load the first-discovered folder keeps the id and every later duplicate mints a fresh ULID and re-saves (Collections and Sets alike).
