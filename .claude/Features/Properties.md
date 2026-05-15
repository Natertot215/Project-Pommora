### Properties

Detailed specification for Pommora's property system. Referenced from `PommoraPRD.md`.

---

#### Model

- **Property values** live in YAML frontmatter on each Page, or under the `properties` key inside each Item's individual `.json` file — directly editable by any text editor, any tool, or Claude.
- **Property schemas** live inside each Collection's `_collection.json` sidecar (canonical, file-based — agent-readable without going through SQLite). SQLite mirrors the schema for fast queries; the JSON file is the source of truth.
- **Properties are scoped to a Collection** (a folder containing `_collection.json`). The `Tasks//` Collection has its own `priority` definition; the `Projects//` Collection has its own. Same property name in two Collections = two independent definitions.
- **The same property catalog works for both Collection kinds** — Pages collections and Items collections share the catalog. Within any one Collection, every member is the same kind (so the storage substrate is uniform): a Pages collection's members store values in YAML frontmatter, an Items collection's members store values in JSON.
- **Loose Pages and loose Items have no schema** (no `_collection.json` governs them). They hold only built-in fields — `id`, `icon`, `spaces` for both; `description` for Items — and any links / wikilinks they declare. Moving a loose entity into a matching-kind Collection folder makes it a member and the schema applies (empty values for new properties).

#### How Properties Are Created

Properties are created on-demand from the page's property panel — same flow as Notion. The user clicks **+ Add property**, names it, and picks a type. Each type loads its own configuration controls. Once added, the property is registered in the database's schema and becomes available on every page in that folder.

The flow:

1. **Add property** — from the property panel on any page in the database
2. **Name it** — `Status`, `Due`, `Tags`, etc.
3. **Pick a type** — opens type-specific config (options for select, format for date, scope for relation, etc.)
4. **Save** — schema entry written to the Collection's `_collection.json` (source of truth) and mirrored to SQLite for fast queries; property appears on every member of the Collection
5. **Set value** — written to the page's frontmatter

#### Property Type Catalog (v1)

Each type has a fixed config shape, stored as JSON inside the property's entry in the Collection's `_collection.json` `properties` array. The shape determines what the UI shows when the property is being edited and how the value is displayed. SQLite mirrors the schema for fast queries; the JSON file is the source of truth.

**The only pure text property is title** — and title is the Page's filename, not a frontmatter property. All other properties are typed: number, date, checkbox, select, multi-select, etc. Where a Notion-style "text" field would appear, Pommora uses **Select** or **Multi-select** with creatable options (Notion's select behavior — typing a new label creates a new option in the catalog).

| Type | Value shape (frontmatter) | Config shape (SQLite) | UI behavior |
|---|---|---|---|
| **Number** | `number` | `{ format: "plain" \| "decimal" \| "percent" \| "currency", currencySymbol?: "$", precision?: 2 }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `boolean` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{ includeTime: false, format: "MMM D, YYYY" }` | Date picker. |
| **Date & Time** | `"2026-06-15T14:30"` | `{ includeTime: true, format: "MMM D, YYYY h:mm A" }` | Date + time picker. |
| **Select** | `"Active"` | `{ options: [{ value: "Active", color: "blue" }, ...] }` | Dropdown with colored pills. New options created inline by typing — text label becomes a new option in the catalog. Option order is user-defined (drag in the option editor) and defines sort behavior — see "Property options and sort order" below. |
| **Multi-select** | `["planning", "frontend"]` | `{ options: [...] }` | Tag-style multi-pick; new options created inline by typing. Same option-order-defines-sort behavior as Select. |
| **Relation** | `"01HXYZ..."` or `["01H...", "01H..."]` (target IDs) | `{ scope?: "Projects//", multiple: true \| false }` | Picker scoped to the configured folder if `scope` is set, otherwise nexus-wide. **Stored as the target's ID** (rename-safe — survives renames of the target). **Displayed as the target's current title**, rendered as styled colored inline text (same look as wikilinks in body). The relation lookup resolves ID → current title at render time; rename a referenced Page and the relation's display updates automatically. |
| **URL** | `"https://..."` | `{}` | URL input; rendered as clickable link with favicon. |

**No separate `Status` type.** Status-like behavior is a Select property named "Status" with options like `Not started`, `In progress`, `Done`.

#### Property options and sort order

For Select and Multi-select properties, the **order of options in the schema defines sort behavior**. Options are an ordered list (drag-to-reorder in the property's option editor); ascending sort returns first-listed values first, descending returns last-listed values first.

Example: A `Status` Select with options `[Awaiting, Active, Done]` — sorting ascending puts `Awaiting` first; sorting descending puts `Done` first. To change sort priority, the user reorders the options themselves.

This replaces alphabetical sorting (which is wrong for things like statuses — "Awaiting" sorts before "Done" but you usually want them in workflow order) and is clearer than Notion's separate "manual sort" mode.

#### Column order in views vs property declaration order

Two different orderings, two different storage layers:

- **Column order in a Table or List view** is view-level config. Drag column headers in the view UI to rearrange; the order is stored in the view's spec inside `_collection.json`. **Visual only — no schema effect.** Different views on the same Collection can show columns in different orders.
- **Property declaration order in `_collection.json`** is schema-level — the order properties appear in the property panel for any member. No drag UI in v1; new properties are appended.
- **Option order inside a Select / Multi-select property** is schema-level — drives sort behavior as described above. Drag-to-reorder in the property's option editor.

#### Schema Mutations

What happens when a user changes a property's definition:

- **Adding a new property** — appears as empty on every member of the Collection; no file writes required until a value is set.
- **Renaming a property** — schema rename + a nexus-wide rewrite across the Collection's members (frontmatter for Pages, `properties` block for Items), using the same atomic-transaction pattern as wikilink renames.
- **Changing a property's type** — only allowed when the conversion is lossless (e.g., Date → Date & Time, or Select → Multi-select). Otherwise the user is prompted and must confirm; on confirm, conflicting values are dropped.
- **Deleting a property** — schema row removed; values removed from every member of the Collection. No backup or `_orphaned` quarantine — Notion-style: the property and its values are gone.

#### Moving Members Between Collections

Moving a Page from one Pages collection to another (or an Item from one Items collection to another) strips any properties not in the destination Collection's schema — same behavior as Notion. **A simple confirmation warning** lists the properties that will be stripped before the move proceeds; the user can cancel, add the property to the destination schema first, or accept the strip.

The same rule applies in both directions involving loose state:

- **Member → Loose** (moving a `.md` or `.json` out of a Collection folder into the nexus root / a cosmetic folder): all schema-conforming properties are stripped; the entity becomes loose with only built-in fields remaining.
- **Loose → Member** (moving into a matching-kind Collection folder): the destination Collection's schema applies; the new member starts with empty values for every property in the schema.

This keeps the model simple and matches user intuition from Notion — no quarantine, no orphan archives, no undo-the-strip-property semantics.

#### Auto-Managed Properties

These fields exist on every Page (in frontmatter) and every Item (in its JSON entry) automatically and aren't user-creatable:

- `id` — ULID assigned at file/entry creation, never changes
- `created_at`, `modified_at` — UNIX timestamps maintained by Pommora

These appear in the property panel at the bottom (collapsed by default).

Items also carry one additional built-in field that isn't a user-defined property but is part of the Item entity:

- `description` — short plain-text field for one-line context. Not Markdown, not editable as a property; rendered alongside the title in views.

(Filename plays the title role for both Pages and Items — no separate `name` field.)
