### Page Types

The operational layer's **Pages-side** schema-bearing container. A Page Type is a folder containing a `_schema.json` sidecar that defines the property schema shared by every Page inside. Page Collections are organizational sub-folders within a Page Type (sharing the Type's schema; no schema of their own).

**UI label divergence:** Page Types render as **"Vault"** in the Pommora app by default; Page Collections render as **"Collection"**. (Doc prose continues to say "Page Type" / "Page Collection" for conceptual clarity — only the UI label diverges.) Both labels renameable via the Settings scaffold (Phase 7).

Items have a parallel structure on the Items side — see [[Items]] for **Item Type** (UI: "Type") and **Item Collection** (UI: "Set"). Each side has one signature UI word + one shared UI word — Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". In generic prose discussing properties or queries, the term "Type" covers both; "Collection" covers both.

Maps to PARA's "Resources" alongside Item Types and Agenda.

---

#### Two-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Page Type** | Folder with property schema; every Page inside shares the schema | Folder under `<nexus>/Pages/` containing `_schema.json` |
| **Page Collection** | Organizational sub-folder inside a Page Type; inherits the Type's schema | Folder inside a Page Type containing its own `_schema.json` (id + ordering only — no properties) |
| **Content** | Pages only (`.md`) | Files inside a Page Collection, or directly inside the Page Type |

Page Collections share the parent Page Type's schema for simplicity (Collection-local overrides are a post-v1 Prospect). Items are NOT inside Page Types — they live on the Items side; see [[Items]].

---

#### On disk

```
<nexus-root>/
  Pages/                              ← organizational wrapper, NOT shown as sidebar row
    Assignments/                      ← Page Type
      _schema.json                    ← shared schema sidecar
      Spring-2026/                    ← Page Collection
        _schema.json                  ← per-Collection metadata
        Essay-1.md                    ← Page
      Final-Project.md                ← Page directly in Page Type root
```

Page Type folder name = Page Type title. Page Collection folder name = Collection title. UI renames rename folders on disk. A Page directly in a Page Type (not inside a Collection) is allowed — Collections are optional grouping.

---

