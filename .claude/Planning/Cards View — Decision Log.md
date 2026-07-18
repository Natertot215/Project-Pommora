## Cards View — Decision Log

> **Evidence vs Decisions:** This log hard-separates the two. A **[decision]** is Nathan's design call (or a jointly ratified one) — it stands on intent, not proof. **Evidence** is what the code/docs actually show, cited by source — it grounds feasibility and adjacency, never silently becomes a decision. Where a decision *uses* evidence, the entry names both halves explicitly.

### Frame

- **Purpose:** Brainstorm → spec the **Cards** view renderer for Collections and depth-1 Sets — the first of the five pending non-Table renderers (v0.6.0 opener) — plus its SurfacePM (view-embed) integration.
- **Core Value:** Pages render as a resizable card grid with cover images and property display, driven by the same pure pipeline that feeds Table.
- **Success Criteria:** A Collection/Set view switched to Cards draws cards (with or without covers), respects filter/group/sort, supports the Standard/Compact card layouts, and persists its layout options per-view.

### Sources

- [[Views]] — saved-view model already reserves `display options (card size, collapsed-group state, cover and banner toggles)` and a per-view `format` (Standard/Compact, currently the table density style); pipeline is columns → filter → group → sort; grouping doc states "calendar, gallery, timeline, cards, and list group mechanically differently — each gets its own surface with its renderer."
- [[TableView]] — the ratified cell gesture matrix is explicitly "portable to Gallery/List/Cards"; editing surfaces live view-agnostic in `PropertyEditing/`, "mounted by this table first and by the other container views later."
- [[Properties]] — File/Attachment is a real type: array of `{ path, original_name, added_at, mime_type }`, files copy into the Nexus.
- [[Navigation]] — NavView/NavWindow gallery is shipped; grid surfaces displace on drag, row surfaces use insertion lines; view mode persists per surface via store slices.
- [[SurfacePM]] — View embeds exist as a tile type (Linked/Custom) behind the slim view-chrome header; a view tile scales its content as a unit within a frozen inset. Code: `Blocks/ViewEmbedBlock.tsx`, scope in `Embeds/ViewEmbedScope.tsx`.
- `src/shared/views.ts` — `VIEW_TYPES` carries both `'cards'` and `'gallery'` (:19); `SavedView` already carried `card_size?: 'small'|'medium'|'large'`, `show_cover?`/`show_banner?`/`hide_page_icons?`, `format?: 'standard'|'compact'` (persisted, inert, documented as the *table density* knob), `collapsed_groups`, and `group_order`/`structural_order_mode`/`sub_group`/`ungrouped_placement`.
- `Components/Detail/ViewSettings.tsx` — `IMPLEMENTED` gates the type grid; unimplemented types render as inert tiles. The "Layout" leaf is `VisibilityList` (HiddenPane.tsx) + `LayoutToggles.tsx` (three Table-only switches, one `view.type === 'table'` gate). **No LayoutPane component existed** — "LayoutPane" for Cards means new content in this leaf.
- `Detail/ContainerView.tsx` hard-mounted `<TableView>`; `ViewEmbedBlock.tsx` was the second hard mount — the renderer switch must be a shared seam both consume (A-2).
- `Detail/Views/pipeline/` — `resolveView.ts` is renderer-agnostic (columns → filter → group → sort → `{columns, groups}`); `ResolvedGroup` (`shared/types.ts`) carries `items`, nested `children`, `isCollapsed`, `bucket`. `resolveColumns` (columns.ts) merges `property_order` + `hidden_properties` + schema — the card-field order source. **No sort-by-location exists** (sort.ts — per-property criteria only; Sorting pane offers Title/Modified/sortable properties).
- `NavWindow/NavGallery.tsx` + `navGallery.css` — the card precedent: pure CSS grid `repeat(auto-fit, minmax(var(--card-min), 1fr))`, knobs `--card-min`/`--card-gap-*`/`--cover-zoom`/`--thumb-share`, container-query typography (`5.5cqi` clamp), `hover-pop`, aspect-ratio card, thumb → divider → title+crumbs anatomy.
- `styles.css:89-132` — the two inset regimes: `--content-inset`/`--gutter` (standard views) vs `--surface-inset`/`--surface-inset-right` (+ banner variants) — the block-surface regime NavView's gallery rides (`navView.css:64`); NavView's *list* deliberately rides `--content-inset` instead. The pane's `.detail-body` applies the inset itself — a view that pads again double-indents (H-1).
- Cover-image plumbing: `FileRef` (`shared/propertyValue.ts:10-15`) `path` is **nexus-relative**, validated under the session root (`main/index.ts:2059-2071`); the `nexus-asset://` scheme (`main/index.ts:232-261`) serves **read-only, `.nexus/assets/` only**, image MIMEs. File values today render as chips only (`Cell.tsx:199-218`) and are **set by typing a path** (`TableView.tsx:751-792` — "multi-file editing is the picker Prospect"); no copy-into-nexus attach flow exists in code (Properties.md's "files copy into the Nexus" is intent, not built).
- Property interaction plumbing: click dispatch `TableView.tsx:692-741`; value pane `PropertyEditing/PropertyPicker.tsx`; two-stage list→detail shell `Components/Detail/PaneSlider.tsx` with `PropertiesPane.tsx`'s `SubView` state machine as the pattern. (No filter add-rule UI exists; SurfacePM has no multi-pane picker — PaneSlider is the real precedent.)
- Breadcrumb precedent: `Detail/Subfield/SubfieldBreadcrumb.tsx` + `crumbs.ts` (`chainOf` returns the Collection → Set → sub-Set chain).
- Group headers: `Detail/Views/Table/GroupHeader.tsx` (structural-set branch renders Set icon + renamable title; chevron twisty; collapse persists to `collapsed_groups` via `TableView.tsx:503-509`).
- Scale-control precedent: `Blocks/BlockHandleMenu.tsx` + `blockZoom.ts` — the drag-handle Scale row: trailing value + double-chevron, a solid nested `PickerMenu` of discrete steps, document-listener dismissal, picks scrub live with an accent check; off-grid stored factors snap to the nearest step.

### Decisions

#### A — Entry & Scope

- **A-1:** [confirmed] This feature is the **Cards** view type. It existed as a blank, non-active choice in the ViewPane/ViewSettings type picker; this work activates it via `IMPLEMENTED`. *(Decision: Nathan.)*
- **A-2:** [confirmed] SurfacePM scope: Cards renders inside the existing view embeds with no dedicated embed features — but two concrete obligations make that true: **(1)** TableView was hard-mounted in TWO places (`ContainerView.tsx` *and* `ViewEmbedBlock.tsx`) — the renderer switch is a shared `view.type` seam both consume (`ViewRenderer`), not a ContainerView-only branch; **(2)** embeds scale by the CSS `zoom` law (`Table.css` — `zoom: calc(var(--zoom) * var(--block-zoom, 1))`), which the cards root carries too or it renders full-size inside embeds. *(Decision: Nathan on scope; the obligations from adversarial review, verified.)*
- **A-3:** [confirmed] **`'gallery'` stays a separate, reserved ViewType** — an inert tile in the type grid, to become its own distinct renderer someday. Nothing in this build claims it. *(Decision: Nathan.)*

#### B — Card Image (v1: Banner-Cover + Preview)

- **B-1:** [confirmed] v1 card images come from **existing plumbing only** — a per-view **Card Banner** control with three modes: **Preview** (the captured page thumbnail, NavGallery's pipeline), **Cover** (the page's banner — the Swift-compatible `cover` frontmatter key), **None** (imageless, compact cards). *(Decision: Nathan — supersedes the file-property-as-cover idea, which moves to Prospects. Evidence: page cover writes at `main/mutate.ts:317-345` — image copied into `.nexus/assets/`, path in frontmatter; `ViewRow.frontmatter` already carries it (`shared/types.ts:476-483`, `io/pageFile.ts:28` models `cover`); thumbnails at `.nexus/assets/<nexus>/thumbnails/` via `useNavThumbnails` + `main/io/thumbnails.ts`; both serve over the existing `nexus-asset://` scheme — no protocol change, no attach flow needed.)*
- **B-2:** [confirmed] No new attach UX in v1 — the banner set flow (pick → crop → copy-to-assets → `cover` write) already exists. *(Decision: Nathan.)*
- **B-3:** [confirmed] Imageless is **per-view** (Card Banner: None), and the whole grid compacts — image-bearing and imageless card heights are each their own treatment, and the vertical distance between disclosure headings adjusts with the compacted grid. Under Preview/Cover, a page *lacking* an image shows the placeholder (uniform card heights within a view, NavGallery's model). *(Decision: Nathan.)*
- **B-6:** [confirmed] **Preview uses the one shared thumbnail cache, and the cache never disappears — it's only amended.** The recents∪pins pruning (`evictThumbs`, fired on nexus open — `store.ts:717`; `main/io/thumbnails.ts` `evictThumbnails`) is retired: a captured thumbnail persists until the next capture of the same page overwrites it (amend-in-place is already today's write — atomic overwrite of the same keyed path; the `?v=` version-bump display path is untouched). Consequences, deliberate: NavWindow/NavView gallery cards keep their thumbnails permanently too (an upgrade, same cache); disk growth is bounded by visited-page count (one JPEG each); a never-visited page has no thumbnail and shows the placeholder (capture requires rendering — inherent). Cleanup becomes **existence-pruning at the same nexus-open hook**: walk the tree for all live entity ids and pass those to `evictThumbnails` (in place of recents∪pins), so a thumbnail whose entity no longer exists is the only thing that dies. *(Decision: Nathan; hook named by adversarial review.)*

#### C — Card Layouts (Standard / Compact)

- **C-1:** [confirmed] Card layout is defined in the **LayoutPane**, as **Standard** or **Compact**. *(Decision: Nathan.)*
- **C-2:** [confirmed] **Standard:** title, then one row per property: `(Property label) – (Value)`. *(Decision: Nathan.)*
- **C-3:** [confirmed] **Compact:** title, then label-less values in a flow layout — each value takes the space it needs, values sit side-by-side, **values never wrap**; tight horizontal padding so multiple values fit per line (Notion-style). *(Decision: Nathan.)*
- **C-4:** [confirmed] Compact values flow in reading order following the property order top-down — "order is derived via property order." *(Decision: Nathan.)*
- **C-5:** [confirmed] Cards show **any and all** visible properties — the view's existing `property_order` + `hidden_properties`; `resolveColumns` yields the card-field order verbatim. Authoring surface: the LayoutPane (ViewSettings' Layout leaf) holds the visibility list. *(Decision: Nathan.)*

