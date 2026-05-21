### Prospects

> Potential features — not committed to any version. The ongoing wishlist. Items move into `Framework.md` when they become committed work.

#### Format

```
#### Feature name
**Description:** 1-4 sentences. Bullets allowed if useful.
```

---

#### Independent UI titles (non-local naming)
**Description:** Allow a Page's display title in the UI to differ from its filename on disk. v1 ties title strictly to filename — renaming the title in the UI renames the file. North-star feature for later; could be implemented as an opt-in alias layer in frontmatter without changing the file-as-source-of-truth principle.

#### In-line view embeds (`@View`) inside Pages
**Description:** Embed a Collection view directly inside a Page's prose via the `@View` directive — Notion-style. Embedded views remain available inside Contexts and Homepage as widget blocks in v1; this is about extending them inline into Pages.

On native TextKit 2, hosting a non-text view inline requires custom layout-attachment work — materially harder than on a JS editor. Feasible if Pommora ever pivots to BlockNote / Tiptap, where node-component approach applies directly. See `// ReactInfo// Editor.md` for the React-pivot path.

#### Ad-hoc page-local properties
**Description:** Allow a Page to declare properties not in its parent Vault's schema (Obsidian-flavor flexibility). v1 enforces schema conformance — every property on a Page must come from the Vault. The only "outside the schema" thing for v1 is sidebar ordering / sorting, which is UI state and lives outside file content.

#### Cloud sync (Supabase or otherwise)
**Description:** Additive translation layer that maps the local file model to a cloud database. The mapping mirrors the local SQLite shape (matching Notion / Airtable / AFFiNE convention): a single shared `pages` table with `vault_id` + `properties` JSONB; a parallel `items` table; each `_vault.json` schema → a row in a `vaults` table; each Context (Space / Topic / Sub-topic) → one row in a `tiers` table with the block tree as a JSON column. v1's on-disk model is designed to make this non-disruptive when it arrives — sync becomes pure translation, not redesign.

#### Mobile companion (iOS / iPad)
**Description:** Real long-term intent. Read + edit access to the nexus from mobile. Same Swift Package codebase ships to iPad and iOS with platform adaptations — the natural growth path on the current stack. React pivot path → `// ReactInfo// ReactInfo.md`.

#### Sub-pages (nested Page hierarchy)
**Description:** v2 candidate. Allow a Page to contain other Pages as children — Notion-style nesting. Filesystem realization: a sub-folder named after the parent Page holds its children. v1 keeps Pages flat within a Vault or Collection (no nesting), with linking handling "this Page belongs to that Page" relationships. Sub-pages complicate the membership rules (is a child Page in the same Vault as its parent? what if the parent moves?) — worth implementing once the flat model is well-exercised in practice.

#### Item ↔ Page promotion / demotion
**Description:** Dropped from v1. If an Item needs prose, the user creates a separate Page and links by ID.

**Insight for future:** Pages and Items share the same property catalog; only the storage substrate differs (Pages = `.md` + body; Items = `.json` properties, no body). Promotion / demotion is **format conversion, not data migration**:

- **Item → Page:** every property carries to frontmatter; `id` preserved (inbound relations intact); body starts empty.
- **Page → Item:** every frontmatter property migrates to `properties`; **body is stripped** — data loss, requires confirmation. `id` preserved.

What migrates either way: properties, `icon`, `tier1/2/3`. Migration code is straightforward (shared schema); only concern is the body-stripping UX. Slot as v1.x or v2.0 once typed-Collection model is exercised.

#### Property panel placement options
**Description:** v1 puts the property panel in the right inspector pane. Two alternate placements are nice-to-haves for later: below the page heading (Notion-style) and at the page bottom. Setting-toggleable per user. Doesn't block v1 — the inspector is the natural starting point — but the placements have different feel for different writing modes (top = reference-while-writing, inspector = reference-while-navigating).