#### `_schema.json` (Page Type)

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
      "relation_scope": {
        "kind": "page_type",
        "type_id": "01HMATERIALSPAGETYPE..."
      },
      "allows_multiple": true,
      "dual_property": {
        "synced_property_name": "Cited By",
        "synced_property_defined_on_type_id": "01HMATERIALSPAGETYPE..."
      }
    },
    {
      "name": "related topics",
      "type": "relation",
      "relation_scope": { "kind": "context_tier", "tier": 2 },
      "allows_multiple": true
    }
  ],
  "default_sort": { "property": "last_edited_time", "direction": "descending" },
  "hidden_properties": [],
  "views": [
    /* per-view saved configurations (table / board / list / cards / gallery) — ships v0.6.0 */
  ],
  "collection_order": [],
  "page_order": [],
  "modified_at": "2026-05-22T14:30:00Z"
}
```

Title = folder name. Schema applies to **every** Page inside (each Page's frontmatter must conform). `default_sort` is the per-Type default in the Table view (v0.3.0); full per-view sort + filter + group ships v0.6.0 with saved views. `hidden_properties` controls **Table column** visibility (Type-wide); distinct from per-entity inspector panel visibility (`<entity>.panel_hidden_properties` — see [[Properties]] "Per-entity property panel visibility"). `collection_order` and `page_order` carry the user-arranged sequence of child Page Collections and root-level Pages respectively.

**Paired relation properties** — the `sources` Relation above (`relation_scope.kind: "page_type"` + `dual_property`) is one half of a paired relation. The target Page Type (`01HMATERIALSPAGETYPE...`) carries the reverse `"Cited By"` in its own `_schema.json`:

```json
{
  "name": "Cited By",
  "type": "relation",
  "relation_scope": {
    "kind": "page_type",
    "type_id": "01HTHISPAGETYPE..."
  },
  "allows_multiple": true,
  "dual_property": {
    "synced_property_name": "sources",
    "synced_property_defined_on_type_id": "01HTHISPAGETYPE..."
  }
}
```

Both properties are created in a single SchemaTransaction two-phase commit. Setting a value on either side mirrors the reverse; renaming or deleting either cascades. See "Dual relations" in [[Properties]] for full lifecycle.

#### Page Type Settings sheet

Central edit surface — schema, sort, filter, group-by, layout, property visibility. v0.3.0 ships six sections; three functional, three placeholder shells filling in at v0.6.0 with Page Type Views.

**UI label note:** This section uses the doc term "Page Type Settings". The sheet's rendered title in the Pommora app reads **"Vault Settings…"** by default (the UI label for Page Type is "Vault"; both renameable via the Settings scaffold, Phase 7).

##### Reaching Page Type Settings

- **PageTypeDetailView toolbar** — gear (`gearshape`) at top-right
- **Page Type row right-click** in sidebar — "Vault Settings…" (default UI label)
- **"+" column header** in the Table view — opens at Edit Properties + "Add property" active
- **Column header right-click** in the Table — "Edit property…" jumps to the relevant row

##### Six sections

| Section | v0.3.0 status | Editable settings |
|---|---|---|
| **Edit Properties** | Fully functional | Add / rename / delete / reorder properties; per-property icon (`IconPickerField`); per-type config (options, scope, dual reverse name, status groups, etc.) |
| **Sort** | Functional (single criterion) | Pick property + direction; persists to `_schema.json.default_sort`. Multi-criterion sort arrives v0.6.0 with saved views. |
| **Property Visibility** | Functional (per-Page-Type) | Show/hide per property in the Table view. Persists to `_schema.json.hidden_properties: [String]`. Per-saved-view visibility ships v0.6.0. Distinct from per-entity `panel_hidden_properties` (inspector panel scope). |
| **Filter** | Placeholder — "Coming v0.6.0 with Page Type Views" | WHERE-style criteria over property values |
| **Group By** | Placeholder — "Coming v0.6.0" | Groups Table rows by a property value — folder-like sections in the Table, each headed by variant name + color, rows clustered beneath. Same data backing as Board's kanban columns; different render. **Single-value types only** at v0.6.0 launch (Number, Select, Status, Date / Date & Time, Checkbox, Relation, Last Edited Time); **Multi-select NOT supported initially** (ambiguous group membership). Group order is **view-specific** (drag-reorder section headers; persists to `_schema.json.views[i].group_by.order: [String]`) — distinct from schema-level option order (Edit Properties → drag-reorder options), which affects the property across all views. Full spec → [[Properties]] "Schema-level option order vs view-level group order". |
| **Layout** | Placeholder — "Current: Table view. Five-type picker arrives v0.6.0" | View type — Table / Board / List / Cards / Gallery |
| **Templates** | Placeholder — "Coming post-v1" | Content templates (Page) that pre-fill body + properties at creation. Page-Type-scoped. Reserved storage at `<nexus>/.nexus/templates/`. |

##### Properties section detail

Schema editor. Each row: icon (if set) + name, type badge, per-property menu (Rename / Change Type / Edit Options or Groups / Delete / Move Up-Down).

"+ Add property" opens the type picker → per-type config sub-view. Relation creation triggers `RelationPropertyWizard` (scope kind → target → name here → reverse name → allow multiple). Per-property config is editable inline within an expandable row (drag-reorder for Select/Multi-select options; 3-group editor for Status; etc.).

##### Settings JSON shape

Page Type Settings reads/writes these `_schema.json` fields:

```json
{
  "properties": [ ... ],
  "default_sort": {
    "property": "last_edited_time",
    "direction": "descending"
  },
  "hidden_properties": [],
  "filter": null,
  "group_by": null,
  "layout": "table"
}
```

`filter` / `group_by` / `layout` are written as `null` / `"table"` defaults v0.3.0; v0.6.0 expands their shapes.

---

#### No Page Type templates (RC-2026-05-19)

Page Type creation does NOT seed default properties. `NewPageTypeSheet` stays as v0.2.0 shipped — name + icon, no template toggles. Users add Status (or anything else) manually via Page Type Settings → Edit Properties → "+ Add property". **Status is built-in only on Agenda** (where EventKit needs it); on user-created Page Types, Status is opt-in.

Future **content-level templates** (Page, Notion-style pre-fill at creation) are reserved for post-v1; v0.3.0 keeps the scaffold compatible. See `// Planning//v0.3.0-Properties-implementation.md` "Content templates (post-v1 reservation)" for storage + Codable sketch + API signature reservation. Property type catalog, scope shapes, Status groups, dual-relation semantics → [[Properties]]. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

---

##### Content inside a Page Type

Pages — `.md` files with YAML frontmatter; prose-bearing. See [[Pages]].

Items are NOT inside Page Types — they live on the Items side inside an [[Items|Item Type]] (the parallel schema-bearing container). The kind-agnostic Vault model from pre-ParadigmV2 is gone.

Tasks and Events live in `<nexus>/Agenda/Tasks/` and `<nexus>/Agenda/Events/` respectively — see [[Agenda]].

---

#### Page Collections (sub-folders within a Page Type)

Filesystem folders inside a Page Type with a minimal sidecar. Pages-only — Page Collections never contain Items. They share the parent Page Type's schema (properties + views live on the Type) but persist stable identity for rename-safe references. Exist for visual / structural grouping inside large Page Types.

**`_schema.json` sidecar** (Page Collection):

```json
{
  "id": "01H...",
  "type_id": "01H...",
  "modified_at": "2026-05-22T...",
  "page_order": []
}
```

