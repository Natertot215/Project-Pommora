### Prospects

> Potential features. Not in immediate scope; brainstormed ideas that we may build in the future. Items here aren't committed to any specific version — they're the ongoing wishlist. Items get pulled out of Prospects and into `Framework.md` when they become committed work.

#### Format

Each prospect uses the format below. Easy to add new entries: copy the template, fill in the description.

```
#### Feature name
**Description:** 1-4 sentences. Bullets allowed if useful.
```

---

#### Independent UI titles (non-local naming)
**Description:** Allow a Page's display title in the UI to differ from its filename on disk. v1 ties title strictly to filename — renaming the title in the UI renames the file. North-star feature for later; could be implemented as an opt-in alias layer in frontmatter without changing the file-as-source-of-truth principle.

#### In-line view embeds (`@View`) inside Pages
**Description:** Embed a Collection view directly inside a Page's prose via the `@View` directive — Notion-style. Embedded Collection views remain available *inside Spaces* (as widget blocks) for v1; this prospect is about extending them inline into Pages.

**For React**

An `@View` directive becomes a custom block / node component on top of BlockNote or Tiptap — well-trodden territory on either.

**For Swift**

On SwiftUI Option 1 (native editor), hosting a non-text view inline in the prose flow requires custom layout attachment work — materially harder than on a JS editor. On Option 2 (WKWebView + JS editor), the same BlockNote / Tiptap approach used on React applies, making this feasible on either stack if a JS editor is chosen.

#### Ad-hoc page-local properties
**Description:** Allow a Page to declare properties not in its Collection's schema (Obsidian-flavor flexibility). v1 enforces schema conformance — every property on a Page must come from the Collection. The only "outside the schema" thing for v1 is sidebar ordering / sorting, which is UI state and lives outside file content.

#### Cloud sync (Supabase or otherwise)
**Description:** Additive translation layer that maps the local file model to a cloud database. The mapping mirrors the local SQLite shape (matching Notion / Airtable / AFFiNE convention): a single shared `pages` table with `collection_id` + `properties` JSONB; a parallel `items` table; each `_collection.json` schema → a row in a `collections` table; each Space → one row in a `spaces` table with the block tree as a JSON column. v1's on-disk model is designed to make this non-disruptive when it arrives — sync becomes pure translation, not redesign.

#### Mobile companion (iOS / iPad)
**Description:** Real long-term intent (not just "potential"). Read and edit access to the vault from mobile devices. iPad and iOS are both on the table.

**For React**

A separate effort — Capacitor wrapper or a parallel native build. Any data-layer TypeScript that's been kept UI-free can be reused, but the React UI is not portable to mobile-native paradigms.

**For Swift**

Essentially free — the same Swift Package codebase ships to iPad and iOS with platform adaptations. The natural growth path on this stack.

#### Sub-pages (nested Page hierarchy)
**Description:** v2 candidate. Allow a Page to contain other Pages as children — Notion-style nesting. Filesystem realization: a sub-folder named after the parent Page holds its children. v1 keeps Pages flat within a Pages collection (no nesting), with linking handling "this Page belongs to that Page" relationships. Sub-pages complicate the membership rules (is a child Page in the same Collection as its parent? what if the parent is loose?) — worth implementing once the flat model is well-exercised in practice.

#### Item ↔ Page promotion / demotion
**Description:** Currently dropped from v1 alongside the typed-Collection model. If an entry inside an Items collection later needs prose, the user has to create a separate loose Page (or a Page inside a different Pages collection) and link to the Item by ID — manual, not automatic.

**The design insight worth preserving for the future build:** Pages and Items share the same property catalog. The only structural difference is the storage substrate (Pages = `.md` with frontmatter + body; Items = `.json` with `properties` key, no body). That makes promotion / demotion **conceptually a format conversion, not a data migration**:

- **Item → Page (promotion):** every property value carries over to the new Page's frontmatter directly (same property names, same value shapes). The new Page starts with an empty body for the user to fill in. The Item's `id` is preserved on the new Page so inbound relations stay intact. The Item file is then deleted (or kept and the new Page is linked).
- **Page → Item (demotion):** every frontmatter property migrates to the new Item's `properties` key. **The Markdown body is stripped** (Items have no body) — this is data loss and must be confirmed by the user before the operation runs. `id` is preserved.

In either direction, what migrates: properties (relations, dates, tags, selects, numbers, etc.), `icon`, `spaces`. What doesn't migrate on demotion: the Markdown body content. The migration code is straightforward (no schema reconciliation needed since both kinds share the same Collection schema) — the only real concern is the body-stripping UX on demotion.

Slot this as a probable v1.x or v2.0 quality-of-life addition once the typed-Collection model is exercised in practice and the friction surfaces (or doesn't).

#### Property panel placement options
**Description:** v1 puts the property panel in the right inspector pane. Two alternate placements are nice-to-haves for later: below the page heading (Notion-style) and at the page bottom. Setting-toggleable per user. Doesn't block v1 — the inspector is the natural starting point — but the placements have different feel for different writing modes (top = reference-while-writing, inspector = reference-while-navigating).

#### AI chat interface in the inspector
**Description:** Add an AI chat surface as a second view in the right inspector pane (toggled or tabbed alongside the property panel). **Frontend to Nathan's existing local CLI, not an API integration** — the chat UI sends user input to a CLI subprocess and renders streamed output. No model hosting inside the app, no API keys to manage, no per-token costs. Nathan has already built and uses this pattern on Obsidian; the same architecture ports cleanly to Pommora. The inspector has the right dimensions for chat (narrow, vertical, persistent during navigation) and the right context (already attached to the active Page). Implementation is essentially a chat-UI component + a subprocess bridge. v1 ships with the inspector hosting only the property panel; this addition slots in cleanly post-v1 without changing the shell.

#### Sidebar Collection-kind indicator toggle
**Description:** A setting that adds a small per-row icon distinguishing Pages collections from Items collections in the sidebar. The default v1 sidebar is kind-agnostic; this is a power-user detail for users who want the type division visible at a glance.

#### Custom color picker for Select / Multi-select properties
**Description:** v1 uses a fixed 9-color Notion-style palette (gray, brown, orange, yellow, green, blue, purple, pink, red). A custom hex picker for option colors could come post-v1 — useful if users want brand-specific palettes or finer distinction across many options. Probably gated by the design-system customization work in Framework v0.12.

#### Hide-empty-properties toggle in the property panel
**Description:** v1 shows every property from the Collection's schema in the property panel (Notion-style), even when the value is unset. A setting-toggleable mode that hides unset properties would reduce visual noise on Pages with many schema properties but few values per entry — useful for sparsely-populated databases. Post-v1.

#### Drag-to-reorder schema-level property declarations
**Description:** v1 appends new properties to the schema in declaration order; there's no UI for reordering the property list itself. Drag handles in some schema-editing view could let users restructure the canonical property order. Note this is distinct from view-level column reordering (which is already in v1, visual, per-view) and from option-order-within-a-Select (also in v1, drives sort).

#### Board view: drag-to-rewrite-frontmatter
**Description:** Planned post-v1.0 feature. Board view (kanban) ships in v0.9 as the visual layout — cards grouped by a property's options; moving a card between columns is done by editing the card's property via the card UI. Drag-to-rewrite-frontmatter (dragging a card across kanban columns to mutate the source's property value directly) is the higher-fidelity UX, but it requires the property edit / atomic write / file watcher loop to be hardened first. Slot for v1.x or v2.0 once foundations stabilize.

