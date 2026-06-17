### Page Types

The operational layer's **Pages-side** schema-bearing container. A Page Type is a folder containing a `_pagetype.json` sidecar that defines the property schema shared by every Page inside. Page Collections are organizational sub-folders within a Page Type carrying their own `_pagecollection.json` sidecar (sharing the Type's schema; no properties of their own). Page Sets are optional schema-less sub-folders within a Page Collection (`_pageset.json`; full spec → [[Sets]]).

**UI labels:** Page Types render as **"Vault"** by default, Page Collections as **"Collection"**, Page Sets as **"Set"** (all renameable via Settings). Doc prose says "Page Type" / "Page Collection" / "Page Set" for conceptual clarity.

Maps to PARA's "Resources" alongside Agenda.

---

#### Three-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Page Type** | Folder with property schema; every Page inside shares the schema | Folder at the nexus root containing `_pagetype.json` |
| **Page Collection** | Organizational sub-folder inside a Page Type; inherits the Type's property schema | Folder inside a Page Type containing its own `_pagecollection.json` (no `properties`) |
| **Page Set** | Optional schema-less sub-folder inside a Page Collection; identity + icon only — views, settings, and open-in all inherit from the Collection | Folder inside a Page Collection containing its own `_pageset.json` — see [[Sets]] |
| **Content** | Pages only (`.md`) | Files inside a Page Set, a Page Collection, or directly inside the Page Type |

Page Collections share the parent Page Type's schema (Collection-local overrides are a Prospect → [[Prospects]]). The hierarchy is strictly three levels: depth-2 folders are Sets; depth-3+ folders are sidecar-less and their pages roll up into the nearest Set.

---

#### On disk

Page Types live as siblings at the nexus root — no `Pages/` wrapper folder. Discovery is sidecar-driven: any root folder carrying `_pagetype.json` is a Page Type regardless of folder name. Folder name = title for Types and Collections; UI renames rename folders on disk. A Page directly in a Page Type (not inside a Collection) is allowed — Collections are optional grouping.

```
<nexus-root>/
  Assignments/            ← Page Type (root folder; identified by sidecar)
    _pagetype.json
    Spring-2026/          ← Page Collection
      _pagecollection.json
      Midterm-Prep/       ← Page Set (optional)
        _pageset.json
        Exam-Review.md    ← Page inside a Set
      Essay-1.md          ← Page at Collection root
    Final-Project.md      ← Page directly in Page Type root
```

---

#### `_pagetype.json` (Page Type sidecar)

