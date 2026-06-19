### Prospects

> Potential features — not committed to any version. The ongoing wishlist. Entries move into `Framework.md` when they become committed work.

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

#### Cloud sync (Supabase or otherwise)
**Description:** Additive translation layer that maps the local file model to a cloud database. The mapping mirrors the local SQLite shape (matching Notion / Airtable / AFFiNE convention): a single shared `pages` table with `page_type_id` + `properties` JSONB; each Page Type's `_pagetype.json` → a row in a `types` table; each Context (Area / Topic / Project) → one row in a `tiers` table with the block tree as a JSON column. v1's on-disk model is designed to make this non-disruptive when it arrives — sync becomes pure translation, not redesign.

#### Mobile companion (iOS / iPad)
**Description:** Real long-term intent. Read + edit access to the nexus from mobile. Same Swift Package codebase ships to iPad and iOS with platform adaptations — the natural growth path on the current stack. React pivot path → `// ReactInfo// ReactInfo.md`.

#### Sub-pages (nested Page hierarchy)
**Description:** v2 candidate. Allow a Page to contain other Pages as children — Notion-style nesting. Filesystem realization: a sub-folder named after the parent Page holds its children. v1 keeps Pages flat within a Page Type or Page Collection (no nesting), with linking handling "this Page belongs to that Page" relationships. Sub-pages complicate the membership rules (is a child Page in the same Page Type as its parent? what if the parent moves?) — worth implementing once the flat model is well-exercised in practice.

#### Per-page open-in override
**Description:** `open_in` is per-vault today — every Page in a vault opens the same way (`compact` PagePreview card vs `window` detail pane). A page-level override would let one Page differ from its vault's default (e.g. a long-form Page in an otherwise compact vault). Worth revisiting once the per-vault model is exercised; a single segmented toggle per vault may prove sufficient.

#### Full Settings UI
**Description:** The Settings scaffold ships with storage + label wiring only — `.nexus/settings.json` persists the user-overridable UI labels and accent color, and the Settings manager threads those labels into the sidebar, sheets, and detail panes. There is no editing UI yet; defaults are baked in and overrides must be edited by hand in the JSON file.

The full Settings UI brings:

- **Accent color picker** — replace the JSON-edited hex value with a swatch grid + custom color well, plus live preview across selection chrome and link styling.
- **Label rename forms** — text inputs for every renameable label (the Areas / Topics / Vaults section headings, "Vault" / "Collection" defaults, "Task" / "Event" defaults, tier labels). Per-Nexus scope.
- **Tier-config consolidation** — the existing `.nexus/tier-config.json` (Area / Topic / Project label customization) folds into the same Settings surface so all label customization lives in one place.

#### Custom color picker for Select / Multi-select properties
**Description:** v1 uses a fixed Notion-style palette. A custom hex picker for option colors could come post-v1 — useful if users want brand-specific palettes or finer distinction across many options. Likely gated by the Full Settings UI work.

#### Pulldown "show empty schema entries" toggle
**Description:** The Pages-main-view Pulldown is lazy in v1 (hides empty schema entries; "+ Add property" picker reveals them). Inspectors (the main-pane `FrontmatterInspector` and the PagePreview inspector) are eager in v1 (already show every schema property). A per-Type setting that switches the Pulldown to eager mode (matching Inspector behavior) would help users explore the full schema inline on the Page main view — useful for densely-populated Page Types where the user wants to fill in many properties per Page without opening the picker. Post-v1.

#### Pinned-property zone for the PagePreview card
**Description:** A configurable set of properties surfaced in a dedicated zone of the `PagePreview` card, with a vault-level default schema overridable per-collection. Deliberately dropped: the card's default-open inspector gives the same glance-level functionality without a stored schema, an editor UI, or override rules. Revisit only if the open-inspector affordance proves insufficient in practice.

#### Drag-to-reorder schema-level property declarations
**Description:** v1 appends new properties to the schema in declaration order; there's no UI for reordering the property list itself. Drag handles in some schema-editing view could let users restructure the canonical property order. Note this is distinct from view-level column reordering (which is already in v1, visual, per-view) and from option-order-within-a-Select (also in v1, drives sort).

#### Board view: drag-to-rewrite-frontmatter
**Description:** Planned post-v1.0 feature. Board view (kanban) ships as the visual layout — cards grouped by a property's options; moving a card between columns is done by editing the card's property via the card UI. Drag-to-rewrite-frontmatter (dragging a card across kanban columns to mutate the source's property value directly) is the higher-fidelity UX, but it requires the property edit / atomic write loop to be hardened first. Deferred until those foundations stabilize.

#### Quick-capture (menu-bar / web clipper)
**Description:** Now committed roadmap, not a post-v1 prospect — full concept + architecture in [[QuickCapture]] (roadmap slot → `Framework.md`). A menu-bar capture pane (and an optional browser / Share-sheet web-clip route) adds Pages / Tasks / Events directly to the nexus as another in-process entry point. Kept here only as a redirect.

#### Hover-icon "+" affordance on sidebar section headings
**Description:** Visible counterpart to the right-click creation menu — section headings (Areas / Topics / Vaults) get a hover-revealed "+" icon at the trailing edge (same pattern as the disclosure chevron). Click triggers the section's default new sheet. **Deliberately skipped** in favor of right-click-only; if sidebar discoverability becomes a friction point pre-quick-capture, this is the open slot. After quick-capture ships, this likely stays deferred indefinitely — quick-capture is the primary discoverable path.

#### Pinned-page user pinning (the "Saved" section's real role)
**Description:** The Saved section currently ships heading-less with three fixed entries (Homepage / Calendar / Recents). Post-v1: users pin arbitrary Pages / Tasks / Events / Contexts; section gets "Saved" heading + "+" affordance; defaults become movable. `saved-config.json` already accommodates arbitrary saved entries.

#### Synced blocks (inline Page-body editing inside embeds)
**Description:** Notion-style synced blocks — embedding a Page inside a composed-page surface such that body edits mirror both ways. v1 covers properties, relations, Agenda, and Collection-row inline editing; **full Page-body transclusion is deferred**. Requires per-block addressable IDs in Markdown, transclusion-aware undo/redo, cross-surface cursor coordination, conflict resolution, and a richer serializer. Post-v1 once the v1 editor is exercised. v1 stand-in: Linked Pages widget (title + frontmatter inline; click opens Page tab).

#### Context-link tier — post-v1 deferrals
**Description:** Genuinely post-v1 deferrals remaining after the Relation→Context refactor (ship record in `History.md`):

- **Tier property icon overrides** at the nexus-default level (IconConfig effort). `BuiltInContextLinkProperties` falls back sidecar-override → hardcoded SF Symbol today; when IconConfig ships, the chain extends to sidecar override → IconConfig default → hardcoded fallback.

(Two former entries here — the "linked from" real surface and context-link sort/filter — are now committed roadmap work, promoted to `Framework.md` under the Context-views surface + per-view sort/group, not post-v1 prospects.)

#### Drag-reorder vaults within a user sidebar section
**Description:** User sidebar sections store their member vaults in display order (`vaultIDs` on `.nexus/sidebar-sections.json`), but the only mutation UI is the "Move to Section" context menu — there's no drag-to-reorder inside a section. Drag handles (or row drag) within a section would let users arrange vaults directly.

#### User-section rename validation
**Description:** Section labels rename inline with only an empty-label guard at the commit site — duplicate labels across sections are currently accepted. A uniqueness check would match the collision rules every other renameable entity follows.

