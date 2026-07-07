### Properties

Pommora's property system. The same type catalog applies to [[Studio/Pommora/II. Features/Pages|Pages]], Tasks, and Events. Page-property definitions live in one nexus-wide registry that [[Collections]] *assign*; Agenda keeps its own definitions on its config sidecars; values live on each member entity. The on-disk file is canonical; the SQLite index mirrors it for fast queries.

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
| **Status**            | `{"$status": "<value>"}`                                                | Tagged object; grouped by workflow phase.       |
| **URL**               | `"https://..."`                                                         | A string with a scheme.                         |
| **Context**           | `[{"$rel": "<id>"}, ...]`                                               | Tagged array; tier-only, not user-creatable.    |
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

A workflow property whose values sort into status **groups**. The group model is open — each group is a stable `id` with a user-editable label, a color, and its own options — seeded and shipped with three calendar-phase defaults:

| Group         | Default label | Default color |
| ------------- | ------------- | ------------- |
| `upcoming`    | Open          | grey          |
| `in_progress` | Active        | cobalt |
| `done`        | Done          | green         |

Group **ids** are the load-bearing keys: every value references its group by id, and all status logic (the checkbox cycle, the group glyph) keys off the id, never list position — order is display-only. The three shipped ids are stable, but the model isn't capped at three: more groups (Paused, Cancelled, or user-defined) drop into the open enum later with no data change, and a future EventKit bridge maps each group by a completion semantic (which groups count as done) rather than a fixed count. Group labels and the options within each group are user-editable. An option's `value` IS its label (value=title): renaming rewrites both and cascades the new value onto every assigning page's `$status`. Each option also carries an optional `color` and its `group_id`. Creating a Status property seeds one starter option per group. Sort is group position first, then option order within a group. Status is built-in and non-deletable on Tasks and Events; on a Collection it's opt-in.

The **Status editor** edits it in place: a group-labeled option list (double-click a heading to relabel its group), each option a pill chip in its group's colour, with a per-group `+` for an inline-named option, a hover palette to recolor, drag to reorder within or across groups, and a right-click **Rename · Remove · Clear** menu.

#### II. Links & URL

A URL property renders each value as a clickable link (opened through the sanctioned IPC). Its variables:

**Property-Specific** — set on the property, applied everywhere:

- **Display** — each link as its full URL, or its fetched page title.
- **Underline** — on or off.
- **Color** — the link colour (a palette key; Default = the app accent).

**View-Specific:** a prospect (see Pending) — a link's look is entirely property-level today; per-view link styling isn't built.

A per-value **alias** (right-click → Rename, stored markdown-native as `[alias](url)`) overrides the display for a single link. In the title look, the page `<title>` is fetched once per URL and cached in `.nexus/linkTitles.json` (device-local, regeneratable), falling back to the bare domain while loading or on failure. *(A separate palette icon beside the colour chip once offered a second recolor source — removed; clicking the chip is the one affordance.)*

#### II. Tier Relations

The three context-tier links (`tier1` / `tier2` / `tier3`) are the only relation-type connection. They store as **bare ULID arrays at the entity root**, not under `properties`, and the schema exposes them as three synthesized relation properties (`_tier1` / `_tier2` / `_tier3`) merged after the user-defined ones. Full cross-layer behavior → `Contexts.md`.

#### II. Auto-Managed Properties

Every Page, Task, and Event carries an `id` (a ULID, assigned at creation), `created_at`, and `modified_at` — maintained by Pommora, not user-creatable. `modified_at` resolves to the stored stamp, falling back to the file's mtime when absent, and surfaces as **Last Edited Time** for sortability. Tasks and Events also carry a plain-text `description` JSON field.

#### II. Where Properties Live

