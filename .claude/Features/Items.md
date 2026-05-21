### Items

An Item is a **row-shaped record** stored as a `.json` file: properties + relations + a 250-char plain-text description, opened in an **Item window** (popover, Calendar-event-detail pattern). For database entries that don't warrant a full Page — wishlist, contacts, references, citations, music releases, recipes-as-rows. No Markdown body.

Items solve the Notion problem of every database row being a full page — by keeping Pages (prose-bearing) and Items (row-shaped) as separate file types that coexist inside the same Vault.

**Tasks and calendar events are NOT Items in v1** — they're **Agenda items** (`.agenda.json`) with EventKit integration. See `Agenda.md`.

Items live inside a Vault or Collection sub-folder. Vaults are kind-agnostic — Pages and Items coexist under the shared schema.

---

#### On disk

**One `.json` file per Item.** Filename = title. Lives in the Vault folder or a Collection sub-folder. No aggregate file.

```
Materials/                  ← Vault
  _vault.json               ← shared schema
  Documents/                ← Collection (sub-folder)
    Annual-report.json      ← Item conforming to Vault schema
  Bookmark.json             ← Item directly in Vault (no Collection sub-folder)
```

Renaming in UI renames the file. Inbound relations stay intact (by `id`, not name).

Each Item file holds:

- `id` — ULID, stable across renames
- `description` — plain text, **hard cap 250 chars**. Fits in the Item window without scrolling.
- `icon` — optional, same catalog as Pages
- `properties` — values conforming to the Vault schema
- `tier1` / `tier2` / `tier3` — per-tier multi-valued relation arrays to Contexts. Independent per tier.
- `created_at` / `modified_at` — UNIX timestamps

No `name` field — filename IS the name.

---

#### When to use Items vs Pages vs Agenda

The decision is per-entry now (Vaults are kind-agnostic):

- **Item** — row-shaped data without prose: contacts, wishlist, bookmarks, citations, music releases, recipes-as-rows, references. Opens in Item Window popover.
- **Page** — prose-bearing content: notes, papers, project briefs, journal entries, reading reports. Opens in the main detail pane with the editor.
- **Agenda item** — calendar-anchored (tasks, events, to-dos, phases). Lives in `<nexus>/Agenda/`, NOT in a Vault. EventKit-integrable. See `Agenda.md`.

If an Item later needs prose, the user creates a Page (in the same Vault or another) and links the two by ID. No in-place promotion in v1 (see `Prospects.md`).

---

#### Capabilities

- Hold typed properties from the parent Vault's schema (same catalog as Pages; full type list → `Properties.md`)
- Hold typed relations to any other entity in the Nexus (Pages, Items, Agenda items, Contexts, Vaults) by ID — rename-safe
- Appear in any Vault view (table / board / list / cards / gallery)
- Relate to Contexts via `tier1` / `tier2` / `tier3` multi-relation fields — surface on those Contexts' composed pages via embedded views
- Be linked-to from a Context page's link-list widget, an embedded Collection view, or wikilinks in body content

---

#### Sidebar visibility

**Items do NOT appear in the sidebar.** They live in detail-pane Tables (`VaultDetailView` hierarchical; `CollectionDetailView` flat). Sidebar shows the structural / Page-shaped view only. Paradigm decision 2026-05-17 — same rule applies to Agenda items and Events.

#### Item window

Items open in a popover-style floating surface anchored to the trigger (row click, cell, wikilink, embedded row). Reference: Calendar.app event-detail popover; Finder's Get Info. Not a tab, not a full page, not the inspector. Contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Icon** — optional SF Symbol, editable via TextField (curated SymbolPicker UI deferred to a polish pass; current sheet supports manual entry).
- **Properties** — typed inputs for each property in the parent Vault's schema (via `PropertyEditorRow` dispatching to per-type controls: TextField for number/url, Toggle for checkbox, DatePicker for date/datetime, Picker for select, `MultiSelectChips` for multi-select; relation editor + tier1/2/3 chip pickers land v0.3.0).
- **Description** — plain-text field, **hard cap 250 characters**. Sized to fit the window without scrolling; keeps the JSON file small and cloud-sync-friendly.
- **Tier 1 / Tier 2 / Tier 3 relations** — read-only ULID display in v0.2; full relation picker UI lands v0.3.0 (shared `ContextTierPicker` component with Pages inspector).
- **Meta footer** — `id`, `created_at`, `modified_at` read-only.

