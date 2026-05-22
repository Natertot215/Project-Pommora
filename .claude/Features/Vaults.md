### Vaults

The operational layer's containment unit. A Vault is a **folder with a shared property schema** applied to all Content inside. Collections are sub-folders that share the Vault's schema. Supersedes the earlier `Collections.md` (now a stub redirect).

Maps to PARA's "Resources" — typed reference data, projects, and source material.

---

#### Two-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Vault** | Folder with property schema; all Content inside shares the schema | Folder containing `_vault.json` at the nexus root |
| **Collection** | Sub-folder inside a Vault; shares the Vault's schema (no own schema in v1) | Folder inside a Vault, no separate schema file |
| **Content** | Pages (`.md`) and Items (`.json`) | Files inside a Collection (or directly inside the Vault) |

Collections share the Vault's schema for simplicity (Collection-local overrides are a post-v1 Prospect). A Materials Vault is one coherent data pool — Pages, Documents, Reports, and Other collections all share the same `type`, `source`, `read_status` etc.

---

#### On disk

```
<nexus-root>/
  Planner/                          ← Vault
    _vault.json                      ← shared schema
    Tasks-archive/                   ← Collection (sub-folder)
      Old-task.json                  ← Item
    Goals/                           ← Collection
      Q1-goals.json                  ← Item
  Materials/                        ← Vault
    _vault.json
    Pages/Attention-is-all-you-need.md   ← Collection / Page
    Documents/Annual-report.json     ← Collection / Item
```

Vault folder name = Vault title. Collection folder name = Collection title. UI renames rename folders on disk. Content directly in a Vault (not in a Collection) is allowed — Collections are optional grouping.

---

#### `_vault.json` schema

```json
{
  "id": "01HVAULTID...",
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
        "kind": "vault",
        "vault_id": "01HMATERIALSVAULT..."
      },
      "allows_multiple": true,
      "dual_property": {
        "synced_property_name": "Cited By",
        "synced_property_defined_on_vault_id": "01HMATERIALSVAULT..."
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
  "hidden_properties": [],                  /* per-Vault: properties hidden as columns in the Vault Table view */
  "views": [
    /* per-view saved configurations (table / board / list / cards / gallery) — ships v0.6.0 */
  ],
  "modified_at": "2026-05-19T14:30:00Z"
}
```

Title = folder name. Schema applies to **all** Content inside (every Page's frontmatter and every Item's `properties` block must conform). `default_sort` is the per-Vault default in the Vault Table view (v0.3.0); full per-view sort + filter + group ships v0.6.0 with saved views. `hidden_properties` controls **Vault Table column** visibility (Vault-wide); distinct from per-entity inspector panel visibility (`<entity>.panel_hidden_properties` — see `// Features//Properties.md` "Per-entity property panel visibility").

**Paired relation properties** — the `sources` Relation above (`relation_scope.kind: "vault"` + `dual_property`) is one half of a paired relation. The target Vault (`01HMATERIALSVAULT...`) carries the reverse `"Cited By"` in its own `_vault.json`:

```json
{
  "name": "Cited By",
  "type": "relation",
  "relation_scope": {
    "kind": "vault",
    "vault_id": "01HTHISVAULT..."           /* points back at this Vault */
  },
  "allows_multiple": true,
  "dual_property": {
    "synced_property_name": "sources",      /* mirror of the source side */
    "synced_property_defined_on_vault_id": "01HTHISVAULT..."
  }
}
```

Both properties are created in a single SchemaTransaction two-phase commit. Setting a value on either side mirrors the reverse; renaming or deleting either cascades. See "Dual relations" in `// Features//Properties.md` for full lifecycle.

#### Vault Settings sheet

Central edit surface — schema, sort, filter, group-by, layout, property visibility. v0.3.0 ships six sections; three functional, three placeholder shells filling in at v0.6.0 with Vault Views.

##### Reaching Vault Settings

- **VaultDetailView toolbar** — gear (`gearshape`) at top-right
- **Vault row right-click** in sidebar — "Vault Settings…"
- **"+" column header** in Vault Table view — opens at Edit Properties + "Add property" active
- **Column header right-click** in Vault Table — "Edit property…" jumps to the relevant row

##### Six sections

