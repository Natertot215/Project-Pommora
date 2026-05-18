### Properties

Detailed specification for Pommora's property system. Referenced from `PommoraPRD.md`.

---

#### Model

- **Property values** live in YAML frontmatter on each Page, in the `properties` key of each Item's `.json`, or in the `properties` key of each Agenda item's `.agenda.json` — directly editable by any text editor, any tool, or Claude.
- **Property schemas** live inside each Vault's `_vault.json` sidecar (canonical, file-based — agent-readable without going through SQLite). Agenda items use a parallel `_agenda.json` schema with one built-in property (`type` Select) plus user-extensible additions. SQLite mirrors schemas for fast queries; the JSON file is the source of truth.
- **Properties are scoped to a Vault** in v1 — every Page, Item, and Collection inside a Vault shares the Vault's schema. Same property name in two Vaults = two independent definitions. Collection-local schema overrides are a post-v1 Prospect.
- **The same property catalog works for all three Content kinds** — Pages, Items, Agenda items share the catalog. Storage substrate varies: Pages in YAML frontmatter, Items in JSON, Agenda items in JSON.
- **Per-tier multi-relations on Content** — Pages / Items / Agenda items each carry `tier1` / `tier2` / `tier3` multi-valued ID arrays pointing to Contexts. These are NOT user-defined properties — they're built-in fields on every Content entity, edited via the property panel's relation pickers.

#### How Properties Are Created

Properties are created on-demand from the page's property panel — same flow as Notion. The user clicks **+ Add property**, names it, and picks a type. Each type loads its own configuration controls. Once added, the property is registered in the Vault's schema and becomes available on every member (Pages + Items) of the Vault.

> **v0.2 status:** the schema editor UI is **not yet implemented** — Vaults ship with empty `properties: []` arrays in v0.2 and the Item Window correctly shows "No properties in this Vault's schema." per-Vault. The schema editor is on the v1.x roadmap; the flow below describes the eventual UX.

The flow:

1. **Add property** — from the property panel on any page in the Vault (or the Vault settings UI when that ships)
2. **Name it** — `Status`, `Due`, `Tags`, etc.
3. **Pick a type** — opens type-specific config (options for select, format for date, scope for relation, etc.)
4. **Save** — schema entry written to the Vault's `_vault.json` (source of truth) and mirrored to SQLite for fast queries; property appears on every member of the Vault
5. **Set value** — written to the Page's frontmatter (or Item's `properties` block, or Agenda item's `properties` block)

#### Property Type Catalog (v1)

