### Items

An Item is a **row-shaped record** stored as a `.json` file: properties + relations + a 250-char plain-text description, opened in an **Item Window** (popover, Calendar-event-detail pattern).

Items live inside an **Item Type** — the schema-bearing container parallel to a [[PageTypes|Page Type]] on the Pages side. **Item Collections** are organizational sub-folders inside an Item Type, parallel to Page Collections on the Pages side.

**UI label divergence:** the Pommora app renders Item Types as **"Type"** and Item Collections as **"Set"** by default — Items-side gets the generic word for container + distinctive word for sub-folder. The Pages-side inverts this: Page Types render as **"Vault"** (distinctive) and Page Collections as **"Collection"** (generic). Each side has one signature word + one shared word; the asymmetry visually reinforces which side you're on. Code, data, and on-disk references always say "ItemType" / "ItemCollection"; only the UI label diverges. All labels renameable via the Settings scaffold (Phase 7).

**Tasks and calendar events are NOT Items** — they are Agenda Tasks (`.task.json`, EKReminder-shaped) or Agenda Events (`.event.json`, EKEvent-shaped). See [[Agenda]]. (Agenda surfaces via the Calendar pin entry, not a dedicated sidebar section.)

In generic prose discussing properties or queries, the term "Type" covers both Page Type and Item Type; "Collection" covers both Page Collection and Item Collection.

---

#### Item Type + Item Collection

The Items-side container layer mirrors the Pages-side ([[PageTypes]]) shape.

**Item Type** — a folder at the nexus root carrying an `_itemtype.json` sidecar. The sidecar defines the property schema shared by every Item inside (the Type itself plus every Item Collection underneath). Folder name = Item Type title; renaming the folder renames the Type. Schema fields: `id`, `icon`, `properties`, `views`, `modified_at`, `collection_order`, `item_order`, `template_config` (reserved — see "Item Templates" below). UI label: **"Type"** by default. Discovery is sidecar-driven: any root folder carrying `_itemtype.json` is an Item Type, regardless of folder name.

**Item Collection** — a sub-folder inside an Item Type carrying its own `_itemcollection.json`. The Collection's sidecar holds only `id`, `type_id`, `modified_at`, and `item_order` — properties + views are inherited from the parent Item Type (no per-Collection schema override in v0.3.0). Folder name = Collection title; renaming the folder renames the Collection. UI label: **"Set"** by default.

**Quick-capture by Type.** New-Item entry points scope to a Type ("New Bookmark"), not to a container ("New Item in X"). The dialog selects an Item Collection (or "directly in Type") at create time.

**Item Window opens an Item.** Properties shown in the window are inherited from the parent Item Type's schema; the Item itself only stores values. (Window UX detail later in this doc.)

---

#### On disk

**One `.json` file per Item.** Filename = title. Lives directly in an Item Type folder, or in an Item Collection sub-folder. No aggregate file.

```
<nexus-root>/
  Bookmarks/                    ← Item Type (root folder; identified by sidecar)
    _itemtype.json              ← shared schema sidecar
    Tech/                       ← Item Collection (UI label: "Set")
      _itemcollection.json      ← per-Collection metadata
      Swift-evolution.json      ← Item
    Hacker-News.json            ← Item directly in Item Type root
```

Item Types are siblings of Page Types and the Agenda singletons at the nexus root — no `Items/` wrapper folder. Sidecar filename alone classifies each root folder.

Renaming in UI renames the file. Inbound relations stay intact (by `id`, not name).

Each Item file holds:

- `id` — ULID, stable across renames
- `description` — plain text, **hard cap 250 chars**. Fits in the Item Window without scrolling.
- `icon` — optional, same catalog as Pages
- `properties` — values conforming to the parent Item Type's schema
- `tier1` / `tier2` / `tier3` — per-tier multi-valued relation arrays to Contexts. Independent per tier.
- `created_at` / `modified_at` — UNIX timestamps

No `name` field — filename IS the name.

---

#### When to use Items vs Pages vs Agenda

