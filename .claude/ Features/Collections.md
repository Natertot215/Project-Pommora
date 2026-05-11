### Collections

A Collection is a **folder + a schema sidecar + an items sidecar**. Conceptually equivalent to a Notion database — it has properties, saved views, and two kinds of members: **Pages** (entries that warrant Markdown prose) and **Items** (lightweight row-shaped entries with properties + a short description, no body). Physically realized as a folder in the vault (which holds the member `.md` files) plus a `_collection.json` file (schema + view configurations) and a `_items.json` file (row-shaped Item entries) inside that folder. Similar in spirit to Make.md's folder-notes pattern, where a folder gains first-class identity through associated metadata files.

Collections have **no text-editor surface** — opening a Collection in the app shows its database UI (one of the saved views), nothing else. Pages and Items appear in the same view; clicking a Page opens the prose editor, clicking an Item opens its property panel.

---

#### On disk

- A folder in the vault (e.g. `~// PommoraVault// Tasks//`)
- Inside the folder: a `_collection.json` file holding the schema and views (underscore-prefix keeps it visually grouped to the top of the folder)
- Inside the folder: `_items.json` holding the Collection's Item entries (optional file — absent if the Collection has no Items yet)
- Inside the folder: the member Pages as `.md` files
- Each Collection has its own ID (ULID), stored in `_collection.json`. Each Item entry has its own ID (ULID), stored as `id` in its JSON entry.

---

#### `_collection.json` schema

```json
{
  "id": "01HXXXXX...",
  "icon": "checkbox",
  "properties": [ /* property schema entries — shared by Pages and Items */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Collection's title comes from the **folder name** (no `title` field in the JSON). Renaming a Collection in the UI renames the folder on disk.

---

#### `_items.json` schema

```json
{
  "items": [
    {
      "id": "01HYYYY...",
      "name": "Steam Deck OLED",
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
  ]
}
```

Each Item carries:

- `id` — ULID, never changes (used by relations targeting this Item)
- `name` — the Item's title equivalent (Items have no filename; `name` plays the title role)
- `description` — short plain-text field for one-line context. Not Markdown, not a body. Items have no prose body.
- `icon` — optional, same icon catalog as Pages and Collections
- `properties` — values conforming to the Collection's schema. Same catalog as Page frontmatter.
- `spaces` — Space ID multi-relation (Items can appear on Space homepages like Pages can)
- `created_at` / `modified_at` — UNIX timestamps, auto-managed

Items are JSON-canonical (the JSON file is the source of truth, SQLite indexes from it). External agents read Items by parsing `_items.json` directly.

---

#### Capabilities

- Property schema (shared across all member Pages and Items)
- Multiple saved views (table / board / list / cards / gallery) — each view shows Pages, Items, or both (configurable per view via a `members: "pages" | "items" | "both"` field; default `"both"`)
- Per-view filter, sort, group, and shown-properties configuration
- Adding a **Page** to a Collection = creating or moving the `.md` file into the Collection's folder. The Page inherits the Collection's schema automatically.
- Adding an **Item** to a Collection = appending a new entry to the Collection's `_items.json` (creating the file if it doesn't exist).
- **Pages vs. Items — choosing:** if the entry needs a Markdown body you'll write or read, make it a Page. If it's a row-shaped entry with properties and maybe a short description (no body), make it an Item. The decision is content-shape, not data-shape — both can hold the same properties and relations.
- A Page belongs to **exactly one Collection or none** (loose). An Item belongs to **exactly one Collection** — Items have no loose form (they only exist inside `_items.json` of some Collection). Multi-Collection membership is not supported.
- Collections are linkable from anywhere: relation properties on Pages, Items, or Spaces outside the Collection's folder can target the Collection itself (behaves as a query) or specific member Pages / Items by ID.

---

#### View types in v1

Five view types ship in v1:

- **Table** — sortable columns, inline edit
- **Board** — drag-and-drop kanban; drag cards between columns updates source Page's frontmatter
- **List** — plain list with title plus selected inline properties
- **Gallery** — grid layout with cards using a cover image
- **Cards** — grid layout without cover-first emphasis

Each view spec carries: source Collection (implicit from the sidecar's location), view type, filter expression, sort, group-by property, properties to display, and (for gallery) cover image property. Filter expressions parse to a small DSL and translate to parameterized `json_extract` SQL queries.

**Filters and sorts on a view never modify the source Collection** — they are purely view-local.

---

#### Two contexts where views appear

1. **Inside a Collection** — saved views configured per-Collection, stored in the Collection's `_collection.json`. Switch between them via tabs above the view area.

2. **Embedded as a Space widget** — the "Embedded Collection View" widget renders any saved Collection view inside a Space. References a Collection by ID and overrides filter / sort / group / shown-properties locally without modifying the Collection's saved views.

**For React**

A single shared `<CollectionViewRenderer>` component dispatches by view type and is reused in both contexts (standalone Collection page and embedded Space widget). Mirrors Notion's `child_database` block pattern.

---

#### Loose Pages (no Collection)

Pages that live anywhere in the vault outside a Collection folder — i.e., outside any folder containing a `_collection.json` — are loose Pages. The sidebar surfaces them in a separate "Loose Pages" group. Loose Pages don't conform to any Collection schema; they hold only the properties their own frontmatter declares (typically just `id`, `icon`, `spaces`, and link properties).

**Items have no loose form** — they exist only inside a Collection's `_items.json`. If you want a row-shaped entry without a Collection, that's a signal it should be a Page (which can be loose).

---

#### Properties

Property values live in Page frontmatter (for Pages) or inside the Item's JSON entry under `properties` (for Items). Property *schemas* live inside each Collection's `_collection.json` and apply to both Pages and Items in that Collection. Adding a property to a Collection updates the schema and propagates to all members.

**v1 types:** number, checkbox, date, datetime, select, status, multi-select, relation, URL. **No free-form text type** — title is the filename (Pages) or the `name` field (Items), and "text-shaped" property values use Select / Multi-select with creatable options (Notion behavior).

Full property type catalog and config shapes → `Properties.md`.
