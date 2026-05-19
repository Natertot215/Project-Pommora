### Properties

Detailed specification for Pommora's property system. Referenced from `PommoraPRD.md`. v0.3.0 implementation spec at `// Planning//v0.3.0-Properties-implementation.md`.

---

#### Model

- **Property values** live in YAML frontmatter on each Page, in the `properties` key of each Item's `.json`, or in the `properties` key of each Agenda item's `.agenda.json` — directly editable by any text editor, any tool, or Claude.
- **Property schemas** live inside each Vault's `_vault.json` sidecar (canonical, file-based — agent-readable without going through SQLite). Agenda items use a parallel `_agenda.json` schema with one built-in property (`type` Select) plus user-extensible additions. SQLite (v0.3.3) mirrors schemas for fast queries; the JSON file is the source of truth.
- **Properties are scoped to a Vault** in v1 — every Page, Item, and Collection inside a Vault shares the Vault's schema. Same property name in two Vaults = two independent definitions. Collection-local schema overrides are a post-v1 Prospect.
- **The same property catalog works for all three Content kinds** — Pages, Items, Agenda items share the catalog. Storage substrate varies: Pages in YAML frontmatter, Items in JSON, Agenda items in JSON.
- **Per-tier multi-relations on Content** — Pages / Items / Agenda items each carry `tier1` / `tier2` / `tier3` multi-valued ID arrays pointing to Contexts. These are NOT user-defined properties — they're built-in fields on every Content entity, edited via the property panel's relation pickers alongside user-defined properties.
- **Property names are the key.** Renaming a property triggers a transactional cross-member rewrite (`_vault.json` + every Page's frontmatter + every Item's `properties` block, atomic via two-phase commit). The legibility benefit (frontmatter keys are human-readable; agents can read values without consulting the schema) outweighs the rewrite cost. Stable opaque property IDs were considered and rejected.
- **Every property can carry an icon.** Optional `icon: String?` (SF Symbol name) on `PropertyDefinition`. Displayed next to the property name in the schema editor list, in the property panel rows, and as the column header glyph in Vault Table views. Settable via per-property `IconPickerField` in the schema editor (reuses the existing SymbolPicker integration).

#### How Properties Are Created

Properties are created from the **Vault Settings sheet** — the central edit surface for everything about a Vault, including its property schema. The sheet has six sections (Edit Properties / Sort / Filter / Group By / Layout / Property Visibility); the Properties section hosts the schema editor.

The Vault Settings sheet is reached from:
- VaultDetailView toolbar gear button
- Vault row right-click → "Vault Settings…"
- "+ Property" column header in Vault Table view (jumps directly to Edit Properties section + "Add property" flow)
- Column header right-click in Vault Table → "Edit property…" (jumps to the relevant row)

The Add Property flow:

1. **Add property** — "+ Add property" button in Vault Settings → Edit Properties section, OR "+" column header in Vault Table view
2. **Name it** — `Status`, `Due`, `Tags`, etc.
3. **Pick an icon** (optional) — `IconPickerField` for an SF Symbol; shown next to the name everywhere the property is rendered
4. **Pick a type** — opens type-specific config (options for Select, format for Number, scope + reverse name for Relation, 3-group editor for Status, etc.)
5. **Save** — schema entry written to the Vault's `_vault.json`; property appears as an empty value on every member of the Vault (for paired Relation properties, the reverse property is also added to the target Vault atomically)
6. **Set value** — written to the Page's frontmatter, the Item's `properties` block, or the Agenda item's `properties` block via `PropertyEditorRow` in the inspector / Item Window

Full Vault Settings UI spec → `// Features//Vaults.md` "Vault Settings sheet" section.

#### Property Type Catalog (v0.3.0)

