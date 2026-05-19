### Items

An Item is a **row-shaped record** stored as a `.json` file. Properties + relations + a 250-character plain-text description, opened in an **Item window** (popover-style — Calendar-event-detail pattern). For database entries that don't warrant a full Page: wishlist entries, contacts, references, citations, music releases, recipes-as-rows. No Markdown body, no tab, no full page.

Items solve the Notion problem of every database row being a full page — by keeping prose-bearing entities (Pages) and row-shaped entities (Items) as separate file types that can coexist inside the same Vault.

**Important: tasks and calendar events are NOT Items in v1.** They live as **Agenda items** (`.agenda.json`) in a separate operational-layer entity with EventKit integration. See `Agenda.md`. Items are for row-shaped data that doesn't need calendar/EventKit semantics.

Items live inside a Vault (or Collection sub-folder within a Vault). See `Vaults.md` for the containment rules. Vaults are kind-agnostic — Pages and Items can coexist in the same Vault under the shared schema.

---

#### On disk

**One `.json` file per Item.** Filename = title (same rule as Pages). Items live inside a Vault — either directly in the Vault folder or in a Collection sub-folder. No aggregate file, no nested `items//` subfolder.

```
Materials/                  ← Vault
  _vault.json               ← shared schema
  Documents/                ← Collection (sub-folder)
    Annual-report.json      ← Item conforming to Vault schema
  Bookmark.json             ← Item directly in Vault (no Collection sub-folder)
```

Renaming an Item in the UI renames the `.json` file on disk. Inbound relations stay intact because relations are by `id`, not by name.

Each Item file holds:

- `id` — ULID, stable across renames (target of relations)
- `description` — plain-text field, **hard cap 250 characters**. Sized so the field fits within the Item window without scrolling. Not Markdown, not a body.
- `icon` — optional, same catalog as Pages and Vaults
- `properties` — values conforming to the Vault's schema (same property catalog as Pages and Agenda)
- `tier1` / `tier2` / `tier3` — per-tier multi-valued relation arrays pointing to Contexts (Spaces / Topics / Sub-topics). Independent per tier — each filled separately. Replaces the earlier `spaces` field.
- `created_at` / `modified_at` — UNIX timestamps, auto-managed

No `name` field — the filename IS the name (consistent with Pages, where filename IS the title).

---

#### When to use Items vs Pages vs Agenda

The decision is per-entry now (Vaults are kind-agnostic):

- **Item** — row-shaped data without prose: contacts, wishlist, bookmarks, citations, music releases, recipes-as-rows, references. Opens in Item Window popover.
- **Page** — prose-bearing content: notes, papers, project briefs, journal entries, reading reports. Opens in a tab with the editor.
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

**Items do NOT appear in the sidebar.** They live exclusively in the detail-pane Tables (`VaultDetailView` shows a hierarchical Table that expands Collections to reveal contained Pages + Items; `CollectionDetailView` shows a flat Table of all Pages + Items in that Collection). The sidebar tree shows the structural / Page-shaped view — Vaults disclose Pages + Collections, Collections disclose Pages, full stop. Putting Items in the sidebar would clutter without serving navigation; the detail pane is where Item discovery happens.

This is a paradigm decision (2026-05-17, in `// Guidelines//Paradigm-Decisions.md`). Same rule applies to Agenda items and Events — sidebar-invisible, detail-pane-only.

#### Item window

Items don't have a prose editor; they open in an **Item window** — a popover-style floating surface anchored to the trigger (detail-pane row click, table cell, wikilink, embedded-view row). Reference pattern: Calendar.app event-detail popover; macOS Finder's Get Info window. Not a tab, not a full page, not the inspector.

The window contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Icon** — optional SF Symbol, editable via TextField (curated SymbolPicker UI deferred to a polish pass; current sheet supports manual entry).
- **Properties** — typed inputs for each property in the parent Vault's schema (via `PropertyEditorRow` dispatching to per-type controls: TextField for number/url, Toggle for checkbox, DatePicker for date/datetime, Picker for select, `MultiSelectChips` for multi-select; relation editor + tier1/2/3 chip pickers land v0.3.0).
- **Description** — plain-text field, **hard cap 250 characters**. Sized to fit the window without scrolling; keeps the JSON file small and cloud-sync-friendly.
- **Tier 1 / Tier 2 / Tier 3 relations** — read-only ULID display in v0.2; full relation picker UI lands v0.3.0 (shared `ContextTierPicker` component with Pages inspector).
- **Meta footer** — `id`, `created_at`, `modified_at` read-only.

Dismissed by clicking Done, pressing Esc, or closing the window. Save commits via `ContentManager.updateItem` (with a `renameItem` pre-step if the title changed). No body, no blocks, no `@Columns`. If the entry needs a body, it should be a Page.

