### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Vaults + Agenda) holds the actual data. Entities in the operational layer relate to entities in the organization layer via per-tier multi-relation fields.

This is the post-RC-revision domain model. Per-entity detail lives in dedicated docs (Contexts.md, Vaults.md, Items.md, Pages.md, Agenda.md, Homepage.md). The complete on-disk schema + validation + CRUD spec lives at `// Planning//Contexts-Vaults-spec.md`.

---

#### PARA mapping

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Spaces** (tier 1) | Organization |
| Projects | **Topics** (tier 2) | Organization |
| (sub-projects) | **Sub-topics** (tier 3) | Organization |
| Resources | **Vaults + Collections + Content** | Operational |
| (calendar) | **Agenda** | Operational |
| (dashboard) | **Homepage** | Singleton |
| Archive | `.trash/` | Singleton |

---

#### Organization layer — Contexts

Three tiers — Spaces (1), Topics (2), Sub-topics (3). Per-tier labels are user-configurable; tier *numbers* are load-bearing in code.

| Tier | Default label | Role | Sidebar render |
|---|---|---|---|
| 1 | Spaces | Broad life domains (Personal, Academics, Work) | Flat row with color/symbol; no chevron |
| 2 | Topics | Subject areas inside Spaces (Productivity, Side Projects) | Chevron-disclosure expanding to Sub-topics |
| 3 | Sub-topics | Specifics within one Topic (CS 161, Pommora) | Leaf row inside parent Topic |

**Rules:**
- Topics multi-parent across Spaces; Sub-topics single-parent at file (folder location = parent Topic)
- Sub-topics carry additional `linked_relations` to other Topics/Spaces as a **typed multi-valued relation property** (NOT body wikilinks)
- No same-tier file-structural links (Topic ↛ Topic; Space ↛ Space)
- Tier-skip allowed: Sub-topic can parent directly to a Space
- All three tiers are composed-blocks surfaces (same `blocks` field as Homepage; can embed anything)

Detail → `Contexts.md`.

---

#### Operational layer — Vaults / Collections / Content

| Entity | Role | On disk |
|---|---|---|
| **Vault** | Folder with shared property schema | Folder + `_vault.json` |
| **Collection** | Sub-folder inside a Vault; shares Vault schema (v1) | Folder inside a Vault; no own schema file |
| **Content** | The data: Pages (`.md`) and Items (`.json`) | Files inside a Collection (or directly in the Vault) |

**Rules:**
- Vault schema applies to ALL Content inside (Pages + Items both)
- Vaults are kind-agnostic — heterogeneous content (Pages + Items together) is allowed
- Collections in v1 are pure folders (no metadata file, no own schema)
- Collection-local schemas are a post-v1 Prospect
- Move between Vaults strips properties not in destination schema (Notion-style, with confirm)

Detail → `Vaults.md` + `Pages.md` + `Items.md`.

---

#### Operational layer — Agenda (separate from Vaults)

Calendar-anchored items (events, tasks, to-dos, phases) live as **a third operational-layer entity** at `<nexus>/Agenda/`. Sibling of Vaults, not nested.

**Why separate:**
- macOS EventKit requires entities matching `EKEvent` and `EKReminder` shapes — fixed schemas that don't map cleanly to generic Vault Items
- Quick-capture from system Calendar / Siri / Reminders / lock-screen widgets needs one known location, not a "what Vault?" decision
- Pommora's Mac-first posture makes EventKit integration load-bearing, not polish

**Shape:**
- Single unified entity (no `kind` field at schema level)
- User-facing type (Task / To-Do / Phase / Event / custom) is a **property** (`properties.type`), user-extensible like any other Select
- EventKit mapping data-driven: `start_at` + `end_at` set → `EKEvent`; `due_at` only → `EKReminder`; neither → unscheduled `EKReminder`
- Same Item Window UI as Items; same tier1/2/3 relations; same sort/filter

Detail → `Agenda.md`.

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational-layer entities (Pages, Items, Agenda items) carry **per-tier multi-relation fields** pointing to Contexts:

```yaml
tier1: [<space-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<subtopic-id>, ...]
```

Each tier filled independently. A Task can link to a Space, a Topic, and a Sub-topic independently — no requirement to fill all three. Editing in the property panel (Item Window, Page property panel) via type-to-search relation pickers.

---

#### Linking model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (wikilink) | `[[Page Name]]` in body or relation property value | Inline reference or structured relation |
| Page → Context (tier N) | `tierN: [<id>]` in frontmatter | Categorical assignment |
| Item → Context (tier N) | `tierN: [<id>]` in `.json` | Categorical assignment |
| Agenda → Context (tier N) | `tierN: [<id>]` in `.agenda.json` | Categorical assignment |
| Context → Context | `parents` (file-structural) + `linked_relations` (property) | Hierarchy + cross-cutting relations |
| Page → Vault / Collection | Implicit by file location | Membership |
| Item → Vault / Collection | Implicit by file location | Membership |
| Anything → Anything | Wikilinks in composed-page body / Markdown body | Free reference |

Relations are stored by ID (rename-safe); body wikilinks reference by name and rewrite on rename.

---

#### Sidebar shape

Four top-level groups (only three carry a heading label):

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable in Settings. Structurally a `Section` wrapper to host future user-pinned pages; renders without a "Saved" header text today
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 Contexts with file-nested Sub-topics
- **Vaults** — chevron-disclosure showing **Pages directly in the vault root + Collection sub-folders** as children; each Collection further discloses its own Pages. Pages render with the `doc.text` icon

Items, Agenda items, and Events do **NOT** appear in the sidebar — they live exclusively in the detail-pane Tables (`VaultDetailView`, `CollectionDetailView`). The sidebar tree shows the Page-shaped / structural view; the detail pane shows the full data view.

No always-visible "+ New" buttons — creation is **right-click context menus, scoped by cursor location** (right-click on a Vault → "New Collection / New Page" both scoped to THAT Vault; right-click on a Collection → "New Page" in THAT Collection; etc.). Hover-icon "+" affordance on section headings is deferred until quick-capture lands. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context page, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Editing flows through to the source file via the file watcher + atomic-write loop. Detail → `Architecture.md` + `// Planning//Contexts-Vaults-spec.md`.

Full-body inline Page editing (Notion-style synced blocks) is post-v1 — see `Prospects.md`.

---

#### Properties

Property schemas live in `_vault.json` (Vault-wide in v1) and `_agenda.json` (built-in `type` Select + built-in `status` Status + user-extensible). Same property catalog applies to Pages, Items, and Agenda items. v0.3.0 catalog: 10 types (number, checkbox, date, datetime, select, multi-select, URL, relation, status, last edited time). **Status is a first-class type with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done)** containing user-editable options. **Vault- and Collection-scoped relations are MANDATORY dual** — paired reverse property auto-created on target. Schema editing centralizes in the Vault Settings sheet (`// Features//Vaults.md`). Full type catalog + scope/dual semantics → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

---

#### What changed from the earlier 3-entity model

- The earlier "Spaces" (composed-page entity holding `.space.json`) became **tier-1 Contexts** — same shape, different role (categorical anchor, not container)
- The earlier "Collections" (folder + `_collection.json` typed at creation) became **Vaults** (folder + `_vault.json`) with **Collections** as sub-folders that share the Vault's schema
- Typed-at-creation distinction (`kind: pages | items`) is dropped — Vaults are kind-agnostic
- **Agenda** is new — a third operational-layer entity for calendar/task items with EventKit integration
- **Homepage** is new — singleton dashboard at `.nexus/homepage.json`, separate from any Space
- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) replace the earlier `spaces` multi-relation
