### Collections

A Collection is a **folder + a `_collection.json` schema sidecar**, equivalent to a Notion database. It holds properties, saved views, and members of a single kind. A Collection is **typed at creation** — either a **Pages collection** (members are `.md` files, prose-bearing) or an **Items collection** (members are `.json` files, row-shaped, no body). The kind is persistent — a Collection is never both kinds. Similar in spirit to Make.md's folder-notes pattern.

Collections have **no text-editor surface** — opening one shows its database UI (one of the saved views). Clicking a Page member opens the prose editor; clicking an Item member opens its property panel.

---

#### On disk

- A folder in the vault (e.g. `~// PommoraVault// Tasks//`)
- Inside the folder: a `_collection.json` file holding the schema, views, **and the Collection's `kind`** (underscore-prefix keeps the schema sidecar visually grouped to the top of the folder)
- Inside the folder: the member files — all `.md` (Pages collection) **or** all `.json` (Items collection). Mixed contents are a vault-integrity warning, not a normal state.
- Each Collection has its own ID (ULID), stored in `_collection.json`. Each Item has its own ID (ULID), stored as `id` inside its own `.json` file. Each Page has its own ID in frontmatter.

```
Tasks//                     ← Items collection
  _collection.json          ← "kind": "items"
  Buy groceries.json
  Fix sink.json
  Steam Deck OLED.json

Papers//                    ← Pages collection
  _collection.json          ← "kind": "pages"
  Attention is all you need.md
  Compiler Construction.md
```

---

#### `_collection.json` schema

```json
{
  "id": "01HXXXXX...",
  "kind": "pages",                /* or "items" — set at creation, persistent */
  "icon": "checkbox",
  "properties": [ /* property schema entries */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Collection's title comes from the **folder name** (no `title` field in the JSON). Renaming a Collection in the UI renames the folder on disk. Changing `kind` after creation is not supported in v1 (the migration is destructive — every member file would need a format conversion).

---

#### Item file shape

Inside an **Items collection**, each member is its own `.json` file. The filename is the title (same rule as Pages). Example: `Steam Deck OLED.json`:

```json
{
  "id": "01HYYYY...",
  "description": "Look for sales — annoying that they don't go on sale often.",
  "icon": "controller",
  "properties": {
    "status": "Watching",
    "price_ceiling": 549,
    "tags": ["gaming", "hardware"],
    "related_project": "01H...projectid"
  },
  "spaces": ["01H...spaceid"],
  "created_at": 1716480000,
  "modified_at": 1716480000
}
```

Each Item file carries:

- `id` — ULID, never changes (used by relations targeting this Item)
- `description` — plain-text field shown in the Item window, **hard cap 250 characters** (sized to fit the window without scrolling). Not Markdown, not a body. Items have no prose body.
- `icon` — optional, same icon catalog as Pages and Collections
- `properties` — values conforming to the Collection's schema. Same catalog as Page frontmatter.
- `spaces` — Space ID multi-relation (Items can appear on Space homepages like Pages can)
- `created_at` / `modified_at` — UNIX timestamps, auto-managed

No `name` field — the filename IS the name (consistent with Pages). Items are JSON-canonical (each file is the source of truth, SQLite indexes from them). External agents read Items by walking the Collection's folder and parsing each `.json` directly.

---

#### Capabilities

- Property schema (applies to every member of the Collection's kind)
- Multiple saved views (table / board / list / cards / gallery) — each view shows members of the Collection's kind. No per-view member-kind filter is needed; the Collection's kind determines what views render.
- Per-view filter, sort, group, and shown-properties configuration
- Creating a new member in a Pages collection produces a `.md` file; creating one in an Items collection produces a `.json` file. The `+ New` action is unambiguous because the Collection is typed.
- **Pages vs. Items — choosing happens at Collection creation, not per-entry.** Decide what the Collection is "for": prose-bearing entries → Pages collection (journals, papers, projects-with-notes); row-shaped entries → Items collection (tasks, contacts, wishlist, events, references). Both kinds use the same property catalog and relation semantics.
- A Page belongs to **exactly one Pages collection or none** (loose). An Item belongs to **exactly one Items collection or none** (loose). Multi-Collection membership is not supported. Loose entities carry built-in fields but no schema-conforming properties (see "Loose Pages and loose Items" below). No promotion of an Item to a Page in v1 (see `Prospects.md`).
- Collections are linkable from anywhere: relation properties on Pages, Items, or Spaces outside the Collection's folder can target the Collection itself (behaves as a query) or specific members by ID.

---

#### View types in v1

Five view types ship in v1:

- **Table** — sortable columns, inline edit
- **Board** — kanban layout grouped by a property's options. v0.9 ships the visual layout (editing a card via the card UI moves it between columns). Drag-to-rewrite-frontmatter (dragging a card across columns to mutate the source's property directly) is a planned follow-up after v1.0 foundations stabilize.
- **List** — plain list with title plus selected inline properties
- **Gallery** — grid layout with cards using a cover image
- **Cards** — grid layout without cover-first emphasis

Each view spec carries: source Collection (implicit from the sidecar's location), view type, filter expression, sort, group-by property, properties to display, and (for gallery) cover image property. Filter expressions parse to a small DSL and translate to parameterized `json_extract` SQL queries.

**Filters and sorts on a view never modify the source Collection** — they are purely view-local.

---

#### Two contexts where views appear

1. **Inside a Collection** — saved views configured per-Collection, stored in the Collection's `_collection.json`. Switch between them via tabs above the view area.

2. **Embedded as a Space widget** — the "Embedded Collection View" widget renders any saved Collection view inside a Space. References a Collection by ID and overrides filter / sort / group / shown-properties locally without modifying the Collection's saved views. The widget shows whatever the source Collection's kind holds (a Pages collection renders Page rows; an Items collection renders Item rows).

**For React**

A single shared `<CollectionViewRenderer>` component dispatches by view type and is reused in both contexts (standalone Collection page and embedded Space widget). Mirrors Notion's `child_database` block pattern.

---

#### Loose Pages and loose Items (no Collection)

Files outside any Collection folder — i.e., outside any folder containing a `_collection.json` — are loose. Both kinds can be loose:

- **Loose Pages** — `.md` files in the vault root or in cosmetic folders (any folder without `_collection.json`). Frontmatter holds only built-in fields (`id`, `icon`, `spaces`) plus whatever the user manually writes. No schema enforcement.
- **Loose Items** — `.json` files in the vault root or cosmetic folders. Carry `id`, `icon`, `description`, `spaces`, timestamps — but no `properties` (no schema to conform to).

Loose entities don't appear as their own sidebar group; reach them via global search or wikilinks. Cosmetic folders carry no semantic meaning to Pommora — they're purely user-driven filesystem organization. Moving a loose entity into a matching-kind Collection folder makes it a member and applies the schema (empty values for new properties); moving a member out drops it back to loose state.

---

#### Properties

Property schemas live inside each Collection's `_collection.json` and apply to every member. Pages members store values in YAML frontmatter; Items members store values inside the `.json` file under `properties`. Same catalog, two storage substrates. Full type catalog → `Properties.md`.
