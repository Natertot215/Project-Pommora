### Items

An Item is a **row-shaped record** stored as a `.json` file: properties + relations + a 250-char plain-text description, opened in an **Item Window** (popover, Calendar-event-detail pattern). Items carry typed relations to any other entity by ID — see [[Properties]] § "Relation target".

Items live inside an **Item Type** — the schema-bearing container parallel to a [[PageTypes|Page Type]] on the Pages side. **Item Collections** are organizational sub-folders inside an Item Type, parallel to Page Collections on the Pages side.

**UI labels:** Item Types render as **"Type"** and Item Collections as **"Set"** by default; code and on-disk names always say "ItemType" / "ItemCollection". Renameable via Settings. (Per-side label divergence — distinctive vs generic word per side — is canonical in [[CLAUDE]].)

**Tasks and calendar events are NOT Items** — they are Agenda Tasks or Agenda Events. See [[Agenda]].

In generic prose discussing properties or queries, the term "Type" covers both Page Type and Item Type; "Collection" covers both Page Collection and Item Collection.

---

#### Item Type + Item Collection

The Items-side container layer mirrors the Pages-side ([[PageTypes]]) shape.

**Item Type** — a folder at the nexus root carrying an `_itemtype.json` sidecar (`schema_version: 2`). The sidecar defines the property schema shared by every Item inside (the Type plus every Item Collection underneath). Folder name = title; renaming the folder renames the Type. Sidecar fields: `id`, `singular`, `icon`, `properties`, `views`, `template_config` (reserved), `modified_at`, `schema_version`, `collection_order`, `item_order`, `default_sort`. Discovery is sidecar-driven: any root folder carrying `_itemtype.json` is an Item Type, regardless of name.

**Item Collection** — a sub-folder inside an Item Type carrying its own `_itemcollection.json` (`id`, `type_id`, `modified_at`, `schema_version`, `item_order`, `pinned_properties`, `views`). It inherits the parent Item Type's **schema** (no per-Collection property override in v1) but carries its **own** `views`. Folder name = title; renaming the folder renames the Collection.

New-Item entry points scope to a Type ("New Bookmark"), not to a container. The Item Window shows properties inherited from the parent Item Type's schema; the Item itself only stores values.

**Row ordering (interim).** Item Type / Item Collection detail tables are display-only for row order — they mirror the sidebar's file-level order (empty-state default = creation order via the ULID id; manual order persists in `item_order`). Type/Set-level drag-reorder, per-view `order`, group-by and sort are deferred to the saved-views system (v0.7.0). Flat reorder inside an Item Collection's own detail view is unaffected. Mirror of the Pages-side note in [[PageTypes]]; record: `Planning/2026-05-31-vault-table-displayonly-interim.md`.

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

Item Types sit at the nexus root as siblings of Page Types and the Agenda singletons — no `Items/` wrapper. Renaming in the UI renames the file; inbound relations stay intact (by `id`, not name).

Each Item file holds:

- `id` — ULID, stable across renames
- `description` — plain text, **hard cap 250 chars**. This IS Items' body field (Items have no Markdown body — that's what Pages are for).
- `icon` — optional, same catalog as Pages
- `properties` — values conforming to the parent Item Type's schema; relation values are tagged arrays (`[{"$rel": "<ULID>"}]`)
- `tier1` / `tier2` / `tier3` — per-tier Context relations, stored at the JSON root as bare ID arrays (`[<ULID>, ...]`). Independent per tier.
- `created_at` / `modified_at` — ISO-8601 timestamps

No `name` field — filename IS the name.

---

#### When to use Items vs Pages vs Agenda

