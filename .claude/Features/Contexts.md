### Contexts

The organization layer. Three **free-standing** tiers — Areas (1), Topics (2), Projects (3) — that act as categorical anchors operational entities (Pages, Agenda) relate *to*. Per-tier labels are user-configurable; tier *numbers* are load-bearing in code.

The tiers are independent: none contains, parents, or is restricted to another. A Project is not "inside" a Topic; a Topic does not belong to an Area. Each tier is a standalone entity with one shared shape. Context→context relations are a deferred design pass — see [Deferred](#deferred).

---

#### Layer mapping (PARA-aligned)

| PARA term | Tier | Default label | Role |
|---|---|---|---|
| Areas | 1 | Area (renamable) | Broad life domains — Personal, Academics, Work |
| Projects | 2 | Topic (renamable) | Subject areas — Productivity, Side Projects, Reading List |
| (sub-projects) | 3 | Project (renamable) | Specifics — CS 161, Pommora, "Atomic Habits" |

Labels are stored per-Nexus (singular + plural, Capacities convention); tier *numbers* are fixed.

---

#### Shared shape

All three tiers are **folders with a config sidecar** — the same idiom as Page Types (folder + `_pagetype.json`). Each entity carries:

- `id` (ULID), `tier` (1/2/3), `icon` (SF Symbol, optional)
- `blocks` — an array reserved for a future composed-blocks surface; **currently always empty**
- `modified_at`
- Tier-1 (Area) additionally carries `color` — the `AreaColor` palette (the 9 Notion-palette colors plus `accent`; `nil` = no tint)

There is no `parents`, no containment field, and no cross-context link property. The folder name is the title; there is no `title` field on disk. Renaming in the UI renames the folder.

---

#### On-disk layout

```
.nexus/
  areas/<Title>/_area.json        id, tier 1, color, icon, blocks, modified_at
  topics/<Title>/_topic.json      id, tier 2, icon, blocks, modified_at
  projects/<Title>/_project.json  id, tier 3, icon, blocks, modified_at
```

Each tier has its own sibling manager — `AreaManager` / `TopicManager` / `ProjectManager` — with identical folder CRUD: create (folder + sidecar via `Filesystem.createFolderWithMetadata`), rename (folder rename with atomic save-or-rollback), delete (move folder to trash), reorder (sibling order persisted to `.nexus/state.json` as `area_order` / `topic_order` / `project_order`). Each manager defensively re-syncs its rows into the SQLite `contexts` index on `loadAll`.

---

#### Sidebar

The three tiers share one **Contexts** section: a `Section` headed "Contexts" containing three `square.grid.2x2` disclosure rows (Areas / Topics / Projects). A tier row toggles its own disclosure only — it is never selectable; its entities are created via the row's hover "+" or right-click "New <Tier>". Each tier's entities render as flat leaf rows inside their disclosure. Full spec → [[Sidebar]].

---

#### Cross-layer relations (Page / Agenda → Context)

Pages and Agenda entries carry **per-tier multi-relation fields** independently:

```yaml
tier1: [<area-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier is a multi-value relation, filled independently. Each renders as its own value-row in the property surface (`tierRow` in `PropertyPanel` / `PropertiesPulldown`; also surfaced by `FrontmatterInspector`); each value displays as the target Context's **icon + title in styled colored text** — the relation-value rendering shared across every surface, not a chip or pill. The `context_tier` target is internal-only — it backs the three built-in tier relations, which are the sole relation-type connection. No user-creatable relation properties exist; `EditPropertyPane` renders a tier target read-only.

A tier relation is a **dual surface**:

- **Outbound (entity → Context).** The operational entity tags the Context by holding its ID in `tier1` / `tier2` / `tier3`. This is the writable side — the value lives in the entity's frontmatter; the Context carries no `properties[]` schema and no reverse field.
- **Inbound (Context → entities).** The Context reads back every entity that tags it. Because tier values emit one row each into the SQLite `context_links` table (`property_id` = the reserved tier ID), the inbound view is a pure index query — no reverse property to maintain.

This cross-layer relation is the one connection contexts have today. It is unaffected by the decoupling: the tiers stop relating to *each other*, but Pages/Agenda still tag them.

---

#### Linked-from

A Context surfaces every operational entity whose tier relation points at it, in a **Linked-from dropdown** on the Context surface. Each linked entity renders as its **icon + title in styled colored text**, grouped by kind (Pages / Agenda Tasks / Agenda Events).

The dropdown is powered by `IndexQuery.incomingContextLinks(targetID:)`, which reads the `context_links` table for every row whose `target_id` is the Context's ID and resolves each source's current title from its owning table. The reverse view is entirely SQLite-derived — Contexts store no inbound list on disk.

---

#### Validation

Enforced at every write:

1. Title is non-empty and contains none of `/ \ :`
2. Title is unique among siblings of the same tier (case-insensitive)
3. Filename (folder name) = title; no separate `title` field

There is no parent, containment, or tier-relation validation — the tiers are free-standing.

---

#### Tier config

Per-Nexus labels at `.nexus/tier-config.json` (defaults):

```json
{ "level": 1, "singular": "Area",    "plural": "Areas",    "exposed": true },
{ "level": 2, "singular": "Topic",   "plural": "Topics",   "exposed": true },
{ "level": 3, "singular": "Project", "plural": "Projects", "exposed": true }
```

- `singular` / `plural` — separate inputs; the UI picks one by context.
- `exposed: false` hides a tier from CRUD/UI without breaking the schema.
- `tagging_style` (`color` | `symbol` | `both`) is currently **vestigial** — it controlled the parent-Area indicator on Topic rows, which was removed with containment. It stays inert pending the future relation/tagging design.

---

#### Deferred

Three capabilities are intentionally out of scope; each gets its own brainstorming + spec:

- **Context→context relations** — Topics relating to Areas, Projects to Topics and Areas, edited via each context's settings surface.
- **Transitive page roll-up** — page → project → topic → area aggregation.
- **Composed-blocks surface** — the `blocks` field stays inert until contexts become editable block surfaces.