Definitions live in the nexus-wide registry (`.nexus/properties.json`) alongside a nexus-wide cosmetic display order; a Collection's sidecar holds only its assignment list, and the read walk joins the two so every surface still receives a resolved schema — the tree also carries the full ordered registry, so the pane lists everything live. The **Properties pane** in the view-settings dropdown is the full assign surface for a Collection: assigned properties on top (chevron → the per-property editor), an **All Properties** disclosure pinned to the pane's bottom that rises open to list every unassigned registry definition in the nexus order, each promotable via its `+` or by dragging into the assigned group at a slot. Dragging within a group reorders it (assigned = the Collection's order; All Properties = the nexus order); dragging an assigned row out Removes it. Creating (the header's top-right `+`) mints into the registry — appending to the nexus order, seeding per-type options — and assigns here; renames (the editor header, or a row's right-click → inline rename), type changes, and option edits change the global definition for every assigner. Remove strips-and-caches (see Schema Mutations); the global **Delete lives only inside a property's own editor pane**, behind its ⋮ menu and a native confirm. **Display formats aren't definition config**: the per-type look and date/time/number formats persist per-VIEW in the SavedView's `column_styles` (a deliberate divergence from Swift's def-level format keys — those ride through definitions as inert foreign keys, round-tripping unread). The first surface for *setting values* is the table's cells (the gesture matrix → `TableView.md`) — a **Date & Time** cell opens the **CalendarPicker**, the calendar-grid-plus-segmented-time value editor, its clock bound to a **nexus-wide time format** (`.nexus/settings.json` `time_format`, resolved onto the tree like the accent; default 12-hour AM/PM); the Page Property Panel is Pending.

### Architecture

#### II. Schema Mutations

| Mutation                   | Effect on existing values                                                                                                                                                                                                                                                                                                              |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Create a property          | Mints a nexus-wide definition (appending its id to the nexus order) and assigns it to the creating Collection; appears empty on every member — no member writes until a value is set.                                                                                                                                                  |
| Assign a property          | Adds this Collection's reference to an existing definition — idempotent, no name check — then restores any Remove-cache: each cached value that still conforms to the definition's current type and options writes back to the page that held it; non-conforming values drop per-value, and the cache block clears either way.         |
| Remove a property          | Strips the value from every member page and caches it (with which pages held it) on the Collection's own sidecar, then unassigns — one atomic transaction, no dormant foreign values left on pages. Re-assigning restores it; the definition and other Collections are untouched.                                                      |
| Rename a property          | Registry-only — members are keyed by ID; every assigner sees the new name.                                                                                                                                                                                                                                                             |
| Reorder properties         | Per-Collection assignment order (sidecar-only); the All Properties group reorders the nexus-wide display order instead (registry-file-only).                                                                                                                                                                                           |
| Change a property's type   | A global definition edit — a value whose shape no longer matches stops rendering but stays in frontmatter.                                                                                                                                                                                                                             |
| Delete a property (global) | A timestamped recovery snapshot of the definition and every value lands in `.trash`, then the value is stripped across every collection's pages and assignment lists, every Remove-cache block for it is purged (a cache without its definition is corrupt state), and the definition leaves the registry — nothing restorable in-app. |
| Edit options               | Global — adding, reordering, and recoloring are registry-only; renaming an option cascades its new value onto every assigning page's `$status` (value=title), and removing or clearing one strips that value from those pages.                                                                                                                                                                                                   |

Remove and its restore each commit atomically across every affected file (the global delete's transaction machinery), rolling back the whole set on any write failure; registry mutations serialize through one write chain so overlapping edits never lose an update. Remove is the daily path — the global delete is the rare destructive one, reachable only inside the property's own editor pane behind a native confirm.

#### II. Validation

At every write: a created property's `name` is non-empty, its `id` is unique and not a reserved one, and a Select / Multi-select / Status carries at least one option with unique option values. **Names need not be unique** — definitions are ID-keyed, so twin names are mechanically safe on both create and rename (a deliberate quirk; the visible All Properties list makes accidental twins unlikely). Agenda's own definitions keep the unique-name rule. Assigning runs no name check — it's a reference to an existing definition, not a new one. `_status` on the Task and Event schemas is non-deletable. Each member value's shape must match its schema entry's type.

#### II. Index

The SQLite `property_definitions` table is a pure mirror of the nexus-wide registry — one row per definition, keyed by id alone, no owner columns; Agenda's own definitions stay out of it. Each member's values mirror into its entity row (a JSON column), keeping filter, sort, and group queries off the file read path. It's regeneratable — a schema-version bump drops and rebuilds it. Full data layer → `Architecture.md`.

### Pending

**Page Property Panel:** The surface for setting property values on a Page (and on a Task or Event) — a panel attached to the content. Values round-trip on disk and through the index, but there's no UI to view or edit them on an entity.

**Lossy Change-Type Strip:** The cross-assigner value strip a lossy type change should trigger (the assign surface itself shipped with the 7-2 pane; `changeType` still accepts-and-ignores the drop flag).

**Per-Type Editor Panes:** The remaining per-type property editors not yet built — the Number value-type pane, its number-format picker, and the relation (context) pickers. The Select, Multi-Select, Status (grouped / flat option lists, add · recolor · reorder · drag, right-click Rename · Remove · Clear), URL, and Date & Time editors have shipped; the rest follow on their patterns.

**Display Formats:** The per-view look + date/time/number formats are read by the renderers and set per-view through the column-header Style menu; the datetime property also gets a discoverable Format editor (Date · a conditional weekday Day · Time), a second surface writing the same `column_styles`. A property-editor Format surface for Number is the remaining gap. Swift's def-level format keys stay inert foreign keys (per "Where Properties Live").

**Larger Color Picker:** option colors store an open solid-palette key (all ten `colors.css` solids, resolved through `chipColorFor` with a legacy read-map for old Notion values), so the ColorPicker's 2×5 grid can grow into a much larger selector (~9×12) over the shared color tokens — reusable across every color-token consumer — with no schema churn. A future enhancement, not a limitation.

**Calendar Picker refinements:** the Date & Time value editor is live in table cells but pending — range values (the picker's range mode is demo-only; a datetime value is a single ISO on disk), keyboard stepping on the time segments, an in-app control for the `time_format` setting, and its own test coverage.

**Per-View Link Styling:** a URL property's look — display (full-URL ⇄ title), underline, colour — is entirely property-level today; a URL column has no per-view style. Letting a view override it (one view titles, another raw URLs, of the same property) is a prospect, not a limitation — the `column_styles` seam already carries per-view looks for the other types.

### Known Issues

**A stray bare-string Multi-Select value reads as Select:** the read-side coercion that overrides a shape-vs-column type mismatch — a value's on-disk shape corrected to what its column actually declares — covers only the single-string kinds (URL / Select / Date). A Multi-Select value stored as a lone string rather than an array therefore stays classified as Select and drops out of grouping and filtering. Unreachable today (nothing writes that shape), but it goes live the moment the **Lossy Change-Type Strip** performs a Select→Multi-Select change; fix it there as a value migration (bare string → single-element array), not a coercion special-case.