Each type has a fixed config shape, stored as JSON inside the property's entry in the Vault's `_vault.json` `properties` array (or the Agenda schema's `_agenda.json` for Agenda items). The shape determines what the UI shows when the property is being edited and how the value is displayed.

**The only pure text property is title** — and title is the Page's filename (or Item's filename), not a frontmatter property. All other properties are typed: number, date, checkbox, select, multi-select, etc. Where a Notion-style "text" field would appear, Pommora uses **Select** or **Multi-select** with creatable options (typing a new label creates a new option in the catalog).

| Type | Value shape (frontmatter / JSON) | Config shape (`_vault.json`) | UI behavior |
|---|---|---|---|
| **Number** | `42` or `3.14` | `{ "number_format": "integer" \| "decimal" \| "percent" \| "currency" }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `true` / `false` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{}` | Date picker, date-only. UTC-anchored on disk. |
| **Date & Time** | `"2026-06-15T14:30:00Z"` (ISO-8601 with timezone) | `{}` | Date + time picker. |
| **Select** | `"Active"` (the option's `value`) | `{ "select_options": [{ "value": "active", "label": "Active", "color": "blue" }, ...] }` | Dropdown picker over the existing options, with colored pills. Option `value` is canonical (immutable post-create); `label` can be renamed freely without rewriting member values. Option order is user-defined (drag in the option editor) and defines sort behavior — see "Property options and sort order" below. **Options are NOT created by typing into the value picker** — see "Managing options" below. |
| **Multi-select** | `["planning", "frontend"]` (option `value`s) | `{ "select_options": [...] }` (same shape as Select — `value`/`label`/`color` per option) | Tag-style multi-pick with `MultiSelectChips`; **each chip renders with its option's color** (same 9-color Notion palette as Select); same option-order-defines-sort behavior as Select. **Options are NOT created by typing into the picker.** |
| **Status** | `"in_progress"` (the option's canonical `value`) | `{ "status_groups": [{ "id": "awaiting", "label": "Awaiting", "color": "gray", "options": [...] }, ...] }` (3 fixed groups: `awaiting` / `in_progress` / `done`; each contains user-editable options) | **Notion-parity workflow property.** Grouped picker popover with 3 sections; one option selected at a time. Pill renders with the resolved color (option's `color` override > group's `color`). Group LABELS user-renamable; group SLOTS structurally fixed. Sort by Status = group position first, then option order within group. **Options are NOT created by typing into the picker.** See "Status property type" section below. |
| **URL** | `"https://..."` | `{}` | URL input; rendered as clickable link with favicon. |
| **Relation** | `{"$rel": "01HXYZ..."}` (single) or `[{"$rel": "01H..."}, ...]` (multi) | `{ "relation_scope": {...}, "allows_multiple": true \| false, "dual_property": {...}? }` | Scope-aware picker popover — see "Relation scope" + "Dual relations" below. **Stored as a tagged JSON object** `{"$rel": "<ULID>"}` so external agents and the graph-view indexer can identify cross-entity edges from any single file without consulting Vault schema. **Displayed as the target's current title** — rendered as styled colored inline text (same look as wikilinks). The lookup resolves ID → current title at render time; rename a referenced Page and the relation's display updates automatically. |
| **Last Edited Time** | *(not stored as a property value)* | `{}` | Auto-derived from each member's `modified_at` field. Read-only. Sortable. Useful for "most recently edited first" in Vault Tables — set as the default sort at v0.3.0. |

**Status is now a first-class type** (was previously folded into Select with a workflow-naming convention; Status as a distinct type locked RC-2026-05-19). With Status carrying the 3-group workflow structure, Selects are now exclusively free-form labels. Use Status for any "where in a process is this?" property.

**Wikilinks are NOT a property type.** Body-text wikilinks (`[[Title]]`) ship at v0.3.2 with their own derived `wikilinks: [...]` frontmatter mirror — derived from body scan, not user-edited via the schema editor. The schema editor does not offer Wikilink as a creatable type.

#### Status property type

The Status type ships v0.3.0 as a workflow property with **3 EventKit-aligned structural groups**. Each group contains **user-editable options**. Single-pick on a Page/Item/Agenda value.

##### The 3 fixed groups (EventKit-aligned)

| Group ID | Default label | Default color | EventKit meaning |
|---|---|---|---|
| `upcoming` | "Upcoming" | gray | `EKReminder.isCompleted = false` + due-date-future; `EKEvent` with future start_at |
| `in_progress` | "In Progress" | blue | Reminders actively due / events currently happening |
| `done` | "Done" | green | `EKReminder.isCompleted = true`; events in the past |

**Group IDs are load-bearing in code; group LABELS are user-renamable.** A user can rename "Upcoming" → "Queued" or "Backlog" — the structural `upcoming` ID stays. The three structural slots themselves are fixed — **adding a 4th group or removing one is not supported** because doing so would break EventKit compatibility at v0.7.0 (no clean mapping target).

User customization of workflow happens by **adding options within groups** ("Backlog", "Queued", "Triaged" all inside Upcoming) — not by inventing new groups.

##### Options within groups

Each group contains an ordered list of user-editable options. Each option has:

- `value` — canonical key, immutable post-create (stored entity-level values reference this)
- `label` — user-facing, renamable freely
- `color` — optional override; nil means inherit the group's color
- `group_id` — which group this option belongs to (load-bearing — drives sort + EventKit + display)

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
- **Move an option between groups** — **DATA-SEMANTIC change** despite being a schema-only file write. Rewrites the option's `group_id` field. The option's `value` stays the same (stored entity-level frontmatter `status: "<value>"` still resolves). But this op affects:
  - Sort behavior — entities with that option now sort according to the NEW group's position
  - Display color — entities show the new group's pill color
  - EventKit mapping (v0.7.0) — flips. Moving from "In Progress" → "Done" flips `EKReminder.isCompleted` from false → true on every Agenda item referencing that option
  - Vault Table grouping (v0.6.0 Group By feature) — entities reshuffle visually
  - **Triggers a confirmation dialog** before commit listing the N affected entities + the downstream effects
- **Delete an option** — removes from group; **voids every entity that referenced the deleted `value` (sets to `.null`)**. Same rule applies to all property-option deletions across types (Select, Status, Multi-select where Multi-select removes only the deleted value from each entity's array instead of voiding the whole property). Confirmation dialog lists affected entity count.
- **Add/remove a group** — not supported (3 groups structural; preserves EventKit compatibility)

##### Sort behavior

Status sort uses **group position first** (`upcoming < in_progress < done` ascending), then **option order within group**. Sorting by Status ascending puts everything in Upcoming first, then In Progress, then Done — matching workflow intuition. Descending reverses to Done first.

##### Value storage

```yaml
properties:
  status: "in_progress"   # the option's canonical value
```

At render time, the editor resolves the value → option → group, giving the displayed label + the resolved color (option override or group default).

##### Where Status is built-in

Status is built-in **only on Agenda** at v0.3.0. There are no Vault-level templates seeding Status into Vaults — users add Status manually if they want it on a Vault's Pages/Items.

**Agenda items** (`<nexus>/Agenda/_agenda.json`) — Status is a built-in property, required and non-deletable. EventKit sync (ships v0.7.0) maps the 3 groups to `EKEvent.status` and `EKReminder.isCompleted`:

| StatusGroup | `EKEvent.status` | `EKReminder.isCompleted` |
|---|---|---|
| `upcoming` | `.tentative` (future-dated) | `false` |
| `in_progress` | `.confirmed` (currently happening) | `false` |
| `done` | `.confirmed` (past) | `true` |

#### Per-entity property panel visibility (wiring v0.3.0; UI later)

Each Page, Item, and Agenda item carries a per-entity **`panel_hidden_properties: [String]`** field controlling which Vault-schema properties show in THIS entity's inspector / Item Window panel. Distinct from `Vault.hidden_properties` (which is Vault-wide and controls Table column visibility).

**Two visibility scopes, never confused:**

| Scope | Field | Effect |
|---|---|---|
| **Per-Vault** | `Vault.hidden_properties: [String]` (set via Vault Settings → Property Visibility section) | Hides column in Vault Table view |
| **Per-Entity** | `<entity>.panel_hidden_properties: [String]` (per-Page / per-Item / per-Agenda — UI ships post-v0.3.0) | Hides property row in THIS entity's inspector / Item Window only |

**v0.3.0 ships the wiring; UI lands later.** The data model fields (`panel_hidden_properties` on PageFrontmatter / Item / AgendaItem), the manager method signature support (`ContentManager.updatePageFrontmatter(_:, panelHiddenProperties: [String]?)` and parallel for Items), and the validator are all in place at v0.3.0. The right-click "Hide property" affordance + the panel-footer "+ Add property" picker (showing currently-hidden properties to un-hide, plus a "New property…" entry that opens the schema editor) land in a follow-up patch.

The Vault's shared schema is unaffected by per-entity visibility — hidden properties still exist on the entity, still hold values (if set), still appear in the Vault Table. Per-entity hidden is purely a UI preference of the property panel surface.

#### Content templates (post-v1 reservation)

**v0.3.0 does NOT ship templates.** Vault-level templates (seeding a Vault's schema at creation) were considered and rejected. Notion-style **content-level templates** — Page templates, Item templates, etc. that pre-populate body + properties at content creation time — are reserved for post-v1.

v0.3.0 keeps the data scaffold compatible: a `<nexus>/.nexus/templates/` directory is reserved for future per-template definitions, and `ContentManager.createPage(...)` / `createItem(...)` signatures accept an optional `template: ContentTemplate? = nil` parameter (always nil v0.3.0). When templates land post-v1, they slot in additively — no rewrite needed.

Full reservation spec at `// Planning//v0.3.0-Properties-implementation.md` "Content templates (post-v1 reservation)" section.

#### Relation scope

Each Relation property targets exactly **one** container at creation time. Notion-style: same property = same target. To relate to a second container, create a second Relation property. **Three scope kinds, no fallback "anywhere" scope** — every Relation has a definite target.

Scope options stored in the `relation_scope` JSON object:

```json
{
  "kind": "vault",
  "vault_id": "01HVAULTID..."
}
```

```json
{
  "kind": "collection",
  "collection_id": "01HCOLLECTIONID..."
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
| `vault` | All Pages + Items in the specified Vault | Cross-Vault relations (e.g., a Page in `Materials` relates to Items in `Wishlist`) | **Required dual** — paired reverse property on target Vault |
| `collection` | All Pages + Items in the specified Collection | Narrower than Vault scope | **Required dual** — paired reverse property on target Collection (stored in its parent Vault's `_vault.json`) |
| `context_tier` | All Contexts at the specified tier (1=Spaces / 2=Topics / 3=Sub-topics) | Categorical relations to organization-layer entities | **One-way** — no paired property (Contexts have no `properties[]` schema); reverse view derived via query, same as `tier1/2/3` backlinks |

Pre-v0.3.3 SQLite: picker uses naive scan over the relevant managers (acceptable at personal scale ~50 Topics, ~200 Pages, ~100 Items). v0.3.3 swaps in indexed lookup transparently — the picker UI doesn't change.

#### Dual relations (mandatory for Vault/Collection scopes)

Creating a Relation property that targets a Vault or Collection is **always a paired operation** — Pommora creates two property definitions, one on each side, kept synchronized. There is no opt-out: a Vault→Vault relation with no reverse property doesn't exist as a concept in Pommora's model. **RC-2026-05-19 refinement** — supersedes the earlier "dual relations are an optional toggle" framing.

Config shape inside the source Relation property:

```json
{
  "dual_property": {
    "synced_property_name": "Cited By",
    "synced_property_defined_on_vault_id": "01HVAULTID..."
  }
}
```

The reverse property in the target Vault carries the mirror config pointing back. Both properties are paired by their `dualProperty` references.

**Lifecycle of a paired relation:**

- **Creation** — the schema editor asks for BOTH names (in source + in target) at the moment of creation. Both property definitions are added to their respective Vaults in a single transactional commit (SchemaTransaction two-phase). If either write fails, both roll back — a half-created pair can't exist.
- **Value setting** — setting a relation value on Page A1 (in source Vault) automatically mirrors a back-reference on the target Page B1. The target's reverse-property value gains A1's ULID; removing the relation removes both ends.
- **Renaming either side** — schema-only write that also updates the OTHER side's `synced_property_name`. The paired identity survives the rename.
- **Deleting either side** — confirmed via dialog ("Deleting this property will also remove '<reverseName>' from <Vault X>. Continue?"). On confirm, BOTH property definitions are deleted + all mirrored values cleared from members on both sides.
- **Moving a Page across Vaults with a paired relation property** — strip rule applies: the source's relation value goes; the target side's reverse value gets the source's ULID removed.

**Constraint: dual relations only work for Vault/Collection scopes.** Context-tier scopes are inherently one-way because Contexts don't have a per-tier `properties[]` schema — there's nowhere on the target side to add a reverse property. The schema editor doesn't show the "reverse name" prompt when scope kind is `context_tier`. The "reverse view" of Context-scoped relations is derived via query — same pattern as the existing `tier1` / `tier2` / `tier3` backlinks today.

#### Creating a Relation property — guided flow

The schema editor handles Relation properties as a multi-step wizard (because the user must specify both names + scope + target):

```
Example: User in Vault Y wants to relate to entries in Vault X.

Step 1 ─ "+ Add property" in Vault Y's schema editor
Step 2 ─ Pick type "Relation"
Step 3 ─ Pick scope kind: ◉ Vault   ◯ Collection   ◯ Context tier
Step 4 ─ Pick target: Vault X (searchable list)
Step 5 ─ Property name in THIS Vault (Y):     "Sources"
Step 6 ─ Reverse property name in TARGET (X): "Cited By"
Step 7 ─ Allow multiple values?  ✓ Yes
Step 8 ─ Save → atomically creates BOTH:
           - Vault Y's schema gains "Sources" (relation → X)
           - Vault X's schema gains "Cited By" (relation → Y)
```

For Context-tier scope, steps 6 and the entire reverse-name input are omitted — those relations are one-way.

For Collection scope, the target picker shows (Vault, Collection) pairs and the reverse property is added to the Vault that owns the target Collection.

#### Managing options (Select / Multi-select / Status)

Option creation, renaming, recoloring, deletion, and reorder happen **only via the schema editor** — never inline by typing into the value picker. This is Notion's pattern: the value picker is for picking from existing options; the schema editor is for managing what those options are.

Three paths reach the option editor for any Select / Multi-select / Status property:

1. **Vault Settings → Edit Properties → expand property → option list** — the canonical surface. Drag-to-reorder, "+ Add option" button, per-option color picker, rename TextField, delete button.
2. **Right-click any property value (pill, chip, status indicator) in a Page inspector / Item Window / Vault Table cell** → "Edit options…" — shortcut that opens Vault Settings sheet directly at this property's option editor.
3. **Right-click a column header in Vault Table view** → "Edit property…" — same shortcut routed through the column header.

For Status specifically, the option editor also exposes the per-group label TextFields + drag-between-groups for moving options between Awaiting / In Progress / Done.

Value pickers (Select dropdown, Multi-select chips, Status grouped popover) display only existing options. Each picker has a "**Manage options…**" link at the bottom that opens Vault Settings → Edit Properties at the relevant property — same destination as right-click → "Edit options…".

#### Property options and sort order

For Select and Multi-select properties, the **order of options in the schema defines sort behavior**. Options are an ordered list (drag-to-reorder in the property's option editor); ascending sort returns first-listed values first, descending returns last-listed values first.

Example: A `Status` Select with options `[Awaiting, Active, Done]` — sorting ascending puts `Awaiting` first; sorting descending puts `Done` first. To change sort priority, the user reorders the options themselves.

This replaces alphabetical sorting (which is wrong for things like statuses — "Awaiting" sorts before "Done" but you usually want them in workflow order) and is clearer than Notion's separate "manual sort" mode.

**Option `value` is immutable; `label` is renamable.** Internally each option carries a canonical `value` (set at creation, never changes) and a user-facing `label` (renamable freely). Stored frontmatter values reference the `value`. Renaming an option's `label` requires no member rewrite — only the schema entry updates. This is the option-level analog of Pommora's stable-target-with-renamable-display pattern (wikilinks resolve ID → current title; relations resolve `$rel` → current title; Select options resolve `value` → current `label`).

#### Schema-level option order vs view-level group order (forward-looking for v0.6.0)

Two distinct orderings drive sort + group behavior, and they live at different layers:

| Ordering | Stored in | Effect | Scope |
|---|---|---|---|
| **Schema-level option order** (Edit Properties → drag-reorder options) | `_vault.json.properties[i].select_options[]` (or `status_groups[i].options[]` for Status) | Drives default sort behavior nexus-wide; **changes the property itself** | Schema (all views, all members of the Vault) |
| **View-level group order** (a v0.6.0 saved view's Group By config — drag-reorder group sections in the view editor) | `_vault.json.views[i].group_by.order: [String]` | Reorders section/folder headers IN THIS VIEW only; **doesn't touch the property** | View-only (one saved view at a time) |

The user can drag option sections in a Group By view to reorder them — that's a view-specific preference. Drag-reordering in Edit Properties is the canonical schema change — affects every view + every sort everywhere. The two paths NEVER collide because they write to different fields. (The "Group By → sort variables is view-specific; Edit Properties → re-arrange variables impacts the property" distinction was locked RC-2026-05-19.)

#### Property type compatibility with Group By (v0.6.0)

When v0.6.0 Vault Views ship with the Group By feature, **only single-value property types support grouping** — for simplicity at launch:

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

This compatibility filter applies to the Vault Settings → Group By picker: Multi-select properties are grayed out / filtered out. Future enhancement (post-v0.6.0): support Multi-select with row-duplication-per-value rendering, or "primary value only" grouping mode.

#### Sort and default sort

v0.3.0 ships sort-by-property in the Vault Table view (`VaultDetailView`). Click any column header to sort by that property; click again to reverse direction. Sort behaves type-aware:

- **Number** — numeric ascending/descending
- **Checkbox** — false-first vs true-first
- **Date / Date & Time** — chronological (oldest first / newest first)
- **Last Edited Time** — chronological; **descending is the v0.3.0 default sort**
- **Select / Multi-select** — option order (see above)
- **URL** — alphabetical on `absoluteString`
- **Relation** — alphabetical on resolved current title of the target

Per-Vault default sort persists in `_vault.json` as a new top-level field `default_sort` (added in v0.3.0). The full per-view sort with saved-view configurations lands at v0.6.0 alongside the five view types — v0.3.0 ships only the per-Vault default.

#### Column order in views vs property declaration order

Two different orderings, two different storage layers:

- **Column order in a Table or List view** is view-level config. Drag column headers in the view UI to rearrange; the order is stored in the view's spec inside `_vault.json` once v0.6.0 ships saved views. **Visual only — no schema effect.** Different views on the same Vault can show columns in different orders. Pre-v0.6.0: column order in the Vault Table view matches property declaration order.
- **Property declaration order in `_vault.json`** is schema-level — the order properties appear in the property panel for any member. Drag-to-reorder in the schema editor lands at v0.3.0.
- **Option order inside a Select / Multi-select property** is schema-level — drives sort behavior as described above. Drag-to-reorder in the property's option editor.

#### Schema Mutations

What happens when a user changes a property's definition (ships v0.3.0):

- **Adding a new property** — appears as empty on every member of the Vault; no file writes required until a value is set.
- **Renaming a property** — schema rename + a transactional rewrite across the Vault's members (frontmatter for Pages, `properties` block for Items, `properties` block for Agenda items). Two-phase commit via `SchemaTransaction` in `AtomicIO//SchemaTransaction.swift`: write all new content to `.tmp-<uuid>` siblings, then atomic-rename in batch. On failure, rolls back to the original `_vault.json` + reports via `pendingError` (v0.2.0 sidebar toast pattern).
- **Changing a property's type** — only allowed when the conversion is lossless (Date → Date & Time, or Select → Multi-select). Otherwise the user is prompted and must confirm; on confirm, conflicting values are dropped.
- **Deleting a property** — schema row removed; values removed from every member of the Vault. No backup or `_orphaned` quarantine — Notion-style: the property and its values are gone.
- **Reordering properties** — drag-to-reorder in the schema editor; updates `_vault.json` declaration order. No member writes needed (values are dictionary-keyed, not order-dependent).
- **Editing Select / Multi-select options** — adding / reordering / renaming labels = schema-only write (no member rewrite). Deleting an option = removes that value from any members that held it.

#### Moving Content Between Vaults

Moving a Page or Item from one Vault to another strips any properties not in the destination Vault's schema — Notion-style move-strip rule. **A simple confirmation warning** lists the properties that will be stripped before the move proceeds; the user can cancel, add the property to the destination Vault's schema first, or accept the strip.

Pages and Items always belong to exactly one Vault — there is no "loose" Content state in v1 (the typed Pages-collection / Items-collection split from the earlier 3-entity model is gone). Within the same Vault, moving Content between Collection sub-folders is a no-strip operation since Collections share the Vault's schema.

This keeps the model simple and matches user intuition from Notion — no quarantine, no orphan archives, no undo-the-strip-property semantics. **Ships v0.3.0** alongside Properties (was deferred to v0.4.0 in earlier roadmap; pulled forward because move-strip is tightly coupled to property schema mutations).

#### Auto-Managed Properties

These fields exist on every Page (in frontmatter) and every Item (in its JSON entry) automatically and aren't user-creatable:

- `id` — ULID assigned at file/entry creation, never changes
- `created_at`, `modified_at` — ISO-8601 timestamps maintained by Pommora

`id` and `created_at` appear in the property panel at the bottom (collapsed by default). `modified_at` is exposed as the **Last Edited Time** property type at the top of the panel for sortability — same value, two surfacings.

Items also carry one additional built-in field that isn't a user-defined property but is part of the Item entity:

- `description` — short plain-text field for one-line context. Hard cap 250 characters. Not Markdown, not editable as a property; rendered alongside the title in views.

(Filename plays the title role for both Pages and Items — no separate `name` field.)

#### Validation

Enforced at every write to `_vault.json` (schema-level) and to each member file (value-level):

**Schema-level (`_vault.json`):**

1. Property name uniqueness within Vault (case-insensitive)
2. Property name non-empty, no reserved characters (`/`, `.`, leading underscore — reserves `_vault.json` / `_collection.json` prefix)
3. Reserved property names: `id`, `created_at`, `modified_at`, `tier1`, `tier2`, `tier3`, `wikilinks`
4. Dual relation requires Vault or Collection scope (Context-tier rejected)
5. Relation scope target (Vault ULID, Collection ULID) must resolve to a live entity at save time
6. Select / Multi-select: at least one option; option `value` uniqueness within property

**Value-level (Page frontmatter, Item `properties`, Agenda `properties`):**

1. Every property value's shape matches its schema entry's type (`PageValidator.unknownProperty`, `propertyTypeMismatch`)
2. Relation `$rel` ULIDs must resolve to a live entity (warned, not enforced — broken-link semantics)
3. Select / Multi-select values must reference live option `value`s (cleaned up on schema mutation)

---

#### Full specification

Complete implementation spec for v0.3.0 — including phase-by-phase task list, file:line citations, transaction model, and test coverage — lives at `// Planning//v0.3.0-Properties-implementation.md`.