#### D — Card Anatomy & Sizing

- **D-1:** [confirmed] Cards reuse the NavView/NavWindow gallery card logic — image with divider + title. *(Decision: Nathan. Evidence: `NavWindow/NavGallery.tsx` + `navGallery.css` — CSS grid `auto-fit`/`minmax(--card-min)`, `--cover-zoom`/`--thumb-share`, container-query typography, `hover-pop`.)*
- **D-2:** [confirmed] Image-bearing and imageless cards each have their own height treatment; one DRY `CardsView.css` home for the CSS. *(Decision: Nathan.)*
- **D-3:** [confirmed] Card resize is the **Scale row in the options footer — a double-chevron step control** (the drag-handle Scale idiom): trailing current factor + chevrons pops the discrete steps `1.50x · 1.25x · 1.00x · 0.75x · 0.50x` in a solid nested PickerMenu; a pick writes live and keeps the dropdown open; an off-grid stored factor snaps to its nearest step on read. Reflow like gallery-mode NavViews. *(Decision: Nathan — supersedes the continuous slider; see Considered & Rejected.)*
- **D-4:** [confirmed] `card_size` persistence reshapes from `'small'|'medium'|'large'` to a number (the scale factor), legacy strings mapped on read (small 0.75 · medium 1 · large 1.25). **The codec changes in the same task:** `card_size` accepts `number | legacy-enum` with `.catch(undefined)` (its optional siblings' pattern) — a bare `z.enum` plus `parseViews`'s (`readNexus.ts`) drop-on-decode-failure means a numeric write against the old codec deletes the view on next read. `card_size` had no other reader (grep-verified), so the codec was the only break point. *(Decision: Nathan; codec requirement from adversarial review, verified.)*
- **D-5:** [confirmed] The Standard/Compact card layout reuses the existing `SavedView.format` field with per-renderer meaning (table: density; cards: card layout) — no new key. *(Decision: Nathan.)*
- **D-6:** [confirmed] **Wrap Titles (on/off)** is a LayoutPane setting for the cards — on lets the title wrap; off keeps it single-line via the shared `OverflowScroll` (NavGallery's title treatment). *(Decision: Nathan.)*
- **D-7:** [confirmed] Cards gets **its own card component**, with a precise DRY line: the **title-area, aspect ratio, non-image borders, and card-to-card padding are DRY-ed** (shared with NavGallery's card CSS); the **title/property inner area starts as a copy and is allowed to diverge**. Borrowed mechanics: the auto-fit grid, the `--card-min` knob family, container-query type, `hover-pop`, the shared tokens. *(Decision: Nathan.)*
- **D-8:** [confirmed] **Any two-option double-chevron control simply toggles on click — never a dropdown** (the Open In idiom). Applies to Card Style and to the table's Format footer row alike; three-plus options keep the PickerControl dropdown. *(Decision: Nathan — a standing UI rule, not cards-only.)*

#### E — Grouping, Location & Sorting

- **E-1:** [confirmed] **No sub-grouping** in Cards — nested disclosure group headings look wrong in a card grid. Sub-*sort* is fine. *(Decision: Nathan.)*
- **E-2:** [confirmed] Location grouping renders **flattened**: top-level disclosure per location (like tables' bands) but no indenting of cards; sub-set nesting never indents cards. Planning detail: `structural()` emits a *nested* tree (`ResolvedGroup.children`) — the cards view defines the flatten traversal (descendants' pages roll up under the top-level band); structural bands never hide empties (`hide_empty_groups` is property-only), so an empty Set still renders its band. *(Decision: Nathan; traversal note from adversarial review.)*
- **E-3:** [confirmed] The card's location footing (Set / sub-Set breadcrumb) is governed by a **"Hide Location" switch** — a standing toggle in the options pane, below Card Style, independent of grouping mode (so it also serves the Sort-by-Location flattened list, where the footing matters most). Polarity: switch off = location visible; "Hide" keeps the pane's verb consistent with its siblings. *(Decision: Nathan.)*
- **E-4:** [confirmed] **Sort by Location** sorts as if grouping by location, but flattened — location-order without the bands. **Mechanism: a flatten mode over structural grouping at the resolve/renderer level** — group structurally, then flatten band items into one headerless list. It is NOT a `sort.ts` criterion: the sorter receives only `(sort, schema, manualOrder)` and has no set tree, so location can't rank there. The Sorting pane's "Location" entry drives this mode, not a `SortCriterion`. *(Decision: Nathan on the behavior; mechanism corrected by adversarial review, verified against `makeSorter`.)*
- **E-5:** [confirmed] **No heading columns** in Cards. *(Decision: Nathan — column mechanism is table-only anyway.)*
- **E-6:** [confirmed] Property grouping **replaces** the location bands, exactly like tables (chip/bucket band headers over card runs). "Display Set Cards" is independent of the grouping mode. *(Decision: Nathan.)*
- **E-7:** [confirmed] Ungrouped/root pages never render as an indented header-less tail (indents look off with cards) — they sit under a heading labeled as **the container itself** (the Collection in a collection view, the Set in a set view). *(Decision: Nathan.)*
- **E-8:** [confirmed] Group By Location's **Order: Custom / Location** semantics copy from tables — Location mirrors the filesystem order (view `group_order` preserved-but-ignored for the flip back), Custom reads the view-owned `group_order`. *(Decision: Nathan. Evidence: `structural_order_mode`, gated in `resolveView.ts` — renderer-agnostic, so the pipeline half is free.)* Known limit, deliberate: with band drag deferred (I-7), Custom order can't be *authored* from inside the cards view — it renders whatever `group_order` holds (authored via the table, or derived) until the band kit arrives.

#### F — Set Cards

- **F-1:** [confirmed] LayoutPane toggle **"Set Cards"**: the top row shows a larger card per Set (or per 1st-level sub-Set in a Set view). *(Decision: Nathan.)*
- **F-2:** [confirmed] v1: clicking a Set Card **navigates to the Set**. The preview-of-the-Set's-view behavior (click → view preview; interact → full-screen or page preview) is **post-v1** — it requires preview-views, which don't exist yet. *(Decision: Nathan — explicitly deferred.)*
- **F-3:** [confirmed] Default cards layout: Set Cards row on top, then per-location disclosures each holding their page cards. *(Decision: Nathan.)*
- **F-4:** [confirmed] Under Card Banner: None the compact imageless page grid sits under the large banner-bearing Set Cards — **intended contrast**. *(Decision: Nathan.)*
- **F-5:** [confirmed] A container with no sets doesn't render the Set Cards row; an empty Set still gets its Set Card. *(Decision: Nathan.)*

#### G — Property Interaction on Cards

- **G-1:** [confirmed] On a Compact card, clicking the properties field's **empty space** opens a dropdown listing available properties as rows → a second pane to pick the value. Clicking an **existing value** opens that property's own picker directly. Costing honesty: the two-stage surface is **net-new** — no property-list→value component exists; it assembles from `PickerMenu` hosting a `PaneSlider` (property-list root → `PropertyPicker` detail, `PropertiesPane`'s `SubView` state pattern). The per-value pickers themselves are pure reuse. *(Decision: Nathan. Evidence: TableView.md gesture matrix ratified as portable; `PropertyEditing/` view-agnostic by design.)*
- **G-2:** [confirmed] Standard cards: each property row's value half opens its per-kind picker on click — the same gesture matrix. The **empty-space two-stage add-picker is Compact-only**: a Standard card renders every visible property as a labeled row, so there's no empty-space-to-add surface. *(Scoping from adversarial review, faithful to the original Compact-scoped decision.)*

#### H — Insets & Chrome

- **H-1:** [confirmed] Cards does **not** use standard view insets (no gutter drag-lines needed); it uses the block-surface inset regime shared by gallery-mode NavView + Block Surfaces (`--surface-inset*`). **Mechanism:** the inset lives on the pane body, not the view — a `Detail.css` `:has(.cards-view)` body rule (the whole-page-table pattern) sets `--surface-inset`/`--surface-inset-right` + the block surfaces' 8px banner clearance; the view itself never pads, since `.detail-body` already applies the pane inset and a second application double-indents. *(Decision: Nathan; mechanism from the live-driving correction.)*

#### I — Interaction Sweep (don't-forget)

- **I-1:** [confirmed] **Cards are draggable in v1** — in-group manual reorder by displacement (the grid-surface law; NavGallery's `SortableZone` mechanics). Drag-between-groups (a real `movePage` / property write) is a follow-up → Prospects. *(Decision: Nathan.)*
- **I-2:** [confirmed] Cards gets the heading hover-"+" on structural headings, inactive on property buckets — exactly the table's rule. *(Decision: Nathan.)*
- **I-3:** [confirmed] **Set Card = the Set's banner (placeholder when unset) + icon + title.** Set Cards are banner-only — the Preview/Cover/None modes don't apply to them. *(Decision: Nathan. Evidence: Sets carry a `banner` sidecar field, `shared/types.ts:162-165`.)*
- **I-4:** [confirmed] **Compact values clamp, never wrap** — chips keep their existing label hover-scroll/melt mechanics; non-chip values (dates, numbers) ellipsis-clamp. *(Decision: Nathan.)*
- **I-5:** [confirmed] **Card height model** — the image band is a fixed height (scaled by the size factor); title + properties extend below; a CSS grid row sizes to its tallest card, shorter cards top-aligned (NavGallery's `align-self: start`). *(Decision: Nathan.)*
- **I-6:** [confirmed] **Card right-click** = the title-cell context menu (Rename · Change Icon · Delete); property values on cards keep their own per-kind menus from the ratified gesture matrix. *(Decision: Nathan.)*
- **I-7:** [confirmed] **Cards heading chrome is collapse + "+" only** — band collapse persists via `collapsed_groups`; `hide_empty_groups`, `ungrouped_placement`, and `group_order` carry over from the pipeline. Inline header rename does NOT apply (renames live in the sidebar/table); band drag, the native header menu, and the fuller band kit are table territory → follow-up. *(Decision: Nathan on rename; the narrowing is the joint call.)*
- **I-8:** [confirmed] **Image loading matches NavGallery's current behavior** — whatever the nav gallery cards do today (plain `<img>` + error-fallback placeholder), no bespoke loading regime. No virtualization (parity with the table's known debt, not new debt). *(Decision: Nathan.)*
- **I-9:** [confirmed] **Card drag uses NavGallery's exact drag + displacement animation**; cross-set/cross-band drops are out of scope for v1. *(Decision: Nathan.)* [assumed] The drop writes the same per-machine manual order the table's sort tiebreaker reads (`sort.ts` viewOrders), and two+ effective sort criteria retire the drag, the table's law.

#### J — Reconciliation Forecast (what ships stale if untouched)

- **J-1:** [confirmed] `Views.md` — "only Table draws" / the Pending renderer list / the Renderers section go false on ship; Cards gets its own feature doc, `Views.md` re-pointed.
- **J-2:** [confirmed] `ViewSettings.tsx` — `IMPLEMENTED`, the per-type gating on the leaf rows/toggles, and the footer all grow cards branches. **`setType` is the entry seam into cards** — every mint path hardcodes table (`mintBase`/`mintNewView`/`mintDefaultView`), so a view becomes a cards view only via the type grid, preserving its existing visible-property set; no `mintVisibility` cards case (it would be dead code).
- **J-3:** [confirmed] The Grouping pane is table-only by ratified design — Cards gets its own Grouping surface (no Sub-Group row, per E-1); the Sorting pane gains the Location **entry** (the flatten mode, not a `SortCriterion` — E-4).
- **J-4:** [confirmed] DRY duties: chips/`OverflowScroll`/`hover-pop`/`PaneSlider`/`PropertyPicker`/`SubfieldBreadcrumb` are reused, never paralleled; `CardsView.css` is the one CSS home (D-2), knobs aliased to design-system tokens.
- **J-5:** [confirmed] The `views.ts` header's Swift-parity claim goes stale — the cards-view keys join its React-ahead superset list when they land.
- **J-6:** [confirmed] The table Format row's native mac menu (`viewFormatMenu` IPC) is orphaned by the D-8 toggle rule — the renderer flips directly; the IPC + preload entry retire with the next main-process batch (B-6's eviction work).

#### K — Build Sequence & Options-Pane Spec

- **K-1:** [confirmed] **Visuals before mechanics, on a branch.** All code lands on a `cards-view` branch, created before any code. Build order: (1) wire Cards as a selectable type (ViewPane type grid + the SettingsPane Layout door) with its options pane, (2) get the card visuals right under live driving, (3) only then the mechanical renderer work (grouping, drag, editing). *(Decision: Nathan.)*
- **K-2:** [confirmed] The cards options live in the **Layout leaf**: the full door shows the table's standard four rows (Layout · Group · Filter · Sort) and cards' **Layout ›** slides into the options block; the flat door (Settings · Layout — it IS the Layout surface) shows the options in its body. **Style + Scale sit together in the ViewSettings footing** (the table-Format slot, pinned on the editor in both doors): Style is the D-8 flip-toggle, Scale the D-3 step dropdown. *(Decision: Nathan.)*
- **K-4:** [confirmed] **Full-door structure for cards matches the table's** — type grid → the four leaf rows. Layout → the K-2 options; Group/Sort → the cards Grouping variant (same logic, no Sub-Group row) and the Sorting pane; Filter follows the table's current treatment (a blank placeholder pending the pane redesign). *(Decision: Nathan — "Group + Sort stay separate like tables; same logic just no sub-groups.")*
- The cards options block (the Layout leaf's content):

  ```
  Card Banner:    (Cover / Preview / None)   ‹picker›
  Hide Location:  Switch
  Wrap Titles:    Switch
  Hide Icons:     Switch
  Set Cards:      Switch
  ───── ViewSettings footing (pinned, both doors) ─────
  Style:          (Standard / Compact)       ‹toggle — flips on click, D-8›
  Scale:          (value)                    ‹double-chevron step dropdown, D-3›
  ─────────────────────────────────────────────────────
  ```

  Field mapping: Card Banner → `card_banner` (B-1) · Style → `format` (D-5) · Hide Location → `hide_location` (E-3) · Wrap Titles → `wrap_titles` (D-6) · Hide Icons → `hide_page_icons` · Set Cards → `set_cards` (F-1) · Scale → `card_size` as the step factor (D-3/D-4). *(Decision: Nathan.)*

  Codec discipline for the new keys: the banner-mode enum ships `.optional().catch(undefined)` (the `format`/`structural_order_mode` pattern — a bare enum is the D-4 view-drop landmine); the new booleans follow the existing bare `z.boolean().optional()` convention. All land in the same task as the `card_size` reshape. The `views.ts` Swift-parity header carries the cards keys in its React-ahead superset list (→ J-5). `show_cover` (a zero-consumer reserved bool) is superseded by `card_banner` and retires with it; `show_banner` stays reserved.

### Core (must-have)

- **The renderer seam:** a shared `view.type` switch (`ViewRenderer`) consumed by BOTH TableView mounts — `ContainerView.tsx` and `ViewEmbedBlock.tsx` (A-2); `'cards'` joins `IMPLEMENTED` in ViewSettings, with `setType` as the entry seam (J-2). The pipeline (`resolveView`) is consumed verbatim; the cards root carries the embed `zoom` law.
- **CardsView + its own card component** (D-7): image band + title + properties + optional breadcrumb footing, NavGallery's grid mechanics (`auto-fit`/`minmax`, container-query type, `hover-pop`), all CSS in one `CardsView.css`, on the `--surface-inset` regime via the pane-body rule (H-1).
- **Card Banner: Preview / Cover / None** per-view (B-1) — thumbnail pipeline, `cover` frontmatter, or compact imageless cards (grid + heading spacing compact together, B-3).
- **Standard / Compact card layouts** off `format` (C-2/C-3, D-5): labeled property rows vs label-less clamped value flow in property order.
- **Property display + editing on cards:** all visible properties via `resolveColumns` (C-5); values render through the shared chip/cell renderers; value click opens the per-kind picker on both layouts; the empty-space two-stage property→value pane (`PaneSlider` + `PropertyPicker`) is Compact-only (G-1/G-2).
- **Grouping:** flattened location bands (no indent, E-2), property bands replace them (E-6), ungrouped under the container's own heading (E-7), collapse persistence, heading "+" on structural headings only (I-2), heading chrome = collapse + "+" (I-7).
- **Cards' own Grouping-pane variant** (no Sub-Group row) + the **Location entry** in the Sorting pane driving the flatten mode (E-4, J-3).
- **The Layout leaf (cards content), K-2's row set exactly:** Card Banner picker (B-1) · Hide Location (standing switch, grouping-independent, E-3) · Wrap Titles (D-6) · Hide Icons (`hide_page_icons`) · Set Cards (F-1); the ViewSettings footing carries Style (D-5/D-8) + Scale (`card_size` → number, D-3/D-4).
- **Set Cards:** larger top-row cards — Set banner + icon + title — clicking navigates to the Set (F-1/F-2, I-3).
- **In-group card drag-reorder** by displacement, retired under multi-key sorts (I-1, I-9).
- **Renders inside existing view embeds** with no special treatment (A-2).
- **The persistent thumbnail cache** (B-6): eviction retires in favor of existence-pruning; Preview covers stop disappearing.

#### Prospects (allowed later, not now)

- **Set-Card view previews** — click opens a preview of the Set's view; full-screen or page-preview to interact. Needs preview-views. Don't-foreclose: Set Cards ship v1 as navigation cards.
- **File-property covers** — any File property declares itself the card's photo-bearing property. Needs: a read-only image-MIME widening of `nexus-asset://` to the nexus root (File paths live anywhere under the root, the scheme serves only `.nexus/assets/`) + a real attach picker (file values are typed paths today). Don't-foreclose: the Card Banner control's mode set is extensible — a fourth "Property" mode slots in beside Preview/Cover/None.
- **Fit Image (contain vs fill) + hover-Reposition on covers** — Notion's remaining cover ergonomics; v1 ships fill-crop only (`--cover-zoom` mechanics). Don't-foreclose: both are per-view display options that slot into the LayoutPane.
- **Cross-group card drag** — a card dropped into another location band is a real `movePage`; into a property band, a property write (the table's cross-band semantics). Don't-foreclose: v1's in-group drag uses the same drag primitives, so the target logic extends rather than rewrites.
- **Full band chrome on cards headings** — band drag, native header menu, inline rename parity with tables, if ever wanted.

#### Out of Scope (won't do)

- Sub-grouping in Cards (E-1). Heading columns (E-5). The `'gallery'` ViewType — reserved for its own future renderer (A-3).

#### Considered & Rejected

- **A continuous Scale slider (0.50×–1.50×)** — built first, replaced by the double-chevron discrete-step dropdown (D-3): the drag-handle Scale idiom already exists, and per-tick whole-view writes fought the save/refetch model.
- **Two-option dropdowns** (Card Style / Format as PickerMenus) — rejected by the standing D-8 rule: a two-option double-chevron flips on click.

#### Lessons

- **A detail-pane view never applies the pane inset itself** — `.detail-body` already carries it; a view that pads `--surface-inset`/`--content-inset` again double-indents. The pane-body `:has(<view-root>)` rule in `Detail.css` is the one place a renderer's inset regime is chosen (the whole-page-table pattern).
