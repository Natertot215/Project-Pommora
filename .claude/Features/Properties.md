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

Schemas declare which properties exist on the Type, what type each property is, and any per-type config (option lists, relation targets, etc.). Member entities store property VALUES conforming to that schema.

Page Collections and Item Collections do not carry their own property schemas — they inherit from their parent Type. Their sidecars (`_pagecollection.json` / `_itemcollection.json`) carry id, parent-Type linkage, an optional `icon` (mirrored into SQLite for the relation picker), and per-view config (`views[]`); `_itemcollection.json` additionally holds the Collection's pinned-property chips.

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
| **Relation** | `[{"$rel": "01HXYZ..."}, ...]` (always an array; a single value is a 1-element array) | `{ "relation_target": {...}, "dual_property": {...}? }` | Always multi-value. Target-aware picker; target kinds are Page Type, Item Type, Agenda Tasks, Agenda Events (Context tiers are internal-only). Stored as tagged JSON objects so external agents can identify cross-entity edges from any file without consulting schema. Each value renders as the target's icon + current title in plain styled colored text (wikilink look). Renames update automatically. |
| **Last Edited Time** | *(not stored — derived from `modified_at`)* | `{}` | Read-only, sortable. Default sort, descending. |
| **File / Attachment** | `[{ "path": "<nexus-relative>", "original_name", "added_at", "mime_type" }, ...]` (array; multi-file) | `{ "accept": ["pdf", "image/*"]? }` | Drag-drop + click-to-pick + thumbnail strip. Files copy into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>` on attach; property stores nexus-relative paths. |

The only pure text field is the **title** (the filename, not a property). Where a Notion-style "text" field would appear, Pommora uses Select or Multi-select with creatable options.

**Not property types:**
- **Wikilinks** — body-text feature with a derived `wikilinks: [...]` frontmatter mirror. Not schema-creatable.
- **Rollups + Formulas** — out of v1 scope. Pommora's catalog is simpler than Notion's by design.

---

#### Where Properties Live (surface architecture)

The **target** surface architecture gives properties two homes, split by where the entity opens:

- **Properties dropdown** (`PropertiesPulldown`) — for **Pages, Contexts, and storage views** (the main content pane); a dropdown frees the trailing inspector to host the LLM / CLI interface.
- **Property panel** (in a pop-out inspector) — for **Items, Page Previews, and Agenda items**, plus always-on pinned-property chips above an Item Window's title.

This split is **planned — not yet wired**: today Pages surface their properties in the property panel (`FrontmatterInspector`, the window `.inspector`) and the dropdown scaffold is unbuilt. The State column tracks where each surface stands.

| Surface | Home (target) | State |
|---|---|---|
| **Page** (main pane) | Properties dropdown | Planned — currently the property panel in the editor's `.inspector` (`FrontmatterInspector`); migrating to free the inspector for the LLM |
| **Context / storage view** | Properties dropdown | Planned (same migration) |
| **Item Window** (popover) | Property panel in the popover inspector + pinned chips above the title | Inspector toggle, default closed; pinned chips render whenever the Collection has any |
| **Page Preview** (standalone window) | Property panel in the window inspector | *Pending* — queued behind the PreviewWindow primitive |
| **Agenda item** | Property panel | — |

Property-panel surfaces render **eager**: all schema properties show regardless of fill state (empty ones as void inputs), edited inline through `PropertyEditorRow` — no "+ Add property" picker (every entry is already visible). Adding a NEW property to the schema happens in Vault / Type Settings. Title is excluded everywhere (filename plays that role); auto-managed `id` + `created_at` collapse to a divider-separated bottom section; `modified_at` surfaces as **Last Edited Time** for sortability.

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
prop_01HXY...: { $status: active }         # display name: "Status" — tagged-object form
prop_01HAB...: ["research", "frontend"]    # display name: "Tags"  (Multi-select stays bare-array)
prop_01HSEL...: "in_review"                # display name: "Stage" (Select stays bare-string)
prop_01HREL...: [{ $rel: 01HTARGET... }]   # display name: "Project" (Relation — always an array)
```

