### Properties

Detailed specification for Pommora's property system. Referenced from `PommoraPRD.md`.

---

#### Model

- **Property values** live in YAML frontmatter on each Page, or under the `properties` key inside each Item's JSON entry in `_items.json` — directly editable by any text editor, any tool, or Claude.
- **Property schemas** live inside each Collection's `_collection.json` sidecar (canonical, file-based — agent-readable without going through SQLite). SQLite mirrors the schema for fast queries; the JSON file is the source of truth.
- **Properties are scoped to a Collection** (a folder containing `_collection.json`). The `Tasks//` Collection has its own `status` definition; the `Projects//` Collection has its own. Same property name in two Collections = two independent definitions.
- **The same property catalog applies to Pages and Items** — both kinds of Collection members conform to the same schema. The only difference is storage substrate: Pages store values in YAML frontmatter, Items store values in JSON.

#### How Properties Are Created

Properties are created on-demand from the page's property panel — same flow as Notion. The user clicks **+ Add property**, names it, and picks a type. Each type loads its own configuration controls. Once added, the property is registered in the database's schema and becomes available on every page in that folder.

The flow:

1. **Add property** — from the property panel on any page in the database
2. **Name it** — `Status`, `Due`, `Tags`, etc.
3. **Pick a type** — opens type-specific config (options for select, format for date, scope for relation, etc.)
4. **Save** — schema entry written to SQLite; property appears on every page in that folder
5. **Set value** — written to the page's frontmatter

#### Property Type Catalog (v1)

Each type has a fixed config shape stored as JSON in the `schemas.config` column. The shape determines what the UI shows when the property is being edited and how the value is displayed.

**The only pure text property is title** — and title is the Page's filename, not a frontmatter property. All other properties are typed: number, date, checkbox, select, multi-select, etc. Where a Notion-style "text" field would appear, Pommora uses **Select** or **Multi-select** with creatable options (Notion's select behavior — typing a new label creates a new option in the catalog).

| Type | Value shape (frontmatter) | Config shape (SQLite) | UI behavior |
|---|---|---|---|
| **Number** | `number` | `{ format: "plain" \| "decimal" \| "percent" \| "currency", currencySymbol?: "$", precision?: 2 }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `boolean` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{ includeTime: false, format: "MMM D, YYYY" }` | Date picker. |
| **Date & Time** | `"2026-06-15T14:30"` | `{ includeTime: true, format: "MMM D, YYYY h:mm A" }` | Date + time picker. |
| **Select** | `"Active"` | `{ options: [{ value: "Active", color: "blue" }, ...] }` | Dropdown with colored pills. New options created inline by typing — text label becomes a new option in the catalog. |
| **Status** | `"In progress"` | Same as Select; pre-seeded with `Not started` (gray), `In progress` (blue), `Done` (green) on creation | Same dropdown; convenience preset over Select. |
| **Multi-select** | `["planning", "frontend"]` | `{ options: [...] }` | Tag-style multi-pick; new options created inline by typing — text labels become new options in the catalog. |
| **Relation** | `"[[Page Name]]"` or `["[[A]]", "[[B]]"]` | `{ scope: "Projects//", multiple: true \| false }` | Page picker scoped to the configured folder. Renders as clickable pill(s). |
| **URL** | `"https://..."` | `{}` | URL input; rendered as clickable link with favicon. |

#### Schema Mutations

What happens when a user changes a property's definition:

- **Adding a new property** — appears as empty on every page in the database; no file writes required until a value is set.
- **Renaming a property** — schema rename + a vault-wide frontmatter rewrite using the same atomic-transaction pattern as wikilink renames.
- **Changing a property's type** — only allowed when the conversion is lossless (e.g., Date → Date & Time, or Select → Multi-select). Otherwise the user is prompted and must confirm; conflicting values are preserved under a `_orphaned` key in frontmatter for safety.
- **Deleting a property** — schema row removed; values removed from all frontmatter; backed up to `_pommora//deleted-properties.log` for one-undo recovery.

#### Auto-Managed Properties

These fields exist on every Page (in frontmatter) and every Item (in its JSON entry) automatically and aren't user-creatable:

- `id` — ULID assigned at file/entry creation, never changes
- `created_at`, `modified_at` — UNIX timestamps maintained by Pommora

These appear in the property panel at the bottom (collapsed by default).

Items also carry two additional built-in fields that aren't user-defined properties but are part of the Item entity itself:

- `name` — the Item's title equivalent (plays the title role since Items have no filename)
- `description` — short plain-text field for one-line context. Not Markdown, not editable as a property; rendered alongside the name in views.

#### Open Questions

- **Color palette** — fixed palette (Notion-style: gray, brown, orange, yellow, green, blue, purple, pink, red) or custom hex picker? Recommend fixed palette for v1; defer custom colors to design system.
- **Per-page property visibility** — does a page's property panel show every property in the database, or only the ones with values? Notion shows all; recommend matching.
- **Property reordering** — drag handles in property panel; order persisted in schema.
