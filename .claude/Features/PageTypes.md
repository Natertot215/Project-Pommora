### Page Types

The operational layer's **Pages-side** schema-bearing container. A Page Type is a folder containing a `_pagetype.json` sidecar that defines the property schema shared by every Page inside. Page Collections are organizational sub-folders within a Page Type carrying their own `_pagecollection.json` sidecar (sharing the Type's schema; no properties of their own).

**UI label divergence:** Page Types render as **"Vault"** in the Pommora app by default; Page Collections render as **"Collection"**. (Doc prose continues to say "Page Type" / "Page Collection" for conceptual clarity — only the UI label diverges.) Both labels renameable via the Settings scaffold (v0.3.0 storage / v0.6.0 editing UI).

Items have a parallel structure on the Items side — see [[Items]] for **Item Type** (UI: "Type") and **Item Collection** (UI: "Set"). Each side has one signature UI word + one shared UI word — Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". In generic prose discussing properties or queries, the term "Type" covers both; "Collection" covers both.

Maps to PARA's "Resources" alongside Item Types and Agenda.

---

#### Two-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Page Type** | Folder with property schema; every Page inside shares the schema | Folder at the nexus root containing `_pagetype.json` |
| **Page Collection** | Organizational sub-folder inside a Page Type; inherits the Type's schema | Folder inside a Page Type containing its own `_pagecollection.json` (id + ordering only — no properties) |
| **Content** | Pages only (`.md`) | Files inside a Page Collection, or directly inside the Page Type |

Page Collections share the parent Page Type's schema for simplicity (Collection-local overrides are a post-v1 Prospect). Items are NOT inside Page Types — they live on the Items side; see [[Items]].

---

#### On disk

```
<nexus-root>/
  Assignments/                        ← Page Type (root folder; identified by sidecar)
    _pagetype.json                    ← shared schema sidecar
    Spring-2026/                      ← Page Collection
      _pagecollection.json            ← per-Collection metadata
      Essay-1.md                      ← Page
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
    { "name": "priority", "type": "number", "number_format": "integer" },
    {
      "name": "sources",
      "icon": "doc.text.magnifyingglass",
      "type": "relation",
      "relation_target": {
        "kind": "page_type",
        "page_type_id": "01HMATERIALSPAGETYPE..."
      },
      "dual_property": {
        "synced_property_id": "prop_01HCITEDBY...",
        "synced_property_defined_on_type_id": "01HMATERIALSPAGETYPE..."
      }
    },
    {
      "name": "related topics",
      "type": "relation",
      "relation_target": { "kind": "context_tier", "tier": 2 }
    }
  ],
  "default_sort": { "property_id": "_modified_at", "direction": "descending" },
  "hidden_properties": [],
  "views": [
    /* per-view saved configurations (table / board / list / cards / gallery) — ships v0.6.0 */
  ],
  "collection_order": [],
  "page_order": [],
  "modified_at": "2026-05-22T14:30:00Z"
}
```

