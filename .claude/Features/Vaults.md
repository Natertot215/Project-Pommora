### Vaults

The operational layer's containment unit. A Vault is a **folder with a shared property schema** that applies to all Content inside it. Collections are sub-folders within a Vault that share the Vault's schema. This doc supersedes most of the earlier `Collections.md`; that doc is now a stub redirect.

Maps to PARA's "Resources" — the place where typed reference data, projects, and source material lives.

---

#### Two-tier shape

| Entity | Role | On disk |
|---|---|---|
| **Vault** | Folder with property schema; all Content inside shares the schema | A folder containing `_vault.json` at the nexus root |
| **Collection** | Sub-folder inside a Vault; shares the Vault's schema (no own schema in v1) | A folder inside a Vault, no separate schema file |
| **Content** | The actual data — Pages (`.md`) and Items (`.json`) | Files inside a Collection (or directly inside the Vault) |

Why Collections share the Vault's schema: simplicity. v1 doesn't support Collection-local property overrides — that's tracked as a Prospect for post-v1. The benefit is that a Materials Vault is one coherent data pool: Pages, Documents, Reports, and Other collections inside it all share the same `type`, `source`, `read_status` etc. — no parallel mini-databases.

---

#### On disk

```
<nexus-root>/
  Planner/                      ← Vault
    _vault.json                  ← shared schema
    Tasks-archive/               ← Collection (sub-folder)
      Old-task.json              ← Item
    Goals/                       ← Collection
      Q1-goals.json              ← Item

  Materials/                    ← Vault
    _vault.json
    Pages/                       ← Collection
      Attention-is-all-you-need.md   ← Page
    Documents/
      Annual-report.json         ← Item
```

Vault folder name = Vault title. Collection folder name = Collection title. File renames in UI rename folders on disk.

Content sitting directly in a Vault (not in a Collection) is allowed — the Collection sub-folder is optional grouping, not a requirement.

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

The Vault's title comes from the folder name. Property schema applies to **all** Content inside (every Page's frontmatter and every Item's `properties` block must conform). `default_sort` is the per-Vault default sort applied to the Vault Table view (v0.3.0); the full per-view sort + filter + group ships at v0.6.0 alongside saved views. `hidden_properties` controls **Vault Table column** visibility — Vault-wide; distinct from per-entity inspector panel visibility (`<entity>.panel_hidden_properties`) which is its own field on Pages / Items / Agenda items (see `// Features//Properties.md` "Per-entity property panel visibility").

**Paired relation properties** — the `sources` Relation property above (`relation_scope.kind: "vault"` + `dual_property` filled) is one half of a paired relation. The target Vault (`01HMATERIALSVAULT...`) carries the corresponding reverse property `"Cited By"` in its own `_vault.json`:

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

The two properties are created in a single atomic transaction (SchemaTransaction two-phase commit). Setting a value on either side mirrors the reverse value automatically. Renaming or deleting either side cascades to the other. See "Dual relations" in `// Features//Properties.md` for full lifecycle.

#### Vault Settings sheet

The central edit surface for everything about a Vault — schema, sort, filter, group-by, layout, property visibility. v0.3.0 ships the sheet with six sections; three are functional at v0.3.0 and three are placeholder shells that fill in at v0.6.0 alongside Vault Views.

##### Reaching Vault Settings

- **VaultDetailView toolbar** — gear button (`gearshape`) at the top-right of the detail pane
- **Vault row right-click** in sidebar — "Vault Settings…" menu entry
- **"+" column header** in Vault Table view — opens to Edit Properties section + "Add property" active
- **Column header right-click** in Vault Table — "Edit property…" jumps to the relevant Property row

##### Six sections

