## Cards View — Implementation Planning Checklist

> **What this is:** the carry-forward list for the Cards view's **proper implementation planning phase**. The current `cards-view` branch is a fast, visuals-first *prototype* (built live, un-reviewed) proving the design out; it is NOT the hardened build. Planning takes the ratified [[Cards View — Decision Log]] + this prototype and produces a real implementation plan. Everything below must be weighed before that plan is called done.

### Current State (the prototype)

Shipped on `cards-view` (commits `dd6f6d1b` → `b530d097`), gates green (1681 tests, but **none cover CardsView itself**):

- Cards activated as a view type — both ViewSettings doors, the options pane (Card Banner · Style · Hide Location · Wrap Titles · Hide Icons · Set Cards · Scale slider), persisted keys with `.catch` codec discipline.
- Renderer seam (`ViewRenderer`) consumed by both `ContainerView` and `ViewEmbedBlock`; pipeline reused verbatim.
- `CardsView`: Set Cards row, flattened disclosure bands, breadcrumb footing, in-band card drag, Standard/Compact property bodies through the table's `Cell`, per-value interaction (`CardValue`), the two-stage add-picker.
- Supporting: design-system `Slider`, the view-save double-walk fix, `hover-pop` compositor fix, the Grouping-pane's `subGrouping={false}` cards variant.

### Pre-Work (prerequisites, land before / alongside the plan)

- **TabBar overflow scroll** — not yet implemented. Many tabs currently have no scroll affordance; needed before the Cards work leans harder on tabbed navigation.
- **Per-collection Open-In toggling** — the collection's full-page vs page-preview Open In, toggled per-collection. Page-card and Set-Card navigation should honor it (a card open respects the collection's Open In, like the table's row-click does).

### Plan Don't-Forget

**Nathan's explicit items:**

- **Card-view default icon** — a cards-type view still shows the **table** glyph as its view icon (`mintBase` hardcodes `icon: 'table'`; `setType` never re-icons). A view's default icon must follow its type (cards → `cards-grid`) while a user's custom icon still overrides. Decide: per-type default at the icon-resolution seam vs. at mint/type-switch.
- **Native right-click "Add Property" context menu** — a real OS/native menu on the card (the `window.nexus.*Menu` IPC pattern), **separate from** the in-app add-picker (the PickerMenu). Right-click a card → native "Add Property" (and likely the card's own Rename · Change Icon · Delete).
- **Compact styling — come back to Nathan first.** Do NOT finalize the Compact card layout's visual treatment (value density, padding, flow packing, chip zoom) without his sign-off. The knobs exist (`--chip-zoom`, `--chip-pad-x`, flow gaps); the *look* is unratified.

**Flagged deferred this session (must be planned in or explicitly parked):**

- **B-6 persistent thumbnail cache — decided but NOT built.** Preview-mode covers still evict on the recents∪pins window (`evictThumbs`), so Preview shows placeholders for anything outside recents and covers vanish over time. The decision: retire the window-pruning, make the cache amend-only, move cleanup to existence-pruning at the nexus-open hook. Real main-process work; Preview mode is half-true until it lands.
- **Sort-by-Location — NOT built.** No `Location` entry in the Sorting pane, no flatten-mode in `resolveView`. E-4's mechanism (flatten structural bands into one headerless list at the resolve/renderer level, NOT a `sort.ts` criterion) is spec'd but unimplemented.
- **Add-picker value panes are chip-only.** First-time *add* covers Select/Status/Multi (the chip-pickable set, `ADDABLE_TYPES`). Date/Number/URL/Checkbox first-add need their value panes built into `CardAddPicker` (calendar, inline editor, toggle). Per-value *editing of existing* values is complete for all kinds.
- **Right-click value context menus — NOT wired.** The left-click matrix is done (`CardValue`); the menu half (Clear · Style · Edit per kind, the table's `A-13` matrix) is pending.
- **Set-Card drag/reorder** — Set Cards don't drag; reordering sets is filesystem semantics, parked with cross-band work.
- **Custom group-order can't be authored in-gallery** — renders whatever `group_order` holds (authored via the table) until band drag arrives (E-8 known limit).
- **`viewFormatMenu` IPC orphan** — the table Format row's native-menu IPC is superseded by the D-8 click-toggle; retire it + its preload entry with the next main-process batch (J-6).

### Quality Gates The Plan Must Schedule

- **CardsView test coverage** — none exists. Cover the pure/logic seams: `flattenGroups`, the `locFor` breadcrumb trim (structural slice), `reorderInBand` (full-order write), the `commitValue` tier/property router, and the add-picker's addable filter.
- **code-simplifier pass** over the whole cards diff (studio rule: required before a multi-step code task is done).
- **build-breaking adversarial review** of the hardened implementation.
- **Post-functional UIX review** of the real working cards surface (mandatory per Review-Discipline, no matter how clean the build).
- **`a11y`** — the prototype litters `biome-ignore noStaticElementInteractions`; the real build needs proper roles/keyboard on the card, value, zone, and breadcrumb click surfaces.
- **Docs** — Cards gets its own `Features/` doc (J-1); `Views.md`'s "only Table draws" / Pending-renderer framing reconciles; the `views.ts` Swift-parity header lists the cards keys (J-5).

### Prospects (later, don't foreclose)

- **File-property covers** — any File property as the card image; needs a read-only image-MIME widening of `nexus-asset://` to the nexus root + a real attach picker. The Card Banner mode set is extensible (a 4th "Property" mode).
- **Fit Image (contain vs fill) + hover-Reposition** on covers.
- **Cross-group card drag** — a card into another location band = `movePage`; into a property band = a property write.
- **Full band chrome** — band drag, native header menu, inline rename parity with tables.
- **Set-Card view previews** — click opens a preview of the Set's view (needs preview-views).

### Open Decisions For Nathan

- **Compact styling** sign-off (above) — the gating visual call.
- **The prototype's fate** — harden `cards-view` in place, or treat it as a reference and rebuild against the plan? (Affects how the plan is structured.)
- **`hideLocation` + no-properties card** — with both off, the card's only add surface is the empty text-area click (no breadcrumb, no property zone). Acceptable, or does it want an explicit affordance?
- **Add-first kind priority** — which non-chip kinds (date/number/url/checkbox) get their add value-panes first.
