### Page Collections

The operational layer's **Pages-side** schema-bearing top tier. A Page Collection is a top-level folder whose sidecar defines the property schema shared by every Page inside it (at any depth). Inside a Collection, **Page Sets** nest to any depth as organizing sub-folders (full spec → [[PageSets]]) — they inherit the Collection's schema and never carry their own. (On-disk sidecar filenames + the pending migration → the lineage note below.)

**UI label:** Page Collections render as **"Collection"** by default (renameable via Settings). Doc prose says "Page Collection" / "Collection" for the top tier; a nested Set is a "Set" (depth-1) or "Sub-Set" (deeper) → [[PageSets]]. Maps to PARA's "Resources" alongside Agenda.

> **Naming lineage + on-disk sidecars.** The top tier was "Page Type" / "Vault" before the rename (→ `History.md`). **A container's tier is its folder position, not its sidecar filename.** The canonical sidecars are **`_pagecollection.json`** (Collection) + **`_pageset.json`** (every Set at any depth). A one-shot migration unifies any legacy nexus on first open — the retired `_pagetype.json` (old top) and the old depth-1 `_pagecollection.json` are converted deepest-first; `_pagetype.json` is read only by that migrator.

---

#### Two-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Page Collection** | Top tier; folder with the property schema every Page inside shares | Folder at the nexus root containing `_pagecollection.json` |
| **Page Set** | Recursive sub-folder inside a Collection (any depth); schema-less, inherits everything. Depth-1 = "Set" (carries its own views); deeper = "Sub-Set" (plain) | Folder containing `_pageset.json` → [[PageSets]] |
| **Content** | Pages only (`.md`) | Files inside any Set/Sub-Set, or directly in the Collection root |

The schema lives **only** on the Collection; Sets inherit it whole (Set-local overrides are a Prospect → [[Prospects]]). Nesting is unbounded — there is no depth cap and no roll-up.

---

#### On disk

Collections live as siblings at the nexus root — no `Pages/` wrapper. Discovery is **position-driven**: any root folder carrying a recognized Pages sidecar is a Collection; its sub-folders are Sets at any depth (tier = folder depth, not filename — see the lineage note). Folder name = title everywhere; UI renames rename folders on disk. A Page directly in the Collection root (not inside a Set) is allowed — Sets are optional grouping.

```
<nexus-root>/
  Assignments/              ← Page Collection (top folder)
    _pagecollection.json    ← schema sidecar (Collection)
    Spring-2026/            ← Set (depth-1; carries its own views)
      _pageset.json         ← set metadata + views[] (depth-1 Set)
      Midterm-Prep/         ← Sub-Set (deeper; plain)
        _pageset.json
        Exam-Review.md      ← Page nested in a Sub-Set
      Essay-1.md            ← Page at the Set root
    Final-Project.md        ← Page directly in the Collection root
```

---

#### `_pagecollection.json` (Collection sidecar)