| Section | v0.3.0 status | Editable settings |
|---|---|---|
| **Edit Properties** | Fully functional | Add / rename / delete / reorder properties; per-property icon (`IconPickerField`); per-type config (options, scope, dual reverse name, status groups, etc.) |
| **Sort** | Functional (single criterion) | Pick property + direction; persists to `_vault.json.default_sort`. Multi-criterion sort arrives v0.6.0 with saved views. |
| **Property Visibility** | Functional (per-Vault) | Show/hide per property in the Vault Table view. Persists to `_vault.json.hidden_properties: [String]`. Per-saved-view visibility ships v0.6.0. Distinct from per-entity `panel_hidden_properties` (inspector panel scope). |
| **Filter** | Placeholder — "Coming v0.6.0 with Vault Views" | WHERE-style criteria over property values |
| **Group By** | Placeholder — "Coming v0.6.0" | Groups Table rows by a property value — **folder-like sections in the Table**, each headed by variant name + color, rows clustered beneath. Same data backing as Board's kanban columns; different render. **Single-value types only** at v0.6.0 launch (Number, Select, Status, Date / Date & Time, Checkbox, Relation, Last Edited Time); **Multi-select NOT supported initially** (ambiguous group membership). Group order is **view-specific** (drag-reorder section headers; persists to `_vault.json.views[i].group_by.order: [String]`) — distinct from schema-level option order (Edit Properties → drag-reorder options), which affects the property across all views. Full spec → `// Features//Properties.md` "Schema-level option order vs view-level group order". |
| **Layout** | Placeholder — "Current: Table view. Five-type picker arrives v0.6.0" | View type — Table / Board / List / Cards / Gallery |
| **Templates** | Placeholder — "Coming post-v1" | Content templates (Page/Item) that pre-fill body + properties at creation. Vault-scoped. Reserved storage at `<nexus>/.nexus/templates/`. |

##### Properties section detail

Schema editor. Each row: icon (if set) + name, type badge, per-property menu (Rename / Change Type / Edit Options or Groups / Delete / Move Up-Down).

"+ Add property" opens the type picker → per-type config sub-view. Relation creation triggers `RelationPropertyWizard` (scope kind → target → name here → reverse name → allow multiple). Per-property config is editable inline within an expandable row (drag-reorder for Select/Multi-select options; 3-group editor for Status; etc.).

##### Settings JSON shape

Vault Settings reads/writes these `_vault.json` fields:

```json
{
  "properties": [ ... ],                  /* edited by Properties section */
  "default_sort": {                       /* edited by Sort section */
    "property": "last_edited_time",
    "direction": "descending"
  },
  "hidden_properties": [],                /* edited by Property Visibility */
  "filter": null,                         /* placeholder — populated v0.6.0 */
  "group_by": null,                       /* placeholder — populated v0.6.0 */
  "layout": "table"                       /* placeholder — only "table" until v0.6.0 */
}
```

`filter` / `group_by` / `layout` are written as `null` / `"table"` defaults v0.3.0; v0.6.0 expands their shapes.

---

#### No Vault templates (RC-2026-05-19)

Vault creation does NOT seed default properties. `NewVaultSheet` stays as v0.2.0 shipped — name + icon, no template toggles. Users add Status (or anything else) manually via Vault Settings → Edit Properties → "+ Add property". **Status is built-in only on Agenda** (where EventKit needs it); on user-created Vaults, Status is opt-in.

Future **content-level templates** (Page/Item, Notion-style pre-fill at creation) are reserved for post-v1; v0.3.0 keeps the scaffold compatible. See `// Planning//v0.3.0-Properties-implementation.md` "Content templates (post-v1 reservation)" for storage + Codable sketch + API signature reservation. Property type catalog, scope shapes, Status groups, dual-relation semantics → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

---

#### Content inside a Vault

- **Pages** — `.md` files with YAML frontmatter; prose-bearing. See `Pages.md`.
- **Items** — `.json` files; row-shaped, no body, open in an Item Window popover. See `Items.md`.

Vaults are kind-agnostic — Pages and Items can coexist sharing the same schema. The typed-Collection split from the earlier 3-entity model is gone.

---

#### Collections (sub-folders within a Vault)

Filesystem folders inside a Vault with a minimal sidecar — share the Vault's schema but persist stable identity. Exist for visual / structural grouping inside large Vaults.

**`_collection.json` sidecar** (paradigm decision 2026-05-16):

```json
{
  "id": "01H...",
  "vault_id": "01H...",
  "modified_at": "2026-05-17T..."
}
```

