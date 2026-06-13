### Page Types

The operational layer's **Pages-side** schema-bearing container. A Page Type is a folder containing a `_pagetype.json` sidecar that defines the property schema shared by every Page inside. Page Collections are organizational sub-folders within a Page Type carrying their own `_pagecollection.json` sidecar (sharing the Type's schema; no properties of their own). Page Sets are optional schema-less sub-folders within a Page Collection (`_pageset.json`; full spec → [[Sets]]).

**UI labels:** Page Types render as **"Vault"** by default, Page Collections as **"Collection"**, Page Sets as **"Set"** (all renameable via Settings). Doc prose says "Page Type" / "Page Collection" / "Page Set" for conceptual clarity.

Maps to PARA's "Resources" alongside Agenda.

---

#### Three-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Page Type** | Folder with property schema; every Page inside shares the schema | Folder at the nexus root containing `_pagetype.json` |
| **Page Collection** | Organizational sub-folder inside a Page Type; inherits the Type's property schema | Folder inside a Page Type containing its own `_pagecollection.json` (no `properties` — carries id, ordering, `icon`, own `views`) |
| **Page Set** | Optional schema-less sub-folder inside a Page Collection; identity + icon only — views, settings, and open-in all inherit from the Collection | Folder inside a Page Collection containing its own `_pageset.json` (carries `id`, `collection_id`, `icon`, `page_order`) — see [[Sets]] |
| **Content** | Pages only (`.md`) | Files inside a Page Set, a Page Collection, or directly inside the Page Type |

Page Collections share the parent Page Type's schema for simplicity (Collection-local overrides are a post-v1 Prospect). The hierarchy is strictly three levels: depth-2 folders are Sets; depth-3+ folders are sidecar-less and their pages roll up into the nearest Set.

---

#### On disk

```
<nexus-root>/
  Assignments/                        ← Page Type (root folder; identified by sidecar)
    _pagetype.json                    ← shared schema sidecar
    Spring-2026/                      ← Page Collection
      _pagecollection.json            ← per-Collection metadata
      Midterm-Prep/                   ← Page Set (optional)
        _pageset.json                 ← per-Set metadata
        Exam-Review.md                ← Page inside a Set
      Essay-1.md                      ← Page at Collection root
    Final-Project.md                  ← Page directly in Page Type root
```

Page Types live as siblings at the nexus root — no `Pages/` wrapper folder. Discovery is sidecar-driven: any root folder carrying `_pagetype.json` is a Page Type, regardless of folder name. Page Type folder name = Page Type title; Page Collection folder name = Collection title. UI renames rename folders on disk. A Page directly in a Page Type (not inside a Collection) is allowed — Collections are optional grouping.

---

#### `_pagetype.json` (Page Type sidecar)

```json
{
  "id": "01HPAGETYPEID...",
  "icon": "folder",
  "properties": [
    {
      "name": "status",
      "type": "status",
      "status_groups": [
        {
          "id": "upcoming",
          "label": "Upcoming",
          "color": "gray",
          "options": [
            { "value": "not_started", "label": "Not started", "group_id": "upcoming" }
          ]
        },
        {
          "id": "in_progress",
          "label": "In Progress",
          "color": "blue",
          "options": [
            { "value": "in_progress", "label": "In progress", "color": "blue", "group_id": "in_progress" }
          ]
        },
        {
          "id": "done",
          "label": "Done",
          "color": "green",
          "options": [
            { "value": "done", "label": "Done", "color": "green", "group_id": "done" }
          ]
        }
      ]
    },
    {
      "name": "tags",
      "type": "multi_select",
      "select_options": [
        { "value": "research",  "label": "Research",  "color": "purple" },
        { "value": "frontend",  "label": "Frontend",  "color": "blue" },
        { "value": "backend",   "label": "Backend",   "color": "orange" }
      ]
    },
    { "name": "due", "type": "date" },
    { "name": "priority", "type": "number", "number_format": "integer" }
  ],
  "schema_version": 2,
  "default_sort": { "property_id": "_modified_at", "direction": "descending" },
  "banner": ".nexus/assets/01HPAGETYPEID.../cover.jpg",
  "views": [
    /* SavedView v2 configs — full schema → [[Views]] */
  ],
  "collection_order": [],
  "page_order": [],
  "modified_at": "2026-05-22T14:30:00Z"
}
```

