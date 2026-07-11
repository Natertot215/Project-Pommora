### Contexts Overview

The organization layer. Three **free-standing** tiers — Areas (1), Topics (2), Projects (3) — that the operational entities (Pages, Tasks, Events) tag. Per-tier labels are user-configurable; tier *numbers* are fixed.

The tiers are independent: none contains, parents, or is restricted to another. A Project isn't "inside" a Topic; a Topic doesn't belong to an Area. Operational entities tag any tiers independently — a Page can relate to a Topic without relating to an Area.

| Tier | Default label | Role |
|---|---|---|
| 1 | Areas | Broad life domains — Personal, Academics, Work |
| 2 | Topics | Subject areas — Productivity, Side Projects, Reading List |
| 3 | Projects | Specifics — CS 161, Pommora, "Atomic Habits" |

Each tier is a **folder with a config sidecar** under `.nexus/` — the same folder-plus-sidecar idiom as Page Collections. A Context holds no pages and no property schema; it's a place things point at, not a container. Context-to-context relations are a deferred design pass (see Prospects).

### Features

#### II. Shared Shape

All three tiers share one sidecar shape: `id` (ULID), `tier` (1 / 2 / 3), an optional `icon`, an optional `banner` (a Nexus-relative image path), `modified_at`, and any foreign keys preserved by value. **Areas additionally carry an optional `color`** drawn from a fixed ten-value palette (gray, brown, orange, yellow, green, blue, purple, pink, red, accent); an unrecognized value degrades to no color rather than failing the sidecar. Topics and Projects carry no color.

There's no `parents` field and no containment. The folder name is the title — there's no `title` field on disk, and renaming in the UI renames the folder. A `blocks` field, if present, rides through as a preserved foreign key — the block-surface system it's reserved for is built ([[SurfacePM]]); whether Contexts host it rides the contexts-architecture pass.

#### II. Sidebar

In the sidebar's **Contexts mode** (opened from the ribbon), the three tiers surface as three disclosure rows, top to bottom Areas → Topics → Projects. A tier row is a structural disclosure — never selectable, open by default, and clicking it toggles its own disclosure only. Each tier's entities render as flat, draggable leaf rows inside it, reordered within the tier. All three tiers' entities use the grid icon.

Tier labels read from the per-Nexus label settings. Creation is a right-click in the Contexts mode area — a native picker offering New Area / Topic / Project, each scoped to its own tier. Full sidebar layout → `Sidebar.md`.

#### II. Cross-Layer Relations

Pages, Tasks, and Events tag Contexts through per-tier multi-relation fields at the frontmatter or JSON root:

```yaml
tier1: [<area-id>, ...]
tier2: [<topic-id>, ...]
tier3: [<project-id>, ...]
```

Each is a multi-value relation, filled independently and stored as **bare ULID arrays** — not the `$rel`-tagged shape, which is reserved for user and Agenda properties. These tier links are the **only** relation-type connection in the product.

A tier relation is a dual surface:

- **Outbound (entity → Context)** — the writable side: the operational entity holds the Context's ID in its `tierN` array. Contexts carry no reverse field.

- **Inbound (Context → entities)** — every tier value emits one edge into the index's `context_links` table, so "every entity tagging this Context" resolves as a pure index query with no stored inbound list.

The effective per-Type schema merges three pre-configured tier relation properties (`_tier1` / `_tier2` / `_tier3`) after the user-defined ones, each adopting the per-Nexus tier label and icon. The index builds tier links directly from the raw `tierN` arrays, independent of that merge.

### Architecture

#### II. On-Disk Layout

```
.nexus/
  areas/<Title>/_area.json        id, tier 1, icon?, color?, banner?, modified_at
  topics/<Title>/_topic.json      id, tier 2, icon?, banner?, modified_at
  projects/<Title>/_project.json  id, tier 3, icon?, banner?, modified_at
```

Contexts live entirely under `.nexus/`, never at the Nexus root. The sidecar filename is the kind authority. Banner image bytes live under `.nexus/assets/<context-id>/` and are served to the renderer over the read-only `nexus-asset://` scheme; the sidecar holds only the Nexus-relative path. Sibling order persists per Nexus in `.nexus/state.json` (`area_order` / `topic_order` / `project_order`).

#### II. CRUD + Validation

All three tiers run through one generic folder-entity CRUD — no per-tier managers:

- **Create** writes the folder plus its sidecar with a fresh ULID and the tier number; Areas also seed `color`.
- **Rename** is a folder rename (filename = title), refused on a sibling collision.
- **Delete** unlinks the Context's ID out of every entity's `tierN` arrays first, then moves the folder to the in-Nexus `.trash` (recoverable).
- **Update** is a read-modify-write that merges the patch and retains foreign keys.

Validation at every write: the title is non-empty and free of path separators, NUL, `.`/`..`, and managed extensions, and can't collide with a same-tier sibling. There's no parent or containment validation — the tiers are free-standing.

#### II. Index

The SQLite index — a regeneratable accelerator off the read path — holds a `contexts` row per tier entity (keyed by tier) and a `context_links` row per tier reference, indexed by source, target, and property. The reverse query reads `context_links` by target. Losing the index loses nothing: it rebuilds from the sidecars and the entities' tier arrays.

### Pending

**Context Block Surfaces:** The Context detail view is a placeholder — a blank surface under the banner. The block-surface system is built host-agnostic ([[SurfacePM]] — live on the Homepage dev host); whether and how Contexts host it rides the contexts-architecture pass. The reserved `blocks` field rides through as a preserved foreign key until then.

**Linked-From:** The inbound reverse query (`context_links` by target) is indexed, but the surface that lists every entity tagging a Context — grouped by kind — isn't built.

**Tier Label Configuration:** Tier labels resolve from the per-Nexus settings labels. A dedicated tier-config singleton (separate singular and plural per tier, plus a hide-tier toggle) is planned; once it lands, the synthesized tier-property names read from it rather than falling back.

### Prospects

**Context-to-Context Relations:** Topics relating to Areas, Projects to Topics and Areas, edited from each Context's settings surface. Out of scope until its own design pass.

**Transitive Roll-Up:** Page → Project → Topic → Area aggregation, so a higher tier can surface everything its lower tiers gather.

**Empty Tier Keys:** Clearing a tier leaves its frontmatter key holding an empty array rather than removing it (the established indexing reads the key's presence); dropping the empty key to match the properties no-empties rule is a possible future alignment.
