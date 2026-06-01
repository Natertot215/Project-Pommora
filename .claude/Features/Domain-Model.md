### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Page Types + Item Types + Agenda) holds the actual data. Operational entities relate to organization entities via per-tier multi-relation fields.

Per-entity detail → dedicated docs in `// Features//`.

---

#### PARA mapping

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Spaces** (tier 1) | Organization |
| Projects | **Topics** (tier 2) | Organization |
| (specifics) | **Projects** (tier 3) | Organization |
| Resources | **Page Types + Item Types + Agenda** | Operational |
| (dashboard) | **Homepage** | Singleton |
| Archive | `.trash/` | Singleton |

PARA's "Projects" maps to Pommora tier-3 "Projects" — same word, intentional alignment.

---

#### Organization layer — Contexts

Three tiers — Spaces (1), Topics (2), Projects (3). Per-tier labels are user-configurable; tier *numbers* are load-bearing in code. Tier-3 Projects are stored as `.project.json` files inside their parent Topic folder.

| Tier | Default label | Role | Sidebar render |
|---|---|---|---|
| 1 | Spaces | Broad life domains (Personal, Academics, Work) | Flat row with color/symbol; no chevron |
| 2 | Topics | Subject areas inside Spaces (Productivity, Side Projects) | Chevron-disclosure expanding to Projects |
| 3 | Projects | Specifics within one Topic (CS 161, Pommora) | Leaf row inside parent Topic |

**Rules:**
- Topics multi-parent across Spaces; Projects single-parent at file (folder location = parent Topic)
- Projects carry additional `linked_relations` to other Topics/Spaces as a **typed multi-valued relation property** (NOT body wikilinks)
- No same-tier file-structural links (Topic ↛ Topic; Space ↛ Space)
- Tier-skip allowed: a Project can parent directly to a Space
- All three tiers are composed-blocks surfaces (same `blocks` field as Homepage; can embed anything)

Detail → `Contexts.md`.

---

#### Operational layer — Pages

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Page Type** | Schema-bearing container for Pages | `<nexus>/<Title>/_pagetype.json` | **"Vault"** |
| **Page Collection** | Organizational sub-folder inside a Page Type | `<nexus>/<Type>/<Title>/_pagecollection.json` | "Collection" |
| **Page** | Markdown document with prose + frontmatter | `<nexus>/<Type>/<Collection>/Page.md` | "Page" |

#### Operational layer — Items

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Item Type** | Schema-bearing container for Items | `<nexus>/<Title>/_itemtype.json` | "Type" |
| **Item Collection** | Organizational sub-folder inside an Item Type | `<nexus>/<Type>/<Title>/_itemcollection.json` | **"Set"** |
| **Item** | Row-shaped JSON record with properties + 250-char description | `<nexus>/<Type>/<Collection>/Item.json` | "Item" |

#### Operational layer — Agenda

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Agenda Task** | EKReminder-shaped: due date, completion, priority | Tasks singleton (root folder carrying `_taskconfig.json`) + `<title>.task.json` | "Task" |
| **Agenda Event** | EKEvent-shaped: start + end, location | Events singleton (root folder carrying `_eventconfig.json`) + `<title>.event.json` | "Event" |