Title = folder name. The schema applies to every Page inside (each Page's frontmatter must conform). `default_sort` is the per-Type default sort. `collection_order` and `page_order` carry the user-arranged sequence of child Page Collections and root-level Pages respectively (the parent holds its children's order — a Collection's sidecar likewise carries `set_order` for its Sets). An optional `open_in` field carries the vault's open-in mode (§ "Open-in mode" below). An optional `banner` field holds a nexus-relative image path for the container banner (full-width image above the title, per view; spec → [[Views]]). `views[]` holds the container's SavedView v2 configs (per-view property order + hidden set, sort, filter, group, column widths, collapsed groups, card size, cover/banner display toggles — full schema → [[Views]]).

**Tier relation values are always multi-valued.** The built-in `_tier1` / `_tier2` / `_tier3` properties hold an array of tagged Context IDs — `[{"$rel": "<ULID>"}]` — one entry per linked Context (a single target is a one-element array). Values render as the target's **icon + title in plain styled colored text** (never chips/pills), resolved live from the target entity.

#### Open-in mode

Each Page Type carries an optional `open_in` field (`compact` | `window`; absent = `window`) deciding where its Pages open — `window` routes a page-tap to the main detail pane, `compact` opens a PagePreview window (full behavior → [[Pages]] § "Opening behavior"). Set via a vault-scoped `Layout` dropdown (`Compact` | `Window`) pinned in the View Settings popover's footer (`StorageMenuRoot` → `ViewSettingsPane` footer slot), persisting through `PageTypeManager.setOpenIn(_:forVault:)`. The control's labels are structural — not user-renameable.

#### Page Type Settings sheet

The schema editor for a Page Type. UI label: "Vault Settings…" by default (renameable via the Settings scaffold).

##### Reaching Page Type Settings

The schema-editor sheet opens from the **Page Type row right-click → "Vault Settings…"** in the sidebar. (Per-view configuration is a separate surface — the View Settings popover off the window toolbar; see § "Sections".)

##### Sections

| Section | Contents |
|---|---|
| **Edit Properties** | Add / rename / delete / reorder properties. Per-property icon (`IconPicker`). Per-type config (options, tier reverse name + icon, status groups, etc.). |
| **Templates** | Empty wiring — placeholder anchor for future content templates. Reserved post-v1. |

Per-view configuration (Sort / Filter / Group / Layout, plus schema-only Edit Properties) lives in the active-view-scoped **View Settings** popover off the window toolbar; views switch via the toolbar Views dropdown → [[Views]]. A per-Type `default_sort` persists on `_pagetype.json` and folds into the minted default view's sort.

##### Properties section detail

Schema editor. Each row: icon (if set) + name, type badge, per-property menu (Rename / Change Type / Edit Options or Groups / Delete / Move Up-Down).

"+ Add property" opens the type picker → per-type config sub-view. The Relation type is not user-creatable and does not appear in the picker — tier relations are pre-configured built-ins. Per-property config is editable inline within an expandable row (drag-reorder for Select/Multi-select options; 3-group editor for Status).

Save-required + concurrent-open forbidden (only one Type's Settings sheet open at a time per window).

##### Settings JSON shape

Page Type Settings reads/writes the `properties` and `default_sort` fields of `_pagetype.json` (full shape above). Saved views (with their own sort / filter / group / layout / property order + hidden set) live in `views[]` as SavedView v2 → [[Views]].

---

#### No Page Type templates

Page Type creation does NOT seed default properties — name + icon only. Users add Status (or anything else) manually via Page Type Settings → Edit Properties → "+ Add property". Status is built-in on AgendaTask and AgendaEvent (where EventKit needs it); on user-created Page Types it is opt-in.

Content-level templates (Notion-style pre-fill at creation) are reserved for post-v1. Property type catalog, relation targets, Status groups → [[Properties]].

---

##### Content inside a Page Type

Pages — `.md` files with YAML frontmatter; prose-bearing. See [[Pages]].

Tasks and Events live in the Tasks singleton and Events singleton respectively (root folders identified by `_taskconfig.json` / `_eventconfig.json`) — see [[Agenda]].

---

#### Page Collections (sub-folders within a Page Type)

Filesystem folders inside a Page Type with a minimal sidecar. They inherit the parent Page Type's property schema but carry their own saved `views[]` (see § "View types"). Exist for visual / structural grouping inside large Page Types.

**`_pagecollection.json` sidecar** (Page Collection):

```json
{
  "id": "01H...",
  "type_id": "01H...",
  "schema_version": 1,
  "icon": "folder",
  "banner": ".nexus/assets/01H.../cover.jpg",
  "page_order": [],
  "set_order": [],
  "views": [],
  "modified_at": "2026-05-22T..."
}
```

Page Collections don't carry their own `properties` — the property schema is inherited from the parent Page Type. The sidecar carries `id`, `type_id` (parent Page Type reference), `schema_version`, `icon` (optional per-Collection SF Symbol, mirrored into SQLite for the context picker), an optional `banner` image path, `page_order` (user-arranged collection-root Pages — pages inside a Set order via that Set's own `page_order`), `set_order` (user-arranged child Page Sets), `views` (independent SavedView v2 configs → [[Views]]), and `modified_at`. An explicit on-disk `type_id` keeps external query tools from inferring it via filesystem nesting and gives Collections stable portable IDs across renames (vs SHA-256 path-hash fallback).

- Title = folder name; create = sub-folder + `_pagecollection.json`; rename = folder rename (id/type_id/modified_at preserved); delete = folder delete (warn-and-confirm if non-empty); moving a Page anywhere within the same Page Type (between Collections, Sets, and the Type root) = pure filesystem move, properties unchanged.

Page Sets subdivide a Collection one level further — schema-less, view-less, settings-less folders whose `_pageset.json` carries identity + icon + `page_order` only. Full spec → [[Sets]].

**Collection-local schemas** are a post-v1 Prospect; see [[Prospects]].

---

#### Sidebar treatment

- Page Types appear as chevron-disclosure rows directly under the `Vaults` section heading (default label per `SidebarSectionLabels.defaults()`; the heading itself is a pure UI grouping — there is no `Pages/` wrapper folder on disk). The sidebar groups under "Vaults" any root folder whose sidecar filename is `_pagetype.json`.
- **A Page Type's disclosure children**: Pages directly in the Type's root + Page Collection sub-folders (Pages above Collections in v1). Pages = `doc.text`; Collections = `folder`
- **A Page Collection's disclosure children**: its Page Sets (`folder`; expandable, never selectable) + its Pages (`doc.text`)
- **A Page Set's disclosure children**: its Pages (`doc.text`)
- **Agenda Tasks and Agenda Events do NOT appear in the sidebar** — they surface via the Calendar pin entry
- Clicking a Page Type opens `PageTypeDetailView` — the active saved view (custom Table or Gallery), vault-scoped, grouped by Collection with Sets nested by default (→ [[Views]])
- Clicking a Page Collection opens `PageCollectionDetailView` — the active saved view, collection-scoped, grouped by Set + an ungrouped root band by default. Page Sets have no detail view of their own
- Clicking a Page opens it in the main detail pane via the TextKit-2 editor (spec → [[PageEditor]])
- A new Page Type is created from the "+" button in the Pages section header. Right-clicking a Page Type row creates its children — "New Collection" / "New Page"; right-clicking a Page Collection gives "New Page" / "New Set"; right-clicking a Page Set gives "New Page". See [[Sidebar]] for the full table.

---

#### View types

Five view types carry through the data model; **Table** and **Gallery** render today (custom renderers, full spec → [[Views]]); **Board** / **List** / **Cards** are muted until later passes.

Table views carry **pre-configured tier columns** — rendered left-to-right as Project / Topic / Area (`tier3` / `tier2` / `tier1`) — at the rightmost content positions, between the last user-property column and the trailing Last Edited Time column. Each is a relation column rendering target icon + title, default-visible and individually hideable.

**Every storage container has view surfaces** — not just the schema-bearing Types. Page Types AND Page Collections both carry `views[]`. The property schema is inherited from the Type, but each container's saved view configuration is independent — a Page Collection can show a Board filtered to a subset of its Pages while the parent Page Type shows a Table.

Saved views persist in each container's sidecar `views[]` (`_pagetype.json` / `_pagecollection.json`) as SavedView v2 — full schema, the renderers, the view pipeline, sort/filter/group/layout config, drag semantics, and covers/banners → [[Views]]. Embedded view widgets in Context pages or Homepage reference by ID and apply local overrides without modifying the saved views (deferred).

---

#### Cross-layer connections

Pages carry `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Pages in Assignments where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page to another Page Type strips properties not in the destination schema (Notion-style, no quarantine). Confirmation warning lists what's stripped. Within the same Page Type (between Collections, Sets, and the Type root) there is no strip — shared schema, and Sets carry none of their own.

---

#### Validation

Enforced at every file write:

1. Page Type folder MUST contain `_pagetype.json` — otherwise it's a cosmetic folder, not a Page Type (eligible for adoption)
2. Every Page inside a Page Type must carry frontmatter values conforming to the Type's schema
3. Page Collection folder name doesn't collide with another Collection in the same Page Type; Page Set folder name doesn't collide with another Set in the same Collection
4. Filename = title

---

#### Adopting existing folders

Opening any folder as a Nexus — including pre-existing user folders that have never seen Pommora — runs an idempotent scan. The adopter classifies and migrates each root folder independently, so fresh folders, legacy sidecars, the prior wrapper layout, and the already-flat target state can coexist in one Nexus.

Shape detection per root folder:

- **Fresh** — no recognized sidecar. Content-sniff always picks Pages: fresh `.md`-bearing or empty folders adopt as Page Types (auto-tagged with a new `_pagetype.json`). Unrecognized legacy sidecars (e.g. a stale `_itemtype.json`) don't change the classification — the adoption semantic is canonical in [[Architecture]] § "Adoption".
- **Legacy Vault sidecar** — folder carries the `_vault` filename; renamed in place to `_pagetype.json`. Any sub-folder carrying a `_collection` sidecar is renamed to `_pagecollection.json`.
- **Legacy wrapper layout** — folder is one of the legacy wrappers (`Pages` / `Agenda` at root, each containing children with a unified `_schema` sidecar). The adopter unwraps each child up to the nexus root and renames the legacy unified sidecar to the appropriate per-kind name based on parent + depth — Page Type children become `_pagetype.json`, their nested Collections become `_pagecollection.json`, the Agenda wrapper's `Tasks` child becomes the Tasks singleton with `_taskconfig.json`, and the Agenda wrapper's `Events` child becomes the Events singleton with `_eventconfig.json`.
- **Already flat (target)** — folder carries one of the per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_pageset.json` / `_taskconfig.json` / `_eventconfig.json`) at the right depth. No-op (with a cleanup pass to delete any co-located legacy orphan sidecars).