Dismissed by clicking Done, pressing Esc, or closing the window. Save commits via `ContentManager.updateItem` (with a `renameItem` pre-step if the title changed). No body, no blocks, no `@Columns`. If the entry needs a body, it should be a Page.

---

#### Item window — design evolution (v0.3.1)

Nathan-sketched 2026-05-17. Supersedes the v0.2 popover at v0.3.1, immediately after v0.3.0 Properties. v0.3.0 ships properties into the existing popover; v0.3.1 reshapes around them.

**Layout:** modal window (not popover) with a `New Item` / item-title header, two-column body, footer with Delete + Save.

```
┌─ New Item ────────────────────────────────  ▣ ▣ ─┐
│                                                   │
│  ┌─────────────────────────┐  Property…    ▼     │
│  │                         │  Property…    ▼     │
│  │  description / notes    │  Property…    ▼     │
│  │  (large multi-line      │  Property…    ▼     │
│  │   text area, can hold   │                     │
│  │   up to the 250-char    │                     │
│  │   description; visually │                     │
│  │   prominent)            │                     │
│  │                         │                     │
│  └─────────────────────────┘                     │
│                                                   │
│  Delete (red)                       [ Save ]      │
└───────────────────────────────────────────────────┘
```

**Region-by-region:**

- **Title bar** — `New Item` (create) / item title (edit). Editable in place via `ContentManager.renameItem`.
- **Top-right action buttons** — icon picker + view-toggle (compact-vs-expanded). Exact actions TBD; SymbolPicker integration retires the TextField fallback per paradigm decision #3.
- **Left column — description/notes body** — large multi-line text area; 250-char cap retained. NOT a Markdown editor (Pages exist for that).
- **Right column — properties** — stacked dropdown pickers, one per Vault property. `PropertyEditorRow` dispatch per type. Replaces the popover's vertical list.
- **Delete (red, destructive)** — edit mode only; confirms via `SidebarConfirmation`.
- **Save (blue, primary)** — commits via `ContentManager.updateItem` / `createItem`. Disabled until title non-empty + schema-valid.

**Why this waits for v0.3.1:** design assumes the v0.3.0 property panel. Shipping the shell before properties exist would leave the right column empty.

**v0.3.1 implementation notes:**
- Window becomes a true `WindowGroup(for: ItemRef.self)` — clicking an Item opens a separate macOS window. Depends on the cross-feature PreviewWindow primitive (`Guidelines/CRUD-Patterns.md`); the earlier `EntityRef` machinery from v0.2.7.2 was deleted at v0.2.7.1 and won't be revived.
- Same view doubles as create + edit via `mode: .create | .edit(Item)`. Create flow hides Delete.
- Two-column `HStack` — body 60% / properties 40% (revisit at implementation).
- Existing `ItemWindow.swift` popover stays as compact / inspector mode if wanted.

---

#### Item creation surfacing — lands at v0.3.0 (decided 2026-05-17; re-confirmed RC-2026-05-19)

Through v0.2.x only `CollectionDetailView`'s footer "+ New Item" exists. Broader surfacing (Vault detail footer + Vault/Collection row right-click) **ships with Properties at v0.3.0** — an Item without typed properties doesn't yet justify the paradigm.

`.newItem(...)` sheet routing is already wired in `SidebarView` + `SidebarDetailView`; v0.3.0 hangs visible entry points off existing routes. Item Window redesign ships at v0.3.1 so the full Item story completes across v0.3.0 → v0.3.1. Full scope → `// Planning//v0.3.0-Properties-implementation.md`.

---

#### Constraints

- An Item belongs to **exactly one Vault** (the Vault whose folder it physically lives in). No multi-Vault membership.
- Items conform to the parent Vault's schema. No ad-hoc page-local properties (Prospect for post-v1).
- An Item's filename cannot be empty — it's the title equivalent (same as Pages).
- No in-place promotion to Page in v1 (see `Prospects.md`).
- Tasks/events use **Agenda items**, not Items, in v1. See `Agenda.md`.

---

#### Why Items exist

Notion conflates "row in a database" with "page with a body." Pommora keeps them as separate file types — Items are pure rows, Pages are prose. Both coexist in the same Vault under the shared schema; user picks per-entry. This:

- Keeps the nexus scannable — Item `.json` is small and EditorViewer-friendly
- Maps cleanly to cloud sync (parallel `pages` / `items` tables keyed by `vault_id`)
- Preserves agent legibility (each Item is its own openable JSON file)
- Removes the per-Vault "kind?" decision the earlier model forced