---

#### Item window — design evolution (v0.3.1 design intent)

Nathan-sketched 2026-05-17. The current v0.2 ItemWindow is functional but Spartan — the design direction below supersedes it at v0.3.1, immediately after v0.3.0 Properties lands. v0.3.0 ships properties into the existing popover; v0.3.1 reshapes the surface around them.

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

- **Title bar** — `New Item` for creation flow; item title (filename) for edit flow. Editable in place — renaming retitles the `.json` file via `ContentManager.renameItem`.
- **Top-right action buttons** (the two squares in the sketch) — icon picker + view-toggle / preview-toggle affordances. Exact actions TBD; expectation is one is SF Symbol icon picker (current TextField fallback retires once SymbolPicker integration completes per paradigm decision #3) and the other is a compact-vs-expanded view toggle.
- **Left column — description/notes body** — large multi-line text area, dark-mode-prominent. Hard cap of 250 characters from the spec retained; the larger visual footprint just gives the field more breathing room. NOT a Markdown editor — Pages exist for that.
- **Right column — properties** — stacked dropdown pickers, one per property in the parent Vault's schema. Auto-populates from `Vault.properties`; uses `PropertyEditorRow` dispatch per type (Select / Multi-select / Date / etc.). Replaces the current vertical list inside the ItemWindow popover.
- **Footer left — Delete (red, secondary destructive)** — visible only in edit mode (hidden during create flow). Confirms via `SidebarConfirmation` dialog before destruction.
- **Footer right — Save (blue, primary)** — commits via `ContentManager.updateItem` (or `createItem` on the create flow). Disabled until title is non-empty + validates against the parent Vault schema.

**Why this evolution waits for v0.3.1:** the design assumes the full property panel UI from v0.3.0. Shipping the new shell before properties exist would leave the right column empty. v0.2's current ItemWindow popover suffices through v0.3.0 (title + icon + description + meta + properties). The shell redesign at v0.3.1 reshapes around the now-filled property column.

**v0.3.1 implementation notes** (forward-looking):
- The window becomes a true `WindowGroup(for: ItemRef.self)` rather than a sheet — clicking an Item row opens a separate macOS window (matching the standalone-Page pattern from `WindowGroup(for: PageRef.self)`, generalized to `EntityRef` at v0.2.8 NavDropdown). Side-by-side editing of two Items becomes possible.
- The same view doubles as create + edit by passing `mode: .create | .edit(Item)`. Create flow hides Delete; edit flow shows it.
- The two-column layout uses `HStack` with proportional widths — body 60% / properties 40% (revisit ratios at implementation).
- The existing `ItemWindow.swift` popover stays as the "compact" / inspector view if we want both modes.

---

#### Item creation surfacing — lands at v0.3.0 (decided 2026-05-17; re-confirmed RC-2026-05-19)

Item creation affordances stay narrow through v0.2.x — only `CollectionDetailView`'s footer "+ New Item" exists. Broader surfacing (Vault detail footer button + sidebar context menu entries on Vault + Collection rows) **ships with Properties at v0.3.0** because an Item without typed properties is just title + icon + 250-char description, which doesn't yet justify the Item paradigm. Teaching users to "create Items" before Properties exist would seat a mental model that changes meaning under them when v0.3.0 arrives.

The `.newItem(...)` sheet routing is already wired in `SidebarView` + `SidebarDetailView` from v0.2; v0.3.0 hangs the visible entry points off existing routes. The Item Window redesign (Nathan sketch above) then ships at v0.3.1 so the full Item story completes in v0.3.0 → v0.3.1 across two minor versions. Full scope + the 3 surfacing additions catalogued at `// Planning//v0.3.0-Properties-implementation.md`.

---

#### Constraints

- An Item belongs to **exactly one Vault** (the Vault whose folder it physically lives in). No multi-Vault membership.
- Items conform to the parent Vault's schema. No ad-hoc page-local properties (Prospect for post-v1).
- An Item's filename cannot be empty — it's the title equivalent (same as Pages).
- No in-place promotion to Page in v1 (see `Prospects.md`).
- Tasks/events use **Agenda items**, not Items, in v1. See `Agenda.md`.

---

#### Why Items exist

Notion conflates "row in a database" with "page with a body" because every database entry is a full page. Pommora keeps them distinct as separate file types — Items are pure rows (no body), Pages are prose. Both can coexist in the same Vault under the shared schema, and the user picks per-entry. This:

- Keeps the nexus scannable — an Item's `.json` is small and EditorViewer-friendly
- Maps cleanly to cloud sync (parallel `pages` / `items` tables keyed by `vault_id`)
- Preserves file-canonical agent legibility (each Item is its own openable JSON file)
- Removes the per-Vault "kind?" decision the earlier 3-entity model forced
