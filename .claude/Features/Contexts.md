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

- `id` (ULID), `tier` (1/2/3), `icon` (optional)
- `blocks` — an array reserved for a future composed-blocks surface; **currently always empty**
- `modified_at`

All three tiers share this one shape exactly — Area is structurally identical to Topic and Project, icon-only with no extra fields.

There is no `parents`, no containment field, and no cross-context link property. The folder name is the title; there is no `title` field on disk. Renaming in the UI renames the folder.

---

#### On-disk layout

```
.nexus/
  areas/<Title>/_area.json        id, tier 1, icon, blocks, modified_at
  topics/<Title>/_topic.json      id, tier 2, icon, blocks, modified_at
  projects/<Title>/_project.json  id, tier 3, icon, blocks, modified_at
```

Each tier has its own sibling manager with identical folder CRUD: create (folder + sidecar), rename (folder rename with atomic save-or-rollback), delete (move folder to trash), reorder (sibling order persisted to `.nexus/state.json` as `area_order` / `topic_order` / `project_order`). Each manager defensively re-syncs its rows into the SQLite `contexts` index on load.

---

#### Sidebar

The three tiers share one **Contexts** section: a section headed "Contexts" containing one disclosure row per tier. A tier row toggles its own disclosure only — it is never selectable; its entities are created via the row's hover "+" or right-click "New <Tier>". Each tier's entities render as flat leaf rows inside their disclosure. Full spec → [[Sidebar]].

---

#### Cross-layer relations (Page / Agenda → Context)

Pages and Agenda entries carry **per-tier multi-relation fields** independently:

```yaml
tier1: [<area-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier is a multi-value relation, filled independently. **Context-tier links are stored by ID** (bare ULID arrays in `tier1` / `tier2` / `tier3`, rename-safe) **and render as the target's current icon + title in a minimal grey chip** on every property surface. The tiers are the sole relation-type connection. Property catalog + the internal `context_tier` target → [[Properties]].

A tier relation is a **dual surface**:

- **Outbound (entity → Context).** The operational entity tags the Context by holding its ID in `tier1` / `tier2` / `tier3`. This is the writable side — the value lives in the entity's frontmatter; the Context carries no `properties[]` schema and no reverse field.
- **Inbound (Context → entities).** The Context reads back every entity that tags it. Because tier values emit one row each into the SQLite `context_links` table (`property_id` = the reserved tier ID), the inbound view is a pure index query — no reverse property to maintain.

This cross-layer relation is the one connection contexts have today: the tiers don't relate to *each other*, but Pages/Agenda tag them.

---

#### Linked-from

A Context surfaces every operational entity whose tier relation points at it, in a **Linked-from dropdown** on the Context surface. Each linked entity renders as its icon + title, grouped by kind (Pages / Tasks / Events).

The dropdown is a reverse index query: it reads the `context_links` table for every row whose `target_id` is the Context's ID and resolves each source's current title from its owning table. The reverse view is entirely SQLite-derived — Contexts store no inbound list on disk.

---

#### Validation

Enforced at every write:

1. Title is non-empty and contains none of `/ \ :`
2. Title is unique among siblings of the same tier (case-insensitive)
3. Filename (folder name) = title; no separate `title` field

There is no parent, containment, or tier-relation validation — the tiers are free-standing.

---

#### Tier config

Per-Nexus tier labels live at `.nexus/tier-config.json` — one entry per tier carrying `level`, `singular`, `plural`, and `exposed`:

- `singular` / `plural` — separate inputs; the UI picks one by context.
- `exposed: false` hides a tier from CRUD/UI without breaking the schema.

---

#### Deferred

Three capabilities are intentionally out of scope; each gets its own brainstorming + spec:

- **Context→context relations** — Topics relating to Areas, Projects to Topics and Areas, edited via each context's settings surface.
- **Transitive page roll-up** — page → project → topic → area aggregation.
- **Composed-blocks surface** — the `blocks` field stays inert until contexts become editable block surfaces.
