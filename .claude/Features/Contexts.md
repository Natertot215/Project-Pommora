### Contexts

The organization layer. Three tiers — Spaces (1), Topics (2), Projects (3) — that act as categorical anchors other entities relate *to*. Per-tier labels are user-configurable; tier *numbers* are load-bearing in code.

All three tiers share the same shape; differences called out below.

---

#### Layer mapping (PARA-aligned)

| PARA term | Pommora term | Tier | Role |
|---|---|---|---|
| Areas | Spaces (renamable) | 1 | Broad life domains — Personal, Academics, Work |
| Projects | Topics (renamable) | 2 | Subject areas inside one or more Spaces — Productivity, Side Projects, Reading List |
| (sub-projects) | Projects (renamable) | 3 | Specifics within one Topic — CS 161, Pommora, "Atomic Habits" |

Tier names are stored in `.nexus/tier-config.json` with both singular and plural forms (Capacities convention). Default labels above; user can rename per-Nexus via Settings.

---

#### Shared shape

All three tiers are composed-blocks surfaces — same pattern as Homepage. Each carries:

- `id` (ULID), `tier` (1/2/3), `icon` (SF Symbol, optional)
- `parents` — IDs of Contexts at lower tier numbers (validated)
- `blocks` — composed-page block tree; can embed any entity by ID
- `modified_at`
- Tier-1 (Space) additionally carries `color` (one of 9 Notion palette colors)

Filename = title. Renaming in the UI renames the file.

---

#### Spaces (tier 1)

- File at `.nexus/spaces/<Title>.space.json` — flat files, no folder structure
- `parents: []` always (tier 1 is root)
- Carry `color` (visual identity used for Topic tagging in the sidebar)
- Sidebar render: flat row with color/symbol indicator, no chevron, no children disclosure
- Clicking opens the Space's composed-blocks page

---

#### Topics (tier 2)

- Folder at `.nexus/topics/<Title>/` containing `_topic.json` and member Project files
- `parents` — multi-valued tier-1 Space IDs (a Topic can belong to multiple Spaces)
- Sidebar render: chevron-disclosure row; expanded view shows file-nested Projects
- Topic's color tag in the sidebar derives from parent Space(s) — multi-Space Topics show multi-color indicators
- The tagging visual mode (color dot / SF Symbol / both) is settable in `.nexus/tier-config.json` (`tagging_style`)
- Clicking opens the Topic's composed-blocks page

---

#### Projects (tier 3)

- File at `.nexus/topics/<TopicFolder>/<Title>.project.json` — file location IS the file-structural parent
- `parents` — single-valued (the parent Topic, encoded by folder location)
- `linked_relations` — **typed multi-valued relation property** on the Project. Holds IDs of additional Topics or Spaces the Project relates to. **Not body wikilinks** — editable in the property panel like any other relation, queryable via the index, surfaced in graph view
- Tier-skip allowed: a Project CAN parent directly to a Space if it has no file-structural Topic parent (handled by treating it as a Topic in v1 — the "standalone project" case is not a distinct user-facing concept)
- Sidebar render: leaf row inside parent Topic's disclosure
- Clicking opens the Project's composed-blocks page

---

#### Connection rules

- **Tier-parent rule** — every value in `parents` must resolve to a Context with `level < this.tier`. Cycles impossible by construction.
- **Multi-parent allowed across tiers** — a Topic can parent to multiple Spaces; a Project's `linked_relations` can target multiple Topics/Spaces.
- **No same-tier file-structural links** — Topic ↛ Topic, Space ↛ Space. Same-tier relationships happen only as body-content wikilinks inside a Context's composed page.
- **Tier-skip allowed** — Projects can connect to Spaces directly via `parents` or `linked_relations`.

---

#### Cross-layer relations (Item / Page / Agenda → Context)

Items, Pages, and Agenda items carry **per-tier multi-relation fields** independently:

```yaml
tier1: [<space-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each tier filled independently. Edited via type-to-search relation pickers in the property panel.

---

#### Validation

Enforced at every file write:

1. `parents[i]` resolves to a Context with `level < this.tier`
2. Project file MUST physically live inside a Topic folder (file location = file-structural parent)
3. Project `parents` array contains exactly one ID (the folder-derived parent)
4. Item / Page / Agenda `tierN` values resolve to Contexts with `level == N`
5. Filename = title; no separate `title` field

---

#### Tier config

User-configurable per Nexus at `.nexus/tier-config.json`:

```json
{
  "schemaVersion": 1,
  "tiers": [
    { "level": 1, "singular": "Space",     "plural": "Spaces",     "exposed": true },
    { "level": 2, "singular": "Topic",     "plural": "Topics",     "exposed": true },
    { "level": 3, "singular": "Project", "plural": "Projects", "exposed": true }
  ],
  "tagging_style": "color"
}
```

- `singular` / `plural` — Capacities-style separate inputs; UI uses one or the other depending on context
- `exposed: false` hides a tier from CRUD/UI without breaking the schema — supports v1 "two tiers only" experimentation if user wants
- `tagging_style` — `"color"` | `"symbol"` | `"both"` — controls Topic-row tagging visual in the sidebar

