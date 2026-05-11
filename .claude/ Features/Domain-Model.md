### Domain Model

Pommora is composed of three top-level entity types: **Pages**, **Collections**, and **Spaces**. They are intentionally distinct — one role per entity, no overlap. Everything else in the product (properties, views, links, search) operates over these three.

This document is the brief overview. Per-entity detail (on-disk shapes, editor surfaces, capabilities, block types) lives in the dedicated feature docs.

---

#### At a glance

| Entity | Role | On disk | Editor surface |
|---|---|---|---|
| **Page** | A single Markdown document. Lives inside a Collection's folder, or anywhere else in the vault as a loose Page. | Yes — `.md` files; location determines Collection membership | Prose-first text editor with one embed type (multi-column) |
| **Collection** | A folder + a schema sidecar. Functions like a Notion database: property schema, saved views, Pages as members. **No text editor** — purely a database viewer. | Yes — a folder in the vault containing a `_collection.json` schema file plus the member `.md` Pages | Database UI: switch between saved views (table / board / list / cards / gallery) over the Collection's member Pages |
| **Space** | A Notion-page-style surface — text + headings + lists + callouts + columns + widgets, all intermixed in a block-composition canvas. Independent of Collections (not inside any). | Yes — `.space.json` config files in `_pommora// spaces//`, holding the full block tree | Block-composition canvas: drag/drop blocks of any type (text or widget) into a layout |

The model deliberately separates *content* (Pages), *structure* (Collections), and *interface surfaces* (Spaces). Collections and Spaces are config-style entities; Pages are the only entity that holds prose content.

Per-entity detail:

- **`Pages.md`** — on-disk shape, frontmatter, block-level features (`@Columns` / callouts / toggles), editor surface (prose-first; React BlockNote / Swift Phase A + Phase B), wikilinks, hierarchy.

- **`Collections.md`** — `_collection.json` schema, view types (table / board / list / cards / gallery), capabilities, loose Pages, embedded views in Spaces.

- **`Spaces.md`** — `.space.json` schema, drag-and-drop canvas, text vs widget block types, why Spaces exist.

---

#### Linking model

Three kinds of links connect the entities:

| Link | Stored as | Purpose |
|---|---|---|
| **Page → Page** (wikilink) | `[[Page Name]]` in body or in a relation property value | Inline reference in prose, or structured relation in frontmatter |
| **Page → Collection** | Implicit by location: the Page's `.md` file lives inside the Collection's folder. Pages outside any Collection folder are loose. | Membership |
| **Page → Space** | `spaces: [<space-id>, ...]` multi-relation property in Page frontmatter | The Page appears on the linked Space's homepage |
| **Space → Page / Collection** | Widget configuration in the Space's `.space.json` layout | The Space displays the linked entity |
| **Collection → Page** | Implicit reverse of Page → Collection | The Collection's member set |

**SQLite reflects all link kinds** — three tables (`pages`, `collections`, `spaces`) plus a unified `links` table track the relationships so queries are fast.

---

#### Properties

Property values live in Page frontmatter. Property *schemas* live inside each Collection's `.collection.json` file (no longer in a single shared `schemas.json`).

- Adding a property to a Collection updates that Collection's schema and propagates to all member Pages
- Property types (v1): number, checkbox, date, datetime, select, status, multi-select, relation, URL. **No free-form text type** — title is the filename, and "text-shaped" property values use Select / Multi-select with creatable options (Notion behavior).
- Loose Pages (no Collection) hold only the properties their own frontmatter declares — they don't conform to any schema

The full property type catalog and config shapes live in `Properties.md`.

---

#### Sidebar navigation

The sidebar surfaces logical organization (Spaces and Collections), not filesystem layout. Top-level groups:

- **Spaces** — list of all Spaces (links to dashboards)
- **Collections** — list of all Collections. Each Collection is a **collapsible disclosure group**; expanding it reveals its member Pages. **Default state: collapsed (un-disclosed).** The user toggles open the Collections they want to see Pages within.
- **Loose Pages** — Pages outside any Collection folder, surfaced as a collapsible group at the same level