Each type has a fixed config shape, stored as JSON inside the property's entry in the Vault's `_vault.json` `properties` array (or the Agenda schema's `_agenda.json` for Agenda items). The shape determines what the UI shows when the property is being edited and how the value is displayed. SQLite mirrors the schema for fast queries; the JSON file is the source of truth.

**The only pure text property is title** — and title is the Page's filename (or Item's filename), not a frontmatter property. All other properties are typed: number, date, checkbox, select, multi-select, etc. Where a Notion-style "text" field would appear, Pommora uses **Select** or **Multi-select** with creatable options (Notion's select behavior — typing a new label creates a new option in the catalog).

| Type | Value shape (frontmatter / JSON) | Config shape (SQLite) | UI behavior |
|---|---|---|---|
| **Number** | `number` | `{ format: "plain" \| "decimal" \| "percent" \| "currency", currencySymbol?: "$", precision?: 2 }` | Numeric input; rendered with the chosen format. |
| **Checkbox** | `boolean` | `{}` | Toggle. |
| **Date** | `"2026-06-15"` | `{ includeTime: false, format: "MMM D, YYYY" }` | Date picker. |
| **Date & Time** | `"2026-06-15T14:30"` | `{ includeTime: true, format: "MMM D, YYYY h:mm A" }` | Date + time picker. |
| **Select** | `"Active"` | `{ options: [{ value: "Active", color: "blue" }, ...] }` | Dropdown with colored pills. New options created inline by typing — text label becomes a new option in the catalog. Option order is user-defined (drag in the option editor) and defines sort behavior — see "Property options and sort order" below. |
| **Multi-select** | `["planning", "frontend"]` | `{ options: [...] }` | Tag-style multi-pick; new options created inline by typing. Same option-order-defines-sort behavior as Select. |
| **Relation** | `{"$rel": "01HXYZ..."}` or `[{"$rel": "01H..."}, {"$rel": "01H..."}]` (tagged-object form) | `{ scope?: "Projects//", multiple: true \| false }` | Picker scoped to the configured folder if `scope` is set, otherwise nexus-wide. **Stored as a tagged JSON object** `{"$rel": "<ULID>"}` (paradigm decision 2026-05-16) — not a bare string, so the encoding is unambiguous vs `.select` strings and graph-view indexers / external agents can identify relation edges without consulting Vault schema. **Displayed as the target's current title**, rendered as styled colored inline text (same look as wikilinks in body). The relation lookup resolves ID → current title at render time; rename a referenced Page and the relation's display updates automatically. |
| **URL** | `"https://..."` | `{}` | URL input; rendered as clickable link with favicon. |

**No separate `Status` type.** Status-like behavior is a Select property named "Status" with options like `Not started`, `In progress`, `Done`.

#### Property options and sort order

For Select and Multi-select properties, the **order of options in the schema defines sort behavior**. Options are an ordered list (drag-to-reorder in the property's option editor); ascending sort returns first-listed values first, descending returns last-listed values first.

Example: A `Status` Select with options `[Awaiting, Active, Done]` — sorting ascending puts `Awaiting` first; sorting descending puts `Done` first. To change sort priority, the user reorders the options themselves.

This replaces alphabetical sorting (which is wrong for things like statuses — "Awaiting" sorts before "Done" but you usually want them in workflow order) and is clearer than Notion's separate "manual sort" mode.

#### Column order in views vs property declaration order

Two different orderings, two different storage layers:

- **Column order in a Table or List view** is view-level config. Drag column headers in the view UI to rearrange; the order is stored in the view's spec inside `_vault.json`. **Visual only — no schema effect.** Different views on the same Vault can show columns in different orders.
- **Property declaration order in `_vault.json`** is schema-level — the order properties appear in the property panel for any member. No drag UI in v1; new properties are appended.
- **Option order inside a Select / Multi-select property** is schema-level — drives sort behavior as described above. Drag-to-reorder in the property's option editor.

#### Schema Mutations

What happens when a user changes a property's definition (lands when the schema editor ships, v1.x):

- **Adding a new property** — appears as empty on every member of the Vault; no file writes required until a value is set.
- **Renaming a property** — schema rename + a nexus-wide rewrite across the Vault's members (frontmatter for Pages, `properties` block for Items, `properties` block for Agenda items), using the same atomic-transaction pattern as wikilink renames.
- **Changing a property's type** — only allowed when the conversion is lossless (e.g., Date → Date & Time, or Select → Multi-select). Otherwise the user is prompted and must confirm; on confirm, conflicting values are dropped.
- **Deleting a property** — schema row removed; values removed from every member of the Vault. No backup or `_orphaned` quarantine — Notion-style: the property and its values are gone.

#### Moving Content Between Vaults

Moving a Page or Item from one Vault to another strips any properties not in the destination Vault's schema — Notion-style move-strip rule. **A simple confirmation warning** lists the properties that will be stripped before the move proceeds; the user can cancel, add the property to the destination Vault's schema first, or accept the strip.

Pages and Items always belong to exactly one Vault — there is no "loose" Content state in v1 (the typed Pages-collection / Items-collection split from the earlier 3-entity model is gone). Within the same Vault, moving Content between Collection sub-folders is a no-strip operation since Collections share the Vault's schema.

This keeps the model simple and matches user intuition from Notion — no quarantine, no orphan archives, no undo-the-strip-property semantics. **v0.2 status:** move-strip rule lands in v0.3 hardening; v0.2 does not implement cross-Vault moves yet.

#### Auto-Managed Properties

These fields exist on every Page (in frontmatter) and every Item (in its JSON entry) automatically and aren't user-creatable:

- `id` — ULID assigned at file/entry creation, never changes
- `created_at`, `modified_at` — UNIX timestamps maintained by Pommora

These appear in the property panel at the bottom (collapsed by default).

Items also carry one additional built-in field that isn't a user-defined property but is part of the Item entity:

- `description` — short plain-text field for one-line context. Not Markdown, not editable as a property; rendered alongside the title in views.

(Filename plays the title role for both Pages and Items — no separate `name` field.)
