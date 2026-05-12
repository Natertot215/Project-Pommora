### Domain Model

Pommora is composed of three top-level entity types — **Pages**, **Collections**, **Spaces** — plus one Collection-bound member type, **Items**. Top-level roles are intentionally distinct.

**Collections are typed at creation.** A Collection is either a **Pages collection** (members are `.md` Pages — prose-bearing) or an **Items collection** (members are `.json` Items — row-shaped, no body). One kind per Collection, persistent. The kind decision happens at the Collection level, not the entry level — papers are a Pages collection, tasks are an Items collection. Personal use never genuinely mixes the two inside one category, so the data model doesn't either.

This document is the brief overview. Per-entity detail (on-disk shapes, editor surfaces, capabilities, block types) lives in the dedicated feature docs.

---

#### At a glance

| Entity | Role | On disk | Editor surface |
|---|---|---|---|
| **Page** | A Markdown document — one continuous Markdown stream. Member of a Pages collection by folder location; otherwise loose. Not a block surface. | `.md` files anywhere in the vault | Prose-first editor: standard Markdown plus two Pommora-specific rendering directives (`@Columns`, `:::callout`); foldable headings built-in; blockquotes and callouts are distinct constructs |
| **Item** | A row-shaped entry. Member of an Items collection by folder location; otherwise loose. For database entries that don't warrant prose. | `.json` files anywhere in the vault | Property panel + short-description field; no prose editor |
| **Collection** | A folder + a `_collection.json` schema sidecar with a `kind` (`"pages"` or `"items"`). Functions like a Notion database: property schema, saved views, members of one kind. No text editor. | A folder containing `_collection.json` plus the member files (all `.md` if Pages, all `.json` if Items) | Database UI: switch between saved views (table / board / list / cards / gallery) over the members |
| **Space** | A Notion-page-style composition surface — text + widgets intermixed. Referential, not container: embeds Pages / Items / Collection views by widget. Independent of Collections. | `.space.json` files in `.pommora// spaces//`, holding the full block tree | Block-composition canvas: drag/drop blocks of any type into a layout |

Loose entities (`.md` or `.json` files outside any Collection folder) hold identity and built-in fields but no schema-conforming properties. Moving a member out of a Collection (or between Collections) **strips properties not in the destination's schema** — Notion-style, no quarantine.

**Picking the Collection kind:**

- **Pages collection** when entries warrant prose — journals, papers, project briefs, reading reports.
- **Items collection** when entries are fundamentally rows — tasks, contacts, wishlist, events, citations. Properties and maybe a short description; no body.

Per-entity detail:

- **`Pages.md`** — on-disk shape, frontmatter, Markdown features (standard MD + two rendering directives: `@Columns`, `:::callout`; foldable headings built-in), editor surface (React BlockNote / Swift Phase A + Phase B), wikilinks.
- **`Collections.md`** — `_collection.json` schema (including `kind`), view types, capabilities, embedded views in Spaces.
- **`Items.md`** — brief: row-shaped `.json` entries; on-disk, capabilities, constraints.
- **`Spaces.md`** — `.space.json` schema, drag-and-drop canvas, block types, referential framing.

---

#### Linking model

Pages and Items share the same relation semantics — both hold typed relation properties pointing at any other entity in the vault.

| Link | Stored as | Purpose |
|---|---|---|
| **Page → Page** (wikilink) | `[[Page Name]]` in body or in a relation property value | Inline reference in prose, or structured relation in frontmatter |
| **Page → Collection** | Implicit by location: a `.md` inside a Pages collection's folder is a member; otherwise loose | Membership |
| **Item → Collection** | Implicit by location: a `.json` inside an Items collection's folder is a member; otherwise loose | Membership |
| **Item → Page / Item / Collection / Space** | Relation property values in the Item's `.json` file (by ID for rename safety) | Typed cross-entity links |
| **Page → Space** | `spaces: [<space-id>, ...]` multi-relation in Page frontmatter | The Page appears on the linked Space's homepage |
| **Item → Space** | `spaces` relation in the Item's `.json` file | The Item appears on the linked Space's homepage |
| **Space → Page / Item / Collection** | Widget configuration in the Space's `.space.json` (embedded-view blocks, link lists) | The Space displays the linked entity (referential — Spaces don't contain their referents) |
| **Collection → Page / Item** | Implicit reverse of Page/Item → Collection | The Collection's member set |

**Reference convention:** relations are stored by ID (rename-safe) and displayed by the target's current title; body wikilinks reference by name and are rewritten on rename.

SQLite reflects all link kinds — four entity tables (`pages`, `items`, `collections`, `spaces`) plus a `links` table track the relationships for fast queries. The `collections` table carries a `kind` column.

---

#### Properties

Property values for Pages live in YAML frontmatter; property values for Items live inside the Item's `.json` file under `properties`. Property *schemas* live inside each Collection's `_collection.json` and apply uniformly to that Collection's members.

- Adding a property to a Collection updates its schema and propagates to all members.
- **V1 catalog (8 types):** number, checkbox, date, datetime, select, multi-select, relation, URL.
- **No free-form text type** — title is the filename; "text-shaped" values use Select / Multi-select with creatable options (Notion behavior).
- **No dedicated `Status` type** — Status-like properties are Selects named "Status."
- Items additionally carry a short `description` field (plain text) — part of the Item entity, not a user-defined property.
- Loose entities have no schema and hold only built-in fields.

Full type catalog and config shapes → `Properties.md`.

---

#### Sidebar navigation

The sidebar surfaces curated, app-relevant navigation, not filesystem layout. Three top-level collapsible disclosure groups, all default-collapsed. **The user can drag the headings to reorder them**; initial-boot order is Spaces / Saved / Collections.

- **Spaces** — list of all Spaces. Each Space is a leaf label (no per-Space disclosure); clicking opens the Space.
- **Saved** — pinned Pages (and eventually Items). Sidebar bookmark only; doesn't modify the pinned entity's properties. Placeholder / non-operational in early v0.x iterations.
- **Collections** — list of all Collections, kind-agnostic. Each Collection is itself a folder-style disclosure expanding to its members. A per-row kind indicator (Page-icon vs Item-icon) is a setting-toggleable Prospect.

**Loose Pages and loose Items aren't a sidebar group.** Reach them via search, wikilinks, or pinning to Saved. Cosmetic folders (no `_collection.json`) carry no semantic meaning. No raw filesystem view in v1.

> "Collapsed-by-default disclosure" is the general default UI pattern for any hierarchical or grouped content elsewhere in the app.

---

#### Main pane tabs

The main pane is multi-tabbed (Obsidian / Notion pattern). Each tab represents one open view — a Page, a Collection (with active saved view), or a Space. Items don't get their own tabs in v1; selecting an Item opens its property panel in the inspector. Open tabs and active tab persist across launches. Detail → `PommoraPRD.md` ("Top-Bar Tabs").

---

#### Open Questions

The domain model is locked except for one item:

1. **Stack** — React+Electron vs SwiftUI. Editor implementations differ for both Pages and Spaces; everything else is identical. Domain model is stack-agnostic.