#### AI chat interface in the inspector
**Description:** Second view in the right inspector pane (toggled or tabbed alongside the property panel). **Frontend to Nathan's local CLI, not an API integration** — chat UI sends to a CLI subprocess and renders streamed output. No model hosting, no API keys, no per-token costs. Nathan already runs this pattern on Obsidian; ports cleanly. Inspector dimensions (narrow, vertical, persistent) fit chat well, and it's already attached to the active Page. Implementation: chat-UI component + subprocess bridge. Slots in post-v1 without shell changes.

#### Sidebar Collection-kind indicator toggle
**Description:** A setting that adds a small per-row icon distinguishing Pages collections from Items collections in the sidebar. The default v1 sidebar is kind-agnostic; this is a power-user detail for users who want the type division visible at a glance.

#### Custom color picker for Select / Multi-select properties
**Description:** v1 uses a fixed 9-color Notion-style palette (gray, brown, orange, yellow, green, blue, purple, pink, red). A custom hex picker for option colors could come post-v1 — useful if users want brand-specific palettes or finer distinction across many options. Probably gated by the design-system customization work in the v0.6.0 Settings scaffold.

#### Hide-empty-properties toggle in the property panel
**Description:** v1 shows every property from the Vault's schema in the property panel (Notion-style), even when the value is unset. A setting-toggleable mode that hides unset properties would reduce visual noise on Pages with many schema properties but few values per entry — useful for sparsely-populated databases. Post-v1.

#### Drag-to-reorder schema-level property declarations
**Description:** v1 appends new properties to the schema in declaration order; there's no UI for reordering the property list itself. Drag handles in some schema-editing view could let users restructure the canonical property order. Note this is distinct from view-level column reordering (which is already in v1, visual, per-view) and from option-order-within-a-Select (also in v1, drives sort).

#### Board view: drag-to-rewrite-frontmatter
**Description:** Planned post-v1.0 feature. Board view (kanban) ships in v0.5.0 as the visual layout — cards grouped by a property's options; moving a card between columns is done by editing the card's property via the card UI. Drag-to-rewrite-frontmatter (dragging a card across kanban columns to mutate the source's property value directly) is the higher-fidelity UX, but it requires the property edit / atomic write / file watcher loop to be hardened first. Slot for v1.x or v2.0 once foundations stabilize.

#### Quick-capture (Cmd+Shift+N / menu-bar)
**Description:** Global Cmd+Shift+N or menu-bar popover creating Items / Pages / Agenda from anywhere in the OS. Right-click is canonical contextual creation; quick-capture is the discoverable global counterpart, absorbs most CRUD entry traffic. Slotted v0.6.0.

Shape borrows from Things 3, NotePlan, Drafts: tiny floating window, defaults to user-configured "inbox" Vault, optional Tier1/2/3 + Vault override fields. Enter submits; Esc dismisses.

#### Hover-icon "+" affordance on sidebar section headings
**Description:** Visible counterpart to the right-click creation menu — section headings (Spaces / Topics / Vaults) get a hover-revealed "+" icon at the trailing edge (same pattern as the disclosure chevron). Click triggers the section's default new sheet. **Explicitly skipped in v0.2** in favor of right-click-only; if sidebar discoverability becomes a friction point pre-quick-capture, this is the open slot. After quick-capture ships, this likely stays deferred indefinitely — quick-capture is the primary discoverable path.

#### Pinned-page user pinning (the "Saved" section's real role)
**Description:** v0.2 ships the Saved section heading-less with three fixed entries (Homepage / Calendar / Recents). Post-v1: users pin arbitrary pages / items / agenda / contexts; section gets "Saved" heading + "+" affordance; defaults become movable. `saved-config.json` already accommodates arbitrary `items[]`.

#### Synced blocks (inline Page-body editing inside embeds)
**Description:** Notion-style synced blocks — embedding a Page inside a composed-page surface such that body edits mirror both ways. v1 covers properties, relations, Items, Agenda, and Collection-row inline editing; **full Page-body transclusion is deferred**. Requires per-block addressable IDs in Markdown, transclusion-aware undo/redo, cross-surface cursor coordination, conflict resolution, and a richer serializer. Post-v1 once the v1 editor + watcher loop is exercised. v1 stand-in: Linked Pages widget (title + frontmatter inline; click opens Page tab).