Making parent-Vault an explicit on-disk property keeps external query/parsing tools from inferring it via filesystem nesting, and gives Collections stable portable IDs across renames (vs SHA-256 path-hash fallback).

- Title = folder name; create = sub-folder + `_collection.json`; rename = folder rename (id/vault_id/modified_at preserved); delete = folder delete (warn-and-confirm if non-empty); moving Content between Collections in the same Vault = pure filesystem move, properties unchanged.

**Collection-local schemas** are a post-v1 Prospect; see `Prospects.md`.

---

#### Sidebar treatment

- Vaults appear as chevron-disclosure rows in the `Vaults` section
- **A Vault's disclosure children**: Pages directly in vault root + Collection sub-folders (Pages above Collections in v1). Pages = `doc.text`; Collections = `folder`
- **A Collection's disclosure children**: its Pages (`doc.text`)
- **Items, Agenda items, Events do NOT appear in the sidebar** — they live in detail-pane Tables. The sidebar tree is the structural / Page-shaped view
- Clicking a Vault opens `VaultDetailView` — hierarchical Finder-style Table over Collections (expandable for contained Pages + Items)
- Clicking a Collection opens `CollectionDetailView` — flat Table of Pages + Items
- Clicking a Page opens it in the main detail pane via TextKit-2 editor (shipped v0.2.7.0; spec → `PageEditor.md`)
- **Creation is right-click-only** — right-click a Vault row → "New Vault / New Collection / New Page"; right-click a Collection → "New Page". See `Sidebar.md` for the full table.

---

#### View types

Five view types (per-Vault and per-Collection scoping): **Table** (sortable columns, inline cell edit), **Board** (kanban grouped by a property's options), **List** (plain list with title + selected inline properties), **Gallery** (grid with cover image), **Cards** (grid without cover-first emphasis).

Saved views configured per-Vault in `_vault.json` `views[]`. Embedded view widgets in Context pages or Homepage reference by ID and apply local overrides without modifying the saved views.

---

#### Cross-layer connections

Vault Content (Pages, Items) carries `tier1` / `tier2` / `tier3` multi-relations to Contexts. Queryable both ways — a Topic's composed page can embed "all Tasks in Planner where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page or Item to another Vault strips properties not in the destination schema (Notion-style, no quarantine). Confirmation warning lists what's stripped. Within the same Vault (between Collections), no strip — shared schema.

---

#### Validation

Enforced at every file write:

1. Vault folder MUST contain `_vault.json` — otherwise it's a cosmetic folder, not a Vault
2. Every Page / Item inside a Vault must carry property values conforming to the Vault's schema
3. Collection folder name doesn't collide with another Collection in the same Vault
4. Filename = title

---

#### Adopting existing folders (shipped v0.2.7.4)

Opening any folder as a Nexus — including pre-existing user folders that have never seen Pommora — runs an idempotent scan that proposes Vaults for top-level folders missing `_vault.json` and Collections for direct sub-folders missing `_collection.json`. A preview sheet shows counts (Vaults / Collections / Pages / Items) plus the skipped set; Adopt writes the sidecars in place, Skip opens the Nexus empty. Re-runs on every open catch newly-dropped folders — the indexer is the source of truth, not first-launch state. Fully-adopted Nexuses skip the sheet silently.

Exclusion set (never adopted): any folder starting with `.` or `_`, plus `node_modules`, `.trash`, `Agenda`. Hidden folders are filtered by `.skipsHiddenFiles` at the enumerator level.

`.md` and `.json` files within an adopted Vault need no Pommora-specific shape to surface — the discovery is extension-based. Pages without Pommora frontmatter open via the lenient loader (synthesized id from path-relative SHA256; details → `Pages.md`). Items that don't decode as the `Item` shape are silently skipped (random `.json` like `package.json` won't pollute the sidebar).

Implementation: `NexusAdopter.scan` + `.apply` at `Pommora/Pommora/Nexus/NexusAdopter.swift`; preview sheet at `AdoptionPreviewView.swift`; both `NexusManager.openPicked` and `openExisting` call `runAdoptionIfNeeded` after identity is set. Indexing status surfaces via `NexusManager.isIndexing` → `IndexingHUD` overlay in the sidebar.

---

#### Full specification

Complete on-disk schema, SQLite mirror, sidebar layout, and CRUD scope → `// Planning//Contexts-Vaults-spec.md`.