```json
// Item / Agenda JSON — properties block keyed by property ID
{
  "id": "01HITEM...",
  "properties": {
    "prop_01HXY...": { "$status": "active" },
    "prop_01HAB...": ["research", "frontend"],
    "prop_01HREL...": [{ "$rel": "01HTARGET..." }]
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

Cross-property references in the schema use IDs: `dual_property.synced_property_id`, `default_sort.property_id`, `views[i].group_by.property_id` (v0.7.0), `views[i].filter[i].property_id` (v0.7.0).

**Reserved property IDs.** Built-in property IDs use a fixed prefix scheme so the schema editor can block collisions and external agents can identify them at a glance: `_id`, `_created_at`, `_modified_at`, `_status`, `_type`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks`. The schema editor blocks user-defined properties from using these IDs.

**Property `name` uniqueness within a Type** is enforced (case-insensitive) at name-write time — for display sanity, not identity. Two properties in the same Type can't share a display name.

---

#### Entity identity vs title

Every entity (Page, Item, Agenda Task, Agenda Event, Context) carries two independent identifiers:

- **`id`** — stable ULID stored in frontmatter / JSON. Assigned at creation, never changes. Used by every cross-reference (wikilinks, relation values, tier1/2/3 links, the SQLite index).
- **Title** — the entity's display name, carried as the filename (minus extension). User-renameable freely; renames are filesystem renames + nothing else.

Duplicate titles allowed within the same container — two Pages named "Meeting Notes" in the same Page Type / Page Collection is fine because their IDs are distinct. Filesystem may auto-append a `(2)` suffix to a colliding filename, but the displayed title stays the user-typed value.

Wikilinks resolve by ID. Disk format: `[[Title|01HXYZ...]]` — title is the rendered label, ULID after the pipe is the unambiguous reference. Renames update the displayed label at render time; the stored reference never changes. Untargeted `[[Title]]` (typed or pasted from another tool) resolves by current basename match; the editor underlines ambiguous matches.

---

#### Per-tier relations

Operational entities (Pages, Items, Agenda Tasks, Agenda Events) each carry three tier relation properties pointing to Contexts. They store at the frontmatter / JSON root (not under `properties`) as ID arrays:

```yaml
tier1: [<space-id>, ...]   # Spaces (Context tier 1)
tier2: [<topic-id>, ...]   # Topics (Context tier 2)
tier3: [<project-id>, ...] # Projects (Context tier 3)
```

Tier values ARE relations — they flow through the same property pipeline as user-defined relations. Three pre-configured relation properties (`_tier1` / `_tier2` / `_tier3`, each a `relation` with a `context_tier` target) merge into every Type's resolved schema via `BuiltInRelationProperties`, picking up per-Nexus tier labels + icons. They render, sort, group, and pick exactly like any relation property; they edit via the property panel's relation pickers alongside user-defined properties and appear in the same surface. Built-in (not user-defined): the schema editor can't create or delete them.

---

#### Status property type

A workflow property with three EventKit-aligned structural groups, each containing user-editable options. Single-pick value.

##### The 3 fixed groups (EventKit-aligned)