A raw filesystem "Files" view is **out of v1 scope** (no toggle, no opt-in). The sidebar surfaces only the logical model.

> **General UI pattern:** "Collapsed-by-default disclosure" is the default behavior for *any* hierarchical or grouped content we build elsewhere in the app — Spaces with nested groups, properties panels, etc.

---

#### Resolved decisions (locked this session)

- A **Collection is a folder + a `_collection.json` schema sidecar inside that folder.** Functions like a Notion database; physically realized like a Make.md folder note. Member Pages are the `.md` files inside the folder.
- Collections have **no text-editor surface** — they are pure database viewers (table / board / list / cards / gallery).
- Spaces are stored as **`.space.json` config files** in `_pommora// spaces//`. Not Markdown.
- Spaces hold a **full block tree** (text blocks + widget blocks intermixed) — they are Notion-page-style composition surfaces, not just widget dashboards. Independent of Collections (never inside one).
- Pages link to Spaces via a **`spaces` multi-relation property** in frontmatter.
- **Page-to-Collection membership is by location** — a Page inside a Collection's folder is a member; a Page anywhere else is loose. No `collection` frontmatter field needed.
- A Page belongs to **exactly one Collection or none**. Multi-Collection membership is not supported.
- **Folders containing a `_collection.json` are Collections** (have semantic meaning). Folders without one are cosmetic filesystem organization (no semantic meaning).
- **Cross-Collection linking** is normal — relation properties on Pages or Spaces can reference any other entity in the vault, regardless of folder location.
- **Filename = title.** No `title` field in Page frontmatter, in `_collection.json`, or in `.space.json`. Renaming any of these in the UI renames the underlying file/folder. Independent UI titles are a prospect (`Prospects.md`).
- **No ad-hoc properties for v1.** A Page's properties must come from its Collection's schema. Loose Pages have no schema, so they hold only `id`, `icon`, and `spaces` plus links. Sidebar ordering / sorting is UI state (not file content) and is the only thing outside the schema. Ad-hoc properties are a prospect (`Prospects.md`).
- **Sidebar pattern:** Spaces and Collections at top level. Collections are collapsible, default state collapsed. No raw filesystem view. "Collapsed-by-default disclosure" is the general UI pattern for any grouped content we build. (Files view is a prospect.)
- **In-line view embeds (`@View`) inside Pages are out of v1 scope**, and the v2+ revisit is React-conditional (block editors like BlockNote support inline custom views; SwiftUI's native `TextEditor` does not). Embedded Collection views remain available *inside Spaces* (as widget blocks) for v1. (Full prospect → `Prospects.md`.)

---

#### Open Questions

Only one item remains open. The domain model is otherwise locked.

1. **Stack** — React+Electron vs SwiftUI. Editor implementations differ for both Pages (Markdown editor) and Spaces (block-composition canvas); everything else is identical. Domain model is stack-agnostic.

---

#### What this replaces in earlier docs

- The PRD's earlier "folder = Collection" model with the schema in a shared `_pommora// schemas.json` — replaced by **per-Collection `_collection.json` sidecars inside each Collection folder**
- The intermediate "Collections aren't folders at all; they live in `_pommora// collections//`" model — replaced by the folder + sidecar pattern (Make.md folder-notes style)
- The intermediate "Pages have a `collection` frontmatter field" — replaced by **membership-by-location** (a Page is in the Collection it physically lives in)
- The PRD's "Pages, Sub-Pages, Hierarchy" section — Pages are flat within a Collection; loose Pages can be in any folder structure
- Earlier proposal that Spaces are `.space.md` files — Spaces are `.space.json` files (not Markdown; structured block tree)
- Earlier framing of Spaces as "widget dashboards" — Spaces are full Notion-page-style block-composition surfaces (text + widgets intermixed)
- Earlier proposal that every Page must belong to a Collection (with an "Inbox" default) — Pages can be loose, and there is no built-in default Collection
- The implicit assumption that every page is a Notion-style block document — Pages are prose-first Markdown; only Spaces are block-composed
