### Properties

Pommora's property system. The same type catalog applies to Pages, Tasks, and Events. Schemas live on each Type's sidecar; values live on each member entity. The on-disk file is canonical; the SQLite index mirrors it for fast queries.

A **property** is a typed field declared on a Type's schema and populated on individual entities of that Type. Schemas declare which properties exist, each property's type, and any per-type config; member entities store the values.

| Type | Schema sidecar |
|---|---|
| Page Collection | `<Collection>/_pagecollection.json` → `properties[]` |
| Task | `<Tasks>/_taskconfig.json` → `property_definitions[]` |
| Event | `<Events>/_eventconfig.json` → `property_definitions[]` |

Page values live in `.md` frontmatter; Task and Event values live in a `properties` JSON object. Sets don't carry their own schema — they inherit the Collection's.

### Features

#### II. Type Catalog

| Type                  | On-disk value                                                           | Notes                                           |
| --------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| **Number**            | `42` or `3.14`                                                          | Bare number.                                    |
| **Checkbox**          | `true` / `false`                                                        | Bare boolean.                                   |
| **Date**              | `"2026-06-15"` (date-only, UTC) or `"2026-06-15T14:30:00Z"` (with time) | A bare date-only value folds into Date on read. |
| **Select**            | `"<value>"`                                                             | Bare string; single colored pill.               |
| **Multi-select**      | `["<value>", ...]`                                                      | Bare array; tag-style multi-pick.               |
| **Status**            | `{"$status": "<value>"}`                                                | Tagged object; three fixed groups.              |
| **URL**               | `"https://..."`                                                         | A string with a scheme.                         |
| **Context** | `[{"$rel": "<id>"}, ...]`                                               | Tagged array; tier-only, not user-creatable.    |
| **Last Edited Time**  | *(derived from `modified_at`)*                                          | Virtual — never persisted.                      |
| **File / Attachment** | `[{ "path", "original_name", "added_at", "mime_type" }, ...]`           | Array; files copy into the Nexus.               |

There's no free-form text type — the filename is the title, and text-shaped values use creatable Select options. **Relation** is reserved for the three context-tier links and isn't offered in the type picker; any user-relation definition is dropped on read.

#### II. Identity vs Name

Every property carries two independent identifiers:

- **`id`** — a stable identity, never changing. User properties mint a `prop_<ulid>`; built-ins use a reserved `_`-prefixed id. This is the key used in member-file values, in cross-property references, and in the index.

- **`name`** — the user-facing display label, renameable freely. A rename is schema-only — member files are keyed by ID, so nothing cascades.

Reserved property IDs (`_id`, `_title`, `_created_at`, `_modified_at`, `_status`, `_type`, `_tier1`, `_tier2`, `_tier3`) are blocked from user properties. The page `cover` is a root frontmatter field, not a property, and never appears in any properties UI.

#### II. On-Disk Value Shapes

A value is recovered from raw JSON by **shape**, in a fixed precedence — the declared type lives in the schema, and the on-disk value is type-erased. Status and Relation use a tagged object (`$status` / `$rel`) so an agent can identify the value type from any single file without the schema; Select stays a bare string and Multi-select a bare array because their shapes don't collide. Setting a property to null clears its key from the member file.

#### II. Status

A workflow property with three fixed, EventKit-aligned groups, each holding user-editable options:

| Group         | Default label | Default color |
| ------------- | ------------- | ------------- |
| `upcoming`    | Upcoming      | gray          |
| `in_progress` | In Progress   | blue          |
| `done`        | Done          | green         |

Group IDs are load-bearing and the three slots are fixed — a fourth would break calendar-sync mapping — while group labels and the options inside each group are user-editable. Each option carries a canonical `value` (immutable), a renameable `label`, an optional `color`, and its `group_id`. Creating a Status property seeds one starter option per group. Sort is group position first, then option order within a group. Status is built-in and non-deletable on Tasks and Events; on a Collection it's opt-in.

#### II. Tier Relations

The three context-tier links (`tier1` / `tier2` / `tier3`) are the only relation-type connection. They store as **bare ULID arrays at the entity root**, not under `properties`, and the schema exposes them as three synthesized relation properties (`_tier1` / `_tier2` / `_tier3`) merged after the user-defined ones. Full cross-layer behavior → `Contexts.md`.

#### II. Auto-Managed Properties

Every Page, Task, and Event carries an `id` (a ULID, assigned at creation), `created_at`, and `modified_at` — maintained by Pommora, not user-creatable. `modified_at` resolves to the stored stamp, falling back to the file's mtime when absent, and surfaces as **Last Edited Time** for sortability. Tasks and Events also carry a plain-text `description` JSON field.

#### II. Where Properties Live

Properties live with the content, never in the trailing inspector (which is reserved for the Claude chat → `Inspector.md`). The schema is edited from the **Properties pane** in the view-settings dropdown — add, rename, change type, and delete properties, seeding per-type options on create. The surface for *setting values* on an entity is the Page Property Panel, which is Pending.

### Architecture

#### II. Schema Mutations

| Mutation | Effect on existing values |
|---|---|
| Add a property | Appears empty on every member; no member writes until a value is set. |
| Rename a property | Schema-only — members are keyed by ID. |
| Reorder properties | Schema-only. |
| Change a property's type | Lossless conversions apply directly; a lossy change drops conflicting values on confirmation. |
| Delete a property | The schema row is removed and the value is stripped from every member. |
| Edit options | Adding, reordering, and relabeling are schema-only; deleting an option voids referencing values. |

Mutations that touch multiple files (a type-change with value-drop, a delete-with-value-clear) commit atomically across every affected file, rolling back the whole set on any write failure. A rename is single-file and needs no cross-file transaction.

#### II. Validation

At every write: a property's `name` is non-empty and unique within the Type (case-insensitive), its `id` is unique and not a reserved one, and a Select / Multi-select / Status carries at least one option with unique option values. `_status` on the Task and Event schemas is non-deletable. Each member value's shape must match its schema entry's type.

#### II. Index

The SQLite index holds a `property_definitions` row per schema entry and mirrors each member's values into its entity row (a JSON column), keeping filter, sort, and group queries off the file read path. It's regeneratable — a schema-version bump drops and rebuilds it. Full data layer → `Architecture.md`.

### Pending

**Page Property Panel:** The surface for setting property values on a Page (and on a Task or Event) — a panel attached to the content. Values round-trip on disk and through the index, but there's no UI to view or edit them on an entity.

**Per-Type Value Editors:** The value-editing controls inside the schema and value surfaces — the Select / Status option editors, the date format pickers, and the relation pickers. The Properties pane manages properties but doesn't yet edit their per-type options.

**Display Formats:** Number formats, date and time formats, and the Status display variant. These ride through as preserved foreign keys until a UI reads them.
