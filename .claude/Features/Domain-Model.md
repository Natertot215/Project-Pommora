### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Page Types + Agenda) holds the actual data. Operational entities relate to organization entities via per-tier multi-relation fields.

Per-entity detail → dedicated docs in `// Features//`.

---

#### PARA mapping

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Areas** (tier 1) | Organization |
| Projects | **Topics** (tier 2) | Organization |
| (specifics) | **Projects** (tier 3) | Organization |
| Resources | **Page Types + Agenda** | Operational |
| (dashboard) | **Homepage** | Singleton |
| Archive | `.trash/` | Singleton |

PARA's "Projects" maps to Pommora tier-3 "Projects" — same word, intentional alignment.

---

#### Organization layer — Contexts

Three **free-standing** tiers — Areas (1), Topics (2), Projects (3). Per-tier labels are user-configurable; tier *numbers* are load-bearing in code. None contains, parents, or is restricted to another — a Project is not "inside" a Topic; a Topic does not belong to an Area. Pages/Agenda tag any tiers independently — a page can relate to a Topic without relating to an Area.

| Tier | Default label | Role |
|---|---|---|
| 1 | Areas | Broad life domains (Personal, Academics, Work) |
| 2 | Topics | Subject areas (Productivity, Side Projects, Reading List) |
| 3 | Projects | Specifics (CS 161, Pommora, "Atomic Habits") |

On-disk shape, sidebar, validation, and tier config → `Contexts.md`.

---

#### Operational layer — Pages

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Page Type** | Schema-bearing container for Pages | `<nexus>/<Title>/_pagetype.json` | **"Vault"** |
| **Page Collection** | Organizational sub-folder inside a Page Type | `<nexus>/<Type>/<Title>/_pagecollection.json` | "Collection" |
| **Page Set** | Optional schema-less sub-folder inside a Page Collection; identity + icon only, everything else inherits from the Collection | `<nexus>/<Type>/<Collection>/<Title>/_pageset.json` | "Set" |
| **Page** | Markdown document with prose + frontmatter | `<nexus>/<Type>/<Collection>/<Set>/Page.md` | "Page" |

#### Operational layer — Agenda

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Agenda Task** | EKReminder-shaped: due date, completion, priority | Tasks singleton (root folder carrying `_taskconfig.json`) + `<title>.task.json` | "Task" |
| **Agenda Event** | EKEvent-shaped: start + end, location | Events singleton (root folder carrying `_eventconfig.json`) + `<title>.event.json` | "Event" |

**Rules:**
- The Page Type's schema applies to every Page inside it, including Pages in Collections and Sets — both inherit it.
- Page Collections **inherit only** the parent Type's property schema but **own** their saved `views` (groups, visibility, sorts) and an optional `icon`. Page Sets carry no schema, views, or settings — identity + icon + page order only.
- Hierarchy is strictly three levels (depth-2 folder = Set; deeper folders are sidecar-less, rolling up into the nearest Set).
- Move between Page Types strips properties absent from the destination schema (Notion-style, with confirm); within the same Type — no strip, schema is shared.
- Agenda Tasks and Agenda Events are separate kinds with separate schemas.

Detail → `PageTypes.md` / `Sets.md` / `Pages.md` / `Agenda.md` / `Properties.md`.

#### Naming convention — three layers

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` / `PageSet` — exact literal names in JSON keys, sidecar fields, file references. |
| **Docs prose** | "Page Type" / "Page Collection" / "Page Set" (or "Type" / "Collection" / "Set" where unambiguous) |
| **UI label (default)** | **"Vault"** + "Collection" + "Set", all user-renameable via Settings. |

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational entities (Pages, Agenda Tasks, Agenda Events) tag Contexts via **per-tier multi-relation fields** at the frontmatter / JSON root, as bare ULID arrays:

```yaml
tier1: [<area-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier is filled independently — no requirement to fill all three. The three tiers are the **only** relation-type connection (pre-configured properties merged onto every Type's schema, edited inline); they stay one-way, since Contexts carry no `properties[]` schema and reverse lookups resolve through the index. Catalog + rendering → `// Features//Properties.md`.

---

#### Entity identity vs title

- **`id`** — stable ULID in frontmatter / JSON, assigned at creation, never changes. Every cross-reference (connections, relation values, tier links, the index) is ID-keyed.
- **Title** — display name carried as the filename (minus extension), freely renameable. Renames are pure filesystem renames; ID-keyed cross-references resolve to the current title at render time and are never rewritten.

**Duplicate titles are rejected within the same container** (case-insensitive) — refused, not auto-renamed. The rejection guards only the on-disk filename slot (`filename = title`); the same title in *different* containers is fine, and recasing an entity's own title is allowed.

`[[ ]]` connection mechanic → [[Connections]].

---

#### Linking model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (`[[ ]]` connection) | plain `[[Title]]` in body; resolved by globally-unique title, indexed in SQLite — see [[Connections]] | Inline reference |
| Page → Context (tier N) | `tierN: [<id>, ...]` in frontmatter | Categorical assignment |
| Agenda Task → Context (tier N) | `tierN: [<id>, ...]` in `.task.json` | Categorical assignment |
| Agenda Event → Context (tier N) | `tierN: [<id>, ...]` in `.event.json` | Categorical assignment |
| Context → Context | None — tiers are free-standing; context→context relations are deferred | — |
| Page → Page Type / Page Collection / Page Set | Implicit by file location | Membership |

Relations are stored by ID (rename-safe); body connections are plain `[[Title]]` on disk, resolved by globally-unique title with rename-safety via cascade — see [[Connections]].

---

#### Sidebar shape

Four top-level groups (three carry a heading; labels renameable via the Settings scaffold), plus user-creatable vault sections:

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable. Section wrapper persists for future user-pinning
- **Contexts** — one section containing one disclosure row per tier; each tier row is never selectable and toggles its own disclosure only; each tier's entities render as flat leaf rows inside their disclosure
- **Vaults** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages (in Type root) + Page Collections (UI label "Collection"); each Collection discloses Page Sets (UI label "Set"; expandable, never selectable) + its Pages; each Set discloses its Pages
- **User sections** — user-created sibling sections that group Vaults for navigation only (`.nexus/sidebar-sections.json`; single-membership; ungrouped Vaults stay in the default Vaults section). Detail → `Sidebar.md`

There are no wrapper folders on disk — Page Types and the Agenda singletons live as siblings at the nexus root; the section headings are pure UI groupings with no on-disk counterpart.

Agenda has **no** sidebar section. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section (Calendar UI ships in a follow-up plan) — they do **not** appear as sidebar leaves.

No always-visible "+ New" — creation via **right-click context menus, scoped by cursor location**. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Edits flow through via the file watcher + atomic-write loop. Full-body inline Page editing (Notion-style synced blocks) is post-v1 → `Prospects.md`. Detail → `Architecture.md`.

---

#### Properties

Schemas live in per-kind sidecars on each typed container — `_pagetype.json` on a Page Type, `_taskconfig.json` on the Tasks singleton, `_eventconfig.json` on the Events singleton. Page Collections carry their own sidecar (`_pagecollection.json`) for id, ordering, `icon`, and their own `views`; only the property **schema** inherits from the parent Type. The same property catalog applies across Pages, Agenda Tasks, and Agenda Events. Status is first-class with EventKit-aligned fixed groups — a required built-in on both Agenda schemas, not auto-seeded on Page Types. The three context-tier relations (`tier1` / `tier2` / `tier3`) are the only relation-type connections — no user-creatable Relation properties. Schema editing centralizes in the Page Type Settings sheet. Full catalog → `// Features//Properties.md`.
