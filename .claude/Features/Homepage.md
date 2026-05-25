### Homepage

Pommora's **singleton dashboard entity** — one per Nexus, fixed location, no parents, no tier. Composed-blocks surface that can embed any entity; the user's landing surface.

Shares the composed-blocks pattern with Contexts (same `blocks` field, widget types, inline editability) but differs in **identity / parenting**: Contexts are tiered entities things relate *to*; Homepage is a singleton that pulls things *in*.

---

#### On disk

```
<nexus-root>/
  .nexus/
    homepage.json          ← singleton; fixed location
```

Seeded on first launch with a minimal default (welcome heading + empty callout). User-deletion not supported (regenerates if removed externally).

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

Same block types as Contexts:
- Text: paragraph, heading, list, callout, code, quote, divider, columns
- Widgets:
  - `embedded-collection-view` — saved Vault view, rendered inline (editable)
  - `embedded-context-view` — auto-collected linked-content from a Context
  - `linked-pages` — Pages whose `tierN` includes a specified Context (queried via `IndexQuery.entitiesByScope(.contextTier(N))`)
  - `link-list` — manually curated links
  - `mini-calendar` — small Agenda view (ships v0.8.0)

All widgets render as **live, fully-editable views of their source** — never read-only snapshots. Edits flow to source files via atomic write. Inline-editing principle → `// Features//Domain-Model.md`.

---

#### Pinned-section integration

The pinned section at the top of the sidebar (heading-less in v0.2; gains "Saved" header when user-pinning ships) contains the `Homepage` entry that opens this file in the main pane. Label is renamable via Settings → Saved Section; the `homepage` code key is fixed.

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
- **Read**: Top of sidebar → Homepage opens in the main detail pane
- **Update**: Composed-blocks editor (Phase 10 in implementation plan); inline-edit any embedded widget per the inline-editing principle
- **Delete**: Not user-deletable; regenerates if removed externally

---

#### Validation

1. Exactly one `.nexus/homepage.json` per Nexus — created on first launch if missing
2. Schema-version respected on load; future migrations handled additively

---

