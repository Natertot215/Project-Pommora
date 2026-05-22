### Domain Model

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Page Types + Item Types + Agenda) holds the actual data. Operational entities relate to organization entities via per-tier multi-relation fields.

Per-entity detail → dedicated docs. Complete on-disk schema + validation + CRUD → `// Planning//Contexts-Vaults-spec.md`.

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
| **Page Type** | Schema-bearing container for Pages | `<nexus>/Pages/<Title>/_schema.json` | **"Vault"** |
| **Page Collection** | Organizational sub-folder inside a Page Type | `<nexus>/Pages/<Type>/<Title>/_schema.json` | "Collection" |
| **Page** | Markdown document with prose + frontmatter | `<nexus>/Pages/<Type>/<Collection>/Page.md` | "Page" |

#### Operational layer — Items

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Item Type** | Schema-bearing container for Items | `<nexus>/Items/<Title>/_schema.json` | "Type" |
| **Item Collection** | Organizational sub-folder inside an Item Type | `<nexus>/Items/<Type>/<Title>/_schema.json` | **"Set"** |
| **Item** | Row-shaped JSON record with properties + 250-char description | `<nexus>/Items/<Type>/<Collection>/Item.json` | "Item" |

#### Operational layer — Agenda

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Agenda Task** | EKReminder-shaped: due date, completion, priority | `<nexus>/Agenda/Tasks/_schema.json` + `<title>.task.json` | "Task" |
| **Agenda Event** | EKEvent-shaped: start + end, location | `<nexus>/Agenda/Events/_schema.json` + `<title>.event.json` | "Event" |

