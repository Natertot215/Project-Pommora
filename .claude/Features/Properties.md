### Properties

Pommora's property system. The same property type catalog applies to Pages, Tasks, and Events. Schemas live on each Type's per-kind sidecar; values live on each member entity. The on-disk file is canonical; SQLite mirrors it for fast queries.

This document is the source of truth for **what** Properties are and **how they behave**. Implementation strategy + phasing live in a separate plan document.

---

#### Overview

A **property** is a typed field defined on a Type's schema and populated on individual entities of that Type. Properties live on:

- **Pages** (`.md` files) — frontmatter
- **Tasks** (`.task.json` files) — `properties` JSON object
- **Events** (`.event.json` files) — `properties` JSON object

Each entity belongs to one Type. Every Type carries a schema in its per-kind sidecar:

| Type | Schema sidecar |
|---|---|
| Page Type | `<Type>/_pagetype.json` |
| Task (singleton) | `<Tasks>/_taskconfig.json` |
| Event (singleton) | `<Events>/_eventconfig.json` |

Schemas declare which properties exist on the Type, what type each property is, and any per-type config (option lists, relation targets, etc.). Member entities store property VALUES conforming to that schema.

Page Collections do not carry their own property schemas — they inherit from their parent Type. Their sidecar (`_pagecollection.json`) carries id, parent-Type linkage, an optional `icon` (mirrored into SQLite for the context picker), and per-view config (`views[]`).

---

#### Property type catalog

The type picker offers the user-creatable property types below. Two types exist but are excluded from the picker: **Relation** (tier-only, not user-creatable) and **Last Edited Time** (auto-managed, derived). A legacy date-only type folds into the unified **Date** type on read.

