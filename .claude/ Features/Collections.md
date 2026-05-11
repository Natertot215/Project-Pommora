### Collections

A Collection is a **folder + a schema sidecar file**. Conceptually equivalent to a Notion database — it has properties, saved views, and contains member Pages. Physically realized as a folder in the vault (which holds the member `.md` files) plus a `_collection.json` file inside that folder (which holds the schema and view configurations). Similar in spirit to Make.md's folder-notes pattern, where a folder gains first-class identity through an associated metadata file.

Collections have **no text-editor surface** — opening a Collection in the app shows its database UI (one of the saved views), nothing else. The user clicks a member Page to enter the prose editor.

---

#### On disk

- A folder in the vault (e.g. `~// PommoraVault// Tasks//`)
- Inside the folder: a `_collection.json` file holding the schema and views (underscore-prefix keeps it visually grouped to the top of the folder)
- Inside the folder: the member Pages as `.md` files
- Each Collection has its own ID (ULID), stored in `_collection.json`

---

#### `_collection.json` schema

```json
{
  "id": "01HXXXXX...",
  "icon": "checkbox",
  "properties": [ /* property schema entries */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Collection's title comes from the **folder name** (no `title` field in the JSON). Renaming a Collection in the UI renames the folder on disk.

---

#### Capabilities

- Property schema (shared across all member Pages)
- Multiple saved views (table / board / list / cards / gallery)
- Per-view filter, sort, group, and shown-properties configuration
- Adding a Page to a Collection = creating or moving the `.md` file into the Collection's folder. The Page inherits the Collection's schema automatically.
- A Page belongs to **exactly one Collection or none** (loose). Multi-Collection membership is not supported.
- Collections are linkable from anywhere: relation properties on Pages or Spaces outside the Collection's folder can target the Collection itself (behaves as a query) or specific member Pages.

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

---

#### Properties

Property values live in Page frontmatter. Property *schemas* live inside each Collection's `_collection.json`. Adding a property to a Collection updates the schema and propagates to all member Pages.

**v1 types:** number, checkbox, date, datetime, select, status, multi-select, relation, URL. **No free-form text type** — title is the filename, and "text-shaped" property values use Select / Multi-select with creatable options (Notion behavior).

Full property type catalog and config shapes → `Properties.md`.
