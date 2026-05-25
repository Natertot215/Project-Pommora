### Properties

Pommora's property system. The same property type catalog applies to Pages, Items, Agenda Tasks, and Agenda Events. Schemas live on each Type's per-kind sidecar; values live on each member entity. The on-disk file is canonical; SQLite mirrors it for fast queries.

This document is the source of truth for **what** Properties are and **how they behave**. Implementation strategy + phasing live in a separate plan document.

---

#### Overview

A **property** is a typed field defined on a Type's schema and populated on individual entities of that Type. Properties live on:

- **Pages** (`.md` files) — frontmatter
- **Items** (`.json` files) — `properties` JSON object
- **Agenda Tasks** (`.task.json` files) — `properties` JSON object
- **Agenda Events** (`.event.json` files) — `properties` JSON object

Each entity belongs to one Type. Every Type carries a schema in its per-kind sidecar:

| Type | Schema sidecar |
|---|---|
| Page Type | `<Type>/_pagetype.json` |
| Item Type | `<Type>/_itemtype.json` |
| AgendaTask (singleton) | `<Tasks>/_taskconfig.json` |
| AgendaEvent (singleton) | `<Events>/_eventconfig.json` |

Schemas declare which properties exist on the Type, what type each property is, and any per-type config (option lists, relation scopes, etc.). Member entities store property VALUES conforming to that schema.

Page Collections and Item Collections do not carry their own schemas — they inherit from their parent Type. Their sidecars (`_pagecollection.json` / `_itemcollection.json`) carry only id + ordering + Collection-level UI preferences (pinned chips).

---

#### Property type catalog (11 types)