| Type | Value shape (keyed by property ID) | Config | UI behavior |
|---|---|---|---|
| **Number** | `42` or `3.14` | `{ "number_format": "integer" \| "decimal" \| "percent" \| "currency" }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `true` / `false` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` (date-only) or `"2026-06-15T14:30:00Z"` (with time) | `{ "date_format": …, "time_format": … }` | Native compact date/time picker; date-only vs with-time chosen by the **Display Time** setting. UTC-anchored on disk. |
| **Select** | `"<option value>"` | `{ "select_options": [{ "value", "label", "color" }, ...] }` | Single-pick colored pill. Option `value` immutable post-create; `label` renameable. Option order defines sort. Options are NOT created by typing into the value picker. |
| **Multi-select** | `["<value>", ...]` | `{ "select_options": [...] }` (same shape as Select) | Tag-style multi-pick. Each chip in its option's color. Option order defines sort. Options NOT created by typing. |
| **Status** | `{"$status": "<option value>"}` (tagged object) | `{ "status_groups": [{ "id", "label", "color", "options" }, ...] }` (3 fixed groups: `upcoming` / `in_progress` / `done`) | Grouped picker popover, 3 sections, single-pick. Pill color resolves option override > group default. Group labels renameable; 3 group slots fixed. Sort = group position first, then option order. Options NOT created by typing. Stored as tagged object (mirrors `$rel` pattern) so external agents can identify status values from any file without consulting the schema; bare-string would shape-collide with Select. |
| **URL** | `"https://..."` | `{}` | URL input; clickable link with favicon. |
| **Relation** | `[{"$rel": "01HXYZ..."}, ...]` (always an array; a single value is a 1-element array) | `{ "relation_target": { "kind": "context_tier", "tier": N } }` | Tier-only; not user-creatable. The only relation properties are the three built-in tier properties (`_tier1` / `_tier2` / `_tier3`), each targeting a `context_tier`. Stored as tagged JSON objects so external agents can identify cross-entity edges from any file without consulting schema. Each value renders as the target's current icon + title. Renames update automatically. |
| **Last Edited Time** | *(not stored — derived from `modified_at`)* | `{}` | Read-only, sortable. Default sort, descending. |
| **File / Attachment** | `[{ "path": "<nexus-relative>", "original_name", "added_at", "mime_type" }, ...]` (array; multi-file) | `{ "accept": ["pdf", "image/*"]? }` | Drag-drop + click-to-pick + thumbnail strip. Files copy into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>` on attach; property stores nexus-relative paths. |

The only pure text field is the **title** (the filename, not a property). Where a Notion-style "text" field would appear, Pommora uses Select or Multi-select with creatable options.

**Not property types:**
- **Connections** — body-text inline `[[ ]]` links, indexed in SQLite with no frontmatter mirror. Not properties, not schema-creatable. Spec → [[Connections]].
- **Rollups + Formulas** — out of v1 scope. Pommora's catalog is simpler than Notion's by design.

---

#### Where Properties Live (surface architecture)

The **target** surface architecture gives properties two homes, split by where the entity opens:

- **Properties dropdown** (`PropertiesPulldown`) — for **Pages, Contexts, and storage views** (the main content pane); a dropdown frees the trailing inspector to host the LLM / CLI interface.
- **Property panel** (in a pop-out inspector) — for **PagePreview windows and Agenda entries**.

This split is **partially wired**: the PagePreview window mounts the property panel; main-pane Pages still surface their properties in the same panel (`FrontmatterInspector`, the window `.inspector`) and the dropdown scaffold is unbuilt. The State column tracks where each surface stands.

| Surface | Home (target) | State |
|---|---|---|
| **Page** (main pane) | Properties dropdown | Planned — currently the property panel in the editor's `.inspector` (`FrontmatterInspector`); migrating to free the inspector for the LLM |
| **Context / storage view** | Properties dropdown | Planned (same migration) |
| **PagePreview window** | Property panel in the window's inspector pane | Shipped — the shared `FrontmatterInspector` mounted in compact mode (defaults open): no section headings, condensed rows, action affordances a typographic step below, small control size, cards flush at uniform insets |
| **Agenda entry** | Property panel | — |

Property-panel surfaces render **eager**: all schema properties show regardless of fill state (empty ones as void inputs), edited inline through `PropertyEditorRow`. Title is excluded everywhere (filename plays that role). On both `FrontmatterInspector` mounts there is no meta section (Title / ID / Created / Icon) — the page ID renders as a bottom-pinned, middle-truncated pane footer (`ID: <ulid>`) — and an **Add Property** affordance (plus + label as one button) opens the `PropertyTypePicker` in a popover, committing through the shared `PropertyCreation` enum (the same default-definition factory the View Settings type-picker pane uses). On `PropertyPanel` / `PropertiesPulldown`, auto-managed `id` + `created_at` + `modified_at` collapse to a bottom meta section; `modified_at` surfaces as **Last Edited Time** for sortability.

---

#### Property identity vs name

Properties follow an ID-truth model. Every property in a Type's schema carries two independent identifiers:

- **`id`** — stable ULID stored in the schema sidecar. Assigned at property creation, never changes. **This is the canonical identity** — the key used in member-file frontmatter / JSON, in cross-property references (`default_sort` references, etc.), and in the SQLite index.
- **`name`** — the property's user-facing display label. Renameable freely; renames are schema-only (no member-file cascade).

On-disk shape:

```yaml
# Page frontmatter — property values keyed by property ID
id: 01HPAGE...
created_at: 2026-05-24T...
modified_at: 2026-05-24T...
icon: doc.text
tier1: [01HAREA...]
tier2: [01HTOPIC...]
prop_01HXY...: { $status: active }         # display name: "Status" — tagged-object form
prop_01HAB...: ["research", "frontend"]    # display name: "Tags"  (Multi-select stays bare-array)
prop_01HSEL...: "in_review"                # display name: "Stage" (Select stays bare-string)
prop_01HREL...: [{ $rel: 01HTARGET... }]   # display name: "Project" (Relation — always an array)
```

Pages carry property values in `.md` frontmatter. Tasks / Events keep a `properties` JSON object:

```json
// Agenda JSON — properties block keyed by property ID (Tasks / Events stay JSON)
{
  "id": "01HTASK...",
  "properties": {
    "prop_01HXY...": { "$status": "active" },
    "prop_01HAB...": ["research", "frontend"],
    "prop_01HREL...": [{ "$rel": "01HTARGET..." }]
  }
}
```

Status + Relation both use a tagged-object on-disk shape (`$status` / `$rel`) so external agents can identify the value type from any single file without consulting the schema sidecar — satisfies the agent-legibility load-bearing constraint (`Architecture.md`). Select stays bare-string and Multi-select stays bare-array because their shapes are unambiguous (no other type collides at the value layer).

Cross-property references in the schema use IDs: `default_sort.property_id`, `views[i].group.property_id`, `views[i].filter.rules[i].property_id` (→ [[Views]]). `_title` is reserved as the title column id in `property_order` (movable, never hideable).

**Reserved property IDs.** Built-in property IDs use a fixed prefix scheme so the schema editor can block collisions and external agents can identify them at a glance: `_id`, `_created_at`, `_modified_at`, `_status`, `_type`, `_title`, `_tier1`, `_tier2`, `_tier3`. The schema editor blocks user-defined properties from using these IDs.

**The `cover` field is not a property.** A page's cover is a root `cover` frontmatter field (nexus-relative image path), never surfaced in any properties UI — not Edit Properties, not the Layout visibility list, not the inspector. It's a per-view Gallery display concern only (→ [[Views]] § "Covers + Banners").

**Property `name` uniqueness within a Type** is enforced (case-insensitive) at name-write time — for display sanity, not identity. Two properties in the same Type can't share a display name.

---

#### Entity identity vs title

Canonical rule → [[Domain-Model]] § "Entity identity vs title". Connection disk format and rename cascade → [[Connections]].

---

#### Per-tier relations

Operational entities (Pages, Tasks, Events) each carry three tier relation properties pointing to Contexts. They store at the frontmatter / JSON root (not under `properties`) as ID arrays:

```yaml
tier1: [<area-id>, ...]    # Areas (Context tier 1)
tier2: [<topic-id>, ...]   # Topics (Context tier 2)
tier3: [<project-id>, ...] # Projects (Context tier 3)
```

Tier values ARE relations — they are the **only** relation-type connections a user interacts with. Three pre-configured context-link properties (`_tier1` / `_tier2` / `_tier3`, each a `relation` with a `context_tier` target) merge into every Type's resolved schema via `BuiltInContextLinkProperties`, picking up per-Nexus tier labels + icons. They render, sort, group, and pick exactly like any property; they edit via the property panel's context pickers (`ContextValueEditor` / `ContextPicker`) and appear in the same surface. Built-in (not user-defined): the schema editor can't create or delete them, and no additional relation properties can be user-created.

---

#### Status property type

A workflow property with three EventKit-aligned structural groups, each containing user-editable options. Single-pick value.

##### The 3 fixed groups (EventKit-aligned)

| Group ID | Default label | Default color | EventKit meaning (deferred sync) |
|---|---|---|---|
| `upcoming` | "Upcoming" | gray | `EKReminder.isCompleted = false`; for Events, user-set "not yet attended" |
| `in_progress` | "In Progress" | blue | Reminders actively due; for Events, user-set "currently attending" |
| `done` | "Done" | green | `EKReminder.isCompleted = true`; for Events, user-set "attended / completed" |

Group IDs are load-bearing; group labels are user-renameable. The 3 slots are fixed across every Status property regardless of where it's used. Workflow customization happens by adding options within groups — users add as many options inside the three structural groups as they want ("Backlog", "Queued", "Triaged" all inside Upcoming).

##### Options within groups

Each group holds an ordered list of options. Each option has `value` (canonical key, immutable post-create), `label` (renameable), optional `color` (nil inherits group's), and `group_id` (drives sort + EventKit + display).

Default seed when a Status property is created:

```
Upcoming       → [{ value: "not_started", label: "Not started", group_id: "upcoming" }]
In Progress    → [{ value: "in_progress", label: "In progress", color: "blue",  group_id: "in_progress" }]
Done           → [{ value: "done",         label: "Done",         color: "green", group_id: "done" }]
```

##### Schema mutations on a Status property

- **Rename a group label** — schema-only write.
- **Add an option** to a group — schema-only write.
- **Rename an option's label** — schema-only write (option `value` immutable).
- **Move an option between groups** — schema-only file write but data-semantic (rewrites the option's `group_id`; affects sort, display color, EventKit mapping and Group By — both deferred). Triggers a confirmation dialog listing affected entities.
- **Delete an option** — voids referencing values (`.null`). Multi-select strips only the deleted value from each entity's array. Confirmation dialog lists affected count.
- **Add / remove a group** — not supported.

##### Sort behavior

Group position first (`upcoming < in_progress < done` ascending), then option order within group. Ascending puts Upcoming first; descending puts Done first.

##### Where Status is built-in

| Schema | Status built-in? | Notes |
|---|---|---|
| **Task** (`_taskconfig.json`) | **Yes** — required, non-deletable. | Default seed includes the 3 groups with one starter option each. EventKit sync (deferred) maps the 3 groups to `EKReminder.isCompleted`: `upcoming` / `in_progress` → `false`; `done` → `true`. |
| **Event** (`_eventconfig.json`) | **Yes** — required, non-deletable. | Same 3 EventKit-aligned groups as Task. User-set (decoupled from `start_at` / `end_at` date math — the user marks status to track their own engagement with the event). EventKit mapping deferred. |
| **Page Types** | **No.** | Not auto-seeded. Users add manually via Vault Settings. When added, the same 3-group structure applies. |

Reserved property ID `_status` on both the Task and Event schemas. Users cannot delete it via the schema editor.

---

#### Relation target — context_tier only

Pre-wired to `_tier1` / `_tier2` / `_tier3` as `{ "kind": "context_tier", "tier": 1/2/3 }`. Not user-selectable; any other target kind in an old sidecar is decode-tolerated but dropped on load. Pickers query the `context_links` table.

---

#### Context-side linked-from picker (deferred)

`LinkedFromDropdown` reads `IndexQuery.incomingContextLinks(targetID:)` — every entity whose tier1/2/3 points at this Context, rendered via `ContextChip`. Full surface is deferred.

---

#### Managing options (Select / Multi-select / Status)

Option creation, renaming, recoloring, deletion, and reorder happen only via the schema editor — never inline in the value picker.

Three commit paths:

1. **Vault / Type Settings → Edit Properties → expand property → option list** — canonical. Drag-reorder, "+ Add option", per-option color picker, rename TextField, delete. Batched with the sheet's Save.
2. **Right-click a property LABEL** (inspector row, panel row) → "Add option…" — small structured popover (Name + Color + Group-for-Status + Save / Cancel) with its own commit boundary.
3. **Right-click a property VALUE** (pill, chip, status indicator) → "Edit options…" — routes to Vault / Type Settings → Edit Properties at that property's row. Value pickers themselves do not accept typed new options; they show a "Manage options…" link routing to the same destination.

For Status, the editor also exposes per-group label TextFields + drag-between-groups across Upcoming / In Progress / Done.

##### Option `value` immutable; `label` renameable

Each option carries a canonical `value` set at creation (never changes) and a user-facing `label` (renameable). Stored frontmatter / JSON references `value`; renaming a `label` is schema-only. Mirrors the stable-target-with-renameable-display pattern across Pommora (connections: title → resolved target; relations: `$rel` → current title; options: `value` → current `label`; properties: ID → current `name`).

##### Schema option order drives sort

For Select and Multi-select, schema option order defines sort behavior — drag-reorder in the option editor; ascending returns first-listed first. Example: a Select with `[Awaiting, Active, Done]` — ascending puts `Awaiting` first; descending puts `Done` first. Status combines this with group position (group first, option order second).

---

#### Two save models

| Edit layer | Save model | UX |
|---|---|---|
| **Schema edits** (Vault / Type level — rename property, change type, add/delete property, edit options) | Save-required | Vault / Type Settings sheet stages edits into a draft; explicit Save commits inside an atomic transaction; Cancel discards. Concurrent-open forbidden — only one Type's Settings sheet open at a time per window. |
| **Value edits** (entity level — setting a property value on a specific Page) | Live-save | Pickers commit on click; text inputs debounce-save after typing stops. No Save button. Invalid values render with a red border; failed saves silently revert; recovery on next valid keystroke. |

---

#### Schema mutations

| Mutation | Effect on existing values |
|---|---|
| **Add a property** | Appears empty on every member (rendered as a void input across every surface). No member writes until a value is set. |
| **Rename a property** | Schema-only write (the `name` field updates on the schema entry; member files untouched because frontmatter / JSON is keyed by property ID). |
| **Change a property's type** | Lossless conversions (e.g. Select → Multi-select) apply directly. Other type changes require confirmation; conflicting values are dropped. |
| **Delete a property** | Schema row removed; values removed from every member (the member's `properties` block loses the property-ID key). No quarantine. |
| **Reorder properties** | Schema-only (members are dictionary-keyed by ID); affects property panel order. No member writes. |
| **Editing Select / Multi-select / Status options** | Add / reorder / rename labels = schema-only. Deleting an option voids member references per the universal void-on-delete rule. |

##### Atomicity

Schema mutations that touch multiple files (type-change with value-drop / delete-with-value-clear) commit atomically across all affected files; on any write failure, complete rollback across every affected file. Property renames specifically do NOT need cross-file atomicity — they're single-file schema updates.

---

#### Moving content between Types

Moving a Page across Page Types strips properties not in the destination schema. Confirmation warning lists what will be stripped; user can cancel, add the property to the destination first, or accept. Within the same Type (between Page Collections), no strip — schema is shared. There is no quarantine, orphan archive, or undo-strip.

**Move-strip is schema-scoped; foreign-key preservation is everything else.** The strip only voids Pommora's own *schema properties* the destination doesn't define. Non-schema frontmatter keys — plugin/foreign keys an external tool wrote onto the `.md` file — are preserved by value on every Page write path, including a cross-Type move (they ride along via the source URL). The two mechanisms are orthogonal: the schema layer governs what Pommora-owned properties survive a move; foreign-key preservation guarantees Pommora never culls a key it doesn't model. (Yams round-trips by value — flow→block reflow + comment drop on a foreign file's first re-serialization; content is safe, exact styling/comments are not.)

---

#### Auto-managed properties

On every Page (frontmatter), Task (JSON), and Event (JSON), not user-creatable:

- `id` — ULID assigned at creation, never changes (stored at frontmatter root, not under `properties`)
- `created_at`, `modified_at` — ISO-8601 timestamps maintained by Pommora (frontmatter root)

Title is NOT a property surface entry. The filename plays the title role — edited inline at the page title position.

Auto-managed properties sit at the bottom of every property surface, in a separate section divided by a horizontal divider. The bottom section holds `id` and `created_at` (read-only, collapsed by default). `modified_at` is exposed alongside user-defined properties at the top of the surface as Last Edited Time for sortability — same value, two surfacings.

Tasks and Events also carry a built-in `description` — a plain-text JSON field (Agenda stays JSON). Not markdown.

##### `modified_at` trigger semantics

Updates on any content or frontmatter edit — body, property value, title rename, icon, tier1/2/3. View-only actions never update. External edits update file mtime but do NOT update frontmatter `modified_at`.

---

#### Validation

Enforced at every write to a Type's per-kind sidecar (schema-level) and to each member file (value-level):

**Schema-level:**

1. Property `name` uniqueness within the Type (case-insensitive) — display sanity, not identity.
2. Property `name` non-empty.
3. Property `id` uniqueness within the Type.
4. Reserved property IDs are blocked from user-defined properties (canonical list in § Property identity vs name).
5. Select / Multi-select: at least one option; option `value` uniqueness within property.
6. Built-in `_status` on the Task and Event schemas is non-deletable.

**Value-level:**

1. Every property value's shape matches its schema entry's type (looked up by property ID).
2. Relation `$rel` ULIDs must resolve to a live entity (warned, not enforced — broken-link semantics).
3. Select / Multi-select / Status values must reference live option `value`s (cleaned up on schema mutation).

---

#### Vault / Type settings architecture

Properties + view configuration spans four surfaces:

##### 1. Vault / Type Settings (schema editor)

The schema editor for a Vault / Type. Reached from the Type detail view toolbar gear button, the Type row's right-click menu, or the "+ Property" column header in the detail-pane Table view. UI label: "Vault Settings…" by default.

| Section | Contents |
|---|---|
| **Edit Properties** | Add / rename / type-change / delete / reorder properties. Per-property icon (`IconPicker`). Per-type config (options, tier reverse name + icon, status groups, etc.). |
| **Templates** | Empty wiring — placeholder anchor for future content templates. Reserved post-v1. |

Save-required + concurrent-open forbidden (only one Type's Settings sheet open at a time per window).

##### 2. Vault / Type View Settings (per-view config)

Per-view configuration via the consolidated `slider.horizontal.3` toolbar button popover at ContentView level. The button is statically positioned in the existing primary-action Liquid Glass capsule beside Navigation + Inspector toggle; its popover content adapts to the currently-selected surface via `ViewSettingsScope`.

The popover is active-view-scoped (resolved via `ActiveViewStore`). Full pane spec → [[Views]] § "View Settings Panes".

| Section | Contents |
|---|---|
| **Edit Properties** | **Schema-only** CRUD pane (Notion-format: icon+title row + Type + Options + Duplicate/Delete footer). Per-type config as before. Tier columns and Modified are removed from its list (non-editable), and it carries no visibility toggles. |
| **Layout** | Per-view: Display Banner toggle, Card Size (gallery), the **Property Visibility** eye-list (show/hide + drag-order over user properties + tier columns + Modified; `_title` non-hideable, cover never listed), and a muted Wrap Text row. The vault-scoped open-in selector ("Open Pages In") sits here. |
| **Sort** | Per-view single picker — Manual / Title A→Z / Z→A / Created / Recent / any property asc·desc. |
| **Filter** | Per-view flat rule list + Match All/Any, conservative per-type operators. |
| **Group** | Per-view — Default (structural) / property picker / Remove Grouping. |

The standalone Property Visibility pane is folded into Layout.

**Schema fields beyond the catalog basics** (on `PropertyDefinition` unless noted):

- `displayAs: DisplayVariant?` (Status-only) — rendering variant: `.box` = colored dot + label (default); `.select` = colored chip + label (same as Select); `.chip` = icon-only chip using a placeholder icon (final per-group icons + Settings config are a Prospect). Other property types ignore this field.
- `dateFormat: DateFormat?` (Date only) — date-portion display, picker-labelled by format-type name (no "Default" row): a short date, a full weekday-and-year date, and the two numeric `DD/MM/YYYY` / `MM/DD/YYYY` orderings. Defaults to the full date. Legacy date-format values migrate on decode.
- `timeFormat: TimeFormat?` (Date only) — time-portion display ("Display Time"): none (date only, default), 12-hour, or 24-hour. None stores a date-only value; 12h/24h store a with-time value.
- `views: [SavedView]` (on `PageType` / `PageCollection`) — each Collection's view config is independent of its parent Type's.

**Chip primitives** (`Pommora/Components/Chips/`):

- `ContextChip` — the single rendering primitive for context-link (tier relation) property values across every surface (Table cells, property panel, page-editor inspector, value picker rows). **Context-tier links render as minimal grey chips — the target's current icon + title.** Both icon and title resolve from the linked target entity, never from the home-side property. Resolution happens at the consumer (via `IndexQuery` against the SQLite `context_links` table); the chip receives pre-resolved strings and is purely visual — the file holds only the target's `$rel` ID, and a chip that renders blank or `(missing)` means the index lookup missed (stale/unbuilt row), not that the on-disk value is gone.
- `FileChip` — faint neutral fill, file SF Symbol, long filenames truncate.
- `LinkChip` — pure accent-blue text, strips the `https://` prefix, long URLs truncate (no chip chrome, lives in Chips folder for naming consistency).
- `ChipLink` — **intentionally dormant design asset**: the chip-link visual, wired to nothing in production (showcased in the Component Library explorer only). Context → [[Connections]] § "Scope".