**Rules:**
- Page Type schema applies to all Pages inside (including Pages in Page Collections — Collections inherit the parent Type's schema)
- Item Type schema applies to all Items inside (Item Collections inherit the parent Type's schema)
- Page Collections and Item Collections are **not** storage-only. They **inherit only the parent Type's property schema** (collection-local schema overrides remain a post-v1 Prospect), but **own** their saved `views` — and the groups, visibility, and sorts configured inside them — persisted in their per-kind sidecar (`_pagecollection.json` / `_itemcollection.json`). Item Collections (Sets) additionally persist `pinned_properties` (the Item Window's pinned-chip set). Titles are the folder name (filename = title). Each Collection/Set also carries an optional `icon` in its sidecar (source of truth), mirrored into a SQLite column so the relation picker can query it (shipped 2026-05-30). Canonical detail → `PageTypes.md` / `Items.md` / `Properties.md`
- Move between Page Types (or between Item Types) strips properties not in destination schema (Notion-style, with confirm); within the same Type (between Collections), no strip — schema is shared
- Agenda Tasks and Agenda Events are separate kinds with separate schemas — the unified `AgendaItem` is gone

#### Naming convention — three layers

Pommora's domain model has three layers of naming that intentionally diverge:

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` / `ItemType` / `ItemCollection` — always exact, side-prefixed, unambiguous. JSON keys, sidecar fields, file references all use these literal names. |
| **Docs prose** | "Type" + "Collection" as generic terms; "Page Type" / "Item Type" / etc. when side-specific |
| **UI label (default)** | Pages-side: **"Vault"** + "Collection". Items-side: "Type" + **"Set"** (intentional divergence — each side: one signature word + one shared word). All labels user-renameable via the Settings scaffold (v0.3.0). |

The on-disk JSON shape is identical across sides (every typed container has a per-kind sidecar — `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json` — and the file inside follows the same schema-carrier shape). Sidecar **filename** is the kind discriminator, so any LLM or external agent reading a folder at the nexus root can classify it immediately without opening the JSON. Only the UI label and the Swift type differ across sides.

Detail → `PageTypes.md` + `Pages.md` + `Items.md` + `Agenda.md`.

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational-layer entities (Pages, Items, Agenda Tasks, Agenda Events) carry **per-tier multi-relation fields** pointing to Contexts, stored at the frontmatter / JSON root as ID arrays:

```yaml
tier1: [<space-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier filled independently. An Agenda Task can link to a Space, a Topic, and a Project independently — no requirement to fill all three.

**Tier values ARE relations.** Spaces / Topics / Projects (`tier1` / `tier2` / `tier3`) are pre-configured Relation properties — `relation_target: { kind: "context_tier", tier: N }` — merged onto every Type's schema via `BuiltInRelationProperties`. They edit inline through the normal property-editing row (`PropertyEditorRow`) like any Relation property, and their values render as the target Context's icon + title in plain styled colored text. In Table views the three tiers appear as default-visible columns at the rightmost content positions (after all user-property columns, before Last Edited Time); each is individually hideable. They stay one-way — no reverse property, since Contexts carry no `properties[]` schema; reverse lookups resolve through the index (`IndexQuery.incomingRelations`).

---

#### Entity identity vs title

Every entity carries two independent identifiers:

- **`id`** — stable ULID stored in frontmatter / JSON. Assigned at creation, never changes. This is the identity used by every cross-reference (wikilinks, relation values, tier links, the SQLite index).
- **Title** — the entity's display name, carried as the filename (minus extension). User-renameable freely; renames are filesystem renames + nothing else. Cross-references are NOT rewritten on rename — they're ID-keyed and resolve to the current title at render time.

**Duplicate titles allowed within the same container** — two Pages named "Meeting Notes" in the same Page Type / Page Collection is fine because their IDs are distinct. Filesystem may auto-disambiguate (append `(2)` etc.) but the displayed title stays the user-typed value. The prior strict-reject duplicate-title validator behavior is dropped.

Full mechanic for wikilinks under the ID-keyed model → [[Pages]] § "Wikilinks".

---

#### Linking model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (wikilink) | `[[Page Name\|01HXYZ...]]` in body (title for display, ULID for resolution) | Inline reference |
| Page → Context (tier N) | `tierN: [<id>, ...]` in frontmatter | Categorical assignment |
| Item → Context (tier N) | `tierN: [<id>, ...]` in `.json` | Categorical assignment |
| Agenda Task → Context (tier N) | `tierN: [<id>, ...]` in `.task.json` | Categorical assignment |
| Agenda Event → Context (tier N) | `tierN: [<id>, ...]` in `.event.json` | Categorical assignment |
| Context → Context | `parents` (file-structural) + `linked_relations` (property) | Hierarchy + cross-cutting relations |
| Page → Page Type / Page Collection | Implicit by file location | Membership |
| Item → Item Type / Item Collection | Implicit by file location | Membership |
| Anything → Anything | Wikilinks in composed-page body / Markdown body | Free reference |

Relations are stored by ID (rename-safe); body wikilinks reference by name and rewrite on rename.

---

#### Sidebar shape

Five top-level groups (only four carry a heading; all labels renameable via Settings scaffold — v0.3.0 storage / v0.4.0 editing UI):

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable. Section wrapper persists for future user-pinning
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Items** — chevron-disclosure showing Item Types (UI label "Type"); each Type discloses its Item Collections (UI label **"Set"**)
- **Pages** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages (in Type root) + Page Collections (UI label "Collection"); each Collection discloses its Pages

Items sits **above** Pages — quicker-capture entities ride higher in the visual hierarchy. There are no wrapper folders on disk — Page Types, Item Types, and the Agenda singletons all live as siblings at the nexus root. The sidebar reads each operational folder's **per-kind sidecar filename** to decide which section heading it groups under (Page Types under "Pages", Item Types under "Items"); the section headings themselves are pure UI groupings with no on-disk counterpart.

Agenda has **no** sidebar section. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section (Calendar UI ships in a follow-up plan). Individual Items, Agenda Tasks, and Agenda Events do **not** appear as sidebar leaves — they live in detail-pane Tables under their parent Type.

No always-visible "+ New" — creation via **right-click context menus, scoped by cursor location**. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Edits flow through via the file watcher + atomic-write loop. Full-body inline Page editing (Notion-style synced blocks) is post-v1 → `Prospects.md`. Detail → `Architecture.md`.

---

#### Properties

Schemas live in per-kind sidecars on each typed container — `_pagetype.json` on a Page Type, `_itemtype.json` on an Item Type, `_taskconfig.json` on the Tasks singleton, `_eventconfig.json` on the Events singleton. Page Collections + Item Collections carry their own per-kind sidecars (`_pagecollection.json` / `_itemcollection.json`) for id, ordering, `icon`, and their own `views` (Sets also persist `pinned_properties`); only the property **schema** inherits from the parent Type. Same property catalog applies across Pages, Items, Agenda Tasks, and Agenda Events. **11 property types in v1:** Number, Checkbox, Date, Date & Time, Select, Multi-select, Status, URL, Relation, Last Edited Time, File / Attachment. **Status is first-class with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done)** — required built-in on both AgendaTask and AgendaEvent schemas; not auto-seeded on Page Types or Item Types. **Page Type, Item Type, Page Collection, and Item Collection-scoped relations are mandatory dual** — paired reverse property auto-created on target. Cross-side relations supported (Item ↔ Page). Schema editing centralizes in the per-Type Settings sheet (Page Type Settings sheet on the Pages side; Item Type Settings sheet on the Items side). Full catalog + scope/dual semantics → `// Features//Properties.md`.