| Section | v0.3.0 status | Editable settings |
|---|---|---|
| **Edit Properties** | Fully functional | Add / rename / delete / reorder properties; per-property icon (`IconPickerField`); per-type config (options, scope, dual reverse name, status groups, etc.) |
| **Sort** | Functional (single criterion) | Pick property + direction; persists to `_vault.json.default_sort`. Multi-criterion sort arrives v0.6.0 with saved views. |
| **Property Visibility** | Functional (per-Vault) | Show/hide per property in the Vault Table view. Persists to `_vault.json.hidden_properties: [String]`. Per-saved-view visibility ships v0.6.0. Distinct from per-entity `panel_hidden_properties` (inspector panel scope). |
| **Filter** | Placeholder — "Coming v0.6.0 with Vault Views" | WHERE-style criteria over property values |
| **Group By** | Placeholder — "Coming v0.6.0" | Groups rows in the Table view by a chosen property value — **renders as folder-like sections inside the Table**, each section headed by the variant's name + color, with rows clustering beneath. Same data backing as Board view's kanban columns; different render. **Restricted to single-value property types** at v0.6.0 launch (Number, Select, Status, Date / Date & Time, Checkbox, Relation, Last Edited Time) — **Multi-select is NOT supported initially** (ambiguous which group a row with multiple values belongs to; deferred to a later patch). Group order within the view is **view-specific** (drag-reorder section headers in the view editor; persists to `_vault.json.views[i].group_by.order: [String]`). This is distinct from schema-level option order (Edit Properties → drag-reorder options), which affects the property itself across all views. Full spec → `// Features//Properties.md` "Schema-level option order vs view-level group order". |
| **Layout** | Placeholder — "Current: Table view. Five-type picker arrives v0.6.0" | View type — Table / Board / List / Cards / Gallery |
| **Templates** | Placeholder — "Coming post-v1" | Content templates (Page templates, Item templates) that pre-fill body + properties at content creation time. Lives in Vault Settings (this section) so templates are scoped to their Vault. Reserved storage at `<nexus>/.nexus/templates/`. |

##### Properties section detail

The Properties section is the schema editor. Each row in the list shows:
- The property's icon (if set) + name
- Type badge (small label)
- Per-property menu: Rename / Change Type / Edit Options or Groups / Delete / Move Up-Down

The "+ Add property" button at the bottom opens the type picker → per-type config sub-view. Relation property creation triggers the multi-step `RelationPropertyWizard` (scope kind → target → property name in this Vault → reverse name in target → allow multiple).

Per-property config is editable inline within the property's expandable row (drag-to-reorder list for Select/Multi-select options; 3-group editor for Status; etc.).

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

`filter` / `group_by` / `layout` are written as `null` / `"table"` defaults in v0.3.0; v0.6.0 expands their shapes when the placeholder sections fill in.

---

#### No Vault templates (RC-2026-05-19)

Vault creation does NOT seed default properties. `NewVaultSheet` stays as v0.2.0 shipped — name + icon, no template toggles. Users who want Status (or any other property) on a Vault add it manually via Vault Settings → Edit Properties → "+ Add property".

**Status is built-in only on Agenda** (where EventKit needs it). On user-created Vaults, Status is a normal property type the user opts into.

Future **content-level templates** (Page templates, Item templates — Notion-style, pre-fill body + properties at creation time) are reserved for post-v1. v0.3.0 keeps the data scaffold compatible without shipping a template surface. See `// Planning//v0.3.0-Properties-implementation.md` "Content templates (post-v1 reservation)" for the reserved storage location + Codable sketch + API signature reservation.

Property type catalog, scope shapes, Status groups, and dual-relation semantics → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

---

#### Content inside a Vault

Two file types are valid Content:
- **Pages** — `.md` files with YAML frontmatter; prose-bearing. See `Pages.md`.
- **Items** — `.json` files; row-shaped, no body, open in an Item Window popover. See `Items.md`.

A single Vault can hold both Pages and Items — heterogeneous content sharing the same property schema. v1 makes no distinction between "Pages Vault" and "Items Vault" — the typed-Collection split from the earlier 3-entity model is gone. Vaults are kind-agnostic.