**Option color palette** — disk persistence keeps a fixed colour set; the render layer maps it onto a fixed chip palette (`gray` maps to the default colour, lossy). The option-edit popover's colour-swatch grid exposes the selectable palette (excluding the default + accent colours) plus a "No color" affordance. Flat palette.

A per-Type default sort lives on the Type sidecar (`default_sort: { property_id, direction }`) as a fallback before per-view sort rules land.

##### 3. Vault / Type Views (saved views)

Multiple saved views per Vault / Type, Notion-database-views model. Each view carries its own config (Sort / Filter / Group / Layout, property order + hidden set) and a path to the schema settings (Vault / Type Settings is accessible from any view).

View definitions persist in the per-kind sidecar as `views[]` (SavedView v2). Multi-view CRUD + a toolbar Views dropdown switcher ship; Table and Gallery render, Board / List / Cards are muted. Full spec → [[Views]].

##### Settings scaffold integration

UI label strings throughout the Properties surface (sheet titles, picker headings, add-button labels, section headings) read from the Settings scaffold — not hardcoded. When the user renames "Collection" to "Folder" in Settings, the picker titles update everywhere.

---

#### Sort and default sort

Sort-by-property in the detail-pane Table view. Click a column header to sort; click again to reverse. Type-aware comparators:

