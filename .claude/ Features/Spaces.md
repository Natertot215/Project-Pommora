### Spaces

A Space is a **Notion-page-style composed surface** — text, headings, lists, callouts, columns, and widgets, all intermixed in a block-composition canvas. The only surface in Pommora with Notion-style block manipulation. Independent of Collections — a Space is never inside one.

**Spaces are referential, not containers.** A Space doesn't *hold* its referenced Pages, Items, or Collection rows — it embeds them via widget blocks: filtered Collection views (`embedded-collection-view`), Pages-with-this-Space-in-`spaces` (`linked-pages`), and manually curated lists (`link-list`). Think "grouping tag plus its own canvas": the Space carries its own content (prose, callouts, layout) and references everything else by query or ID. This is what keeps Spaces queryable and agent-legible without duplicating content.

---

#### On disk

- A `.space.json` file in `.pommora// spaces//` (e.g. `.pommora// spaces// Pommora.space.json`).
- Each Space has an ID (ULID).
- The file holds the full block tree as structured JSON — the block tree is the canonical content. No Markdown body.
- Title = filename (e.g. `Pommora.space.json` → "Pommora"). Renaming in the UI renames the file.

---

#### Schema

```json
{
  "id": "01HXXXXX...",
  "icon": "rocket",
  "blocks": [
    { "type": "heading", "level": 1, "text": "Pommora" },
    { "type": "paragraph", "text": "Active project notes." },
    { "type": "linked-pages", "view": "list", "filter": "..." },
    { "type": "columns", "children": [
      { "type": "embedded-collection-view", "collection_id": "01H...", "view_id": "01H..." },
      { "type": "link-list", "items": [ /* ... */ ] }
    ]},
    { "type": "callout", "text": "..." }
  ]
}
```

---

#### Editor surface

Spaces are composed in a **page-like canvas with drag-and-drop blocks** — Notion-style structured layout (1D vertical flow with one nestable `columns` container), not free X/Y positioning. Drag and drop blocks of any type, slash-menu insertion, reordering, multi-column layout, the full Notion-style block experience. This is the only surface in Pommora with this composition complexity.

**For React**

`@dnd-kit/core` v6.x with a flat-array `[id, depth, parentId]` tree representation. Cross-level drag (a block dragged into a `columns` child or out into the top-level vertical flow) requires the flat-array shape; nested arrays don't compose well with dnd-kit's sortable strategies. Block JSON is validated with Zod on load and save; atomic write via `.tmp` + rename; ULID per block. Detail → `// ReactInfo.md`.

**For Swift**

`Codable` `Block` enum as the model + `ReorderableVStack` from `visfitness/reorderable` (the vertical block stack) + `HSplit` from `stevengharris/SplitView` (the columns container). No SwiftUI library is a clean equivalent of React's `dnd-kit-sortable-tree`, but the shape of Pommora's problem (one nestable `columns` container + 1D vertical flow elsewhere) is the easiest version of this and the libraries above compose cleanly. Rough edges to handle: drop-indicator UX, auto-scroll while dragging, slash-menu positioning, HSplitView polish in nested splits, heterogenous `Transferable` for the block enum. Detail → `// SwiftInfo.md`.

---

#### Block types in v1

**Text blocks** (same as a Notion page):

- Paragraph
- Headings (H1–H3)
- Lists (bulleted, numbered)
- Callout
- Code block
- Quote
- Divider
- Columns (multi-column container, can nest other blocks)

**Widget blocks** (the data-aggregation layer):

- **Linked Pages** — list / cards / grid of Pages whose `spaces` property includes this Space. Filterable, sortable. Items whose `spaces` field includes this Space surface in the same widget (configurable: pages-only, items-only, or both).

- **Embedded Collection View** — render a saved view from any Collection inline within the Space. References a Collection by ID and overrides filter / sort / group / shown-properties locally without modifying the Collection's saved views. Renders members of whichever kind the source Collection is (a Pages collection renders Pages; an Items collection renders Items). Same `<CollectionViewRenderer>` (React) used in standalone Collection pages.

- **Link list** — manually curated list of links to specific Pages, Items, Collections, or Spaces.

---

#### Why Spaces exist

Spaces subsume what Notion calls "homepage" pages and what Obsidian users assemble manually with Dataview queries. They're the *aggregation and dashboard* layer — where you compose a topic-level view of your work. A Space called "Pommora" gathers every Page linked to it (via the Page's `spaces` property), can embed views from any Collection, and lets the user write supporting text and structure around all of it.
