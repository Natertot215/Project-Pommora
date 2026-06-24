### Page Sets

The recursive sub-container on the Pages side. A Page Set is a folder inside a [[PageCollections|Collection]] that nests to **any depth**. It is one type (`PageSet`) playing two roles by position:

- **Set** (depth-1 — a direct child of the Collection): carries its **own views + sorting**, is selectable, and opens a detail view. This is the former middle "Collection" tier.
- **Sub-Set** (depth-2+): a plain organizing folder — no views, expand-only. This is the former "Set" tier.

UI labels: **"Set"** + **"Sub-Set"** ("Sub-Set" derived from the Set label). A Set carries no schema — it inherits the parent Collection's whole (Set-local overrides are a Prospect → [[Prospects]]). The top tier + schema → [[PageCollections]].

> **Naming lineage + sidecars.** The old three-tier model (Vault → Collection → Set) collapsed to two: a Collection nesting recursive Sets — old `PageCollection` (middle) + `PageSet` (bottom) merged into one recursive `PageSet` (→ `History.md`). **A Set's depth is its folder position, not its sidecar filename.** Every Set at any depth carries `_pageset.json`; a one-shot migration converts any legacy depth-1 `_pagecollection.json` to it on first open.

---

#### Entity + sidecar

`_pageset.json` holds the Set's ULID, `parent_id` (its immediate parent — a Collection at depth-1, a Set deeper), icon, `page_order`, and `set_order` (child Sets). A **depth-1** Set additionally carries `views[]` + an optional `banner` (→ [[Views]]); deeper Sub-Sets carry these fields too but they're **ignored** (graceful — never rendered, never seeded). Title = folder name. Default icon `folder`. Set titles are unique among siblings; Sets are never connection or relation targets.

Ordering is parent-holds-children: a parent's sidecar carries `set_order` (its child Sets) + `page_order` (its own root Pages); each Set orders its own pages.

---

#### Recursive nesting — no cap, no roll-up

Sets nest to **any depth**; there is no depth limit and no roll-up. Discovery, rendering, adoption, navigation, and the index all recurse on the **real folder tree** (`childFolders`), which makes the whole recursion surface cycle-proof by construction — depth is the literal directory depth, and a drifted `parent_id` is healed from folder position on load. A Set's role (Set vs Sub-Set, view-bearing or not) is a function of depth, decided at runtime — never stored.

---

#### Depth-1 view rule

Only a **depth-1** Set (its parent is a top-tier Collection) carries and renders views; deeper Sub-Sets are plain. Eligibility is an **O(1) render-time check** (the manager holds the set of top-tier Collection ids; a Set is view-eligible iff its `parent_id` is in that set) — NOT stored state. Consequences:

- **Move-safe.** Reparenting a depth-1 Set under another Set makes it depth-2: its `views[]` stay in the sidecar but go dormant (stop rendering). No sidecar rewrite.
- **Promotion re-surfaces.** Deleting an intermediate Set (or otherwise lifting a Set to depth-1) makes its dormant `views[]` render again — purely because the render-time check now passes.

---

#### Manager + index

`PageSetManager` (owned + injected by `NexusEnvironment`) owns **all** Sets at every depth, cross-wired to the Collection manager (which supplies the top-tier id set). CRUD is one recursive path per operation — atomic folder-rename with rollback, trash-on-delete, index upsert per write, defensive `loadAll` heal-on-read.

The index follows the **Model A** convention (→ `History.md`): each page row records its owning top-tier Collection (`page_collection_id`, for every page at any depth) and its **immediate** container (`page_set_id`, nil only for a page at the bare Collection root). `page_sets` rows reference exactly one parent — `parent_collection_id` (depth-1) or `parent_set_id` (deeper). The depth-1 collection is derived by walking `page_sets.parent_collection_id`, never stored on the page. Pages in Sets are ordinary page rows, so search, autocomplete, relations, and connections include them inherently; wikilink opening folds Collection/Set/Sub-Set/Page paths at any depth.

---

#### Sidebar + navigation

- **Depth-1 Sets are selectable** — they open a detail view (the former Collection-scoped view). **Sub-Sets (depth-2+) are expandable, never selectable** — clicking toggles the disclosure; they have no detail view and don't appear in Recents.
- A Set's disclosure shows its child Sub-Sets (recursively) + its Pages.
- **Recents** holds only selectable containers; a Set demoted past depth-1 (by a move) is pruned.
- **Breadcrumb:** `Collection › Set › Sub-Set › … › Page` at any depth; only depth-1 Set segments are clickable.
- **PagePreview** opens set pages — a page reference carries an optional set id; editor/preview/inspector write paths are set-aware (a save never re-points a page's set).

---

#### Delete — two modes

- **Delete Set Only** — pages re-home **up one level** into the Set's *immediate parent* (collision-checked), never flattened to the Collection root. A page in dissolved `Drafts` (inside `Inbox`) lands in `Inbox`.
- **Delete Set and Pages** — the folder moves to `.trash/` whole, recoverable.

---

#### Moves

- **In-Collection moves are strip-free at any depth** — a page or whole Set moving between Sets/Sub-Sets and the Collection root is a pure filesystem move (shared schema; Sets carry none of their own); no sidecar rename. Reparenting that changes depth flips view-eligibility (dormant ↔ re-surface) automatically.
- **Cross-Collection moves** strip per page with one batched carried-values confirmation; the moved Set assumes the destination's inherited schema (it never carried its own).

---

#### Adoption + healing

Adoption auto-tags sidecar-less folders inside a Collection as Sets at **any** depth (`_pageset.json`) — idempotent, honors `excluded_folders`, preview-labeled. Container-ID healing (general): Finder-duplicating a container folder clones its sidecar ULID — on load the first-discovered keeps the id and every later duplicate mints a fresh ULID and re-saves, at any depth. Full adoption semantics → [[PageCollections]] + [[Architecture]].
