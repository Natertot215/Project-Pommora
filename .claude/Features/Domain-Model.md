### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Page Types + Agenda) holds the actual data. Operational entities relate to organization entities via per-tier multi-relation fields.

Per-entity detail → dedicated docs in `// Features//`.

---

#### PARA mapping

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Spaces** (tier 1) | Organization |
| Projects | **Topics** (tier 2) | Organization |
| (specifics) | **Projects** (tier 3) | Organization |
| Resources | **Page Types + Agenda** | Operational |
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
- Projects carry additional `project_links` to other Topics/Spaces as a **typed multi-valued context-link property** (NOT body connections)
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

#### Operational layer — Agenda

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Agenda Task** | EKReminder-shaped: due date, completion, priority | Tasks singleton (root folder carrying `_taskconfig.json`) + `<title>.task.json` | "Task" |
| **Agenda Event** | EKEvent-shaped: start + end, location | Events singleton (root folder carrying `_eventconfig.json`) + `<title>.event.json` | "Event" |

**Rules:**
- Page Type schema applies to all Pages inside (including Pages in Page Collections — Collections inherit the parent Type's schema)
- Page Collections are **not** storage-only. They **inherit only the parent Type's property schema** (collection-local schema overrides remain a post-v1 Prospect), but **own** their saved `views` — and the groups, visibility, and sorts configured inside them — persisted in their sidecar (`_pagecollection.json`). Titles are the folder name (filename = title). Each Collection also carries an optional `icon` in its sidecar (source of truth), mirrored into a SQLite column so the context picker can query it. Canonical detail → `PageTypes.md` / `Properties.md`
- Move between Page Types strips properties not in destination schema (Notion-style, with confirm); within the same Type (between Collections), no strip — schema is shared
- Agenda Tasks and Agenda Events are separate kinds with separate schemas

#### Naming convention — three layers

Pommora's domain model has three layers of naming that intentionally diverge:

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` — always exact, unambiguous. JSON keys, sidecar fields, file references all use these literal names. |
| **Docs prose** | "Page Type" / "Page Collection" (or "Type" / "Collection" where unambiguous) |
| **UI label (default)** | **"Vault"** + "Collection". All labels user-renameable via the Settings scaffold (storage v0.3.0; editing UI v0.6.0). |

Every typed container has a per-kind sidecar — `_pagetype.json` / `_pagecollection.json` / `_taskconfig.json` / `_eventconfig.json` — and the sidecar **filename** is the kind discriminator, so any LLM or external agent reading a folder at the nexus root can classify it immediately without opening the JSON.

Detail → `PageTypes.md` + `Pages.md` + `Agenda.md`.

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational-layer entities (Pages, Agenda Tasks, Agenda Events) carry **per-tier multi-relation fields** pointing to Contexts, stored at the frontmatter / JSON root as ID arrays:

```yaml
tier1: [<space-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier filled independently. An Agenda Task can link to a Space, a Topic, and a Project independently — no requirement to fill all three.

**Tier values ARE relations.** Spaces / Topics / Projects (`tier1` / `tier2` / `tier3`) are pre-configured context-link properties — `relation_target: { kind: "context_tier", tier: N }` — merged onto every Type's schema via `BuiltInContextLinkProperties`. They edit inline through the normal property-editing row (`PropertyEditorRow`), and their values render as the target Context's icon + title in plain styled colored text. In Table views the three tiers appear as default-visible columns at the rightmost content positions (after all user-property columns, before Last Edited Time); each is individually hideable. They stay one-way — no reverse property, since Contexts carry no `properties[]` schema; reverse lookups resolve through the index (`IndexQuery.incomingContextLinks`).

---

#### Entity identity vs title

Every entity carries two independent identifiers:

- **`id`** — stable ULID stored in frontmatter / JSON. Assigned at creation, never changes. This is the identity used by every cross-reference (connections, relation values, tier links, the SQLite index).
- **Title** — the entity's display name, carried as the filename (minus extension). User-renameable freely; renames are filesystem renames + nothing else. Cross-references are NOT rewritten on rename — they're ID-keyed and resolve to the current title at render time.

**Duplicate titles are rejected within the same container** — creating, renaming, or moving any entity (Page, Agenda Task/Event, or a Context/container) to a title a sibling already holds (case-insensitive) is refused, not auto-renamed. Identity is the ULID, not the title; the rejection guards only the on-disk filename slot, since `filename = title` and a folder can't hold two files with the same name. The same title in *different* containers is fine, and recasing an entity's own title is allowed. (Truly independent duplicate titles would need a separate title field — see [[Prospects]].)

Full mechanic for `[[ ]]` connections → [[Connections]].

---

#### Linking model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (`[[ ]]` connection) | plain `[[Title]]` in body; resolved by globally-unique title, indexed in SQLite — see [[Connections]] | Inline reference |
| Page → Context (tier N) | `tierN: [<id>, ...]` in frontmatter | Categorical assignment |
| Agenda Task → Context (tier N) | `tierN: [<id>, ...]` in `.task.json` | Categorical assignment |
| Agenda Event → Context (tier N) | `tierN: [<id>, ...]` in `.event.json` | Categorical assignment |
| Context → Context | `parents` (file-structural) + `project_links` (property, Projects only) | Hierarchy + cross-cutting relations |
| Page → Page Type / Page Collection | Implicit by file location | Membership |

Relations are stored by ID (rename-safe); body connections are plain `[[Title]]` on disk, resolved by globally-unique title with rename-safety via cascade — see [[Connections]].

---

#### Sidebar shape

Four top-level groups (three carry a heading; labels renameable via Settings scaffold — v0.3.0 storage / v0.6.0 editing UI), plus user-creatable vault sections:

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable. Section wrapper persists for future user-pinning
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Vaults** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages (in Type root) + Page Collections (UI label "Collection"); each Collection discloses its Pages
- **User sections** — user-created sibling sections that group Vaults for navigation only (`.nexus/sidebar-sections.json`; single-membership; ungrouped Vaults stay in the default Vaults section). Detail → `Sidebar.md`

There are no wrapper folders on disk — Page Types and the Agenda singletons live as siblings at the nexus root; the section headings are pure UI groupings with no on-disk counterpart.

Agenda has **no** sidebar section. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section (Calendar UI ships in a follow-up plan) — they do **not** appear as sidebar leaves.

No always-visible "+ New" — creation via **right-click context menus, scoped by cursor location**. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Edits flow through via the file watcher + atomic-write loop. Full-body inline Page editing (Notion-style synced blocks) is post-v1 → `Prospects.md`. Detail → `Architecture.md`.

---

#### Properties

Schemas live in per-kind sidecars on each typed container — `_pagetype.json` on a Page Type, `_taskconfig.json` on the Tasks singleton, `_eventconfig.json` on the Events singleton. Page Collections carry their own sidecar (`_pagecollection.json`) for id, ordering, `icon`, and their own `views`; only the property **schema** inherits from the parent Type. Same property catalog applies across Pages, Agenda Tasks, and Agenda Events. **10 property types in v1.** **Status is first-class with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done)** — required built-in on both AgendaTask and AgendaEvent schemas; not auto-seeded on Page Types. The three context-tier relations (`tier1` / `tier2` / `tier3`) are the only relation-type connections — no user-creatable Relation properties. Schema editing centralizes in the Page Type Settings sheet. Full catalog → `// Features//Properties.md`.