---

#### Collections (sub-folders within a Vault)

Collections in v1 are **filesystem folders inside a Vault** with a minimal sidecar — they share the Vault's schema but persist their own stable identity. They exist for visual / structural grouping inside large Vaults.

**`_collection.json` sidecar** (paradigm decision 2026-05-16) — every Collection folder contains:

```json
{
  "id": "01H...",
  "vault_id": "01H...",
  "modified_at": "2026-05-17T..."
}
```

Making the parent-Vault relation an explicit on-disk property keeps external query/parsing tools from having to infer it from filesystem nesting, and gives Collections stable portable IDs across renames (vs the SHA-256 path-hash fallback the original spec assumed).

- A Collection's title comes from its folder name
- Creating a Collection = creating a sub-folder + writing `_collection.json`
- Renaming a Collection = renaming the folder (id/vault_id/modified_at preserved in sidecar)
- Deleting a Collection = deleting the folder (with warn-and-confirm if it contains Content)
- Moving Content between Collections within the same Vault: pure filesystem move; properties survive unchanged (same schema)

**Collection-local schemas** are a post-v1 Prospect; see `Prospects.md`.

---

#### Sidebar treatment

- Vaults appear as chevron-disclosure rows in the sidebar's `Vaults` section
- **A Vault's disclosure children are: Pages directly in the vault root + Collection sub-folders** (Pages above Collections in v1). Pages render with the `doc.text` icon; Collections render with the `folder` icon
- **A Collection's disclosure children are: its Pages** (also `doc.text` icon)
- **Items, Agenda items, Events do NOT appear in the sidebar** — they live exclusively in the detail-pane Tables. The sidebar tree is the structural / Page-shaped view; the detail pane is the full data view including Items
- Clicking a Vault opens `VaultDetailView` — a hierarchical Finder-style Table over Collections (expandable to show contained Pages + Items)
- Clicking a Collection opens `CollectionDetailView` — a flat Table of Pages + Items in that Collection
- Clicking a Page is a no-op until the Markdown editor lands (v0.6); the row is visible / selectable in the sidebar but doesn't open anything yet
- **Creation is right-click-only** — right-click a Vault row → "New Vault / New Collection / New Page" (all scoped to that Vault); right-click a Collection row → "New Page" (in that Collection); see `Sidebar.md` for the full right-click table

---

#### View types

Five view types over Vault Content (and per-Collection scoping):
- **Table** — sortable columns, inline cell edit
- **Board** — kanban layout grouped by a property's options
- **List** — plain list with title + selected inline properties
- **Gallery** — grid with cover image
- **Cards** — grid without cover-first emphasis

Saved views configured per-Vault in `_vault.json` `views[]`. Embedded view widgets in Context pages or Homepage reference these by ID and apply local overrides (filter / sort / group / shown-properties) without modifying the Vault's saved views.

---

#### Cross-layer connections

Vault Content (Pages, Items) carries `tier1` / `tier2` / `tier3` multi-relation fields pointing to Contexts. The relations are queryable both ways — a Topic's composed page can embed a view of "all Tasks in Planner where `tier2` includes this Topic."

---

#### Move-strip rule

Moving a Page or Item from one Vault to another strips properties not in the destination Vault's schema (Notion-style, no quarantine). Simple confirmation warning lists what will be stripped. Within the same Vault (between Collections), no strip — schema is shared.

---

#### Validation

Enforced at every file write:

1. Vault folder MUST contain `_vault.json` — otherwise it's a cosmetic folder, not a Vault
2. Every Page / Item inside a Vault must carry property values conforming to the Vault's schema
3. Collection folder name doesn't collide with another Collection in the same Vault
4. Filename = title

---

#### Full specification

Complete on-disk schema, SQLite mirror, sidebar layout, and CRUD scope live in `// Planning//Contexts-Vaults-spec.md`.
