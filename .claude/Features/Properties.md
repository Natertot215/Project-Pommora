### Properties

Pommora's property system. The same type catalog applies to Pages, Tasks, and Events. Page-property definitions live in one nexus-wide registry that Collections *assign*; Agenda keeps its own definitions on its config sidecars; values live on each member entity. The on-disk file is canonical; the SQLite index mirrors it for fast queries.

A **property** is a typed field defined once in the nexus-wide registry and populated on the members of every Collection that assigns it. The registry declares each property's type and per-type config; a Collection's assignment list names which registry properties its Pages validate and show; member entities store the values.

| Scope | Definitions |
|---|---|
| Nexus-wide registry | `.nexus/properties.json` → `propId → definition` |
| Page Collection | `<Collection>/_pagecollection.json` → `properties[]` (assigned registry ids) |
| Task | `<Tasks>/_taskconfig.json` → `property_definitions[]` (own defs — separate from the registry) |
| Event | `<Events>/_eventconfig.json` → `property_definitions[]` (own defs — separate from the registry) |

Page values live in `.md` frontmatter; Task and Event values live in a `properties` JSON object. Sets don't carry their own schema — they inherit the Collection's. A definition — options included — is one shared object everywhere it's assigned; genuinely divergent needs get a separate property, never per-Collection option forks.

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

- **`name`** — the user-facing display label, renameable freely. A rename is registry-only — member files are keyed by ID, so nothing cascades; every assigning Collection sees the new name.

Reserved property IDs (`_id`, `_title`, `_created_at`, `_modified_at`, `_status`, `_type`, `_tier1`, `_tier2`, `_tier3`) are blocked from user properties. The page `cover` is a root frontmatter field, not a property, and never appears in any properties UI.

#### II. On-Disk Value Shapes

A value is recovered from raw JSON by **shape**, in a fixed precedence — the declared type lives in the schema, and the on-disk value is type-erased. Status and Relation use a tagged object (`$status` / `$rel`) so an agent can identify the value type from any single file without the schema; Select stays a bare string and Multi-select a bare array because their shapes don't collide. **No value, no key:** setting a property to null — or to any empty value (an empty array or empty string) — clears its key from the member file; a member without a value never carries a null / `[]` / `''` placeholder. Checkbox false and number zero are real values and stay. (Tier keys are the exception — see the Contexts spec.)

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

Properties live with the content, never in the trailing inspector (which is reserved for the Claude chat → `Inspector.md`). Definitions live in the nexus-wide registry (`.nexus/properties.json`); a Collection's sidecar holds only its assignment list, and the read walk joins the two so every surface still receives a resolved schema. The **Properties pane** in the view-settings dropdown works per Collection — creating a property mints it into the registry (seeding per-type options) and assigns it here; renames, type changes, and option edits change the global definition for every assigner; removing a property unassigns it non-destructively. **Display formats aren't definition config**: the per-type look and date/time/number formats persist per-VIEW in the SavedView's `column_styles` (a deliberate divergence from Swift's def-level format keys — those ride through definitions as inert foreign keys, round-tripping unread). The first surface for *setting values* is the table's cells (the gesture matrix → `TableView.md`); the Page Property Panel is Pending.

### Architecture

#### II. Schema Mutations

| Mutation | Effect on existing values |
|---|---|
| Create a property | Mints a nexus-wide definition and assigns it to the creating Collection; appears empty on every member — no member writes until a value is set. |
| Assign a property | Adds this Collection's reference to an existing definition — idempotent, no name check. Values already sitting in members' frontmatter surface immediately. |
| Unassign a property | Drops this Collection's reference only. Values stay in frontmatter as foreign data — re-assigning restores them; the definition and other Collections are untouched. |
| Rename a property | Registry-only — members are keyed by ID; every assigner sees the new name. |
| Reorder properties | Per-Collection assignment order; sidecar-only. |
| Change a property's type | A global definition edit — a value whose shape no longer matches stops rendering but stays in frontmatter. |
| Delete a property (global) | A timestamped recovery snapshot of the definition and every value lands in `.trash`, then the value is stripped from every assigner's pages and assignment lists, and the definition leaves the registry. |
| Edit options | Global — adding, reordering, and relabeling are registry-only; deleting an option voids referencing values everywhere it's assigned. |

The global delete commits atomically across every affected file, rolling back the whole set on any write failure; registry mutations serialize through one write chain so overlapping edits never lose an update. Unassign is the daily path — the global delete is the rare destructive one.

#### II. Validation

At every write: a created property's `name` is non-empty and unique across the whole registry (case-insensitive), its `id` is unique and not a reserved one, and a Select / Multi-select / Status carries at least one option with unique option values. Assigning runs no name check — it's a reference to an existing definition, not a new one. `_status` on the Task and Event schemas is non-deletable. Each member value's shape must match its schema entry's type.

#### II. Index

The SQLite `property_definitions` table is a pure mirror of the nexus-wide registry — one row per definition, keyed by id alone, no owner columns; Agenda's own definitions stay out of it. Each member's values mirror into its entity row (a JSON column), keeping filter, sort, and group queries off the file read path. It's regeneratable — a schema-version bump drops and rebuilds it. Full data layer → `Architecture.md`.

### Pending

**Page Property Panel:** The surface for setting property values on a Page (and on a Task or Event) — a panel attached to the content. Values round-trip on disk and through the index, but there's no UI to view or edit them on an entity.

**Assignment Surface:** The UI for assigning an existing registry property to a Collection, plus the cross-assigner value strip a lossy type change should trigger. The data-layer ops exist; the pane currently creates-and-assigns only.

**Per-Type Value Editors:** The value-editing controls inside the schema and value surfaces — the Select / Status option editors, the date format pickers, and the relation pickers. The Properties pane manages properties but doesn't yet edit their per-type options.

**Display Formats:** Number formats, date and time formats, and the Status display variant. These ride through as preserved foreign keys until a UI reads them.
