### Domain Model

Pommora is composed of three top-level entity types — **Pages**, **Collections**, **Spaces** — plus one Collection-bound member type, **Items**. Top-level roles are intentionally distinct: one role per entity, no overlap. Within a Collection, Pages and Items are sibling member types — Pages for entries that warrant Markdown prose, Items for entries that don't. Everything else in the product (properties, views, links, search) operates over these four.

This document is the brief overview. Per-entity detail (on-disk shapes, editor surfaces, capabilities, block types) lives in the dedicated feature docs.

---

#### At a glance

| Entity | Role | On disk | Editor surface |
|---|---|---|---|
| **Page** | A single Markdown document. Member of a Collection by folder location, or anywhere else in the vault as a loose Page. | Yes — `.md` files; location determines Collection membership | Prose-first text editor with one embed type (multi-column) |
| **Item** | A lightweight row-shaped entry inside a Collection. Has properties, relations, and a short description — no Markdown body. For database entries that don't warrant a full Page (ideas, tasks, references, list items). | Yes — JSON entries inside the Collection's `_items.json` sidecar | Property panel + short-description field; no prose editor |
| **Collection** | A folder + a schema sidecar + an items sidecar. Functions like a Notion database: property schema, saved views, with Pages and Items as members. **No text editor** — purely a database viewer. | Yes — a folder in the vault containing `_collection.json` (schema), optional `_items.json` (item entries), and member `.md` Pages | Database UI: switch between saved views (table / board / list / cards / gallery) over the Collection's Pages and Items |
| **Space** | A Notion-page-style surface — text + headings + lists + callouts + columns + widgets, all intermixed in a block-composition canvas. Referential, not container: embeds via `@view` directives and wikilinks. Independent of Collections (not inside any). | Yes — `.space.json` config files in `_pommora// spaces//`, holding the full block tree | Block-composition canvas: drag/drop blocks of any type (text or widget) into a layout |

The model deliberately separates *content* (Pages), *row-shaped data* (Items), *structure* (Collections), and *interface surfaces* (Spaces). Collections and Spaces are config-style entities; Pages are the only entity that holds prose content; Items are the lightweight database-row entity for non-prose entries.

**Pages vs. Items — when to use which:**

- **Page** when the entry has a body you'll write or read — notes, project briefs, journal entries, anything you'd open and edit prose in.
- **Item** when the entry is fundamentally a row — wishlist entries, quick ideas, tasks without notes, reference list items. Has properties and maybe a short description, but no body. Solves the Notion problem of every wishlist line being a full page.

Per-entity detail:

- **`Pages.md`** — on-disk shape, frontmatter, block-level features (`@Columns` / callouts / toggles), editor surface (prose-first; React BlockNote / Swift Phase A + Phase B), wikilinks, hierarchy.

- **`Collections.md`** — `_collection.json` schema, `_items.json` items sidecar, view types (table / board / list / cards / gallery), capabilities, loose Pages, embedded views in Spaces.

- **`Items.md`** — brief: row-shaped entries inside Collections; entry shape, Page-vs-Item choice, capabilities, constraints.

- **`Spaces.md`** — `.space.json` schema, drag-and-drop canvas, text vs widget block types, why Spaces exist, referential framing.

---

#### Linking model

Links connect the entities. Pages and Items share the same relation semantics — both can hold typed relation properties pointing at any other entity in the vault:

| Link | Stored as | Purpose |
|---|---|---|
| **Page → Page** (wikilink) | `[[Page Name]]` in body or in a relation property value | Inline reference in prose, or structured relation in frontmatter |
| **Page → Collection** | Implicit by location: the Page's `.md` file lives inside the Collection's folder. Pages outside any Collection folder are loose. | Membership |
| **Item → Collection** | Implicit by file: the Item is an entry in the Collection's `_items.json`. Items are never loose — they only exist inside a Collection. | Membership |
| **Item → Page / Item / Collection / Space** | Relation property values in the Item's JSON entry (by ID for rename safety) | Typed cross-entity links from row-shaped data |
| **Page → Space** | `spaces: [<space-id>, ...]` multi-relation property in Page frontmatter | The Page appears on the linked Space's homepage |
| **Item → Space** | `spaces` relation in the Item's JSON entry | The Item appears on the linked Space's homepage |
| **Space → Page / Item / Collection** | Widget configuration in the Space's `.space.json` layout (`@view` directives, link lists) | The Space displays the linked entity (referential — Spaces don't *contain* their referents) |
| **Collection → Page / Item** | Implicit reverse of Page/Item → Collection | The Collection's member set |

**SQLite reflects all link kinds** — four entity tables (`pages`, `items`, `collections`, `spaces`) plus a unified `links` table track the relationships so queries are fast.

---

#### Properties

Property values for Pages live in YAML frontmatter. Property values for Items live in the Item's JSON entry inside `_items.json`. Property *schemas* live inside each Collection's `_collection.json` file (no longer in a single shared `schemas.json`), and are shared between the Collection's Pages and Items — same property catalog, two storage substrates.

- Adding a property to a Collection updates that Collection's schema and propagates to all member Pages and Items
- Property types (v1): number, checkbox, date, datetime, select, status, multi-select, relation, URL. **No free-form text type** — title is the filename (Pages) or the Item's `name` field (Items); "text-shaped" property values use Select / Multi-select with creatable options (Notion behavior)
- Items additionally carry a short `description` field (plain text, no Markdown body) — this is part of the Item entity, not a user-defined property
- Loose Pages (no Collection) hold only the properties their own frontmatter declares — they don't conform to any schema. Items have no loose counterpart; an Item only exists inside a Collection

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
- **Items are a Collection-bound row entity, distinct from Pages.** Stored as JSON entries in `_items.json` alongside `_collection.json` inside each Collection's folder. Items hold properties (same catalog as Pages), relations (by ID), an `id`, a `name` (acts as title), and a short `description` field. No Markdown body. Items solve the Notion problem of every database row being a full Page (e.g. wishlist entries, quick ideas, reference list items don't warrant prose). The capture UX has to be frictionless — typed property entry happens at create time, not as a follow-up — so the relation graph populates rather than rotting.
- **Pages and Items are sibling member types of a Collection** — same schema, same views show both, same relation semantics. Choosing between them is a content-shape decision: prose body → Page; row-only → Item.
- **Spaces are referential, not containers.** A Space's `.space.json` doesn't *hold* its referenced Pages or Items — it embeds them via `@view` directives and wikilinks that resolve through the index or by walking files. Think "grouping tag plus its own canvas" rather than "folder of files." This is what makes Spaces queryable and agent-legible without duplicating content.
- **Persistent immediate legibility for agents is a load-bearing principle.** Every entity is a file an external agent can read directly — Pages as `.md`, Items as entries in `_items.json`, Collection schemas as `_collection.json`, Spaces as `.space.json`. No SQLite-only state, no API gating. Architecture choices that would trade file-canonical legibility for app-internal convenience violate this constraint. (Full statement → `PommoraPRD.md` "Persistent Immediate Legibility for Agents" section.)

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