| Type | Value shape (keyed by property ID) | Config | UI behavior |
|---|---|---|---|
| **Number** | `42` or `3.14` | `{ "number_format": "integer" \| "decimal" \| "percent" \| "currency" }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `true` / `false` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{}` | Date picker. UTC-anchored on disk. |
| **Date & Time** | `"2026-06-15T14:30:00Z"` | `{}` | Date + time picker. |
| **Select** | `"<option value>"` | `{ "select_options": [{ "value", "label", "color" }, ...] }` | Single-pick colored pill. Option `value` immutable post-create; `label` renameable. Option order defines sort. Options are NOT created by typing into the value picker. |
| **Multi-select** | `["<value>", ...]` | `{ "select_options": [...] }` (same shape as Select) | Tag-style multi-pick. Each chip in its option's color. Option order defines sort. Options NOT created by typing. |
| **Status** | `{"$status": "<option value>"}` (tagged object) | `{ "status_groups": [{ "id", "label", "color", "options" }, ...] }` (3 fixed groups: `upcoming` / `in_progress` / `done`) | Grouped picker popover, 3 sections, single-pick. Pill color resolves option override > group default. Group labels renameable; 3 group slots fixed. Sort = group position first, then option order. Options NOT created by typing. Stored as tagged object (mirrors `$rel` pattern) so external agents can identify status values from any file without consulting the schema; bare-string would shape-collide with Select. |
| **URL** | `"https://..."` | `{}` | URL input; clickable link with favicon. |
| **Relation** | `{"$rel": "01HXYZ..."}` (single) or `[{"$rel": "..."}, ...]` (multi) | `{ "relation_scope": {...}, "allows_multiple": bool, "dual_property": {...}? }` | Scope-aware picker. Stored as tagged JSON object so external agents can identify cross-entity edges from any file without consulting schema. Displayed as the target's current title — styled colored inline text (wikilink look). Renames update automatically. |
| **Last Edited Time** | *(not stored — derived from `modified_at`)* | `{}` | Read-only, sortable. Default sort, descending. |
| **File / Attachment** | `[{ "path": "<nexus-relative>", "original_name", "added_at", "mime_type" }, ...]` (array; multi-file) | `{ "accept": ["pdf", "image/*"]? }` | Drag-drop + click-to-pick + thumbnail strip. Files copy into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>` on attach; property stores nexus-relative paths. |

The only pure text field is the **title** (the filename, not a property). Where a Notion-style "text" field would appear, Pommora uses Select or Multi-select with creatable options.

**Not property types:**
- **Wikilinks** — body-text feature with a derived `wikilinks: [...]` frontmatter mirror. Not schema-creatable.
- **Rollups + Formulas** — out of v1 scope. Pommora's catalog is simpler than Notion's by design.

---

#### Where Properties Live (surface architecture)

Properties live in three surfaces depending on context:

| Surface | Property home | Render mode |
|---|---|---|
| **Page in main window** | NavDropdown-style pulldown at top of content; "+ Add property" picker over schema | **Lazy** — populated properties only; empty schema entries invisible until populated via the picker |
| **Page Preview** (standalone window) | Property panel inside the window's inspector (toggle, default closed) | **Eager** — ALL schema properties shown; user can void or fill each from there |
| **Item Window** (popover) | Property panel inside the popover's inspector (toggle, default closed) + pinned-property chips above title | **Eager** — ALL schema properties shown in the inspector; user can void or fill each |
| **Main window inspector** | Claude chat (CLI subprocess bridge). Property panel never lives in the main-window inspector. | n/a |

Title is excluded from every property surface (filename plays the title role). Auto-managed `id` + `created_at` sit at the bottom of each surface in a divider-separated section, collapsed by default. `modified_at` appears in the main list as **Last Edited Time** for sortability.

##### Render modes

The Pages Pulldown is **lazy**: only populated properties render; empty schema entries are invisible. The Pulldown's "+ Add property" picker lists schema properties NOT yet populated on this Page — selecting one populates the entry with an empty/default value, ready to edit. Empty-state: when a Page has zero populated properties, the Pulldown renders an explicit "No properties" message + "+ Add property" affordance. Never collapses to invisible.

The Page Preview inspector + Item Window inspector are **eager**: ALL schema properties from the parent Type render regardless of fill state. Populated entries show their value; empty entries render as void inputs ready to fill. The user voids or fills inline — no "+ Add property" picker over the schema (every schema entry is already visible). Adding a NEW property to the schema happens in Vault / Type Settings.

The Pages Pulldown is content-focused — populated-only keeps the surface tight against the Markdown body. The Inspectors are property-focused — eager rendering makes the full schema discoverable in one view.

---

#### Property identity vs name

Properties follow an ID-truth model. Every property in a Type's schema carries two independent identifiers:

- **`id`** — stable ULID stored in the schema sidecar. Assigned at property creation, never changes. **This is the canonical identity** — the key used in member-file frontmatter / JSON, in cross-property references (`dual_property` mirrors, `default_sort` references, etc.), and in the SQLite index.
- **`name`** — the property's user-facing display label. Renameable freely; renames are schema-only (no member-file cascade).

On-disk shape:

```yaml
# Page frontmatter — property values keyed by property ID
id: 01HPAGE...
created_at: 2026-05-24T...
modified_at: 2026-05-24T...
icon: doc.text
tier1: [01HSPACE...]
tier2: [01HTOPIC...]
prop_01HXY...: { $status: active }       # display name: "Status" — tagged-object form
prop_01HAB...: ["research", "frontend"]  # display name: "Tags"  (Multi-select stays bare-array)
prop_01HSEL...: "in_review"              # display name: "Stage" (Select stays bare-string)
prop_01HREL...: { $rel: 01HTARGET... }   # display name: "Project" (Relation, single)
```

```json
// Item / Agenda JSON — properties block keyed by property ID
{
  "id": "01HITEM...",
  "properties": {
    "prop_01HXY...": { "$status": "active" },
    "prop_01HAB...": ["research", "frontend"],
    "prop_01HREL...": { "$rel": "01HTARGET..." }
  }
}
```

Status + Relation both use a tagged-object on-disk shape (`$status` / `$rel`) so external agents can identify the value type from any single file without consulting the schema sidecar — satisfies the agent-legibility load-bearing constraint (`Architecture.md`). Select stays bare-string and Multi-select stays bare-array because their shapes are unambiguous (no other type collides at the value layer).

Schema sidecar shape:

```json
{
  "properties": [
    { "id": "prop_01HXY...", "name": "Status", "type": "status", "status_groups": [...] },
    { "id": "prop_01HAB...", "name": "Tags",   "type": "multi_select", "select_options": [...] }
  ]
}
```

Cross-property references in the schema use IDs: `dual_property.synced_property_id`, `default_sort.property_id`, `views[i].group_by.property_id` (v0.6.0), `views[i].filter[i].property_id` (v0.6.0).

**Reserved property IDs.** Built-in property IDs use a fixed prefix scheme so the schema editor can block collisions and external agents can identify them at a glance: `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks`. The schema editor blocks user-defined properties from using these IDs.

**Property `name` uniqueness within a Type** is enforced (case-insensitive) at name-write time — for display sanity, not identity. Two properties in the same Type can't share a display name.

---

#### Entity identity vs title

Every entity (Page, Item, Agenda Task, Agenda Event, Context) carries two independent identifiers:

- **`id`** — stable ULID stored in frontmatter / JSON. Assigned at creation, never changes. Used by every cross-reference (wikilinks, relation values, tier1/2/3 links, the SQLite index).
- **Title** — the entity's display name, carried as the filename (minus extension). User-renameable freely; renames are filesystem renames + nothing else.

Duplicate titles allowed within the same container — two Pages named "Meeting Notes" in the same Page Type / Page Collection is fine because their IDs are distinct. Filesystem may auto-append a `(2)` suffix to a colliding filename, but the displayed title stays the user-typed value.

Wikilinks resolve by ID. Disk format: `[[Title|01HXYZ...]]` — title is the rendered label, ULID after the pipe is the unambiguous reference. Renames update the displayed label at render time; the stored reference never changes. Untargeted `[[Title]]` (typed or pasted from another tool) resolves by current basename match; the editor underlines ambiguous matches.

---

#### Per-tier multi-relations

Operational entities (Pages, Items, Agenda Tasks, Agenda Events) each carry three built-in multi-valued ID arrays pointing to Contexts:

```yaml
tier1: [<space-id>, ...]   # Spaces (Context tier 1)
tier2: [<topic-id>, ...]   # Topics (Context tier 2)
tier3: [<project-id>, ...] # Projects (Context tier 3)
```

These are built-in (not user-defined) and edited via the property panel's relation pickers alongside user-defined properties. They appear in the same surface as user-defined properties.

---

#### Status property type

A workflow property with three EventKit-aligned structural groups, each containing user-editable options. Single-pick value.

##### The 3 fixed groups (EventKit-aligned)

| Group ID | Default label | Default color | EventKit meaning (v0.6.0 sync) |
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
- **Move an option between groups** — schema-only file write but data-semantic (rewrites the option's `group_id`; affects sort, display color, EventKit mapping at v0.6.0, Group By at v0.6.0). Triggers a confirmation dialog listing affected entities.
- **Delete an option** — voids referencing values (`.null`). Multi-select strips only the deleted value from each entity's array. Confirmation dialog lists affected count.
- **Add / remove a group** — not supported.

##### Sort behavior

Group position first (`upcoming < in_progress < done` ascending), then option order within group. Ascending puts Upcoming first; descending puts Done first.

##### Where Status is built-in

| Schema | Status built-in? | Notes |
|---|---|---|
| **AgendaTask** (`_taskconfig.json`) | **Yes** — required, non-deletable. | Default seed includes the 3 groups with one starter option each. EventKit sync (v0.6.0) maps the 3 groups to `EKReminder.isCompleted`: `upcoming` / `in_progress` → `false`; `done` → `true`. |
| **AgendaEvent** (`_eventconfig.json`) | **Yes** — required, non-deletable. | Same 3 EventKit-aligned groups as AgendaTask. User-set (decoupled from `start_at` / `end_at` date math — the user marks status to track their own engagement with the event). EventKit mapping for events ships at v0.6.0. |
| **Page Types and Item Types** | **No.** | Not auto-seeded. Users add manually via Vault / Type Settings. When added, the same 3-group structure applies. |

Reserved property ID `_status` on both AgendaTask and AgendaEvent schemas. Users cannot delete it via the schema editor.

---

#### Relation values bind to specific entities

The VALUE of a relation property is always a specific entity's ULID — a specific Page, a specific Item, a specific Context. Never a Type-abstraction, never a Collection-abstraction.

**"Scope" is the picker constraint, not what the value points at.** Scope narrows the picker from "any entity in the Nexus" down to "any Page in PageType X" or "any Item in ItemCollection Y." The user picks one specific entity from that filtered set; the stored value is that entity's ULID alone.

Notion-model exactly. A relation property's definition points at a database (= container in Pommora terms — Vault / Type / Collection). Each row's value is one or more specific pages from that database.

Example: A Page Type "Notes" has a relation property called "Project" scoped to Page Collection "Active Projects." A specific Note Page sets the property:

- **Schema:** `{"id": "prop_01HPROJ...", "name": "Project", "type": "relation", "relation_scope": {"kind": "page_collection", "page_collection_id": "01HACTIVE..."}, "allows_multiple": false}`
- **Picker UX:** dropdown lists all Pages in the "Active Projects" Page Collection
- **User picks:** "Q3 Launch" Page
- **Value on disk:** `prop_01HPROJ...: {"$rel": "01HQ3LAUNCH..."}`
- **Display:** "Q3 Launch" rendered as styled inline text
- **If target "Q3 Launch" is renamed:** display updates; stored ULID never changes
- **If the property "Project" is renamed:** schema-only update; `prop_01HPROJ...` is still the key in frontmatter

Scope hierarchy (broadest → narrowest): Vault (Page Type / Item Type) → Collection (Page Collection / Item Collection) → Context tier. Scope can be set at the Vault / Type root (picker shows all members across all Collections) or drilled into a specific Collection / Set (picker is narrowed). The VALUE is always specific.

---

#### Relation scope

Each Relation property targets exactly one container at creation. For a second container, create a second Relation property. Five scope kinds; no fallback "anywhere" scope.

```json
{ "kind": "page_type", "page_type_id": "01HPAGETYPEID..." }
{ "kind": "item_type", "item_type_id": "01HITEMTYPEID..." }
{ "kind": "page_collection", "page_collection_id": "01HPAGECOLLID..." }
{ "kind": "item_collection", "item_collection_id": "01HITEMCOLLID..." }
{ "kind": "context_tier", "tier": 2 }
```

| Scope kind | Picker source | Bidirectional? |
|---|---|---|
| `page_type` | All Pages in the specified Page Type | Required dual — paired reverse property on the target Page Type's `_pagetype.json` |
| `item_type` | All Items in the specified Item Type | Required dual — paired reverse property on the target Item Type's `_itemtype.json` |
| `page_collection` | All Pages in the specified Page Collection | Required dual — paired reverse on the parent Page Type's `_pagetype.json` |
| `item_collection` | All Items in the specified Item Collection | Required dual — paired reverse on the parent Item Type's `_itemtype.json` |
| `context_tier` | All Contexts at the specified tier (1=Spaces / 2=Topics / 3=Projects) | One-way — no paired property; reverse view derived via SQLite query |

**Cross-side relations (Item ↔ Page) are supported.** Item-side Relation pickers list Page Types / Page Collections alongside Item Types / Item Collections; Page-side pickers do the inverse. Unified picker, no side-locking. Cross-side *promotion* (transforming an Item into a Page or vice versa) is a separate concept — post-v1 Prospect.

Relation pickers query the SQLite index.

---

#### Dual relations

Creating a Relation property targeting a Page Type, Item Type, Page Collection, or Item Collection is always paired — Pommora creates two property definitions, one on each side, synchronized. No opt-out — without naming both sides, the reverse side can't identify its relationship.

Config shape inside the source Relation property:

```json
{
  "dual_property": {
    "synced_property_id": "prop_01HCITED...",
    "synced_property_defined_on_type_id": "01HMATERIALSPAGETYPE..."
  }
}
```

The reverse property in the target Type carries the mirror config pointing back (by property ID). The `synced_property_defined_on_type_id` field always points at a Page Type or Item Type (the parent Type) — never at a Collection directly, since Collection-scoped reverses are stored in the parent Type's per-kind sidecar.

Lifecycle:

- **Creation** — schema editor asks for BOTH names (source + target). Both definitions land atomically; either write failing rolls back both.
- **Value setting** — setting a relation on Page A1 mirrors a back-reference on target Page B1; removing the relation removes both ends.
- **Renaming either side** — schema-only write that updates the `name` field on this side. The OTHER side's `dual_property` reference is by ID, so it's untouched. Paired identity survives.
- **Deleting either side** — confirmation dialog ("Deleting this property will also remove '<reverseName>' from <Type X>"). On confirm, BOTH definitions deleted + mirrored values cleared both sides.
- **Moving a Page across Page Types (or an Item across Item Types) with a paired relation** — strip rule applies: source's value goes; target side's reverse value loses the source's ULID.

Dual relations are mandatory for the four container scopes (`page_type` / `item_type` / `page_collection` / `item_collection`) and unavailable for `context_tier` (Contexts have no `properties[]` schema). Schema editor omits the reverse-name prompt for `context_tier`. The reverse view is query-derived via SQLite.

##### Creating a Relation property — guided flow

Multi-step wizard:

```
Example: User in Page Type Y wants to relate to Pages in Page Type X.

