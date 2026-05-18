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
  "id": "01H...",
  "icon": "folder",
  "properties": [
    {
      "name": "status",
      "type": "select",
      "options": [
        { "value": "Active", "color": "blue" },
        { "value": "Done",   "color": "green" }
      ]
    },
    { "name": "due", "type": "date" }
  ],
  "views": [
    /* saved view configurations (table / board / list / cards / gallery) */
  ],
  "modified_at": 1716480000
}
```

The Vault's title comes from the folder name. Property schema applies to **all** Content inside (every Page's frontmatter and every Item's `properties` block must conform). Saved views can scope to specific Collections or span the whole Vault.

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