| Group ID | Default label | Default color | EventKit meaning (v0.5.0 sync) |
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
- **Move an option between groups** — schema-only file write but data-semantic (rewrites the option's `group_id`; affects sort, display color, EventKit mapping at v0.5.0, Group By at v0.7.0). Triggers a confirmation dialog listing affected entities.
- **Delete an option** — voids referencing values (`.null`). Multi-select strips only the deleted value from each entity's array. Confirmation dialog lists affected count.
- **Add / remove a group** — not supported.

##### Sort behavior

Group position first (`upcoming < in_progress < done` ascending), then option order within group. Ascending puts Upcoming first; descending puts Done first.

##### Where Status is built-in

| Schema | Status built-in? | Notes |
|---|---|---|
| **AgendaTask** (`_taskconfig.json`) | **Yes** — required, non-deletable. | Default seed includes the 3 groups with one starter option each. EventKit sync (v0.5.0) maps the 3 groups to `EKReminder.isCompleted`: `upcoming` / `in_progress` → `false`; `done` → `true`. |
| **AgendaEvent** (`_eventconfig.json`) | **Yes** — required, non-deletable. | Same 3 EventKit-aligned groups as AgendaTask. User-set (decoupled from `start_at` / `end_at` date math — the user marks status to track their own engagement with the event). EventKit mapping for events ships at v0.5.0. |
| **Page Types and Item Types** | **No.** | Not auto-seeded. Users add manually via Vault / Type Settings. When added, the same 3-group structure applies. |

Reserved property ID `_status` on both AgendaTask and AgendaEvent schemas. Users cannot delete it via the schema editor.

---

#### Relation values bind to specific entities

The VALUE of a relation property is always one or more specific entities' ULIDs — specific Pages, specific Items, specific Agenda items, specific Contexts. Never a Type-abstraction, never a Collection-abstraction.

**The target is the picker constraint, not what the value points at.** The target narrows the picker from "any entity in the Nexus" down to "any Page in Page Type X" or "any Item in Item Type Y." The user picks specific entities from that filtered set; the stored value is those entities' ULIDs alone.

Notion-model exactly. A relation property's definition points at a database (= container in Pommora terms — a Vault / Type or an Agenda side). Each row's value is one or more specific entries from that database.

Example: A Page Type "Notes" has a relation property called "Project" targeting Page Type "Active Projects." A specific Note Page sets the property:

- **Schema:** `{"id": "prop_01HPROJ...", "name": "Project", "type": "relation", "relation_target": {"kind": "page_type", "page_type_id": "01HACTIVE..."}}`
- **Picker UX:** dropdown lists all Pages in the "Active Projects" Page Type; multiple entries selectable
- **User picks:** "Q3 Launch" Page
- **Value on disk:** `prop_01HPROJ...: [{"$rel": "01HQ3LAUNCH..."}]`
- **Display:** "Q3 Launch" rendered as the target's icon + title in styled inline text
- **If target "Q3 Launch" is renamed:** display updates; stored ULID never changes
- **If the property "Project" is renamed:** schema-only update; `prop_01HPROJ...` is still the key in frontmatter

Relations are always multi-value — there is no single/multi toggle. A single chosen entity is stored as a 1-element array. The VALUE is always specific.

---

#### Relation target

Each Relation property points at exactly one target at creation. For a second target, create a second Relation property. The schema stores the target under the `relation_target` key as a tagged object; no fallback "anywhere" target.

Four user-creatable target kinds:

```json
{ "kind": "page_type", "page_type_id": "01HPAGETYPEID..." }
{ "kind": "item_type", "item_type_id": "01HITEMTYPEID..." }
{ "kind": "agenda_tasks" }
{ "kind": "agenda_events" }
```

| Target kind | Picker source | Paired? |
|---|---|---|
| `page_type` | All Pages in the specified Page Type | Required dual — paired reverse property on the target Page Type's `_pagetype.json` |
| `item_type` | All Items in the specified Item Type | Required dual — paired reverse property on the target Item Type's `_itemtype.json` |
| `agenda_tasks` | All Agenda Tasks in the Nexus | Required dual — paired reverse property on `_taskconfig.json` |
| `agenda_events` | All Agenda Events in the Nexus | Required dual — paired reverse property on `_eventconfig.json` |

One internal-only target kind, `context_tier`, is reserved for the built-in tier relations (`_tier1` / `_tier2` / `_tier3` → Spaces / Topics / Projects). It carries the tier number (`{ "kind": "context_tier", "tier": 2 }`) and is never user-selectable in the editor — Contexts have no `properties[]` schema, so its reverse view is SQLite-query-derived rather than paired. (`page_collection` / `item_collection` kinds are read-tolerated for migration only and never offered in the editor.)

**Cross-side relations (Item ↔ Page) are supported.** Item-side Relation pickers list Page Types alongside Item Types and the two Agenda sides; Page-side pickers do the inverse. Unified picker, no side-locking. Cross-side *promotion* (transforming an Item into a Page or vice versa) is a separate concept — post-v1 Prospect.

Relation pickers query the SQLite index.

---

#### Dual relations

Every user-created Relation property is paired — Pommora creates two property definitions, one on each side, synchronized. The paired/reverse relation resolves all four target kinds: Page Type, Item Type, Agenda Tasks, Agenda Events. No opt-out — without naming both sides, the reverse side can't identify its relationship.

Config shape inside the home Relation property:

```json
{
  "dual_property": {
    "synced_property_id": "prop_01HCITED...",
    "synced_property_defined_on_type_id": "01HMATERIALSPAGETYPE..."
  }
}
```

The reverse property in the target Type carries the mirror config pointing back (by property ID). The `synced_property_defined_on_type_id` field points at the target's schema carrier — a Page Type, an Item Type, or the Agenda Tasks / Agenda Events config.

Lifecycle:

- **Creation** — the relation editor sets the home side, a reverse (mirror) name, and a reverse icon. Both definitions land atomically; either write failing rolls back both.
- **Value setting** — setting a relation on Page A1 mirrors a back-reference on target Page B1; removing the relation removes both ends.
- **Renaming either side** — schema-only write that updates the `name` field on this side. The OTHER side's `dual_property` reference is by ID, so it's untouched. Paired identity survives.
- **Deleting either side** — confirmation dialog ("Deleting this property will also remove '<reverseName>' from <Type X>"). On confirm, BOTH definitions deleted + mirrored values cleared both sides.
- **Moving a Page across Page Types (or an Item across Item Types) with a paired relation** — strip rule applies: source's value goes; target side's reverse value loses the source's ULID.

The built-in tier relations (`context_tier` target) are not paired — Contexts have no `properties[]` schema, so their reverse view is query-derived via SQLite. They're internal, not created through the relation editor.

##### Creating a Relation property — the relation editor

A single-pane editor handles creation: it sets the home target plus the reverse (mirror) name and reverse icon — no multi-step wizard. (Post-creation editing of a relation's name/icon is #34, pending; today renaming is per-side via the property menu — see Lifecycle above.)

```
Example: User in Page Type Y wants to relate to Pages in Page Type X.

1. "+ Add property" in Page Type Y's schema editor
2. Pick type "Relation" → the relation editor opens
3. Pick target kind + target: ◉ Page Type → Page Type X
       (◯ Item Type   ◯ Agenda Tasks   ◯ Agenda Events; searchable list)
4. Home property name in THIS Type (Y):    "Sources"
5. Reverse property name in TARGET (X):    "Cited By"   + reverse icon
6. Save → atomically creates Page Type Y's "Sources" + Page Type X's "Cited By".
```

Pickers are unified across sides — a Pages-side editor lists Page Types AND Item Types AND the two Agenda sides as targets.

---

#### Agenda Tasks and Events as relation targets

Agenda Tasks and Agenda Events are first-class relation targets. A Relation property on any Type (or on the other Agenda side) can target `agenda_tasks` or `agenda_events`; the picker lists all Agenda Tasks / Agenda Events in the Nexus, multi-select. Each is a singleton target (no per-container drilldown — there's one Tasks side and one Events side). The reverse property lands on `_taskconfig.json` / `_eventconfig.json` exactly like a Page-Type / Item-Type reverse. This lets, say, a "Meeting Notes" Page relate to the Agenda Events it documents, or an Item relate to its blocking Tasks.

#### Context-side linked-from picker

A Context (Space / Topic / Project) shows what links to it through a dropdown surface — `LinkedFromDropdown`. Because the built-in tier relations are one-directional (Contexts carry no `properties[]` schema), the Context can't store an explicit reverse list; instead the dropdown reads the incoming edges live from the SQLite index via `IndexQuery.incomingRelations(targetID:)`, which returns every entity whose `tier1` / `tier2` / `tier3` (or any user relation) points at that Context. Each row renders through the same `RelationChip` primitive (target icon + title). This is the Context-side counterpart to a paired reverse property; the full surface is a follow-on.

---

#### Managing options (Select / Multi-select / Status)

Option creation, renaming, recoloring, deletion, and reorder happen only via the schema editor — never inline in the value picker.

Three commit paths:

1. **Vault / Type Settings → Edit Properties → expand property → option list** — canonical. Drag-reorder, "+ Add option", per-option color picker, rename TextField, delete. Batched with the sheet's Save.
2. **Right-click a property LABEL** (inspector row, panel row, Item Window row) → "Add option…" — small structured popover (Name + Color + Group-for-Status + Save / Cancel) with its own commit boundary.
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
| **Add a property** | Appears empty on every member (rendered as a void input across every surface). No member writes until a value is set. |
| **Rename a property** | Schema-only write (the `name` field updates on the schema entry; member files untouched because frontmatter / JSON is keyed by property ID). |
| **Change a property's type** | Lossless conversions (Date → Date & Time, Select → Multi-select) apply directly. Other type changes require confirmation; conflicting values are dropped. |
| **Delete a property** | Schema row removed; values removed from every member (the member's `properties` block loses the property-ID key). No quarantine. |
| **Reorder properties** | Schema-only (members are dictionary-keyed by ID); affects property panel order. No member writes. |
| **Editing Select / Multi-select / Status options** | Add / reorder / rename labels = schema-only. Deleting an option voids member references per the universal void-on-delete rule. |

##### Atomicity

Schema mutations that touch multiple files (type-change with value-drop / delete-with-value-clear / paired-relation create / paired-relation delete) commit atomically across all affected files; on any write failure, complete rollback across every affected file. Property renames specifically do NOT need cross-file atomicity — they're single-file schema updates.

---

#### Moving content between Types

Moving a Page across Page Types (or an Item across Item Types) strips properties not in the destination schema. Confirmation warning lists what will be stripped; user can cancel, add the property to the destination first, or accept. Within the same Type (between Page Collections, or between Item Collections), no strip — schema is shared.

Cross-side promotion (Item → Page, Page → Item) is NOT supported in v1 — post-v1 Prospect. There is no quarantine, orphan archive, or undo-strip.

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

Updates on any content or frontmatter edit — body, property value, title rename, icon, tier1/2/3. View-only actions never update. External edits update file mtime but do NOT update frontmatter `modified_at` until the file watcher closes the gap (v0.4.0).

---

#### Validation

Enforced at every write to a Type's per-kind sidecar (schema-level) and to each member file (value-level):

**Schema-level:**

1. Property `name` uniqueness within the Type (case-insensitive) — display sanity, not identity.
2. Property `name` non-empty.
3. Property `id` uniqueness within the Type.
4. Reserved property IDs are blocked from user-defined properties (canonical list in § Property identity vs name).
5. User-created relations are paired and require a `page_type` / `item_type` / `agenda_tasks` / `agenda_events` target; the internal `context_tier` target rejects dual.
6. A relation target's ULID must resolve to a live entity at save time. Cross-side targets are allowed.
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
| **Edit Properties** | Add / rename / type-change / delete / reorder properties. Per-property icon (`IconPicker`). Per-type config (options, relation target, dual reverse name + icon, status groups, etc.). |
| **Templates** | Empty wiring — placeholder anchor for future content templates (Page / Item templates pre-filling body + properties at creation). Reserved post-v1. |

Save-required + concurrent-open forbidden (only one Type's Settings sheet open at a time per window).

##### 2. Vault / Type View Settings (per-view config)

Per-view configuration via the consolidated `slider.horizontal.3` toolbar button popover at ContentView level. The button is statically positioned in the existing primary-action Liquid Glass capsule beside NavDropdown + Inspector toggle; its popover content adapts to the currently-selected surface via `ViewSettingsScope`.

| Section | Contents | Ships |
|---|---|---|
| **Edit Properties** | Schema CRUD pane (Notion-format: icon+title row + Type + Options with chevron-push to per-option EditOptionPane + Duplicate/Delete footer). Per-type config: Select/Multi-Select drag-only options; Status `.box`/`.select`/`.chip` display variant + 3 group sections; Date 6-format Display as picker; File/URL no per-type config (rename-only). Shared with VaultSettingsSheet + TypeSettingsSheet via extracted `Pommora/Properties/Editor/` module. | v0.3.1 |
| **Property Visibility** | Per-view; show/hide columns + drag-reorder. Click-to-toggle with strikethrough on hidden. `_modified_at` always visible. | v0.3.1 |
| **Layout** | Per-view; one of Table / Board / List / Cards / Gallery (Table active since v0.3.1; the other renderers ship with the view system at v0.7.0). | v0.3.1 (Table); v0.7.0 (others) |
| **Sort** | Per-view; multi-criterion, lands with saved views. Option ordering itself is drag-only at the property level (not view-level Sort) per Edit Property pane. | v0.7.0 |
| **Filter** | Per-view; operators equals / not-equals / contains / empty / not-empty; AND- and OR-grouped, wired to `IndexQuery`. | v0.7.0 |
| **Group By** | Per-view; single property; pairs with Board view. | v0.7.0 |

**Schema fields beyond the catalog basics** (on `PropertyDefinition` unless noted):

- `displayAs: DisplayVariant?` (Status-only) — `.box` / `.select` / `.chip` rendering variant. `.box` = colored dot + label (default); `.select` = colored chip + label (same as Select); `.chip` = icon-only chip using a hardcoded `square.dashed` placeholder (final per-group icons + Settings config are a Prospect). Other property types ignore this field.
- `dateFormat: DateFormat?` (Date / Date & Time only) — six display-format cases: `monthDayLong` ("March 4") / `monthDayYearLong` ("March 4, 2026") / `numericShort` ("03-04") / `numericMedium` ("03-04-26") / `numericLong` ("03-04-2026") / `iso` ("2026-03-04"). Default `.monthDayYearLong`.
- `singular: String?` (on `ItemType`) — Capacities-style singular form for "+ Add <singular>" button labels (e.g. ItemType "Books" with `singular: "Book"` drives "+ Add Book"). nil falls back to title. Per the RC-session decision list (see `History.md`), only Item Types carry this (Pages aren't renameable concepts).
- `views: [SavedView]` (on `PageType` / `ItemType` / `PageCollection` / `ItemCollection`) — each Collection's view config is independent of its parent Type's.

**Chip primitives** (`Pommora/Properties/Chips/`):

- `RelationChip` — the single rendering primitive for relation property values across every surface (Table cells, property panel, page-editor inspector, Item Window, value picker rows). Renders the **target object's icon + current title in plain styled colored text** — no pill, box, or chrome. Both icon and title resolve from the linked target entity, never from the home-side property. Resolution happens at the consumer (via `IndexQuery` against the SQLite index); the chip receives pre-resolved strings and is purely visual — the file holds only the target's `$rel` ID, and a chip that renders blank or `(missing)` means the index lookup missed (stale/unbuilt row), not that the on-disk value is gone. A dedicated chip visual (boxed, colored) is a future design.
- `FileChip` — quaternary fill, `link` SF Symbol, filename truncated 13 chars.
- `LinkChip` — pure accent-blue text, strips `https://` prefix, truncates 15 chars (no chip chrome, lives in Chips folder for naming consistency).
- `OptionColorPicker` — 5×2 grid of 10 selectable colors + "No color" affordance.

**Option color palette — two enums.** Two distinct color types serve two layers:

- `PropertyDefinition.SelectColor` — the **persistence layer**: 9 cases (`gray` / `brown` / `orange` / `yellow` / `green` / `blue` / `purple` / `pink` / `red`). This is what an option's stored `color` field holds on disk.
- `PropertyChipColor` — the **render layer**: 12 cases (`.default` nil/grey fallback / `.red` / `.orange` / `.yellow` / `.green` / `.blue` / `.accent` current Nexus accent / `.teal` / `.indigo` / `.purple` / `.pink` / `.brown`). `.default` and `.accent` aren't user-pickable, so the 5×2 swatch grid (`OptionColorPicker`) uses `selectablePalette` — 10 cases. `PropertyChipColor(selectColor:)` maps the 9 stored cases up to the render enum (lossy: `gray` → `.default`; the render-only `teal` / `indigo` / `accent` have no stored counterpart). Green + Teal render at reduced opacity; Yellow (`#FFDE21`) + Pink (`#E89EB8`) use custom hex. Flat palette — no color tiers.

A per-Type default sort lives on the Type sidecar (`default_sort: { property_id, direction }`) as a fallback before per-view sort rules land.

##### 3. Vault / Type Views (saved views)

Multiple saved views per Vault / Type, Notion-database-views model. Each view carries its own View Settings (Sort / Group By / Filter / Layout / Property Visibility) and a path to the schema settings (Vault / Type Settings is accessible from any view).

View definitions persist in the per-kind sidecar as `views[]`. Single-view-per-container today (popover binds to `views[0]`). Multi-saved-view support + view-tabs row beneath the detail-view title, and the non-Table renderer types (Board / List / Cards / Gallery), all ship together at v0.7.0.

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
- **Relation** — alphabetical on the resolved current title of the first target value
- **File / Attachment** — by count, then by `original_name` of the first file

##### Per-Type default sort

Persists in the Type's per-kind sidecar as a top-level `default_sort: { property_id: "prop_...", direction: "ascending" | "descending" }`. Full per-view sort with saved-view configs lives in Vault / Type View Settings (v0.7.0).

##### Hidden-property-used-for-sort-or-group-by = auto-show

If a hidden property is selected as the sort criterion or as the Group By criterion (v0.7.0), it auto-unhides. Sort / group-by precedence beats visibility.

---

#### Group By compatibility (v0.7.0)

Only property types that hold one value per entity support Group By:

| Type | Compatible? | Why / Why not |
|---|---|---|
| Number | ✓ | Each numeric value (or numeric range) becomes a group |
| Select | ✓ | Each option becomes a group |
| Status | ✓ | Each option becomes a group; groups inherit Status group colors |
| Date / Date & Time | ✓ | Groups by day / week / month |
| Checkbox | ✓ | Two groups: true / false |
| URL | ⚠ Not useful | Holds one value; rarely meaningful |
| Relation | ✗ | Multiple target values per entity; ambiguous group membership (same as Multi-select) |
| Multi-select | ✗ | Multiple values per entity; ambiguous group membership |
| Last Edited Time | ✓ | Groups by day / week / month |
| File / Attachment | ✗ | Multi-value by nature; same ambiguity as Multi-select |

---

#### Column order in views vs property declaration order

Three orderings, three layers:

- **Column order in a Table or List view** is view-level. Drag column headers to rearrange; stored in the view's spec inside the per-kind sidecar (v0.7.0 with saved views). Visual only — no schema effect.
- **Property declaration order in the per-kind sidecar** is schema-level — the order properties appear in the property panel. Drag-to-reorder writes to the sidecar.
- **Option order inside a Select / Multi-select** is schema-level — drives sort. Drag-to-reorder in the option editor.

##### Schema-level option order vs view-level group order

| Ordering | Stored in | Effect | Scope |
|---|---|---|---|
| **Schema-level option order** (Edit Properties → drag-reorder options) | Per-kind sidecar `properties[i].select_options[]` (or `status_groups[i].options[]`) | Drives default sort nexus-wide; changes the property itself | All views, all members of the Type |
| **View-level group order** (Group By config — drag-reorder group sections) | Per-kind sidecar `views[i].group_by.order: [String]` | Reorders sections IN THIS VIEW only; doesn't touch the property | One saved view at a time |

---

#### Built-in tier columns in Table views

The three tier relations (Spaces / Topics / Projects) surface in a Table view as pre-configured relation columns at the RIGHTMOST content positions — after every user-property column and immediately before the trailing Last Edited Time column. Order is Project, then Topic, then Space (`_tier3`, `_tier2`, `_tier1`). They render through `RelationChip` like any relation column and are reorderable + hideable like any column (hidden via Property Visibility). A schema without tiers (e.g. a Type that doesn't carry them) gets no tier columns.

---

#### Out-of-scope boundaries

The full property data layer (all 11 types, ID-truth identity, schema CRUD on all four carriers, paired relations, move-strip, file-attachment copy-on-attach, reserved-ID enforcement, the SQLite indexer) is in scope; the value editors, Settings sheet, and pickers all have a working UI path. Phasing of remaining UI polish lives in [[Framework]]; per-feature deferrals live in [[Prospects]]. Design constraints that don't fit elsewhere in this doc:

- **Computed properties** (Formula, Rollup, People), **ad-hoc page-local properties** (no schema entry), and **Collection-local schema overrides** are out of v1.
- **A 4th Status group (`cancelled`) is never added** — the 3-slot structure is preserved for clean EventKit mapping; `EKEvent.status = .canceled` maps to `done` if/when the sync layer bridges it.
- **Cross-side *promotion*** (transforming an Item into a Page or vice versa) is a post-v1 Prospect — distinct from cross-side *relations*, which are supported.

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
