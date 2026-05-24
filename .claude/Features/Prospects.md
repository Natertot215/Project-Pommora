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
**Description:** Allow a Page to declare properties not in its parent Page Type's schema (Obsidian-flavor flexibility). v1 enforces schema conformance — every property on a Page must come from the Page Type. The only "outside the schema" thing for v1 is sidebar ordering / sorting, which is UI state and lives outside file content.

#### Cloud sync (Supabase or otherwise)
**Description:** Additive translation layer that maps the local file model to a cloud database. The mapping mirrors the local SQLite shape (matching Notion / Airtable / AFFiNE convention): a single shared `pages` table with `page_type_id` + `properties` JSONB; a parallel `items` table with `item_type_id` + `properties` JSONB; each Page Type's `_pagetype.json` and each Item Type's `_itemtype.json` → a row in a `types` table (kind-discriminated by sidecar filename); each Context (Space / Topic / Project) → one row in a `tiers` table with the block tree as a JSON column. v1's on-disk model is designed to make this non-disruptive when it arrives — sync becomes pure translation, not redesign.

#### Mobile companion (iOS / iPad)
**Description:** Real long-term intent. Read + edit access to the nexus from mobile. Same Swift Package codebase ships to iPad and iOS with platform adaptations — the natural growth path on the current stack. React pivot path → `// ReactInfo// ReactInfo.md`.

#### Sub-pages (nested Page hierarchy)
**Description:** v2 candidate. Allow a Page to contain other Pages as children — Notion-style nesting. Filesystem realization: a sub-folder named after the parent Page holds its children. v1 keeps Pages flat within a Page Type or Page Collection (no nesting), with linking handling "this Page belongs to that Page" relationships. Sub-pages complicate the membership rules (is a child Page in the same Page Type as its parent? what if the parent moves?) — worth implementing once the flat model is well-exercised in practice.

#### Item ↔ Page promotion / demotion
**Description:** Dropped from v1. If an Item needs prose, the user creates a separate Page and links by ID.

**Insight for future:** Items and Pages share the same property catalog; only the storage substrate differs (Pages = `.md` + body; Items = `.json` properties, no body). Promotion / demotion is **cross-side format conversion, not data migration** — an Item under Item Type X is converted into a Page under Page Type Y (or vice versa). It is NOT a same-side move between containers, and it does NOT preserve the source's typed container.

- **Item → Page (promote):** every property in the destination Page Type's schema carries to frontmatter; properties absent from the destination Page Type are **stripped** (move-strip rule applies cross-side); `id` preserved (inbound relations intact); body starts empty.
- **Page → Item (demote):** every frontmatter property in the destination Item Type's schema carries to `properties`; properties absent from the destination Item Type are **stripped**; **body is stripped** unconditionally — data loss, requires confirmation. `id` preserved.

What carries either way (subject to destination schema): properties, `icon`, `tier1/2/3`. The user picks the destination Type at promotion / demotion time; the strip-on-promote warning lists what will be dropped. Migration code is straightforward (shared property catalog); the body-stripping confirmation is the main UX concern. Slot for v1.x or v2.0 once the parallel Page Type / Item Type model is exercised.

#### Item Templates (per-Item-Type customization)
**Description:** Per-Item-Type template configuration carried on the Item Type's `_itemtype.json` via a reserved `template_config` field. v0.3.0 ships every Item with the standard Item Window shape (title + properties + 250-char plain-text description) and `template_config` is always `null`. Post-v1 unlocks per-Item-Type customization:

- **Window layout** — per-Type Item Window arrangement (e.g., a Bookmarks Type shows URL prominently with a small description below; a Reading List Type shows author + rating above description).
- **Character cap override** — Item Types where 250 chars is too tight (long-form journal jottings) or too generous (single-line quick captures) can override the description cap per-Type.
- **Default description text** — placeholder or seed text inserted when an Item of this Type is created (e.g., a meeting-notes Type pre-fills a "Attendees / Decisions / Next steps" skeleton).

The `template_config` field is reserved in v0.3.0 so the on-disk shape is forward-compatible — adding per-Type templates later is additive (existing Items with `null` continue to render the standard Item Window). Editing UI ships post-v1 alongside the broader Settings UI work.

#### Full Settings UI
**Description:** The Settings scaffold ships at v0.3.0 with storage + label wiring only — `.nexus/settings.json` persists the user-overridable UI labels and accent color, and `SettingsManager` threads those labels into the sidebar, sheets, and detail panes. There is no editing UI in v0.3.0; defaults are baked in and overrides must be edited by hand in the JSON file.

The full Settings UI ships v0.6.0 and brings:

- **Accent color picker** — replace the JSON-edited hex value with a swatch grid + custom color well, plus live preview across selection chrome and link styling.
- **Label rename forms** — text inputs for every renameable label (Pages section heading, Items section heading, "Vault" / "Collection" / "Type" / "Set" defaults, "Task" / "Event" defaults, tier labels). Per-Nexus scope.
- **Tier-config consolidation** — the existing `.nexus/tier-config.json` (Space / Topic / Project label customization) folds into the same Settings surface so all label customization lives in one place.