Sidecar-less sub-folders auto-tag by depth (idempotent, honors `excluded_folders`): depth-1 folders inside a Page Type get `_pagecollection.json`, depth-2 folders inside a Collection get `_pageset.json`. Depth-3+ folders stay sidecar-less — their pages roll up into the nearest Set. The adoption preview labels third-level folders as Sets.

A preview sheet shows counts + a warnings list (ambiguous classifications, collisions, etc.). Adopt applies each folder's migration as a self-atomic step (no two-phase transaction across folders) — a single failure doesn't block the rest, and re-launching after an interruption is safe (already-migrated folders are recognized as "already flat" and skipped). Fully-flat Nexuses skip the sheet silently.

Exclusion set (never adopted): any folder starting with `.` or `_` (e.g. `.nexus`, `.trash`, `.obsidian`, `.makemd`, `.space`). Hidden folders are filtered by `.skipsHiddenFiles` at the enumerator level. There are no reserved top-level folder names — `Pages/` / `Agenda/` exist only as legacy input shapes the adopter unwraps.

`.md` files within an adopted Page Type need no Pommora-specific shape to surface — discovery is extension-based, and Pages without frontmatter open via the lenient loader ([[Pages]] § "On disk").

Implementation: `NexusAdopter.scan` + `.apply` at `Pommora/Pommora/Nexus/NexusAdopter.swift`; preview sheet at `AdoptionPreviewView.swift`; both `NexusManager.openPicked` and `openExisting` call `runAdoptionIfNeeded` after identity is set. Indexing status surfaces via `NexusManager.isIndexing` → `IndexingHUD` overlay in the sidebar.

---