- **Number** — numeric ascending/descending
- **Checkbox** — false-first vs true-first
- **Date** — chronological (oldest first / newest first)
- **Last Edited Time** — chronological; descending is the default sort
- **Select / Multi-select** — schema option order
- **Status** — group position first (Upcoming < In Progress < Done), then option order within group
- **URL** — alphabetical on `absoluteString`
- **Relation** — alphabetical on the resolved current title of the first target value
- **File / Attachment** — by count, then by `original_name` of the first file

##### Per-Type default sort

Persists in the Type's per-kind sidecar as a top-level `default_sort: { property_id: "prop_...", direction: "ascending" | "descending" }`. Full per-view sort with saved-view configs is deferred.

##### Hidden-property-used-for-sort-or-group-by = auto-show

If a hidden property is selected as the sort or grouping criterion, it auto-unhides. Precedence beats visibility.

---

#### Group By compatibility (deferred)

Only property types that hold one value per entity support Group By:

| Type | Compatible? | Why / Why not |
|---|---|---|
| Number | ✓ | Each numeric value (or numeric range) becomes a group |
| Select | ✓ | Each option becomes a group |
| Status | ✓ | Each option becomes a group; groups inherit Status group colors |
| Date | ✓ | Groups by day / week / month |
| Checkbox | ✓ | Two groups: true / false |
| URL | ⚠ Not useful | Holds one value; rarely meaningful |
| Relation | ✗ | Multiple target values per entity; ambiguous group membership (same as Multi-select) |
| Multi-select | ✗ | Multiple values per entity; ambiguous group membership |
| Last Edited Time | ✓ | Groups by day / week / month |
| File / Attachment | ✗ | Multi-value by nature; same ambiguity as Multi-select |