The decision is per-Type, made at creation time (you pick which side's container to create the entry under):

- **Item** — row-shaped data without prose: contacts, wishlist, bookmarks, citations, music releases, recipes-as-rows, references. Created inside an Item Type; opens in Item Window popover.
- **Page** — prose-bearing content: notes, papers, project briefs, journal entries, reading reports. Created inside a Page Type; opens in the main detail pane with the editor.
- **Agenda Task** / **Agenda Event** — calendar-anchored; lives in the Tasks / Events singletons, not an Item Type. See [[Agenda]].

If an Item later needs prose, the user creates a Page under a Page Type and links the two by ID. No in-place promotion in v1 (see [[Prospects]]).

---

#### Capabilities

- Hold typed properties (same catalog as Pages → [[Properties]]) and typed relations to any entity by ID, rename-safe
- Appear in any view defined on the parent Item Type **or** on the Item Collection they live in — every storage container has its own `views[]`. Tier columns in Table views → [[Properties]] § "Built-in tier columns".
- Relate to Contexts via `tier1` / `tier2` / `tier3`, surfacing on those Contexts via embedded views; be linked-to from a Context's link-list widget, an embedded view, or body wikilinks

---

#### Sidebar visibility

**Items do NOT appear in the sidebar.** They live in detail-pane Tables (`ItemTypeDetailView` hierarchical; `ItemCollectionDetailView` flat); the sidebar shows the container layer only (Item Type + Item Collection rows). Same rule applies to Agenda Tasks and Agenda Events.

#### Item Window

Items open in a popover-style floating surface anchored to the trigger (row click, cell, wikilink, embedded row). Reference: Calendar.app event-detail popover; Finder's Get Info. The Item Window has **its own** inspector — a top-right toggle, default closed — that renders the property panel when opened. Current design is a placeholder.

**Pinned-property chips** above the title give always-on access to selected properties without opening the inspector. Two Item-specific rules: items in a Type root (no Collection) get no pinning controls (the pinned set persists per Item Collection), and stale pinned IDs referencing deleted schema properties are filtered on render. Persistence shape + pin/unpin mechanics are canonical in [[Properties]] § "Where Properties Live" + § "Item Inspector → Pinned Properties".

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Icon** — optional SF Symbol; edited as a plain TextField in the placeholder (the native `IconPicker` swaps in with the redesign).
- **Properties** — typed inputs for each property in the parent Item Type's schema, via `PropertyEditorRow` dispatching to per-type controls (TextField for number/url, Toggle for checkbox, DatePicker for date/datetime, Picker for select, `MultiSelectChips` for multi-select).
- **Description** — plain-text body field, **hard cap 250 characters**. This IS Items' body field (Items have no Markdown body).
- **Spaces / Topics / Projects (tier 1 / 2 / 3) relations** — pre-configured Relation properties (`relation_target` `{ kind: "context_tier", tier: N }`) merged onto the schema via `BuiltInRelationProperties`, edited inline like any Relation property. Values render as the target's icon + title in plain styled colored text (the placeholder currently shows raw IDs).
- **Meta footer** — `id`, `created_at`, `modified_at` read-only.

Dismissed by clicking Done, pressing Esc, or closing the window. Save commits via `ItemContentManager.updateItem`. No body, no blocks, no `@Columns` — if the entry needs a body, it should be a Page.

---

#### Item creation surfacing

Item creation runs through right-click context menus on Item Type / Item Collection rows ("New Item" scoped to the cursor's parent) and the detail-pane footer "+ New Item" inside `ItemCollectionDetailView` / `ItemTypeDetailView`. Each "New Item" stubs an item with a default title and flips its row into inline-rename (the F.0 stub-and-inline-rename CRUD pattern; no creation sheet).

---

#### Item Templates (reserved for post-v1)

The `_itemtype.json` sidecar carries a `template_config` field (always `null` today) reserving the on-disk shape for a post-v1 per-Item-Type template feature — per-Type window layout, character-cap override, default description seeds. See [[Prospects]].

---

#### Constraints

- An Item belongs to **exactly one Item Type** — the one whose folder it physically lives in. No multi-Item-Type membership.
- Items conform to the parent Item Type's schema, shared across its Item Collections (no per-Collection override in v1 — a Prospect).
- Moving an Item across Item Types triggers the **move-strip rule** (→ [[Properties]]); moving between Item Collections of the same Type strips nothing (schema is shared).
- Filename cannot be empty — it's the title.
- No in-place promotion to Page in v1 (see [[Prospects]]).

---

#### Why Items exist as a separate paradigm from Pages

Notion conflates "row in a database" with "page with a body". Pommora keeps them separate: **Items are pure rows** (properties + 250-char description, no Markdown body); **Pages are prose-bearing** (Markdown body + frontmatter). Each side carries its own schema mechanics via parallel containers (Item Type + Item Collection vs Page Type + Page Collection), keeping `.json` Items small, agent-legible, and cleanly mappable to cloud sync, and letting quick-capture scope to a Type ("New Bookmark") rather than a container.
