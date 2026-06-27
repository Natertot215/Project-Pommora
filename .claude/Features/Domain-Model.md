### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Page Collections + Agenda) holds the actual data. Operational entities relate to organization entities via per-tier multi-relation fields.

Per-entity detail → dedicated docs in `// Features//`.

---

#### PARA mapping

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Areas** (tier 1) | Organization |
| Topics | **Topics** (tier 2) | Organization |
| Projects | **Projects** (tier 3) | Organization |
| Resources | **Page Collections + Agenda** | Operational |
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

| Entity | Role | Default UI label |
|---|---|---|
| **Page Collection** | Schema-bearing top container for Pages | **"Collection"** |
| **Page Set** | Recursive sub-folder inside a Collection (any depth); schema-less, inherits everything. Depth-1 carries its own views; deeper is plain | "Set" / "Sub-Set" |
| **Page** | Markdown document with prose + frontmatter | "Page" |

The Collection's property schema applies to every Page inside it (at any depth) — all Sets inherit it. Only a depth-1 Set owns its saved `views`; deeper Sub-Sets carry none. On-disk shapes → [[Architecture]]; the top tier + schema → [[PageCollections]]; recursive Set mechanics → [[PageSets]]; the page document → [[Pages]].

#### Operational layer — Agenda

Agenda is the parent schema holding two separate kinds, each with its own property schema:

| Entity | Role | Default UI label |
|---|---|---|
| **Task** | EKReminder-shaped: due date, completion, priority | "Task" |
| **Event** | EKEvent-shaped: start + end, location | "Event" |

Detail → [[Agenda]]; the property catalog across all kinds → [[Properties]].

#### Naming convention — three layers

| Layer | Use |
|---|---|
| **Code + data** | `PageCollection` (top) / `PageSet` (recursive) — exact literal names in JSON keys, sidecar fields, file references. `PageType` is retired. |
| **Docs prose** | "Page Collection" / "Page Set" (or "Collection" / "Set" / "Sub-Set" where unambiguous) |
| **UI label (default)** | **"Collection"** + "Set" (+ derived "Sub-Set"), user-renameable via Settings. |

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational entities (Pages, Tasks, Events) tag Contexts via **per-tier multi-relation fields** (`tier1` / `tier2` / `tier3`) at the frontmatter / JSON root, each a bare ULID array filled independently. The three tiers are the **only** relation-type connection — one-way, since Contexts carry no `properties[]` schema and reverse lookups resolve through the index. On-disk shape, rendering, and catalog → [[Properties]] (tier mechanics also in [[Contexts]]).

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
| Page → Page (`[[ ]]` connection) | plain `[[Title]]` in body, resolved by globally-unique title — see [[Connections]] | Inline reference |
| Operational entity → Context (tier N) | `tierN: [<id>, ...]` at the frontmatter / JSON root | Categorical assignment |
| Context → Context | None — tiers are free-standing; context→context relations are deferred | — |
| Page → Page Collection / Page Set | Implicit by file location | Membership |

Tier relations are stored by ID (rename-safe); body connections are plain `[[Title]]` on disk, rename-safe via cascade — full rules in [[Connections]].

---

#### Sidebar shape

Four top-level groups (three carry a heading; labels renameable via the Settings scaffold), plus user-creatable Collection sections:

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable. Section wrapper persists for future user-pinning
- **Contexts** — one section containing one disclosure row per tier; each tier row is never selectable and toggles its own disclosure only; each tier's entities render as flat leaf rows inside their disclosure
- **Collections** — chevron-disclosure showing Page Collections (UI label "Collection"); each Collection discloses its root Pages + its Sets (UI label "Set"); each Set discloses its Sub-Sets (recursively) + its Pages — a depth-1 Set is selectable, deeper Sub-Sets are expand-only
- **User sections** — user-created sibling sections that group Collections for navigation only (`.nexus/sidebar-sections.json`; single-membership; ungrouped Collections stay in the default Collections section). Detail → `Sidebar.md`

There are no wrapper folders on disk — Page Collections and the Agenda singletons live as siblings at the nexus root; the section headings are pure UI groupings with no on-disk counterpart.

Agenda has **no** sidebar section. Tasks + Events surface via the Calendar entry in the Pinned section (Calendar UI ships in a follow-up plan) — they do **not** appear as sidebar leaves.

No always-visible "+ New" — creation via **right-click context menus, scoped by cursor location**. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Edits flow through via the file watcher + atomic-write loop. Full-body inline Page editing (Notion-style synced blocks) is post-v1 → `Prospects.md`. Detail → `Architecture.md`.

---

#### Properties

Property schemas live in per-kind sidecars on each typed container; the same catalog applies across Pages, Tasks, and Events, with the three context-tier relations as the only relation-type connection. Full catalog, sidecar map, and Status semantics → [[Properties]].
