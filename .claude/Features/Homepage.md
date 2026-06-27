### Homepage

Pommora's **singleton dashboard entity** — one per Nexus, fixed location, no `id` / tier / parents. The user's landing surface. It shares the composed-blocks pattern with Contexts (same `blocks` field, widget types, inline editability) but differs in identity: Contexts are tiered entities things relate *to*; Homepage is a singleton that pulls things *in*.

---

#### On disk

```
<nexus-root>/
  .nexus/
    homepage.json          ← singleton; fixed location
```

Seeded on first launch with empty `blocks`; not user-deletable (regenerates if removed externally).

---

#### Schema

```json
{
  "schemaVersion": 1,
  "icon": "house",
  "banner": "<nexus-relative image path>",   // optional; absent = no banner
  "blocks": [ /* composed-blocks tree — types below */ ],
  "modified_at": "<ISO-8601 timestamp>"
}
```

No `id` / `tier` / `parents` (the file location is the identity), and no `title` — the Homepage surfaces under the **Nexus header** (the nexus folder name). See [[Sidebar]].

---

#### Banner

A full-width banner heads the dashboard — a bounded image band **identical to the content-view banner** (shared band height, gutters, and title treatment), set / changed / removed in place. It's a **background layer**: the folder title overlays it now, and pinned widgets (time, weather, …) overlay it later, while the dashboard body flows below a divider. Image bytes live in `.nexus/assets/homepage/`; the nexus-relative path persists as `banner` (absent ⇒ no banner). The shared banner mechanism is one component reused by both the Homepage and content views.

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

#### Sidebar integration

The **Nexus header** at the top of the sidebar — per-Nexus avatar, folder-name title, and subtitle — is the Homepage's entry point: selecting it opens this file in the main pane (saved-key `homepage`, fixed). The former Homepage / Calendar / Recents pinned leaves were retired in its favor. Sidebar structure is canonical in [[Sidebar]].

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