Fields: `id`, `icon`, `properties` (the schema — every Page's frontmatter must conform), `default_sort` (per-Type default sort), an optional `banner` (nexus-relative image path for the container banner → [[Views]]), `views` (the container's SavedView configs → [[Views]]), `collection_order` + `page_order` (user-arranged sequence of child Collections and root-level Pages — the parent holds its children's order), an optional `open_in` (§ "Open-in mode"), and `modified_at`. Title is the folder name, not a field.

**Property schema** carries each property's `name`, `type`, and per-type config (Select/Multi-select options, Status groups, etc.). Full property-type catalog, relation targets, Status-group shape, and the built-in `tier1` / `tier2` / `tier3` shape → [[Properties]].

#### Open-in mode

Each Page Type carries an optional `open_in` field (`compact` | `window`; absent = `window`) deciding where its Pages open — `window` routes a page-tap to the main detail pane, `compact` opens a PagePreview window (full behavior → [[Pages]] § "Opening behavior"). Set via a vault-scoped `Layout` dropdown (`Compact` | `Window`) pinned in the View Settings popover footer. The control's labels are structural — not user-renameable.

---

#### Page Type Settings sheet

The schema editor for a Page Type. UI label: "Vault Settings…" by default (renameable via the Settings scaffold). Opens from the **Page Type row right-click → "Vault Settings…"** in the sidebar. Per-view configuration is a separate surface — the View Settings popover off the window toolbar.

The sheet reads/writes the `properties` and `default_sort` fields of `_pagetype.json`; saved views live in `views[]` → [[Views]]. Save-required, and only one Type's Settings sheet may be open at a time per window.

##### Sections

- **Edit Properties** — add / rename / delete / reorder properties; per-property icon; per-type config (options, tier reverse name + icon, Status groups). "+ Add property" opens the type picker → per-type config sub-view, edited inline within an expandable row (drag-reorder for Select/Multi-select options; group editor for Status). The Relation type is not user-creatable and is absent from the picker — tier relations are pre-configured built-ins.
- **Templates** — placeholder anchor for content templates; not yet wired.

Per-view configuration (Sort / Filter / Group / Layout) lives in the active-view-scoped **View Settings** popover off the window toolbar; views switch via the toolbar Views dropdown → [[Views]]. The per-Type `default_sort` folds into the minted default view's sort.

---

#### No Page Type templates

Page Type creation does NOT seed default properties — name + icon only. Users add Status (or anything else) manually via Page Type Settings → Edit Properties. Status is built-in on Tasks and Events (where EventKit needs it); on user-created Page Types it is opt-in. Content-level templates (Notion-style pre-fill at creation) are not part of v1.

---

#### Content inside a Page Type

Pages — `.md` files with YAML frontmatter; prose-bearing. See [[Pages]]. Tasks and Events live in their own singletons (root folders identified by `_taskconfig.json` / `_eventconfig.json`) — see [[Agenda]].

---

#### Page Collections (sub-folders within a Page Type)

Filesystem folders inside a Page Type with a minimal `_pagecollection.json` sidecar. They inherit the parent Page Type's property schema but carry their own saved `views[]`, existing for visual / structural grouping inside large Page Types.

The sidecar carries: `id`; `type_id` (explicit parent-Type reference — keeps external query tools from inferring nesting and gives Collections stable portable IDs across renames); `icon` (optional per-Collection SF Symbol, mirrored into SQLite for the context picker); an optional `banner` image path; `page_order` (user-arranged collection-root Pages — pages inside a Set order via that Set's own `page_order`); `set_order` (user-arranged child Sets); `views` (independent SavedView configs → [[Views]]); and `modified_at`. No `properties` — the schema is the parent Type's.

- Title = folder name; create = sub-folder + `_pagecollection.json`; rename = folder rename (id / type_id preserved); delete = folder delete (warn-and-confirm if non-empty); moving a Page anywhere within the same Page Type (between Collections, Sets, and the Type root) = pure filesystem move, properties unchanged.

Page Sets subdivide a Collection one level further — schema-less, view-less, settings-less folders whose `_pageset.json` carries identity + icon + `page_order` only. Full spec → [[Sets]].

---

#### Sidebar treatment

- Page Types appear as chevron-disclosure rows directly under the `Vaults` section heading (the heading is pure UI grouping — there is no `Pages/` wrapper on disk). The sidebar groups under "Vaults" any root folder carrying `_pagetype.json`.
- **A Page Type's disclosure children**: Pages directly in the Type's root (`doc.text`) + Page Collection sub-folders (`folder`).
- **A Page Collection's disclosure children**: its Page Sets (`folder`; expandable, never selectable) + its Pages (`doc.text`).
- **A Page Set's disclosure children**: its Pages (`doc.text`).
- **Tasks and Events do NOT appear in the sidebar** — they surface via the Calendar pin entry.
- Clicking a Page Type opens its active saved view, vault-scoped, grouped by Collection with Sets nested by default (→ [[Views]]). Clicking a Page Collection opens its active saved view, collection-scoped, grouped by Set plus an ungrouped root band by default. Page Sets have no detail view of their own. Clicking a Page opens it in the main detail pane via the TextKit-2 editor (→ [[PageEditor]]).
- A new Page Type is created from the "+" in the Pages section header. Right-clicking a Page Type row offers "New Collection" / "New Page"; a Page Collection offers "New Page" / "New Set"; a Page Set offers "New Page". Full table → [[Sidebar]].

---

#### View types

Five view types carry through the data model; **Table** and **Gallery** render today; **Board** / **List** / **Cards** land in later passes. Full schema, renderers, view pipeline, sort/filter/group/layout config, drag semantics, covers/banners, and the tier-column layout → [[Views]].

**Every storage container has view surfaces** — not just the schema-bearing Types. Page Types AND Page Collections both carry `views[]`. The property schema is inherited from the Type, but each container's saved view configuration is independent — a Page Collection can show one view of a subset of its Pages while the parent Page Type shows another.

Saved views persist in each container's sidecar `views[]` (`_pagetype.json` / `_pagecollection.json`). Embedded view widgets in Context pages or Homepage reference a view by ID and apply local overrides without modifying the saved view (deferred).

---

#### Cross-layer connections

Pages carry `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Pages in Assignments where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page to another Page Type strips properties not in the destination schema (Notion-style, no quarantine); a confirmation warning lists what's stripped. Within the same Page Type (between Collections, Sets, and the Type root) there is no strip — shared schema, and Sets carry none of their own. Strip mechanics + foreign-key preservation → [[Properties]].

---

#### Validation

Enforced at every file write:

1. A Page Type folder MUST contain `_pagetype.json` — otherwise it's a cosmetic folder eligible for adoption.
2. Every Page inside a Page Type must carry frontmatter conforming to the Type's schema.
3. A Page Collection folder name doesn't collide with another Collection in the same Page Type; a Page Set folder name doesn't collide with another Set in the same Collection.
4. Filename = title.

---

#### Adopting existing folders

Opening any folder as a Nexus — including pre-existing user folders that have never seen Pommora — runs an idempotent scan. The adopter classifies and migrates each root folder independently, so fresh folders, legacy sidecars, the prior wrapper layout, and the already-flat target state can coexist in one Nexus.

Shape detection per root folder:

- **Fresh** — no recognized sidecar. Content-sniff always picks Pages: `.md`-bearing or empty folders adopt as Page Types (auto-tagged with a new `_pagetype.json`). Unrecognized legacy sidecars (e.g. a stale `_itemtype.json`) don't change the classification — the adoption semantic is canonical in [[Architecture]] § "Adoption".
- **Legacy Vault sidecar** — folder carries the `_vault` filename; renamed in place to `_pagetype.json`. Any sub-folder carrying a `_collection` sidecar is renamed to `_pagecollection.json`.
- **Legacy wrapper layout** — folder is one of the legacy wrappers (`Pages` / `Agenda` at root, each containing children with a unified `_schema` sidecar). The adopter unwraps each child up to the nexus root and renames the legacy sidecar to the appropriate per-kind name by parent + depth — Page Type children become `_pagetype.json`, nested Collections become `_pagecollection.json`, the Agenda wrapper's `Tasks` child becomes the Tasks singleton with `_taskconfig.json`, and its `Events` child the Events singleton with `_eventconfig.json`.
- **Already flat (target)** — folder carries one of the per-kind sidecars at the right depth. No-op (with a cleanup pass to delete any co-located legacy orphan sidecars).

Sidecar-less sub-folders auto-tag by depth (idempotent, honors `excluded_folders`): depth-1 folders inside a Page Type get `_pagecollection.json`, depth-2 folders inside a Collection get `_pageset.json`. Depth-3+ folders stay sidecar-less — their pages roll up into the nearest Set. The adoption preview labels third-level folders as Sets.

A preview sheet shows counts + a warnings list (ambiguous classifications, collisions, etc.). Adopt applies each folder's migration as a self-atomic step (no two-phase transaction across folders) — a single failure doesn't block the rest, and re-launching after an interruption is safe (already-migrated folders are recognized as "already flat" and skipped). Fully-flat Nexuses skip the sheet silently.

Exclusion set (never adopted): any folder starting with `.` or `_` (e.g. `.nexus`, `.trash`, `.obsidian`). Hidden folders are filtered at the enumerator level. There are no reserved top-level folder names — `Pages/` / `Agenda/` exist only as legacy input shapes the adopter unwraps.

`.md` files within an adopted Page Type need no Pommora-specific shape to surface — discovery is extension-based, and Pages without frontmatter open via the lenient loader ([[Pages]] § "On disk").

Implementation lives in `NexusAdopter` (`Pommora/Pommora/Nexus/NexusAdopter.swift`) with a preview view; both nexus-open paths run adoption after identity is set, and indexing status surfaces via an indexing HUD overlay in the sidebar.
