### Properties

Pommora's property system spec. Referenced from `PommoraPRD.md`. v0.3.0 conceptual spec at `// Planning//v0.3.0-Properties-spec.md`; implementation plan at `// Planning//v0.3.0-Properties-plan.md`.

---

#### Model

- **Property values** live in YAML frontmatter on each Page, in the `properties` key of each Item's `.json`, in the `properties` key of each Agenda Task's `.task.json`, or in the `properties` key of each Agenda Event's `.event.json` — directly editable by any text editor, tool, or Claude.
- **Property schemas** live inside each Type's per-kind sidecar (canonical, agent-readable without SQLite) — Page Types at `<nexus>/<Title>/_pagetype.json` and Item Types at `<nexus>/<Title>/_itemtype.json`. Agenda has two parallel singleton sidecars: `_taskconfig.json` inside the Tasks singleton (AgendaTask schema) and `_eventconfig.json` inside the Events singleton (AgendaEvent schema). SQLite (v0.3.3) mirrors schemas for fast queries; the JSON file is the source of truth.
- **Properties are scoped to a Type** in v1 — every Page inside a Page Type shares that Page Type's schema (across all of its Page Collections); every Item inside an Item Type shares that Item Type's schema (across all of its Item Collections). Same property name in two Types = two independent definitions. Collection-local schema overrides are a post-v1 Prospect.
- **Same catalog across all entities** — Pages, Items, Agenda Tasks, and Agenda Events share the property type catalog. Storage substrate varies: Pages in YAML frontmatter; Items, Agenda Tasks, and Agenda Events in JSON.
- **Per-tier multi-relations on operational entities** — Pages / Items / Agenda Tasks / Agenda Events each carry `tier1` / `tier2` / `tier3` multi-valued ID arrays pointing to Contexts. Built-in (not user-defined); edited via the property panel's relation pickers alongside user-defined properties.
- **Property names are the key.** Renaming triggers a transactional cross-member rewrite (the relevant per-kind sidecar — `_pagetype.json` / `_itemtype.json` / `_taskconfig.json` / `_eventconfig.json` — plus every Page's frontmatter + every Item's `properties` block + every Agenda Task / Agenda Event's `properties` block, atomic two-phase commit). Legibility (human-readable frontmatter keys; agent-readable without schema lookup) outweighs the rewrite cost. Stable opaque IDs considered and rejected.
- **Every property can carry an icon.** Optional `icon: String?` (SF Symbol name) on `PropertyDefinition`. Shown next to the name in the schema editor list, property panel rows, and as the column header glyph in detail-pane Table views. Settable via per-property `IconPickerField` (reuses SymbolPicker integration).

#### How Properties Are Created

Properties are created from the **Type Settings sheet** — six sections (Edit Properties / Sort / Filter / Group By / Layout / Property Visibility); the Properties section hosts the schema editor. Reached from:
- Type detail view toolbar gear button (PageTypeDetailView for Page Types; ItemTypeDetailView for Item Types)
- Type row right-click → "Type Settings…" (UI label varies per side: "Vault Settings…" on Page Types; "Type Settings…" on Item Types — labels renameable via the Settings scaffold, Phase 7)
- "+ Property" column header in the detail-pane Table view (jumps to Edit Properties + "Add property" flow)
- Column header right-click in detail-pane Table → "Edit property…" (jumps to the relevant row)

Add Property flow:

1. **Add property** — "+ Add property" in Type Settings → Edit Properties, OR "+" column header in detail-pane Table view
2. **Name it** — `Status`, `Due`, `Tags`, etc.
3. **Pick an icon** (optional) — `IconPickerField` for an SF Symbol
4. **Pick a type** — opens type-specific config (options for Select, format for Number, scope + reverse name for Relation, 3-group editor for Status, etc.)
5. **Save** — schema entry written to the Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json` / `_taskconfig.json` / `_eventconfig.json` depending on side); property appears as empty on every member of that Type (paired Relation properties atomically add the reverse to the target Type)
6. **Set value** — written to the Page's frontmatter, Item's `properties` block, or Agenda Task / Agenda Event's `properties` block via `PropertyEditorRow` in the inspector / Item Window

Full Type Settings UI spec → [[PageTypes]] "Page Type Settings sheet" (parallel structure applies on the Items side once Item Type settings ship).

#### Property Type Catalog (v0.3.0)

Each type has a fixed config shape stored as JSON inside the property's entry in the Type's per-kind sidecar `properties` array (Page Type's `_pagetype.json` / Item Type's `_itemtype.json` / AgendaTask's `_taskconfig.json` / AgendaEvent's `_eventconfig.json` — same shape across all four; **the property schema lives on FOUR per-kind sidecar carriers, not six** — Page Collection's `_pagecollection.json` and Item Collection's `_itemcollection.json` carry only id + ordering metadata, no property schema). The shape determines edit UI + value display.

**The only pure text property is title** — the filename, not a frontmatter property. All others are typed. Where a Notion-style "text" field would appear, Pommora uses **Select** or **Multi-select** with creatable options.

| Type | Value shape (frontmatter / JSON) | Config shape (in the Type's per-kind sidecar) | UI behavior |
|---|---|---|---|
| **Number** | `42` or `3.14` | `{ "number_format": "integer" \| "decimal" \| "percent" \| "currency" }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `true` / `false` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{}` | Date picker, date-only. UTC-anchored on disk. |
| **Date & Time** | `"2026-06-15T14:30:00Z"` (ISO-8601 with timezone) | `{}` | Date + time picker. |
| **Select** | `"Active"` (option's `value`) | `{ "select_options": [{ "value": "active", "label": "Active", "color": "blue" }, ...] }` | Dropdown over existing options, colored pills. `value` immutable post-create; `label` renamable freely. Option order user-defined (drag in option editor) defines sort — see "Property options and sort order". **Options NOT created by typing into the value picker** — see "Managing options". |
| **Multi-select** | `["planning", "frontend"]` (option `value`s) | `{ "select_options": [...] }` (same shape as Select) | Tag-style multi-pick via `MultiSelectChips`; **each chip in option's color** (same 9-color Notion palette); same option-order-defines-sort. **Options NOT created by typing.** |
| **Status** | `"in_progress"` (option's canonical `value`) | `{ "status_groups": [{ "id": "awaiting", "label": "Awaiting", "color": "gray", "options": [...] }, ...] }` (3 fixed groups: `awaiting` / `in_progress` / `done`; user-editable options inside) | **Notion-parity workflow property.** Grouped picker popover, 3 sections; single-pick. Pill color resolves option override > group default. Group LABELS user-renamable; SLOTS structurally fixed. Sort = group position first, then option order. **Options NOT created by typing.** See "Status property type". |
| **URL** | `"https://..."` | `{}` | URL input; clickable link with favicon. |
| **Relation** | `{"$rel": "01HXYZ..."}` (single) or `[{"$rel": "01H..."}, ...]` (multi) | `{ "relation_scope": {...}, "allows_multiple": true \| false, "dual_property": {...}? }` | Scope-aware picker popover — see "Relation scope" + "Dual relations". **Stored as tagged JSON object** `{"$rel": "<ULID>"}` so external agents + graph-view indexer can identify cross-entity edges from any file without consulting schema. **Displayed as the target's current title** — styled colored inline text (wikilink look). Renames update automatically. |
| **Last Edited Time** | *(not stored)* | `{}` | Derived from `modified_at`. Read-only, sortable. v0.3.0 default sort. |

**Status is a first-class type** (Status-as-distinct-type locked RC-2026-05-19; previously folded into Select). With Status carrying the 3-group workflow structure, Selects are now exclusively free-form labels. Use Status for any "where in a process is this?" property.

**Wikilinks are NOT a property type.** Body-text wikilinks (`[[Title]]`) ship at v0.3.2 with their own derived `wikilinks: [...]` frontmatter mirror — derived from body scan, not schema-editable.

#### Status property type

Ships v0.3.0 as a workflow property with **3 EventKit-aligned structural groups**, each containing user-editable options. Single-pick value.

##### The 3 fixed groups (EventKit-aligned)

| Group ID | Default label | Default color | EventKit meaning |
|---|---|---|---|
| `upcoming` | "Upcoming" | gray | `EKReminder.isCompleted = false` + due-date-future; `EKEvent` with future start_at |
| `in_progress` | "In Progress" | blue | Reminders actively due / events currently happening |
| `done` | "Done" | green | `EKReminder.isCompleted = true`; events in the past |

**Group IDs are load-bearing; group LABELS are user-renamable.** Rename "Upcoming" → "Queued" — the structural `upcoming` ID stays. The 3 slots are fixed — **adding/removing groups is not supported** (would break EventKit compat at v0.6.0). Workflow customization happens via **adding options within groups** ("Backlog", "Queued", "Triaged" all inside Upcoming).

##### Options within groups

Each group contains an ordered list of user-editable options. Each option has `value` (canonical key, immutable post-create), `label` (renamable), `color` (optional override; nil inherits group's), and `group_id` (load-bearing — drives sort + EventKit + display).

Default seed when a Status property is created:

```
Upcoming       → [{ value: "not_started", label: "Not started", group_id: "upcoming" }]
In Progress    → [{ value: "in_progress", label: "In progress", color: "blue",  group_id: "in_progress" }]
Done           → [{ value: "done",         label: "Done",         color: "green", group_id: "done" }]
```

##### Schema mutations on a Status property

- **Rename a group label** — schema-only write (group identified by its structural ID; rename touches `label` only)
- **Add an option** to a group — schema-only write (new option's `group_id` set to the target group)
- **Rename an option's label** — schema-only write (option `value` immutable; `label` renames freely)
- **Move an option between groups** — **DATA-SEMANTIC change** despite being a schema-only file write. Rewrites the option's `group_id`; `value` is preserved (stored frontmatter `status: "<value>"` still resolves). Affects sort (new group position), display color (new group's pill), EventKit mapping v0.6.0 (e.g. In Progress → Done flips `EKReminder.isCompleted` false → true on every referencing Agenda Task), and detail-pane Table Group By v0.6.0 (rows reshuffle). **Triggers a confirmation dialog** listing N affected entities + effects.
- **Delete an option** — removes from group; **voids every entity that referenced the deleted `value` (sets to `.null`)**. Same rule for all option deletions (Multi-select strips only the deleted value from each entity's array instead of voiding). Confirm dialog lists affected count.
- **Add/remove a group** — not supported (3 slots structural; EventKit compat)

##### Sort behavior

**Group position first** (`upcoming < in_progress < done` ascending), then **option order within group**. Ascending puts Upcoming first; descending puts Done first.

##### Value storage

```yaml
properties:
  status: "in_progress"   # the option's canonical value
```

At render time the editor resolves value → option → group, yielding the displayed label + resolved color (option override or group default).

##### Where Status is built-in

Built-in **only on the AgendaTask schema** at v0.3.0. Status is NOT auto-seeded on Page Types, Item Types, or the AgendaEvent schema; users add it manually on those Types if wanted.

**AgendaTask schema** (`_taskconfig.json` on the Tasks singleton) — Status is built-in, required, non-deletable. EventKit sync (v0.6.0) maps the 3 groups to `EKReminder.isCompleted`:

| StatusGroup | `EKReminder.isCompleted` |
|---|---|
| `upcoming` | `false` |
| `in_progress` | `false` |
| `done` | `true` |

**AgendaEvent schema** (`_eventconfig.json` on the Events singleton) — Status is NOT built-in. Completion isn't an event concept; events derive their effective state from `start_at` / `end_at` relative to now. Users can add a Status property manually if a custom workflow is wanted, but no default is seeded.

#### Per-entity property panel visibility (wiring v0.3.0; UI later)

Each Page, Item, Agenda Task, and Agenda Event carries a per-entity **`panel_hidden_properties: [String]`** field controlling which Type-schema properties show in THIS entity's inspector / Item Window panel. Distinct from the Type's wide column visibility setting.

| Scope | Field | Effect |
|---|---|---|
| **Per-Type** | `<Type>.hidden_properties: [String]` (Type Settings → Property Visibility — set on PageType / ItemType / AgendaTaskSchema / AgendaEventSchema) | Hides column in the Type's detail-pane Table view |
| **Per-Entity** | `<entity>.panel_hidden_properties: [String]` (per-Page / per-Item / per-Agenda Task / per-Agenda Event — UI post-v0.3.0) | Hides property row in THIS entity's inspector / Item Window only |

**v0.3.0 ships the wiring; UI lands later.** Data model fields (`panel_hidden_properties` on PageFrontmatter / Item / AgendaTask / AgendaEvent), manager signatures (`PageContentManager.updatePageFrontmatter(_:, panelHiddenProperties: [String]?)` and parallels for ItemContentManager / AgendaTaskManager / AgendaEventManager), and validators are in place. The right-click "Hide property" + panel-footer "+ Add property" picker (lists currently-hidden to un-hide, plus "New property…" entry that opens the schema editor) lands in a follow-up patch. Hidden properties still exist on the entity, still hold values, still appear in the Table — per-entity hidden is purely a UI preference.

#### Content templates (post-v1 reservation)

**v0.3.0 does NOT ship templates.** Type-level templates (schema-seeding at creation) were rejected. Notion-style **content-level templates** (Page/Item templates pre-filling body + properties at creation) are reserved for post-v1. v0.3.0 keeps the scaffold compatible: `<nexus>/.nexus/templates/` reserved; no manager-method `template:` parameter is added until templates actually ship. A per-Item-Type `template_config` field is reserved on the Item Type's `_itemtype.json` (always `null` in v0.3.0; see [[Items]] and [[Prospects]]). Reservation summary at `// Planning//v0.3.0-Properties-spec.md` "Type templates rejected; content templates reserved".

#### Relation scope

Each Relation property targets exactly **one** container at creation time (Notion-style: same property = same target). For a second container, create a second Relation property. **Five scope kinds (four side-specific containers + one for Contexts), no fallback "anywhere" scope.**

Scope options stored in the `relation_scope` JSON object:

```json
{
  "kind": "page_type",
  "page_type_id": "01HPAGETYPEID..."
}
```

```json
{
  "kind": "item_type",
  "item_type_id": "01HITEMTYPEID..."
}
```

```json
{
  "kind": "page_collection",
  "page_collection_id": "01HPAGECOLLID..."
}
```

```json
{
  "kind": "item_collection",
  "item_collection_id": "01HITEMCOLLID..."
}
```

```json
{
  "kind": "context_tier",
  "tier": 2
}
```

| Scope kind | Picker source | Purpose | Bidirectional? |
|---|---|---|---|
| `page_type` | All Pages in the specified Page Type | Cross-Type relations on the Pages side (e.g., a Page in `Materials` relates to Pages in `Sources`) | **Required dual** — paired reverse property on the target Page Type's `_pagetype.json` |
| `item_type` | All Items in the specified Item Type | Cross-Type relations on the Items side (e.g., an Item in `Bookmarks` relates to Items in `People`) | **Required dual** — paired reverse property on the target Item Type's `_itemtype.json` |
| `page_collection` | All Pages in the specified Page Collection | Narrower than Page Type scope | **Required dual** — paired reverse property on the target Page Collection's parent Page Type (`_pagetype.json`) |
| `item_collection` | All Items in the specified Item Collection | Narrower than Item Type scope | **Required dual** — paired reverse property on the target Item Collection's parent Item Type (`_itemtype.json`) |
| `context_tier` | All Contexts at the specified tier (1=Spaces / 2=Topics / 3=Projects) | Categorical relations to organization-layer entities | **One-way** — no paired property (Contexts have no `properties[]` schema); reverse view derived via query, same as `tier1/2/3` backlinks |

Cross-side relations (Item ↔ Page) are NOT supported at v0.3.0 — Item-side Relation pickers list Item Types / Item Collections only; Page-side pickers list Page Types / Page Collections only. Cross-side promotion + relations are a post-v1 Prospect (see [[Prospects]]).

Pre-v0.3.3 SQLite: picker scans the relevant managers (acceptable at personal scale ~50 Topics, ~200 Pages, ~100 Items). v0.3.3 swaps to indexed lookup transparently.

#### Dual relations (mandatory for Type and Collection scopes)

Creating a Relation property targeting a Page Type, Item Type, Page Collection, or Item Collection is **always paired** — Pommora creates two property definitions, one on each side, synchronized. No opt-out. **RC-2026-05-19 refinement** — supersedes the earlier "optional toggle" framing.

Config shape inside the source Relation property:

```json
{
  "dual_property": {
    "synced_property_name": "Cited By",
    "synced_property_defined_on_type_id": "01HPAGETYPEID..."
  }
}
```

The reverse property in the target Type carries the mirror config pointing back. Both are paired by their `dual_property` references. The `synced_property_defined_on_type_id` field always points at a Page Type or Item Type (the parent Type) — never at a Collection directly, since Collection-scoped reverses are stored in the parent Type's per-kind sidecar (`_pagetype.json` or `_itemtype.json`).

**Lifecycle of a paired relation:**

- **Creation** — schema editor asks for BOTH names (source + target) at creation. Both definitions are added in a single SchemaTransaction two-phase commit; either write failing rolls back both.
- **Value setting** — setting a relation on Page A1 mirrors a back-reference on target Page B1; removing the relation removes both ends.
- **Renaming either side** — schema-only write that updates the OTHER side's `synced_property_name`. Paired identity survives.
- **Deleting either side** — dialog confirm ("Deleting this property will also remove '<reverseName>' from <Type X>. Continue?"). On confirm, BOTH definitions are deleted + mirrored values cleared both sides.
- **Moving a Page across Page Types (or an Item across Item Types) with a paired relation property** — strip rule applies: source's value goes; target side's reverse value loses the source's ULID.

**Constraint: dual relations are mandatory for the four container/sub-folder scopes (`page_type` / `item_type` / `page_collection` / `item_collection`) and unavailable for `context_tier`.** Context-tier scopes are one-way (Contexts have no per-tier `properties[]` schema). Schema editor omits the reverse-name prompt for `context_tier`. The reverse view is query-derived — same pattern as `tier1` / `tier2` / `tier3` backlinks.

#### Creating a Relation property — guided flow

Multi-step wizard (specifies both names + scope + target):

```
Example: User in Page Type Y wants to relate to Pages in Page Type X.

1. "+ Add property" in Page Type Y's schema editor
2. Pick type "Relation"
3. Pick scope kind: ◉ Page Type   ◯ Page Collection   ◯ Item Type   ◯ Item Collection   ◯ Context tier
4. Pick target: Page Type X (searchable list, filtered to the chosen scope kind)
5. Property name in THIS Type (Y):       "Sources"
6. Reverse property name in TARGET (X):  "Cited By"
7. Allow multiple values?  ✓ Yes
8. Save → atomically creates Page Type Y's "Sources" (relation → X) + Page Type X's "Cited By" (relation → Y).
```

Context-tier scope omits step 6 (one-way). Page Collection / Item Collection scopes show (Type, Collection) pairs as targets; the reverse property is stored in the parent Type's per-kind sidecar (`_pagetype.json` or `_itemtype.json`). Pickers stay side-locked — a Pages-side wizard never lists Item Types / Item Collections as targets, and vice versa.

#### Managing options (Select / Multi-select / Status)

Option creation, renaming, recoloring, deletion, and reorder happen **only via the schema editor** — never inline in the value picker. Notion's pattern.

Three paths to the option editor:

1. **Type Settings → Edit Properties → expand property → option list** — canonical. Drag-reorder, "+ Add option", per-option color picker, rename TextField, delete.
2. **Right-click a property value (pill / chip / status indicator)** in Page inspector / Item Window / detail-pane Table cell → "Edit options…".
3. **Right-click a Table column header** → "Edit property…" — same destination.

For Status, the editor also exposes per-group label TextFields + drag-between-groups across Upcoming / In Progress / Done. Value pickers display existing options only; each has a "**Manage options…**" link routing to Type Settings → Edit Properties.

#### Property options and sort order

For Select and Multi-select, **schema option order defines sort behavior** — drag-reorder in the option editor; ascending returns first-listed first. Example: `Status` Select with `[Awaiting, Active, Done]` — ascending puts `Awaiting` first; descending puts `Done` first. Replaces alphabetical sort (wrong for workflow stages) and is clearer than Notion's separate "manual sort" mode.

**Option `value` is immutable; `label` is renamable.** Each option carries canonical `value` (set at creation, never changes) and user-facing `label` (renamable). Stored frontmatter references `value`; renaming a `label` is schema-only. The option-level analog of Pommora's stable-target-with-renamable-display pattern (wikilinks resolve ID → current title; relations resolve `$rel` → current title; options resolve `value` → current `label`).

#### Schema-level option order vs view-level group order (forward-looking for v0.6.0)

Two orderings at different layers:

| Ordering | Stored in | Effect | Scope |
|---|---|---|---|
| **Schema-level option order** (Edit Properties → drag-reorder options) | Per-kind sidecar `properties[i].select_options[]` (or `status_groups[i].options[]` for Status) | Drives default sort behavior nexus-wide; **changes the property itself** | Schema (all views, all members of the Type) |
| **View-level group order** (a v0.6.0 saved view's Group By config — drag-reorder group sections in the view editor) | Per-kind sidecar `views[i].group_by.order: [String]` | Reorders section/folder headers IN THIS VIEW only; **doesn't touch the property** | View-only (one saved view at a time) |

Drag option sections in a Group By view = view-specific preference. Drag-reorder in Edit Properties = canonical schema change (affects every view + every sort). The two never collide — different fields. (Locked RC-2026-05-19.)

#### Property type compatibility with Group By (v0.6.0)

At v0.6.0 launch, **only single-value property types support Group By** in the detail-pane Table view (across Page Types, Item Types, AgendaTask, AgendaEvent):

| Type | Group By compatible? | Why / Why not |
|---|---|---|
| **Number** | ✓ | Each numeric value (or numeric range, v0.6.0-prep) becomes a group |
| **Select** | ✓ | Each option becomes a group (folder-like Table section) |
| **Status** | ✓ | Each option becomes a group; groups inherit Status group colors |
| **Date / Date & Time** | ✓ | Groups by day / week / month (config in view) |
| **Checkbox** | ✓ | Two groups: true / false |
| **URL** | ⚠ Not useful in practice | Technically single-value; grouping by URLs creates one group per URL (rarely meaningful) |
| **Relation** | ✓ | Each target entity becomes a group |
| **Multi-select** | ✗ NOT supported at v0.6.0 launch | An entity can have multiple values — ambiguous which group each row belongs to. Defer to a later patch with explicit duplicate-rendering semantics. |
| **Last Edited Time** | ✓ | Groups by day / week / month |

The Type Settings → Group By picker grays out / filters Multi-select. Post-v0.6.0: row-duplication-per-value rendering or "primary value only" grouping mode.

#### Sort and default sort

v0.3.0 ships sort-by-property in the Pages-side detail-pane Table view (`PageTypeDetailView`). Click a column header to sort; click again to reverse. Type-aware:

- **Number** — numeric ascending/descending
- **Checkbox** — false-first vs true-first
- **Date / Date & Time** — chronological (oldest first / newest first)
- **Last Edited Time** — chronological; **descending is the v0.3.0 default sort**
- **Select / Multi-select** — option order (see above)
- **URL** — alphabetical on `absoluteString`
- **Relation** — alphabetical on resolved current title of the target

Per-Type default sort persists in the Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json` / `_taskconfig.json` / `_eventconfig.json`) as a top-level `default_sort` (added v0.3.0). Full per-view sort with saved-view configs ships v0.6.0. Item Types and the AgendaTask / AgendaEvent schemas carry the same `default_sort` field; the Items-side detail UI lands in a follow-up plan.

#### Column order in views vs property declaration order

Three orderings, three layers:

- **Column order in a Table or List view** is view-level. Drag column headers to rearrange; stored in the view's spec inside the per-kind sidecar once v0.6.0 ships saved views. **Visual only — no schema effect.** Pre-v0.6.0: matches property declaration order.
- **Property declaration order in the per-kind sidecar** is schema-level — the order properties appear in the property panel. Drag-to-reorder lands v0.3.0.
- **Option order inside a Select / Multi-select** is schema-level — drives sort. Drag-to-reorder in the option editor.

#### Schema Mutations

User changes to a property's definition (v0.3.0):

- **Adding a property** — appears empty on every member; no file writes until a value is set.
- **Renaming a property** — schema rename + transactional rewrite across Type members (Page frontmatter / Item `properties` block / Agenda Task + Agenda Event `properties` blocks). Two-phase commit via `SchemaTransaction` in `AtomicIO//SchemaTransaction.swift`: write to `.tmp-<uuid>` siblings, then batch atomic-rename. On failure, rolls back + reports via `pendingError` (v0.2.0 sidebar toast pattern).
- **Changing a property's type** — only lossless conversions (Date → Date & Time, Select → Multi-select). Otherwise user must confirm; conflicting values are dropped.
- **Deleting a property** — schema row removed; values removed from every member. No quarantine — Notion-style.
- **Reordering properties** — drag-to-reorder; updates the Type's per-kind sidecar declaration order. No member writes (values are dictionary-keyed).
- **Editing Select / Multi-select options** — add / reorder / rename labels = schema-only. Deleting an option removes that value from members.

#### Moving Content Between Types

Moving a Page across Page Types (or an Item across Item Types) strips properties not in the destination schema (Notion-style). Confirmation warning lists what'll be stripped; user can cancel, add the property to the destination first, or accept. Pages always belong to one Page Type; Items always belong to one Item Type (no "loose" state in v1). Within the same Page Type, moving between Page Collection sub-folders is no-strip (shared schema); same applies for Items moving between Item Collections inside one Item Type. Cross-side promotion (Item → Page, Page → Item) is NOT supported at v0.3.0 — it's a post-v1 Prospect. No quarantine / orphan archive / undo-strip. **Ships v0.3.0** (pulled forward from v0.4.0; coupled to schema mutations).

#### Auto-Managed Properties

On every Page (frontmatter), Item (JSON), Agenda Task (JSON), and Agenda Event (JSON), not user-creatable:

- `id` — ULID assigned at creation, never changes
- `created_at`, `modified_at` — ISO-8601 timestamps maintained by Pommora

`id` and `created_at` appear at the bottom of the property panel (collapsed by default). `modified_at` is exposed as **Last Edited Time** at the top for sortability — same value, two surfacings.

Items, Agenda Tasks, and Agenda Events also carry one built-in field that isn't a property:

- `description` — plain-text, hard cap 250 characters. Not Markdown, not property-editable; rendered alongside the title in views.

(Filename plays the title role; no `name` field on any of these kinds.)

#### Validation

Enforced at every write to a Type's per-kind sidecar (schema-level) and to each member file (value-level):

**Schema-level (Page Type's `_pagetype.json` / Item Type's `_itemtype.json` / AgendaTask's `_taskconfig.json` / AgendaEvent's `_eventconfig.json`):**

1. Property name uniqueness within the Type (case-insensitive)
2. Property name non-empty, no reserved characters (`/`, `.`, leading underscore — reserves the per-kind sidecar filename prefix)
3. Reserved property names: `id`, `created_at`, `modified_at`, `tier1`, `tier2`, `tier3`, `wikilinks`
4. Dual relation requires `page_type` / `item_type` / `page_collection` / `item_collection` scope; `context_tier` scope rejected for dual
5. Relation scope target ULID (Page Type / Item Type / Page Collection / Item Collection) must resolve to a live entity at save time, and must be same-side (Pages-side schemas can't target Item Types / Item Collections, and vice versa)
6. Select / Multi-select: at least one option; option `value` uniqueness within property
7. Built-in `status` on the AgendaTask schema is non-deletable; not auto-seeded on the AgendaEvent schema, Page Types, or Item Types

**Value-level (Page frontmatter, Item `properties`, Agenda Task `properties`, Agenda Event `properties`):**

1. Every property value's shape matches its schema entry's type (`PageValidator.unknownProperty`, `propertyTypeMismatch`)
2. Relation `$rel` ULIDs must resolve to a live entity (warned, not enforced — broken-link semantics)
3. Select / Multi-select values must reference live option `value`s (cleaned up on schema mutation)

---

#### Full specification

v0.3.0 conceptual spec — locked decisions, catalog, scope rules, Status semantics, atomicity requirement — at `// Planning//v0.3.0-Properties-spec.md`. Implementation plan (phase-by-phase tasks, file:line citations, transaction class shapes, test coverage) at `// Planning//v0.3.0-Properties-plan.md`.
