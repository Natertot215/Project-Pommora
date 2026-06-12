## Views — Spec (solution-neutral)

**Status:** the design intent for the Views cluster, rewritten **solution-neutral** (2026-06-12) after the first implementation — a hand-rolled SwiftUI table — was abandoned on hands-on review. This file captures WHAT Views must be and do; it deliberately does NOT prescribe the renderer technology. The renderer is an open design choice for the retry (see the post-mortem in `Handoff.md` and the reusable inventory in `Views-Salvage-Manifest.md`). A fresh design pass + implementation plan come after this spec is reviewed.

### Guiding Principles

- **Native-first is non-negotiable.** Every behavior the platform provides for free — disclosure/outline groups, column resize + reorder + width persistence, row selection, keyboard navigation, drag-to-reorder, alternating row backgrounds, focus handling — MUST come from the platform's own table/outline machinery. **Do not reimplement a native control from primitives.** Custom UI is allowed ONLY where the platform verifiably cannot deliver a specific required behavior, and only for that behavior. (The first attempt failed precisely by rebuilding a native macOS table by hand; that is out of bounds.)
- **It must look and feel like a real native macOS table** — indistinguishable from the system control, not an approximation. If it doesn't read as native at first glance, the approach is wrong.
- **Files stay canonical + portable.** All view configuration persists in on-disk sidecars as a clean, stack-independent shape; the on-disk data model below is the contract and survives any renderer choice.
- **Instant reflection.** Editing a property value re-runs the active sort / filter / grouping immediately — no manual refresh, no restart.
- **Reuse existing machinery.** Cell editors, chips, the page-open router, icon picker, and the managers already exist and are reused, not re-created.

### Scope

- **Table + Gallery ship fully.** Board / List / Cards remain view-type cases the data model carries; their UI comes later.
- Ships with them: multiple saved views per container with a toolbar dropdown switcher; per-view sort / filter / group / column configuration; per-view manual reorder; per-page cover images + per-container banners; and a merged Edit Properties / Layout settings model (the standalone Property Visibility pane is retired).
- Out of scope here: page-editor rendering of the cover/banner (a later editor session), Board/List/Cards UI, multi-level sort chains, nested filter groups, full-text search wiring.

### Design Decisions (desires + intent)

1. **The table is a native macOS table** in look and behavior: native-style disclosure group rows (the real ones, not styled bands), resizable + reorderable columns with widths persisted across sessions, row selection with the standard focus/selection language, full keyboard navigation, and drag-to-reorder. How this is achieved is an implementation choice bound by the native-first principle.
2. **Title column**: movable to any position, never hideable. The Modified column IS hideable (sorting must not depend on a column being visible).
3. **Gallery card sizes** Small / Medium / Large = exactly **8 / 6 / 4** cards per row.
4. **Covers + banners:**
   - **Cover** = a per-page image (a reserved frontmatter field, nexus-relative path). Cover DISPLAY is a per-view toggle, **default OFF**; toggled on with no cover set, cards show an empty fill. **The cover field never appears in any properties UI** (not Edit Properties, not the visibility list, not the inspector). Access points: gallery view settings, right-clicking a card's visible cover area (Set / Change / Remove), and — later — inline on the page editor. No cover access from the table view.
   - **Banner** = a per-container image (on the vault / collection sidecar). When unset, the banner area does not exist at all; when set, a full-width image renders above the container title (the header zone grows taller), in every view type, and is hideable per view. **Add Banner is a hover-revealed floating button that appears only when no banner is set** — it must follow the SAME affordance as the page "Add Icon" button (a faint ghost button, not a colored link).
   - Chosen image files are copied into a nexus-internal assets folder (per-entity), so covers/banners are self-contained and portable.