1. "+ Add property" in Page Type Y's schema editor
2. Pick type "Relation"
3. Pick scope kind: ◉ Page Type   ◯ Page Collection   ◯ Item Type   ◯ Item Collection   ◯ Context tier
4. Pick target: Page Type X (searchable list, filtered to the chosen scope kind)
5. Property name in THIS Type (Y):       "Sources"
6. Reverse property name in TARGET (X):  "Cited By"
7. Allow multiple values?  ✓ Yes
8. Save → atomically creates Page Type Y's "Sources" + Page Type X's "Cited By".
```

Context-tier scope omits step 6. Pickers are unified across sides — a Pages-side wizard lists Page Types / Page Collections AND Item Types / Item Collections as targets.

---

#### Managing options (Select / Multi-select / Status)

Option creation, renaming, recoloring, deletion, and reorder happen only via the schema editor — never inline in the value picker.

Three commit paths:

1. **Vault / Type Settings → Edit Properties → expand property → option list** — canonical. Drag-reorder, "+ Add option", per-option color picker, rename TextField, delete. Batched with the sheet's Save.
2. **Right-click a property LABEL** (pulldown row, panel row, Item Window row) → "Add option…" — small structured popover (Name + Color + Group-for-Status + Save / Cancel) with its own commit boundary.
3. **Right-click a property VALUE** (pill, chip, status indicator) → "Edit options…" — routes to Vault / Type Settings → Edit Properties at that property's row. Value pickers themselves do not accept typed new options; they show a "Manage options…" link routing to the same destination.

For Status, the editor also exposes per-group label TextFields + drag-between-groups across Upcoming / In Progress / Done.

##### Option `value` immutable; `label` renameable

Each option carries a canonical `value` set at creation (never changes) and a user-facing `label` (renameable). Stored frontmatter / JSON references `value`; renaming a `label` is schema-only. Mirrors the stable-target-with-renameable-display pattern across Pommora (wikilinks: ID → current title; relations: `$rel` → current title; options: `value` → current `label`; properties: ID → current `name`).

##### Universal void-on-delete

Deleting an option voids referencing entity values (`.null`). Multi-select differs only in that the deleted value is removed from each array (the array shrinks; `.null` only if it becomes empty). Confirmation dialog lists affected entity count before commit.

Same principle for deleting a property: schema row removed; values removed from every member (the member's `properties` block loses the property-ID key). No quarantine.

##### Schema option order drives sort

For Select and Multi-select, schema option order defines sort behavior — drag-reorder in the option editor; ascending returns first-listed first. Example: a Select with `[Awaiting, Active, Done]` — ascending puts `Awaiting` first; descending puts `Done` first. Status combines this with group position (group first, option order second).

---

#### Two save models

| Edit layer | Save model | UX |
|---|---|---|
| **Schema edits** (Vault / Type level — rename property, change type, add/delete property, edit options) | Save-required | Vault / Type Settings sheet stages edits into a draft; explicit Save commits inside an atomic transaction; Cancel discards. Concurrent-open forbidden — only one Type's Settings sheet open at a time per window. |
| **Value edits** (entity level — setting a property value on a specific Page or Item) | Live-save | Pickers commit on click; text inputs debounce-save after typing stops. No Save button. Invalid values render with a red border; failed saves silently revert; recovery on next valid keystroke. |

Schema edits affect every entity of the Type — high blast radius, needs explicit confirmation. Value edits affect one entity — low blast radius, friction-free.

The right-click "Add option…" popover is a third commit boundary — its own Save inside the popover, separate from the parent sheet.

---

#### Schema mutations

| Mutation | Effect on existing values |
|---|---|
| **Add a property** | Appears empty on every member (visible in eager surfaces; invisible in lazy Pulldown until populated). No member writes until a value is set. |
| **Rename a property** | Schema-only write (the `name` field updates on the schema entry; member files untouched because frontmatter / JSON is keyed by property ID). |
| **Change a property's type** | Lossless only at v0.3.0 (Date → Date & Time, Select → Multi-select). Otherwise user must confirm; conflicting values are dropped. |
| **Delete a property** | Schema row removed; values removed from every member (the member's `properties` block loses the property-ID key). No quarantine. |
| **Reorder properties** | Schema-only (members are dictionary-keyed by ID); affects property panel order. No member writes. |
| **Editing Select / Multi-select / Status options** | Add / reorder / rename labels = schema-only. Deleting an option voids member references per the universal void-on-delete rule. |

##### Atomicity

Schema mutations that touch multiple files (type-change with value-drop / delete-with-value-clear / paired-relation create / paired-relation delete) commit atomically across all affected files; on any write failure, complete rollback across every affected file. Property renames specifically do NOT need cross-file atomicity — they're single-file schema updates.

---

#### Moving content between Types

Moving a Page across Page Types (or an Item across Item Types) strips properties not in the destination schema. Confirmation warning lists what will be stripped; user can cancel, add the property to the destination first, or accept. Within the same Type (between Page Collections, or between Item Collections), no strip — schema is shared.

Cross-side promotion (Item → Page, Page → Item) is NOT supported in v1 — post-v1 Prospect. No quarantine / orphan archive / undo-strip in v0.3.0.

The "what would be stripped" computation compares the source's property-ID set against the destination Type's property-ID set. Same-name properties with different IDs (semantically different properties that happen to share a display name) are stripped — correct behavior under ID-truth (the user is moving between unrelated property definitions).

---

#### Auto-managed properties

On every Page (frontmatter), Item (JSON), Agenda Task (JSON), and Agenda Event (JSON), not user-creatable:

- `id` — ULID assigned at creation, never changes (stored at frontmatter root, not under `properties`)
- `created_at`, `modified_at` — ISO-8601 timestamps maintained by Pommora (frontmatter root)

Title is NOT a property surface entry. The filename plays the title role — edited inline at the page title position (Pages) or as the Item Window's title field (Items).

Auto-managed properties sit at the bottom of every property surface, in a separate section divided by a horizontal divider. The bottom section holds `id` and `created_at` (read-only, collapsed by default). `modified_at` is exposed alongside user-defined properties at the top of the surface as Last Edited Time for sortability — same value, two surfacings.

Items, Agenda Tasks, and Agenda Events also carry one built-in field that isn't a property:

- `description` — plain-text body field, hard cap 250 characters. This IS Items' body field (Items don't have Markdown bodies — description fills that role at a deliberately short size; fits in the Item Window without scrolling). Same field on AgendaTask + AgendaEvent. Not Markdown — Pages exist for Markdown.

##### `modified_at` trigger semantics

Updates on any content or frontmatter edit — body, property value, title rename, icon, tier1/2/3. View-only actions never update. External edits update file mtime but do NOT update frontmatter `modified_at` until the file watcher closes the gap (v0.3.3).

---

#### Validation

Enforced at every write to a Type's per-kind sidecar (schema-level) and to each member file (value-level):

**Schema-level:**

1. Property `name` uniqueness within the Type (case-insensitive) — display sanity, not identity.
2. Property `name` non-empty.
3. Property `id` uniqueness within the Type.
4. Reserved property IDs (block user-defined properties from claiming these): `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks`.
5. Dual relation requires `page_type` / `item_type` / `page_collection` / `item_collection` scope; `context_tier` scope rejects dual.
6. Relation scope's target ULID must resolve to a live entity at save time. Cross-side targets are allowed.
7. Select / Multi-select: at least one option; option `value` uniqueness within property.
8. Built-in `_status` on the AgendaTask and AgendaEvent schemas is non-deletable.

**Value-level:**

1. Every property value's shape matches its schema entry's type (looked up by property ID).
2. Relation `$rel` ULIDs must resolve to a live entity (warned, not enforced — broken-link semantics).
3. Select / Multi-select / Status values must reference live option `value`s (cleaned up on schema mutation).

---

#### Vault / Type settings architecture

Properties + view configuration spans four surfaces:

##### 1. Vault / Type Settings (schema editor)

The schema editor for a Vault / Type. Reached from the Type detail view toolbar gear button, the Type row's right-click menu, or the "+ Property" column header in the detail-pane Table view. UI label per side: "Vault Settings…" on Page Types by default; "Type Settings…" on Item Types by default.

| Section | Contents |
|---|---|
| **Edit Properties** | Add / rename / type-change / delete / reorder properties. Per-property icon (`IconPickerField`). Per-type config (options, scope, dual reverse name, status groups, etc.). |
| **Templates** | Empty wiring — placeholder anchor for future content templates (Page / Item templates pre-filling body + properties at creation). Reserved post-v1. |

Save-required + concurrent-open forbidden (only one Type's Settings sheet open at a time per window).

##### 2. Vault / Type View Settings (per-view config)

Per-view configuration sheet. Ships at v0.6.0 alongside saved views.

| Section | Contents |
|---|---|
| **Sort by** | Per-view; multi-criterion. |
| **Group By** | Per-view. |
| **Filter** | Per-view; WHERE-style criteria. |
| **Layout** | Per-view; one of Table / Board / List / Cards / Gallery. |
| **Property Visibility** | Per-view; show/hide columns. |

A per-Type default sort lives on the Type sidecar (`default_sort: { property_id, direction }`) as a fallback before saved views ship.

##### 3. Vault / Type Views (saved views)

Multiple saved views per Vault / Type, Notion-database-views model. Each view carries its own View Settings (Sort / Group By / Filter / Layout / Property Visibility) and a path to the schema settings (Vault / Type Settings is accessible from any view).

View definitions persist in the per-kind sidecar as `views[]`. Ships at v0.6.0.

##### 4. Item Inspector → Pinned Properties

Per-Collection UI preference managed inside the Item Window inspector. Right-click any property row in the inspector → "Pin to chips"; right-click chip → "Unpin." Pinned set persists at the Item Collection level in the Collection's config file:

```json
// _itemcollection.json
{
  "pinned_properties": ["prop_01HXY...", "prop_01HAB..."]
}
```

All Items in a Collection share the chip layout. Chips render above the title in the Item Window popover.

##### Settings scaffold integration

UI label strings throughout the Properties surface (sheet titles, picker headings, add-button labels, section headings) read from the Settings scaffold — not hardcoded. When the user renames "Set" to "Library" in Settings, the Items-side picker title updates everywhere.

---

#### Sort and default sort

Sort-by-property in the detail-pane Table view. Click a column header to sort; click again to reverse. Type-aware comparators:

- **Number** — numeric ascending/descending
- **Checkbox** — false-first vs true-first
- **Date / Date & Time** — chronological (oldest first / newest first)
- **Last Edited Time** — chronological; descending is the default sort
- **Select / Multi-select** — schema option order
- **Status** — group position first (Upcoming < In Progress < Done), then option order within group
- **URL** — alphabetical on `absoluteString`
- **Relation** — alphabetical on resolved current title of the target
- **File / Attachment** — by count, then by `original_name` of the first file

##### Per-Type default sort

Persists in the Type's per-kind sidecar as a top-level `default_sort: { property_id: "prop_...", direction: "ascending" | "descending" }`. Full per-view sort with saved-view configs lives in Vault / Type View Settings (v0.6.0).

##### Hidden-property-used-for-sort-or-group-by = auto-show

If a hidden property is selected as the sort criterion or as the Group By criterion (v0.6.0), it auto-unhides. Sort / group-by precedence beats visibility.

---

#### Group By compatibility (v0.6.0)

Only single-value property types support Group By:

| Type | Compatible? | Why / Why not |
|---|---|---|
| Number | ✓ | Each numeric value (or numeric range) becomes a group |
| Select | ✓ | Each option becomes a group |
| Status | ✓ | Each option becomes a group; groups inherit Status group colors |
| Date / Date & Time | ✓ | Groups by day / week / month |
| Checkbox | ✓ | Two groups: true / false |
| URL | ⚠ Not useful | Technically single-value; rarely meaningful |
| Relation | ✓ | Each target entity becomes a group |
| Multi-select | ✗ | Multiple values per entity; ambiguous group membership |
| Last Edited Time | ✓ | Groups by day / week / month |
| File / Attachment | ✗ | Multi-value by nature; same ambiguity as Multi-select |

---

#### Column order in views vs property declaration order

Three orderings, three layers:

- **Column order in a Table or List view** is view-level. Drag column headers to rearrange; stored in the view's spec inside the per-kind sidecar (v0.6.0 with saved views). Visual only — no schema effect.
- **Property declaration order in the per-kind sidecar** is schema-level — the order properties appear in the property panel. Drag-to-reorder writes to the sidecar.
- **Option order inside a Select / Multi-select** is schema-level — drives sort. Drag-to-reorder in the option editor.

##### Schema-level option order vs view-level group order

| Ordering | Stored in | Effect | Scope |
|---|---|---|---|
| **Schema-level option order** (Edit Properties → drag-reorder options) | Per-kind sidecar `properties[i].select_options[]` (or `status_groups[i].options[]`) | Drives default sort nexus-wide; changes the property itself | All views, all members of the Type |
| **View-level group order** (Group By config — drag-reorder group sections) | Per-kind sidecar `views[i].group_by.order: [String]` | Reorders sections IN THIS VIEW only; doesn't touch the property | One saved view at a time |

---

#### Scope at v0.3.0

v0.3.0 ships the **complete data layer** for every property type in the catalog, plus **placeholder UI** for every interaction that needs UI. The placeholder UI is not polished — final Figma-driven UI replaces it in fast-follow patches — but every data field has a working UI path so behavior is verifiable end-to-end.

##### In scope at v0.3.0

Data layer (full):
- All 11 property types — data + validation + value round-trip on Pages, Items, AgendaTask, AgendaEvent
- Property ID-truth identity model + migration for existing nexuses
- Schema CRUD on all four schema-bearing carriers (PageType, ItemType, AgendaTask schema, AgendaEvent schema)
- Status built-in on AgendaTask + AgendaEvent (default seed)
- Cross-side relations (no side-locking)
- Paired-relation creation + lifecycle (dual_property)
- Move-strip rule + cross-Type move methods
- File-attachment copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/`
- `_itemcollection.json.pinned_properties` field
- `default_sort` field on all four schema-bearing sidecars
- Reserved property ID prefix enforcement
- SQLite indexer (per-nexus DB at `<nexus>/.nexus/index.db`; powers relation pickers + move-strip "affected count" + sort/filter at scale)