Title = folder name. Schema applies to every Page inside (each Page's frontmatter must conform). `default_sort` is the per-Type default sort. `hidden_properties` (per-Type column visibility) and `panel_hidden_properties` (per-entity hide-list) are deferred from v0.3.0 — the Pages Pulldown's lazy mode handles "hide empty" implicitly there; Inspectors are eager, so explicit `panel_hidden_properties` ships post-v0.3.0 if users need to exclude properties from inspector visibility. `collection_order` and `page_order` carry the user-arranged sequence of child Page Collections and root-level Pages respectively.

**Relation values are always multi-valued.** A relation property holds an array of tagged target objects — `[{"$rel": "<ULID>"}]` — in the member file's frontmatter / JSON, one entry per linked target (a single target is a one-element array). Values render as the target's **icon + title in plain styled colored text** (never chips/pills), resolved live from the target entity.

**Paired relation properties** — the `sources` Relation above (`relation_target.kind: "page_type"` + `dual_property`) is one half of a paired relation. The target Page Type (`01HMATERIALSPAGETYPE...`) carries the reverse `"Cited By"` in its own `_pagetype.json`:

```json
{
  "name": "Cited By",
  "type": "relation",
  "relation_target": {
    "kind": "page_type",
    "page_type_id": "01HTHISPAGETYPE..."
  },
  "dual_property": {
    "synced_property_id": "prop_01HSOURCES...",
    "synced_property_defined_on_type_id": "01HTHISPAGETYPE..."
  }
}
```

Both properties are created in a single SchemaTransaction two-phase commit. Setting a value on either side mirrors the reverse; renaming or deleting either cascades. See "Dual relations" in [[Properties]] for full lifecycle.

#### Page Type Settings sheet

The schema editor for a Page Type. UI label: "Vault Settings…" by default (renameable via the Settings scaffold).

##### Reaching Page Type Settings

- **PageTypeDetailView toolbar** — gear (`gearshape`) at top-right
- **Page Type row right-click** in sidebar — "Vault Settings…"
- **"+" column header in Table view** — opens Edit Properties + Add Property flow
- **Column header right-click → "Edit property…"** — jumps to the relevant row

##### Sections

| Section | Contents |
|---|---|
| **Edit Properties** | Add / rename / delete / reorder properties. Per-property icon (`IconPickerField`). Per-type config (options, scope, dual reverse name, status groups, etc.). |
| **Templates** | Empty wiring — placeholder anchor for future content templates. Reserved post-v1. |

Per-view configuration (Sort / Group By / Filter / Layout / Property Visibility) lives in **Vault / Type View Settings**, which ships at v0.6.0 alongside saved views. A per-Type default sort persists on `_pagetype.json.default_sort` as a fallback before saved views ship.

##### Properties section detail

Schema editor. Each row: icon (if set) + name, type badge, per-property menu (Rename / Change Type / Edit Options or Groups / Delete / Move Up-Down).

"+ Add property" opens the type picker → per-type config sub-view. Relation properties are created and edited via the View Settings popover (`EditPropertyPane` `.newRelation` route); selecting Relation in these legacy sheets cancels silently and defers to that path. Per-property config is editable inline within an expandable row (drag-reorder for Select/Multi-select options; 3-group editor for Status).

Save-required + concurrent-open forbidden (only one Type's Settings sheet open at a time per window).

##### Settings JSON shape

Page Type Settings reads/writes these `_pagetype.json` fields:

```json
{
  "properties": [ /* schema; see Properties.md for full shape */ ],
  "default_sort": {
    "property_id": "_modified_at",
    "direction": "descending"
  },
  "template_config": null
}
```

Saved views (with their own filter / group_by / layout / property_visibility) live in `views[]`, populated at v0.6.0 when the saved-views system ships.

---

#### No Page Type templates

Page Type creation does NOT seed default properties — name + icon only. Users add Status (or anything else) manually via Page Type Settings → Edit Properties → "+ Add property". Status is built-in on both AgendaTask and AgendaEvent (where EventKit needs it); on user-created Page Types and Item Types, Status is opt-in.

Future **content-level templates** (Page, Notion-style pre-fill at creation) are reserved for post-v1; v0.3.0 keeps the scaffold compatible. Property type catalog, scope shapes, Status groups, dual-relation semantics → [[Properties]]. Implementation plan → `// Planning//v0.3.0-Properties-plan.md`.

---

##### Content inside a Page Type

Pages — `.md` files with YAML frontmatter; prose-bearing. See [[Pages]].

Items are NOT inside Page Types — they live on the Items side inside an [[Items|Item Type]] (the parallel schema-bearing container).

Tasks and Events live in the Tasks singleton and Events singleton respectively (root folders identified by `_taskconfig.json` / `_eventconfig.json`) — see [[Agenda]].

---

#### Page Collections (sub-folders within a Page Type)

Filesystem folders inside a Page Type with a minimal sidecar. Pages-only — Page Collections never contain Items. They share the parent Page Type's schema (properties + views live on the Type) but persist stable identity for rename-safe references. Exist for visual / structural grouping inside large Page Types.

**`_pagecollection.json` sidecar** (Page Collection):

```json
{
  "id": "01H...",
  "type_id": "01H...",
  "modified_at": "2026-05-22T...",
  "page_order": []
}
```

Page Collections don't carry their own `properties` or `views` — schema is inherited from the parent Page Type. The sidecar carries only `id`, `type_id` (parent Page Type reference), `page_order` (user-arranged sequence of child Pages), and `modified_at`. Making `type_id` an explicit on-disk property keeps external query/parsing tools from inferring it via filesystem nesting, and gives Page Collections stable portable IDs across renames (vs SHA-256 path-hash fallback).

- Title = folder name; create = sub-folder + `_pagecollection.json`; rename = folder rename (id/type_id/modified_at preserved); delete = folder delete (warn-and-confirm if non-empty); moving a Page between Collections in the same Page Type = pure filesystem move, properties unchanged.

**Collection-local schemas** are a post-v1 Prospect; see [[Prospects]].

---

#### Sidebar treatment

- Page Types appear as chevron-disclosure rows directly under the `Vaults` section heading (default label per `SidebarSectionLabels.defaults()`; the heading itself is a pure UI grouping — there is no `Pages/` wrapper folder on disk). The sidebar groups under "Vaults" any root folder whose sidecar filename is `_pagetype.json`.
- **A Page Type's disclosure children**: Pages directly in the Type's root + Page Collection sub-folders (Pages above Collections in v1). Pages = `doc.text`; Collections = `folder`
- **A Page Collection's disclosure children**: its Pages (`doc.text`)
- **Items, Agenda Tasks, Agenda Events do NOT appear in the sidebar** — Items live in detail-pane Tables under their Item Type; Tasks + Events surface via the Calendar pin entry
- Clicking a Page Type opens `PageTypeDetailView` — hierarchical Finder-style Table over Collections (expandable for contained Pages)
- Clicking a Page Collection opens `PageCollectionDetailView` — flat Table of Pages
- Clicking a Page opens it in the main detail pane via TextKit-2 editor (shipped v0.2.7.0; spec → [[PageEditor]])
- **Creation is right-click-only** — right-click a Page Type row → "New Vault / New Collection / New Page" (UI labels); right-click a Page Collection → "New Page". See [[Sidebar]] for the full table.

---

#### View types

Five view types: **Table** (sortable columns, inline cell edit), **Board** (kanban grouped by a property's options), **List** (plain list with title + selected inline properties), **Gallery** (grid with cover image), **Cards** (grid without cover-first emphasis).

Table views carry **pre-configured tier columns** — Spaces / Topics / Projects (`tier1` / `tier2` / `tier3`) — at the rightmost content positions, between the last user-property column and the trailing Last Edited Time column. Each is a relation column rendering target icon + title, default-visible and individually hideable.

**Every storage container has view surfaces** — not just the schema-bearing Types. Page Types AND Page Collections both carry `views[]`; on the Items side, Item Types AND Item Sets do too. Schema is inherited from the Type (Collections don't override schema in v1), but each container's saved view configuration is independent. A Page Collection can have a Board view filtered to a subset of its Pages while the parent Page Type shows a Table — same data, two view surfaces.

Saved views persist in each container's sidecar `views[]` (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json`). Embedded view widgets in Context pages or Homepage reference by ID and apply local overrides without modifying the saved views.

---

#### Cross-layer connections

Pages carry `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Pages in Assignments where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page to another Page Type strips properties not in the destination schema (Notion-style, no quarantine). Confirmation warning lists what's stripped. Within the same Page Type (between Collections), no strip — shared schema.

---

#### Validation

Enforced at every file write:

1. Page Type folder MUST contain `_pagetype.json` — otherwise it's a cosmetic folder, not a Page Type (eligible for adoption)
2. Every Page inside a Page Type must carry frontmatter values conforming to the Type's schema
3. Page Collection folder name doesn't collide with another Collection in the same Page Type
4. Filename = title

---

#### Adopting existing folders

Opening any folder as a Nexus — including pre-existing user folders that have never seen Pommora — runs an idempotent scan. The adopter classifies each root folder independently and tolerates mixed states: fresh folders, legacy sidecars from earlier shapes, the wrapper layout from a prior refactor, and the already-flat target state can all coexist in one Nexus, and each folder is migrated on its own.

Shape detection per root folder:

- **Fresh** — no recognized sidecar. Content-sniff (recursive `.md` vs `.json` count): `.md` dominant → Page Type candidate; `.json` dominant → Item Type candidate; empty → default Page Type.
- **Legacy Vault sidecar** — folder carries the `_vault` filename; renamed in place to `_pagetype.json`. Any sub-folder carrying a `_collection` sidecar is renamed to `_pagecollection.json`.
- **Legacy wrapper layout** — folder is one of the legacy wrappers (`Pages` / `Items` / `Agenda` at root, each containing children with a unified `_schema` sidecar). The adopter unwraps each child up to the nexus root and renames the legacy unified sidecar to the appropriate per-kind name based on parent + depth — Page Type children become `_pagetype.json`, their nested Collections become `_pagecollection.json`, the Items wrapper's children become `_itemtype.json` / `_itemcollection.json`, the Agenda wrapper's `Tasks` child becomes the Tasks singleton with `_taskconfig.json`, and the Agenda wrapper's `Events` child becomes the Events singleton with `_eventconfig.json`.
- **Already flat (target)** — folder carries one of the six per-kind sidecars at the right depth. No-op (with a cleanup pass to delete any co-located legacy orphan sidecars).

A preview sheet shows counts + a warnings list (ambiguous classifications, collisions, etc.). Adopt applies each folder's migration as a self-atomic step (no two-phase transaction across folders) — a single failure doesn't block the rest, and re-launching after an interruption is safe (already-migrated folders are recognized as "already flat" and skipped). Fully-flat Nexuses skip the sheet silently.

Items-side adoption follows the parallel rule (root folders with `_itemtype.json`) — see [[Items]].

Exclusion set (never adopted): any folder starting with `.` or `_` (e.g. `.nexus`, `.trash`, `.obsidian`, `.makemd`, `.space`). Hidden folders are filtered by `.skipsHiddenFiles` at the enumerator level. There are no reserved top-level folder names — `Pages/` / `Items/` / `Agenda/` exist only as legacy input shapes the adopter unwraps.

`.md` files within an adopted Page Type need no Pommora-specific shape to surface — the discovery is extension-based. Pages without Pommora frontmatter open via the lenient loader (synthesized id from path-relative SHA256; details → [[Pages]]).

Implementation: `NexusAdopter.scan` + `.apply` at `Pommora/Pommora/Nexus/NexusAdopter.swift`; preview sheet at `AdoptionPreviewView.swift`; both `NexusManager.openPicked` and `openExisting` call `runAdoptionIfNeeded` after identity is set. Indexing status surfaces via `NexusManager.isIndexing` → `IndexingHUD` overlay in the sidebar.

---