5. **Grouping** is either **structural** (by the natural container) or **by a property**:
   - Structural defaults — Vault views group by Collection (table: Sets nested inside the Collection disclosure; gallery: one section level per Collection, each card carrying a Set label chip). Collection views group by Set, plus an ungrouped root band; zero Sets ⇒ one flat headerless band.
   - Property grouping replaces structural grouping and flattens it into buckets (in the property's natural option order), plus a "no value" bucket.
   - Sort applies within each group.
6. **Both group-drop behaviors ship**: dropping a row into a property group rewrites that property's value in the page's frontmatter; dropping into a structural group performs a real file move (Collection / Set).
7. **Manual order is the shared container order** — the same order the sidebar mirrors. A view reorder writes through to the owning container's sidecar; it is NOT a view-local override. Manual reorder is available only when the active sort is "Manual." Sort / filter / group are pure view-level overlays that never move files. **A view-config write must never silently undo a manual reorder** (the two write paths must not clobber each other).
8. **Sort**: one active sort per view — Manual, Title A→Z / Z→A, Created, Recent, or any property ascending / descending; select & status sort by their schema option order (not alphabetic). Stored extensibly so multi-sort is a future additive change.
9. **Filters**: a flat list of rules + Match All / Any, with conservative per-type operators (matrix below). Editing happens in the View Settings popover, scoped to the active view.
10. **View switching = a toolbar Views dropdown** (a clearly SEPARATE toolbar button, not merged into the settings capsule; not tabs). Rows show the view icon + name with a muted right-side type label (e.g. **"Table"**, **"Gallery | Small"** — pipe + full size word); the type label is itself an inline type switcher (Table + Gallery active now; Board/List/Cards shown muted). A "New View" footer mints **"Untitled View"** (defaults to Table). Rename / duplicate / delete via row context menu, with a guard that at least one view always remains. The toolbar button itself has two display modes — icon-only or icon + active-view title — toggled via right-click and persisted. The last-active view per container persists across sessions.
11. **A Layout pane holds per-view display config**: a Display Banner toggle, Card Size (gallery), the **Property Visibility** list (per-view eye toggles + drag-to-reorder over ALL columns — user properties, the tier columns, and Modified; Title pinned and non-hideable; cover never listed), and a muted "Wrap Text" row (table; functional wrapping is a later pass). **Edit Properties is schema-only** — the tier columns and Modified are removed from its list (they're non-editable), and it carries no visibility toggles. The standalone Property Visibility pane is retired (its function moves into Layout).
12. **Per-view configuration persists in the view's sidecar entry**: column order + hidden set, sort, filter, group, column widths (written when a resize ends), collapsed group ids, card size, and the cover/banner display toggles.
13. **Type-switchable in place** — the same saved view can change its `type`; shared config carries across.
14. **Inline editing & interaction:**
    - Table rows rename via the context menu (no click-to-edit on the Title cell). Cards rename via double-click ON THE TITLE TEXT; double-click anywhere else on a card opens the page; a single click selects. Clicking an icon edits the icon — consistent across both view types. The saved view's own name + icon edit inline on the dropdown rows.
    - **Card property zones are fully interactive** — values can be assigned and removed directly on the card using the same editors as table cells.
    - Property edits reflect INSTANTLY in the active sort / group / filter.
15. **Page icons render correctly** — icons may be SF Symbols OR emoji/custom glyphs; every surface that shows a page icon must render both (no broken-glyph fallback).

### On-Disk Data Model

The persisted shape is renderer-independent and portable. (This is the design contract; field names are the on-disk vocabulary, not an implementation detail.)

**Saved view** (one per entry in a container's `views[]`, snake_case, all newer fields optional/`decodeIfPresent`):

```json
{
  "id": "view_<ULID>",
  "name": "All Pages",
  "icon": "tablecells",
  "type": "table | board | list | cards | gallery",
  "property_order": ["_title", "prop_<ulid>", "_tier1", "_modified_at", "..."],
  "hidden_properties": ["prop_<ulid>"],
  "sort": [{ "property_id": "_modified_at", "direction": "descending" }],
  "filter": { "match": "all | any", "rules": [{ "property_id": "...", "op": "...", "value": "..." }] },
  "group": { "kind": "structural | property | flat", "property_id": "...", "order": ["..."] },
  "column_widths": { "_title": 240.0 },
  "collapsed_groups": ["<containerULID | option value | _ungrouped>"],
  "card_size": "small | medium | large",
  "show_cover": false,
  "show_banner": true
}
```

- **`property_order`** is ONE ordered list of all column ids (including `_title`, tiers, `_modified_at`) paired with the **`hidden_properties`** set — replacing any older visible/hidden split. Schema properties not yet in the order are appended at resolution; reserved Title (`_title`) is structurally guaranteed (a stored order may omit it, and the resolver must still produce it).
- **`group`** is a tagged object: structural (group by the natural container) / property (group by `property_id`, optional explicit bucket `order`) / flat (no grouping). Missing ⇒ structural default. Unknown shapes degrade leniently (never poison the sidecar decode). Group ids are stable (container id / option value / `"true"`/`"false"` / `"_ungrouped"`) so collapse state survives.
- **Sort presets** map to reserved ids: Title → `_title`, Created → creation order, Recent → modified-descending. Any prior per-type default sort folds into the minted default view's sort.
- **Filter operators** (unknown op = the rule no-ops, never excludes): number `is / is_not / greater_than / less_than / is_empty / is_not_empty`; checkbox `is`; date / datetime / last-edited `is / on_or_after / on_or_before / is_empty / is_not_empty`; select / status `is / is_not / is_empty / is_not_empty`; multiSelect `contains / does_not_contain / is_empty / is_not_empty`; relation/tier links `contains / does_not_contain / is_empty / is_not_empty`; url `is / contains / is_empty / is_not_empty`; file `is_empty / is_not_empty`.
- **Cover** = a reserved `cover` field on page frontmatter; **banner** = a `banner` field on the container sidecar. Both are nexus-relative paths into a per-entity assets folder. Foreign frontmatter must be preserved on every write.
- **Active view** = a `{ containerID: viewID }` map in the per-nexus state file (session state, not the sidecar — a view-switch must not churn the sidecar). Missing entry ⇒ first view.
- **No index/database schema changes** — views are sidecar-only.

### The View Pipeline (logical model)

A single transformation feeds whichever renderer is used: **fetch (in manual/container order) → filter → group → sort within groups → a list of resolved groups**. It is pure data-in/data-out, runs in memory off the already-loaded page data (so any property edit recomputes instantly with no extra reads), and is independently testable. Drop intent (reorder vs structural-move vs property-rewrite) is likewise a pure decision over the same model. This pipeline is renderer-agnostic and is the same regardless of how the table is built.

### Table — desired look & behavior

The table must be a native macOS table (per the principles). Behaviors it must have:

- **Native-style disclosure group rows** that read exactly like the platform's outline disclosure rows (triangle + the grouping value's label + item count), scrolling with the content — NOT heavy filled bands. They carry the container affordances today's Collection/Set rows provide (Open / Edit Title / Edit Icon / Delete with the existing confirmation dialogs) and persist their collapsed state.
- **Columns**: resizable (widths persist), reorderable to any position (including before Title), right-click a header to Hide Column (Title exempt). A fixed column header.
- **Rows**: standard native row height and the native alternating-row treatment (a subtle, restrained fill). Cells reuse the existing property editors (display-first, popover-on-demand; checkboxes/status toggle directly). Rename via context menu; icon-click edits the icon. Page icons render SF-Symbol-or-emoji correctly.
- **Selection + keyboard**: single / ⌘ / ⇧ selection with the native selection language; arrow-key navigation, type-select, and Return/double-click to open via the existing page-open router (honoring the container's open-in mode). **Selecting a row must NOT highlight the whole pane** — selection chrome is per-row, native.
- **Must-not-regress** (from the current detail view): double-click routing per open-in mode; Title-cell context menus (Edit Title / Edit Icon / Pin / Delete + container dialogs); per-type cell-editor behaviors + popover commit semantics; collection-root-only manual drag (Sets are not draggable as items); the rename alert; the icon picker; the footer crumb; and the context-resolver warm-up on appear.

### Gallery — desired look & behavior

- A responsive card grid at 8 / 6 / 4 columns per Small / Medium / Large; one section per resolved group, with the same disclosure/collapse behavior as the table.
- **Card anatomy**: cover area only when the view's cover display is on (fixed aspect, fill + clip; empty fill when no cover set) → header (icon + title) → property zones — chips (select / multiSelect / status / tier relations, + the Set label chip at vault scope), meta (dates / last-edited / number / checkbox), links (url) — ordered by the view's property order, showing non-hidden properties, and **fully interactive** (the same editors as table cells; assign + remove on the card). Exact visual treatment lands with a Figma pass; the zone partition is componentized so visuals slot in.
- Hover gives a subtle scale/shadow; single click selects, double-click on the title renames, double-click elsewhere opens; right-click = the page context menu; right-click the visible cover area = Set / Change / Remove Cover. Reuses the existing chip components. (The gallery is a real grid and was not the part that failed — it largely carries forward.)

### Drag & Drop (behaviors)

- Rows reorder by drag with a clear, live drop indicator (insertion line / gap for the table; live reflow for the gallery). Multi-selected rows drag together. Use the platform's native drag-reorder where the chosen control provides it; only fall back to custom drag mechanics for a specific behavior the platform can't deliver.
- Group headers and section bodies are drop targets; the drop's intent resolves to a same-container reorder (only when sort = Manual), a structural file move, or a property rewrite.
- Auto-scroll near the edges during a drag.
- The same drag-reorder quality applies to the settings reorder surfaces (the property-order / option-list editors).

### Covers + Banners

- Thumbnails load efficiently — downsampled decode, in-flight coalescing, and a cross-launch cache of decoded thumbnails (an established image pipeline rather than a hand-built loader; the specific library is an implementation choice).
- Add Cover (cards) and Add Banner (container header) follow the page "Add Icon" hover-button pattern → an image file picker; the chosen file is copied into the per-entity assets folder (the copy must complete within the file-access grant before the async write). Replacing or removing a cover/banner deletes the orphaned asset after the write succeeds.

### Views Dropdown + View Settings

- **Views dropdown**: a clearly separate window-toolbar button (its own pill, a visual peer of the settings capsule). One popover of custom rows; the type label is an inline expander (no nested popovers); view name + icon edit inline on the row. System menus can't render this — custom rows are required.
- **View Settings popover** is active-view-scoped, with panes: **Edit Properties** (schema-only), **Layout** (Display Banner + Card Size + Property Visibility + muted Wrap Text; the vault-scoped open-in selector is labeled "Open Pages In"), **Sort** (single picker), **Filter** (rule list + match toggle), **Group** (Default / property picker / Remove grouping). All four panes resolve and write the ACTIVE view.

### Open Implementation Questions (for the design pass)

- Which native control backs the table (the obvious candidate is the platform's outline/table view wrapped for SwiftUI — Pommora already wraps native AppKit views elsewhere), and how the resolved-groups pipeline feeds it.
- Whether the gallery's existing grid carries forward as-is.
- The thumbnail image pipeline choice.
- These are settled in a short brainstorm before the implementation plan — not in this spec.

### Deferred

Board / List / Cards UI; multi-level sort; nested filter groups; page-editor rendering of the cover/banner; a "columns = Sets" Board variant; embedded-view query support.