Placeholder UI (every interaction has a working path):
- Property panel for every property type (Pages-side via extended `FrontmatterInspector`; Items-side via extended `PropertyEditorRow`)
- Vault / Type Settings sheet with Edit Properties + Templates sections (Pages-side + Items-side)
- Relation picker (scope-aware; cross-side targets supported)
- Status grouped picker (3 sections, single-pick)
- File attachment editor (drag-drop + click-to-pick + thumbnail strip)
- Pinned-property chips above title in Item Window (basic rendering; pin / unpin via right-click)
- Move-strip confirmation dialog (lists what's stripped)
- Column-header click-to-sort on Pages-side detail-pane Table
- Live red-border validation feedback on every value editor

##### Out of scope at v0.3.0 (deferred to specific later versions)

- Real polished Properties Pulldown + Property Panel SwiftUI component (Figma-driven; v0.3.0 fast-follow / v0.3.1)
- Real polished Item Window redesign with finalized chip UX (Figma-driven; v0.3.x)
- PreviewWindow primitive (Page Preview, Context Preview) — v0.3.x
- Claude chat main-window inspector — ships independently
- Per-entity `panel_hidden_properties` field — revisit post-v0.3.0 if needed
- Vault / Type Views + Vault / Type View Settings (saved views) — v0.6.0 with the five view types
- Detail-pane property columns + reimagined view shape — v0.6.0
- Multi-criterion sort — v0.6.0
- Wikilink resolution + autocomplete + `wikilinks: []` mirror — v0.3.2
- Watcher-driven Last Edited Time updates from external edits — v0.3.3
- EventKit sync (Status bridges to `EKReminder.isCompleted` for AgendaTask; AgendaEvent bridge TBD) — v0.6.0+
- Cross-side *promotion* (transforming an Item INTO a Page or vice versa) — post-v1 Prospect (cross-side *relations* ARE supported at v0.3.0)
- Per-Item-Type templates — post-v1 Prospect
- Computed properties (Formula, Rollup, People) — out of v1
- 4th Status group (`cancelled`) — 3-slot structural preserved for EventKit; `EKEvent.status = .canceled` maps to `done` if/when bridged
- Cross-Type lossy type-change auto-conversion — lossless only in v0.3.0
- Ad-hoc page-local properties (one-off properties without schema entry) — out of v1
- Collection-local schema overrides — post-v1 Prospect

---

#### Cross-references

- [[Domain-Model]] — 2-layer domain model overview
- [[PageTypes]] — Page Type + Page Collection container layer
- [[Items]] — Item Type + Item Collection container layer + Item Window
- [[Agenda]] — AgendaTask + AgendaEvent split; per-side schemas
- [[Contexts]] — Spaces / Topics / Projects tier system
- [[Pages]] — on-disk shape, wikilink mechanics
- [[Prospects]] — post-v1 deferrals
- [[Framework]] — version roadmap
