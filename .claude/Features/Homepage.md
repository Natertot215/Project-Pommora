### Homepage

Pommora's **singleton dashboard entity** — one per Nexus, fixed location, no `id` / tier / parents. The user's landing surface. It shares the composed-blocks pattern with Contexts (same `blocks` field, widget types, inline editability) but differs in identity: Contexts are tiered entities things relate *to*; Homepage is a singleton that pulls things *in*.

---

#### On disk

```
<nexus-root>/
  .nexus/
    homepage.json          ← singleton; fixed location
```

Seeded on first launch with empty `blocks`. Not user-deletable (regenerates if removed externally).

---

#### Schema

```json
{
  "schemaVersion": 1,
  "icon": "house",
  "blocks": [ /* composed-blocks tree — types below */ ],
  "modified_at": <epoch-seconds>
}
```

No `id` / `tier` / `parents` (the file location is the identity), and no `title` — the sidebar label comes from `saved-config.json` (renameable). See [[Sidebar]].

---

#### Composition surface

The planned block catalog (shared with Contexts; the block tree is an empty placeholder until the composed-blocks editor ships):

- Text: paragraph, heading, list, callout, code, quote, divider, columns
- Widgets:
  - `embedded-collection-view` — a saved Type/Collection view, rendered inline
  - `embedded-context-view` — auto-collected linked content from a Context
  - `linked-pages` — entities linked to a specified Context, resolved live from the index
  - `link-list` — manually curated links
  - `mini-calendar` — small Agenda view

Every widget is a **live, fully-editable view of its source**, never a read-only snapshot; edits flow to source files via atomic write (inline-editing principle → [[Domain-Model]]).

**Value rendering inside widgets** mirrors the rest of the app: tier relation values (Areas / Topics / Projects) render as the target entity's **icon + title in plain styled colored text** — never chips/pills — resolved live from the target; body wikilinks render as inline styled colored text. Both resolve by ID, so renaming a target updates the rendered label without rewriting the source.

---

#### Pinned-section integration

The pinned section at the top of the sidebar holds the `Homepage` entry that opens this file in the main pane. Its label is renameable via `saved-config.json` (the `homepage` key is fixed). Pinned-section structure + `saved-config.json` shape are canonical in [[Sidebar]] / [[NavDropdown]].

---

#### CRUD

- **Create**: Seeded on first launch — no user-creation action (Homepage is a singleton)
- **Read**: Top of sidebar → Homepage opens in the main detail pane
- **Update**: composed-blocks editor (planned); inline-edit any embedded widget per the inline-editing principle
- **Delete**: Not user-deletable; regenerates if removed externally

---

#### Validation

1. Exactly one `.nexus/homepage.json` per Nexus — created on first launch if missing
2. Schema-version respected on load; future migrations handled additively

---