Fields: `id`, `icon`, `properties` (the schema — every Page's frontmatter must conform), `default_sort`, an optional `banner` (nexus-relative image path → [[Views]]), `views` (the Collection's SavedView configs → [[Views]]), `set_order` + `page_order` (the parent holds its children's order — child Sets + root-level Pages), an optional `open_in` (§ "Open-in mode"), and `modified_at`. Title is the folder name, not a field.

**Property schema** carries each property's `name`, `type`, and per-type config (Select/Multi-select options, Status groups, etc.). Full property-type catalog, relation targets, Status-group shape, and the built-in `tier1` / `tier2` / `tier3` shape → [[Properties]].

#### Open-in mode

Each Collection carries an optional `open_in` field (`compact` | `window`; absent = `window`) deciding where its Pages open — `window` routes a page-tap to the main detail pane, `compact` opens a PagePreview window (full behavior → [[Pages]] § "Opening behavior"). Set via a Collection-scoped `Layout` dropdown pinned in the View Settings popover footer. The control's labels are structural — not user-renameable.

---

#### Collection Settings sheet

The schema editor for a Collection. UI label: "Collection Settings…" by default (renameable via the Settings scaffold), opened from the **Collection row right-click**. Per-view configuration is a separate surface — the View Settings popover off the window toolbar.

The sheet reads/writes the `properties` and `default_sort` fields of `_pagecollection.json`; saved views live in `views[]` → [[Views]]. Save-required; only one Collection's Settings sheet may be open at a time per window.

##### Sections

- **Edit Properties** — add / rename / delete / reorder properties; per-property icon; per-type config (options, tier reverse name + icon, Status groups). "+ Add property" opens the type picker → per-type config sub-view, edited inline within an expandable row. The Relation type is not user-creatable and is absent from the picker — tier relations are pre-configured built-ins.
- **Templates** — placeholder anchor for content templates; not yet wired.

Per-view configuration (Sort / Filter / Group / Layout) lives in the active-view-scoped **View Settings** popover; views switch via the toolbar Views dropdown → [[Views]]. The per-Collection `default_sort` folds into the minted default view's sort.

---

#### No Collection templates

Collection creation does NOT seed default properties — name + icon only. Users add Status (or anything else) manually via Collection Settings → Edit Properties. Status is built-in on Tasks and Events (where EventKit needs it); on user-created Collections it is opt-in. Content-level templates (Notion-style pre-fill at creation) are not part of v1.

---

#### Views

**A Collection and each of its depth-1 Sets carry independent `views[]`** — the schema is inherited, but the saved-view configuration stands alone (a Set can show a Board while its Collection stays on Table). Deeper Sub-Sets carry no views — they render structurally within their depth-1 ancestor's view. Five view types carry through the data model; **Table** and **Gallery** render today. Full schema, renderers, pipeline, drag semantics → [[Views]].

#### Sidebar treatment

- Collections appear as chevron-disclosure rows under the `Collections` section heading (pure UI grouping — no `Pages/` wrapper on disk).
- A Collection's disclosure children: root Pages (`doc.text`) + its Sets (`folder`). A Set's children: its Sub-Sets + Pages, recursively. A depth-1 Set is selectable (opens its view); deeper Sub-Sets are expand-only.
- Clicking a Collection opens its active saved view, grouped structurally (Sets nested) by default. Clicking a Page opens it in the main detail pane (→ [[PageEditor]]).
- Right-click offers "New Set" / "New Page"; full table → [[Sidebar]]. Tasks/Events surface via the Calendar pin, not the sidebar.

---

#### Cross-layer connections

Pages carry `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Pages in Assignments where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page to a **different Collection** strips properties not in the destination schema (Notion-style, no quarantine); a confirmation lists what's stripped. Moving **within one Collection** (between its Sets/Sub-Sets and the root, at any depth) never strips — shared schema, Sets carry none of their own. Strip mechanics + foreign-key preservation → [[Properties]].

---

#### Index

The SQLite index is a regeneratable accelerator (delete-and-rebuild on schema-version bump, never canonical). Each page row records its owning **Collection** (`page_collection_id`, for every page at any depth) and its **immediate container** (`page_set_id`, nil only at the bare Collection root) — the **Model A** convention (→ `History.md`); the mid-level grouping is derived by walking `page_sets.parent_collection_id`, never stored. Full schema → [[Architecture]].

---

#### Validation

Enforced at every file write:

1. A Collection folder MUST contain `_pagecollection.json` — otherwise it's a cosmetic folder eligible for adoption.
2. Every Page inside a Collection must carry frontmatter conforming to the Collection's schema.
3. A Set folder name doesn't collide with a sibling Set in the same parent. Filename = title.

---

#### Adopting existing folders

Opening any folder as a Nexus runs an idempotent scan — fresh folders, legacy sidecars, the prior wrapper layout, and the already-flat target can coexist in one Nexus. Per root folder: **Fresh** (no sidecar) → `.md`-bearing/empty folders adopt as Collections (`_pagecollection.json`); **legacy** sidecars rename in place to the per-kind name; **already-flat** → no-op. Sidecar-less sub-folders inside a Collection auto-tag as Sets at **any** depth (`_pageset.json`; no roll-up), honoring `excluded_folders` (any folder starting with `.` or `_` is never adopted). A preview sheet shows counts + warnings; each folder's migration is self-atomic and re-launch-safe. Full semantics → [[Architecture]] § "Adoption"; recursion + healing detail → [[PageSets]]. Implementation: `NexusAdopter` (`Pommora/Pommora/Domain/Nexus/NexusAdopter.swift`).