Slotted v0.6.0 alongside the quick-capture / design-system customization batch.

#### Property panel placement options — RETIRED 2026-05-23
**Status:** Superseded by the locked surface architecture (see [[Properties]] § "Where Properties Live"). Properties live in the NavDropdown-style pulldown for Pages in the main window, and in the inspector panel for Page Preview / Item Window. Alternate placements (below page heading, page bottom) are no longer being considered as toggleable user preferences.

#### Claude chat interface as main-window inspector — IN ROADMAP 2026-05-23
**Status:** Promoted out of Prospects. Becomes the main-window inspector under the locked surface architecture (Properties live in pulldown / preview inspectors; main-window inspector is Claude chat). Frontend to Nathan's local CLI, not an API integration — chat UI sends to a CLI subprocess and renders streamed output. No model hosting, no API keys, no per-token costs. Ships in a v0.3.x patch, whenever designed.

#### Sidebar Collection-kind indicator toggle
**Description:** A setting that adds a small per-row icon distinguishing Page Collections from Item Collections in the sidebar. The default v1 sidebar already separates the two via the Pages / Items section split + the "Vault" / "Collection" vs "Type" / "Set" UI labels; this is a power-user detail for users who want an extra glance-level signal at the row level.

#### Custom color picker for Select / Multi-select properties
**Description:** v1 uses a fixed 9-color Notion-style palette (gray, brown, orange, yellow, green, blue, purple, pink, red). A custom hex picker for option colors could come post-v1 — useful if users want brand-specific palettes or finer distinction across many options. Likely gated by the Full Settings UI work in v0.6.0.

#### Pulldown "show empty schema entries" toggle
**Description:** The Pages-main-view Pulldown is lazy in v1 (hides empty schema entries; "+ Add property" picker reveals them). Inspectors (Page Preview, Item Window) are eager in v1 (already show every schema property). A per-Type setting that switches the Pulldown to eager mode (matching Inspector behavior) would help users explore the full schema inline on the Page main view — useful for densely-populated Page Types where the user wants to fill in many properties per Page without opening the picker. Post-v1.

#### Drag-to-reorder schema-level property declarations
**Description:** v1 appends new properties to the schema in declaration order; there's no UI for reordering the property list itself. Drag handles in some schema-editing view could let users restructure the canonical property order. Note this is distinct from view-level column reordering (which is already in v1, visual, per-view) and from option-order-within-a-Select (also in v1, drives sort).

#### Board view: drag-to-rewrite-frontmatter
**Description:** Planned post-v1.0 feature. Board view (kanban) ships in v0.5.0 as the visual layout — cards grouped by a property's options; moving a card between columns is done by editing the card's property via the card UI. Drag-to-rewrite-frontmatter (dragging a card across kanban columns to mutate the source's property value directly) is the higher-fidelity UX, but it requires the property edit / atomic write / file watcher loop to be hardened first. Slot for v1.x or v2.0 once foundations stabilize.

#### Quick-capture (Cmd+Shift+N / menu-bar)
**Description:** Global Cmd+Shift+N or menu-bar popover creating Items / Pages / Agenda Tasks / Agenda Events from anywhere in the OS. Right-click is canonical contextual creation; quick-capture is the discoverable global counterpart, absorbs most CRUD entry traffic. Slotted v0.6.0.

Shape borrows from Things 3, NotePlan, Drafts: tiny floating window, defaults to a user-configured "inbox" Page Type (or Item Type, per kind), optional Tier1/2/3 + Type override fields. Enter submits; Esc dismisses.

#### Hover-icon "+" affordance on sidebar section headings
**Description:** Visible counterpart to the right-click creation menu — section headings (Spaces / Topics / Items / Pages) get a hover-revealed "+" icon at the trailing edge (same pattern as the disclosure chevron). Click triggers the section's default new sheet. **Explicitly skipped in v0.2** in favor of right-click-only; if sidebar discoverability becomes a friction point pre-quick-capture, this is the open slot. After quick-capture ships, this likely stays deferred indefinitely — quick-capture is the primary discoverable path.

#### Pinned-page user pinning (the "Saved" section's real role)
**Description:** v0.2 ships the Saved section heading-less with three fixed entries (Homepage / Calendar / Recents). Post-v1: users pin arbitrary Pages / Items / Agenda Tasks / Agenda Events / Contexts; section gets "Saved" heading + "+" affordance; defaults become movable. `saved-config.json` already accommodates arbitrary `items[]`.

#### Synced blocks (inline Page-body editing inside embeds)
**Description:** Notion-style synced blocks — embedding a Page inside a composed-page surface such that body edits mirror both ways. v1 covers properties, relations, Items, Agenda, and Collection-row inline editing; **full Page-body transclusion is deferred**. Requires per-block addressable IDs in Markdown, transclusion-aware undo/redo, cross-surface cursor coordination, conflict resolution, and a richer serializer. Post-v1 once the v1 editor + watcher loop is exercised. v1 stand-in: Linked Pages widget (title + frontmatter inline; click opens Page tab).

