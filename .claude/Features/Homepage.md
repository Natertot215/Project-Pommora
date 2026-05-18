### Homepage

Pommora's **singleton dashboard entity** — one per Nexus, fixed location, no parents, no tier. A composed-blocks surface that can embed any other Pommora entity, designed as the user's general dashboard / landing surface.

Structurally distinct from Contexts (Spaces / Topics / Sub-topics) but **shares the same composed-blocks surface pattern** — same `blocks` field, same widget types, same inline editability rules. The only difference is **identity / parenting**: Contexts are tiered, parented entities that things relate *to*; Homepage is a singleton that pulls things *in*.

---

#### On disk

```
<nexus-root>/
  .nexus/
    homepage.json          ← singleton; fixed location
```

Seeded on first launch (along with `nexus.json`, `tier-config.json`, etc.) with a minimal default — welcome heading + empty callout — so the file always exists. User-deletion is not supported (the file regenerates if removed externally).

---

#### Schema

```json
{
  "schemaVersion": 1,
  "icon": "house",
  "blocks": [
    /* composed-blocks tree — text, headings, callouts, columns,
       embedded-collection-view, embedded-context-view,
       linked-pages, link-list, mini-calendar (Agenda), etc. */
  ],
  "modified_at": 1716480000
}
```

Notable absences vs. Context entities:
- **No `id`** — the file location IS the identity
- **No `tier`** — Homepage isn't part of the tier system
- **No `parents`** — it's not parented to anything
- **No `title`** — UI label comes from `saved-config.json` (renamable)

---

#### Composition surface

Same block types as Spaces / Topics / Sub-topics:
- Text blocks: paragraph, heading, list, callout, code, quote, divider, columns
- Widget blocks:
  - `embedded-collection-view` — a saved view from any Vault, rendered inline (editable per the inline-editing principle)
  - `embedded-context-view` — auto-collected linked-content from a Space / Topic / Sub-topic
  - `linked-pages` — Pages whose `tierN` includes a specified Context
  - `link-list` — manually curated list of links
  - `mini-calendar` (post-v0.10) — small Agenda view

All widget blocks render as **live, fully-editable views of their source** — never read-only snapshots. Inline editing of properties, completion toggles, row creation, etc. all flow through to the underlying source files via atomic write. See `// Planning//Contexts-Vaults-spec.md` for the full inline-editing principle.

---

#### Pinned-section integration

The pinned section at the top of the sidebar (heading-less in v0.2; gains a "Saved" header when user-pinning ships per the Prospects entry) contains the `Homepage` entry that opens this file in the main pane. The label is user-renamable via Settings → Saved Section (per `saved-config.json`); the `homepage` code key is fixed.

```json
// .nexus/saved-config.json
{
  "schemaVersion": 1,
  "items": [
    { "key": "homepage", "label": "Homepage" },
    { "key": "calendar", "label": "Calendar" },
    { "key": "recents",  "label": "Recents" }
  ]
}
```

---

#### CRUD

- **Create**: Seeded on first launch — no user-creation action (Homepage is a singleton)
- **Read**: Top of sidebar → Homepage opens in a tab
- **Update**: Composed-blocks editor (Phase 10 in implementation plan); inline-edit any embedded widget per the inline-editing principle
- **Delete**: Not user-deletable; regenerates if removed externally

---

#### Validation

1. Exactly one `.nexus/homepage.json` per Nexus — created on first launch if missing
2. Schema-version respected on load; future migrations handled additively

---

#### Full specification

Complete schema and CRUD details live in `// Planning//Contexts-Vaults-spec.md`.