The decision is per-Type, made at creation time (you pick which side's container to open the new entry under):

- **Item** — row-shaped data without prose: contacts, wishlist, bookmarks, citations, music releases, recipes-as-rows, references. Created inside an Item Type; opens in Item Window popover.
- **Page** — prose-bearing content: notes, papers, project briefs, journal entries, reading reports. Created inside a Page Type; opens in the main detail pane with the editor.
- **Agenda Task** / **Agenda Event** — calendar-anchored. Lives in the Tasks singleton (root folder carrying `_taskconfig.json`) or the Events singleton (root folder carrying `_eventconfig.json`), NOT in an Item Type. EventKit-integrable. See [[Agenda]].

If an Item later needs prose, the user creates a Page under a Page Type and links the two by ID. No in-place promotion in v1 (see [[Prospects]]).

---

#### Capabilities

- Hold typed properties from the parent Item Type's schema (same catalog as Pages; full type list → [[Properties]])
- Hold typed relations to any other entity in the Nexus (Pages, Items, Agenda Tasks, Agenda Events, Contexts, Page Types, Item Types) by ID — rename-safe
- Appear in any view defined on the parent Item Type (table / board / list / cards / gallery)
- Relate to Contexts via `tier1` / `tier2` / `tier3` multi-relation fields — surface on those Contexts' composed pages via embedded views
- Be linked-to from a Context page's link-list widget, an embedded Item Collection view, or wikilinks in body content

Item Collections are organizational only — they do not carry their own properties or views; everything is inherited from the parent Item Type's schema.

---

#### Sidebar visibility

**Items do NOT appear in the sidebar.** They live in detail-pane Tables (`ItemTypeDetailView` hierarchical; `ItemCollectionDetailView` flat). Sidebar shows the container layer only — Item Type rows (UI label "Type") and Item Collection rows (UI label "Set"). Paradigm decision 2026-05-17 — same rule applies to Agenda Tasks and Agenda Events.

#### Item Window

Items open in a popover-style floating surface anchored to the trigger (row click, cell, wikilink, embedded row). Reference: Calendar.app event-detail popover; Finder's Get Info. Not a tab, not a full page, not part of the main-window inspector (which is Claude chat). The Item Window has **its own** inspector — toggle button in the popover's top-right; default closed — that hosts the property panel when opened. Contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Icon** — optional SF Symbol, editable via TextField (curated SymbolPicker UI deferred to a polish pass; current sheet supports manual entry).
- **Properties** — typed inputs for each property in the parent Item Type's schema (via `PropertyEditorRow` dispatching to per-type controls: TextField for number/url, Toggle for checkbox, DatePicker for date/datetime, Picker for select, `MultiSelectChips` for multi-select; relation editor + tier1/2/3 chip pickers land v0.3.0).
- **Description** — plain-text field, **hard cap 250 characters**. Sized to fit the window without scrolling; keeps the JSON file small and cloud-sync-friendly.
- **Tier 1 / Tier 2 / Tier 3 relations** — read-only ULID display in v0.2; full relation picker UI lands v0.3.0 (shared `ContextTierPicker` component with the Pages-side property surface — pulldown / Page Preview inspector).
- **Meta footer** — `id`, `created_at`, `modified_at` read-only.

Dismissed by clicking Done, pressing Esc, or closing the window. Save commits via `ItemContentManager.updateItem` (with a `renameItem` pre-step if the title changed). No body, no blocks, no `@Columns`. If the entry needs a body, it should be a Page.

---

#### Inspector Panel + Pinned Chips — to-be-implemented (v0.3.x patch)

The Item Window has its own inspector — toggle in the popover's top-right corner, **default closed** — that hosts a Property Panel when opened. Same lazy-properties model as Pages: populated properties only, "+ Add property" picker over the Item Type's schema. **Pinned-property chips** sit above the title in the popover, providing always-on access to a subset of properties without opening the inspector. Pinned set is saved at the **Item Collection level** (`_itemcollection.json.pinned_properties: [String]`) — all Items in a Collection share the chip layout, cohabiting with the future Item Templates feature (both Collection-scoped UI prefs). Right-click any property row in the inspector → "Pin to chips"; right-click chip → "Unpin". Title (filename) is NOT included in the property surface — it's the popover's title bar. Ships in v0.3.x patch alongside the Item Window redesign; v0.3.0 placeholder UI uses the existing popover with extended PropertyEditorRow. Canonical architecture: [[Properties]] § "Where Properties Live".

---

#### Item Window — design evolution (v0.3.x, timing TBD)

Nathan-sketched 2026-05-17, refined 2026-05-23 brainstorm. Supersedes the v0.2 popover in a later v0.3.x patch. v0.3.0 ships properties into the existing popover (placeholder UI); the redesigned Item Window with inspector toggle + pinned-property chips ships when designed.

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

- **Title bar** — `New Item` (create) / item title (edit). Editable in place via `ItemContentManager.renameItem`.
- **Top-right action buttons** — icon picker + view-toggle (compact-vs-expanded). Exact actions TBD; SymbolPicker integration retires the TextField fallback per paradigm decision #3.
- **Left column — description/notes body** — large multi-line text area; 250-char cap retained. NOT a Markdown editor (Pages exist for that).
- **Right column — properties** — stacked dropdown pickers, one per Item Type property. `PropertyEditorRow` dispatch per type. Replaces the popover's vertical list.
- **Delete (red, destructive)** — edit mode only; confirms via `SidebarConfirmation`.
- **Save (blue, primary)** — commits via `ItemContentManager.updateItem` / `createItem`. Disabled until title non-empty + schema-valid.

**Why this waits:** design assumes the fast-follow Property Panel SwiftUI component (host-agnostic; slots into the popover's inspector). Until that ships, the v0.3.0 placeholder UI uses the existing popover with extended PropertyEditorRow.

**Implementation notes (timing TBD):**
- Window becomes a true `WindowGroup(for: ItemRef.self)` — clicking an Item opens a separate macOS window. Depends on the cross-feature PreviewWindow primitive (`Guidelines/CRUD-Patterns.md`); the earlier `EntityRef` machinery from v0.2.7.2 was deleted at v0.2.7.1 and won't be revived.
- Same view doubles as create + edit via `mode: .create | .edit(Item)`. Create flow hides Delete.
- Inspector toggle in top-right corner (alongside exit button) — default closed; reveals property panel as a panel to the right of the body.
- **Pinned-property chips** above the title — saved at the Item Collection level (`_itemcollection.json.pinned_properties: [String]`) so all Items in a Collection share the chip set. Right-click any property row in the inspector → "Pin to chips" to add; right-click chip → "Unpin" to remove. Cohabits with future Item Templates feature (both Collection-scoped UI prefs).

---

#### Item creation surfacing — v0.3.0

Through v0.2.x only `ItemCollectionDetailView`'s footer "+ New Item" exists. Broader surfacing (Item Type detail footer + Item Type / Item Collection row right-click) ships with Properties at v0.3.0 — an Item without typed properties doesn't yet justify the paradigm.

`.newItem(...)` sheet routing is already wired in `SidebarView` + `SidebarDetailView`; v0.3.0 hangs visible entry points off existing routes. Item Window redesign ships at v0.3.1 so the full Item story completes across v0.3.0 → v0.3.1. Full scope → `// Planning//v0.3.0-Properties-plan.md`.

---

#### Item Templates (reserved for post-v1)

The Item Type `_itemtype.json` sidecar carries a `template_config` field reserved for the post-v1 per-Item-Type template feature. In v0.3.0 the field is always `null`: every Item ships with the standard 250-char description cap and the default Item Window layout. Post-v1, `template_config` will let users customize per-Item-Type window layout, override the character cap, and seed default description text. UI is a Prospect — see [[Prospects]].

---

#### Constraints

- An Item belongs to **exactly one Item Type** (the Item Type whose folder it physically lives in, possibly via an Item Collection sub-folder). No multi-Item-Type membership.
- Items conform to the parent Item Type's schema. Item Collections share the parent Item Type's schema — no per-Collection schema override in v0.3.0 (Prospect for post-v1).
- Moving an Item across Item Types triggers the **move-strip rule** — properties not in the destination Item Type's schema are dropped, with a confirmation warning listing what will be stripped. Within the same Item Type (between Item Collections), no strip — schema is shared.
- An Item's filename cannot be empty — it's the title equivalent (same as Pages).
- No in-place promotion to Page in v1 (see [[Prospects]]).
- Tasks/events use **Agenda Tasks** / **Agenda Events**, not Items, in v1. See [[Agenda]].

---

#### Why Items exist as a separate paradigm from Pages

Notion conflates "row in a database" with "page with a body" — every database entry is a full page. Pommora keeps them as separate paradigms: **Items are pure rows** (properties + 250-char description, no Markdown body); **Pages are prose-bearing** (Markdown body + frontmatter properties). The parallel container structure (Item Type + Item Collection vs Page Type + Page Collection) means each side has its own schema mechanics without forcing one to absorb the other.

This:
- Keeps the nexus scannable — Item `.json` is small and EditorViewer-friendly
- Maps cleanly to cloud sync (parallel `items` / `pages` tables keyed by type ID)
- Preserves agent legibility (each Item is its own openable JSON file)
- Lets quick-capture scope to a Type ("New Bookmark") rather than to a container ("New Item in X Vault")