Page Collections don't carry their own `properties` or `views` — schema is inherited from the parent Page Type. The sidecar carries only `id`, `type_id` (parent Page Type reference), `page_order` (user-arranged sequence of child Pages), and `modified_at`. Making `type_id` an explicit on-disk property keeps external query/parsing tools from inferring it via filesystem nesting, and gives Page Collections stable portable IDs across renames (vs SHA-256 path-hash fallback).

- Title = folder name; create = sub-folder + `_schema.json`; rename = folder rename (id/type_id/modified_at preserved); delete = folder delete (warn-and-confirm if non-empty); moving a Page between Collections in the same Page Type = pure filesystem move, properties unchanged.

**Collection-local schemas** are a post-v1 Prospect; see [[Prospects]].

---

#### Sidebar treatment

- Page Types appear as chevron-disclosure rows directly under the `Pages` section heading (the `<nexus>/Pages/` wrapper folder is disk-layout only — not rendered as a sidebar row)
- **A Page Type's disclosure children**: Pages directly in the Type's root + Page Collection sub-folders (Pages above Collections in v1). Pages = `doc.text`; Collections = `folder`
- **A Page Collection's disclosure children**: its Pages (`doc.text`)
- **Items, Agenda Tasks, Agenda Events do NOT appear in the sidebar** — Items live in detail-pane Tables under their Item Type; Tasks + Events surface via the Calendar pin entry
- Clicking a Page Type opens `PageTypeDetailView` — hierarchical Finder-style Table over Collections (expandable for contained Pages)
- Clicking a Page Collection opens `PageCollectionDetailView` — flat Table of Pages
- Clicking a Page opens it in the main detail pane via TextKit-2 editor (shipped v0.2.7.0; spec → [[PageEditor]])
- **Creation is right-click-only** — right-click a Page Type row → "New Vault / New Collection / New Page" (UI labels); right-click a Page Collection → "New Page". See [[Sidebar]] for the full table.

---

#### View types

Five view types (per-Page-Type and per-Page-Collection scoping): **Table** (sortable columns, inline cell edit), **Board** (kanban grouped by a property's options), **List** (plain list with title + selected inline properties), **Gallery** (grid with cover image), **Cards** (grid without cover-first emphasis).

Saved views configured per-Page-Type in `_schema.json` `views[]`. Embedded view widgets in Context pages or Homepage reference by ID and apply local overrides without modifying the saved views.

---

#### Cross-layer connections

Pages carry `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Pages in Assignments where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page to another Page Type strips properties not in the destination schema (Notion-style, no quarantine). Confirmation warning lists what's stripped. Within the same Page Type (between Collections), no strip — shared schema.

---

#### Validation

Enforced at every file write:

1. Page Type folder MUST contain `_schema.json` — otherwise it's a cosmetic folder, not a Page Type
2. Every Page inside a Page Type must carry frontmatter values conforming to the Type's schema
3. Page Collection folder name doesn't collide with another Collection in the same Page Type
4. Filename = title

---

#### Adopting existing folders

Opening any folder as a Nexus — including pre-existing user folders that have never seen Pommora — runs an idempotent scan. Post-ParadigmV2, **only folders under `<nexus>/Pages/` are adopted as Page Types** — the wrapper is mandatory. Top-level folders at the nexus root outside `Pages/` are NOT adopted.

For folders under `<nexus>/Pages/` missing `_schema.json`, the adopter proposes Page Types; for direct sub-folders inside an adopted Page Type missing `_schema.json`, it proposes Page Collections. A preview sheet shows counts (Page Types / Page Collections / Pages) plus the skipped set; Adopt writes the sidecars in place, Skip opens the Nexus empty. Re-runs on every open catch newly-dropped folders — the indexer is the source of truth, not first-launch state. Fully-adopted Nexuses skip the sheet silently.

Items-side adoption (folders under `<nexus>/Items/`) follows the parallel rule — see [[Items]].

Exclusion set (never adopted): any folder starting with `.` or `_`, plus `node_modules`, `.trash`, `Agenda`. Hidden folders are filtered by `.skipsHiddenFiles` at the enumerator level.

`.md` files within an adopted Page Type need no Pommora-specific shape to surface — the discovery is extension-based. Pages without Pommora frontmatter open via the lenient loader (synthesized id from path-relative SHA256; details → [[Pages]]).

Implementation: `NexusAdopter.scan` + `.apply` at `Pommora/Pommora/Nexus/NexusAdopter.swift`; preview sheet at `AdoptionPreviewView.swift`; both `NexusManager.openPicked` and `openExisting` call `runAdoptionIfNeeded` after identity is set. Indexing status surfaces via `NexusManager.isIndexing` → `IndexingHUD` overlay in the sidebar.

---

#### Full specification

Complete on-disk schema, SQLite mirror, sidebar layout, and CRUD scope → `// Planning//Contexts-Vaults-spec.md`.