---

#### Column order in views vs property declaration order

Three orderings, three layers:

- **Column order in a Table or List view** is view-level. Drag column headers to rearrange; stored in the view's spec inside the per-kind sidecar (deferred with saved views). Visual only — no schema effect.
- **Property declaration order in the per-kind sidecar** is schema-level — the order properties appear in the property panel. Drag-to-reorder writes to the sidecar.
- **Option order inside a Select / Multi-select** is schema-level — drives sort. View-level group reorder is per-saved-view (deferred). Drag-to-reorder in the option editor.

---

#### Built-in tier columns in Table views

The three tier relations (Areas / Topics / Projects) surface in a Table view as pre-configured relation columns at the RIGHTMOST content positions — after every user-property column and immediately before the trailing Last Edited Time column. Order is Project, then Topic, then Area (`_tier3`, `_tier2`, `_tier1`). They render through `ContextChip` like any relation column and are reorderable + hideable like any column (via the Layout pane's visibility list → [[Views]]). A schema without tiers (e.g. a Type that doesn't carry them) gets no tier columns.

---

#### Out-of-scope boundaries

The full property data layer (all 10 types, ID-truth identity, schema CRUD on all four carriers, move-strip, file-attachment copy-on-attach, reserved-ID enforcement, the SQLite indexer) is in scope; the value editors, Settings sheet, and pickers all have a working UI path. Phasing of remaining UI polish lives in [[Framework]]; per-feature deferrals live in [[Prospects]]. Design constraints that don't fit elsewhere in this doc:

- **Computed properties** (Formula, Rollup, People), **ad-hoc page-local properties** (no schema entry), and **Collection-local schema overrides** are out of v1.
- **A 4th Status group (`cancelled`) is never added** — the 3-slot structure is preserved for clean EventKit mapping; `EKEvent.status = .canceled` maps to `done` if/when the sync layer bridges it.

---

#### Cross-references

- [[Domain-Model]] — 2-layer domain model overview
- [[PageTypes]] — Page Type + Page Collection container layer
- [[Agenda]] — Task + Event split; per-side schemas
- [[Contexts]] — Areas / Topics / Projects tier system
- [[Pages]] — on-disk shape, connection mechanics
- [[Prospects]] — post-v1 deferrals
- [[Framework]] — version roadmap