**Rules:**
- Page Type schema applies to all Pages inside (including Pages in Page Collections — Collections inherit the parent Type's schema)
- Item Type schema applies to all Items inside (Item Collections inherit the parent Type's schema)
- Page Collections and Item Collections in v0.3.0 are organizational only — their `_schema.json` carries `id` + `type_id` + ordering + `modified_at`; properties and views live on the parent Type. Collection-local schema overrides are a post-v1 Prospect
- Move between Page Types (or between Item Types) strips properties not in destination schema (Notion-style, with confirm); within the same Type (between Collections), no strip — schema is shared
- Agenda Tasks and Agenda Events are separate kinds with separate schemas — the unified `AgendaItem` is gone

#### Naming convention — three layers

Pommora's domain model has three layers of naming that intentionally diverge:

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` / `ItemType` / `ItemCollection` — always exact, side-prefixed, unambiguous. JSON keys, sidecar fields, file references all use these literal names. |
| **Docs prose** | "Type" + "Collection" as generic terms; "Page Type" / "Item Type" / etc. when side-specific |
| **UI label (default)** | Pages-side: **"Vault"** + "Collection". Items-side: "Type" + **"Set"** (intentional divergence — each side: one signature word + one shared word). All labels user-renameable via the Settings scaffold (Phase 7). |

The on-disk file shape is identical across sides (every typed container has a `_schema.json`); only the UI label and the Swift type differ.

Detail → `PageTypes.md` + `Pages.md` + `Items.md` + `Agenda.md`.

---

#### Singleton — Homepage

One per Nexus, fixed location (`.nexus/homepage.json`). Composed-blocks surface — same shape as a Context's `blocks` field, but no `id` / no `tier` / no `parents`. Designed as the user's general dashboard / landing surface. Seeded on first launch; not user-deletable.

Detail → `Homepage.md`.

---

#### Cross-layer relations

Operational-layer entities (Pages, Items, Agenda Tasks, Agenda Events) carry **per-tier multi-relation fields** pointing to Contexts:

```yaml
tier1: [<space-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier filled independently. An Agenda Task can link to a Space, a Topic, and a Project independently — no requirement to fill all three. Editing in the property panel (Item Window, Page property panel) via type-to-search relation pickers.

---

#### Linking model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (wikilink) | `[[Page Name]]` in body or relation property value | Inline reference or structured relation |
| Page → Context (tier N) | `tierN: [<id>]` in frontmatter | Categorical assignment |
| Item → Context (tier N) | `tierN: [<id>]` in `.json` | Categorical assignment |
| Agenda Task → Context (tier N) | `tierN: [<id>]` in `.task.json` | Categorical assignment |
| Agenda Event → Context (tier N) | `tierN: [<id>]` in `.event.json` | Categorical assignment |
| Context → Context | `parents` (file-structural) + `linked_relations` (property) | Hierarchy + cross-cutting relations |
| Page → Page Type / Page Collection | Implicit by file location | Membership |
| Item → Item Type / Item Collection | Implicit by file location | Membership |
| Anything → Anything | Wikilinks in composed-page body / Markdown body | Free reference |

Relations are stored by ID (rename-safe); body wikilinks reference by name and rewrite on rename.

---

#### Sidebar shape

Five top-level groups (only four carry a heading; all labels renameable via Settings scaffold — Phase 7):

- **Pinned (heading-less, at top)** — fixed entries (Homepage, Calendar, Recents); labels renamable. Section wrapper persists for future user-pinning
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Items** — chevron-disclosure showing Item Types (UI label "Type"); each Type discloses its Item Collections (UI label **"Set"**)
- **Pages** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages (in Type root) + Page Collections (UI label "Collection"); each Collection discloses its Pages

Items sits **above** Pages — quicker-capture entities ride higher in the visual hierarchy. The `<nexus>/Pages/`, `<nexus>/Items/`, and `<nexus>/Agenda/` wrapper folders are **NOT** rendered as sidebar rows — the section headings are the visual representation.

Agenda has **no** sidebar section. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section (Calendar UI ships in a follow-up plan). Individual Items, Agenda Tasks, and Agenda Events do **not** appear as sidebar leaves — they live in detail-pane Tables under their parent Type.

No always-visible "+ New" — creation via **right-click context menus, scoped by cursor location**. Detail → `Sidebar.md`.

---

#### Inline editing principle

Every embedded view inside a composed-blocks surface (Context, Homepage) is **a live, fully-editable view of its source** — never a read-only snapshot. Edits flow through via the file watcher + atomic-write loop. Full-body inline Page editing (Notion-style synced blocks) is post-v1 → `Prospects.md`. Detail → `Architecture.md`.

---

#### Properties

Schemas live in `_schema.json` sidecars on each typed container — one per Page Type, Item Type, AgendaTask, and AgendaEvent. Page Collections + Item Collections carry their own `_schema.json` for id + ordering only; properties + views inherit from the parent Type. Same property catalog applies across Pages, Items, Agenda Tasks, and Agenda Events. v0.3.0 catalog: 10 types (number, checkbox, date, datetime, select, multi-select, URL, relation, status, last edited time). **Status is first-class with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done)** — required on AgendaTask schemas, not auto-seeded on Page Types or Item Types. **Page Type, Item Type, Page Collection, and Item Collection -scoped relations are MANDATORY dual** — paired reverse property auto-created on target. Schema editing centralizes in the per-Type Settings sheet (Page Type Settings sheet on the Pages side; Item Type Settings sheet on the Items side). Full catalog + scope/dual semantics → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

---

#### What changed from the earlier 3-entity model

- Earlier "Spaces" (composed-page `.space.json`) became **tier-1 Contexts** — same shape, different role (anchor, not container)
- Earlier "Collections" (folder + `_collection.json` typed at creation) became **Vaults** (folder + `_vault.json`) with **Collections** as sub-folders sharing the Vault schema
- Typed-at-creation distinction (`kind: pages | items`) dropped — Vaults are kind-agnostic
- **Agenda** new — third operational entity for calendar/task items with EventKit
- **Homepage** new — singleton dashboard at `.nexus/homepage.json`
- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) replace the earlier `spaces` multi-relation
- **ParadigmV2 (2026-05-22)** — Operational layer made symmetric: Page Type + Page Collection on the Pages side; Item Type + Item Collection on the Items side. Agenda split into Tasks + Events (EKReminder vs EKEvent aligned). Schema sidecars unified to `_schema.json` across all typed containers. Sub-topics renamed to Projects. UI label divergence: Item Collections render as "Set" by default (renameable via Settings scaffold). "Pommora" prohibited in on-disk schemas + Swift namespace qualifications.
