## Multi-View Scaffolding — Reconciliation Report

The final-state understanding companion to the Decision Log: the complete feature model in plain English, the concrete menu-CSS refactor map grounded in the actual code, and the session's resolved calls. Every claim here traces to a file opened this session.

### I. The Feature — Final Shape

#### The Term Map (exact, per Nathan)

- **ViewDropdown** — the toolbar button (in `Toolbar/`, standalone left of the trio) that opens the ViewPane. Glyph = the active view's icon. Right-clicking IT opens the native context menu for show / hide title + toolbar/dropdown style.
- **ViewPane** — the dropdown the button discloses: a pure **navigation menu** — one row per saved view (icon · name · push chevron) over a footer BottomRow (`+` pinned left, `…` pinned right). Nothing else. No option rows.
- **ViewSettings** — the shared per-view editor a row's chevron pushes into (and the SettingsPane's Layout leaf opens flat): ‹ back header with icon + editable title, the 3×2 view-type grid, a separator, the view-type-dependent **Layout ›** leaf (blank this cycle; order + visibility for Tables next session), then view-type-specific toggles below (Tables get **Format** Standard/Compact; a future Gallery might get **Size**). One DRY component, PropertiesPane-style, consumed by both doors and any view-types individual setting requirements.
- **SettingsPane** — the renamed current ViewPane (behind the toolbar sliders button): container icon + rename header over Configuration · Properties · Visibility · Layout · Group · Filter · Sort.

#### The Flows

- **Switching:** click a view row → the active view switches (per-machine `activeViews.json`) and the pane closes — nav-menu semantics, like the toolbar's navigation dropdown.
- **Configuring a view:** row chevron → ViewSettings (full door: ⋮ with Duplicate/Delete). Or SettingsPane → Layout (flat door: same pane for the active view, no leafs, no ⋮). Back labels: ‹ Views from the list; ‹ Settings from a leaf (the Figma's "Table Settings" is non-canonical).
- **Creating:** footer `+` mints "Untitled" (type Table, title-only — schema props AND tiers hidden), disclosure-folds in at the bottom, no navigation unless the per-nexus `openViewOnCreate` says so.
- **Button presentation:** right-click the ViewDropdown → native menu: **Show Title / Hide Title** (dynamic item, `view_button`) over **Style ▸ Dropdown / Toolbar** (`view_style`), current values checked. It rides the **returning-picker pattern** (`optionMenu.ts`/`propertyMenu`): the popup resolves the picked action back to the renderer, and the ViewDropdown performs the write through the one container-settings preload op with its own path + kind. Native-only; reachable in either style mode because it rides the button/bar itself. My tooling can't drive native menus — Nathan manually verifies this surface.
- **Collection behavior:** **Open In** (full-page vs page-preview) lives in SettingsPane → Configuration as its first row — it configures the collection and its pages, never a view. Collection-owned; a Set's row proxies its parent's value.

#### The Data Layer

- Three sidecar keys, each with BOTH allowlist sides specced: `view_button` + `view_style` (container zod schemas → node fields → readNexus branches → a net-new container-settings mutate op/IPC/preload surface), `format` on SavedView (codec field = its own read side; consumer = a class on the table root, inert until Compact CSS exists). `open_in` exists in the collection schema (`compact|window`) but has NO read or write surface today — both get built, with the `full-page|page-preview` rename + legacy coercion.
- **The invariant (log G-1):** views never empty where views can be seen. Creation-seed (createContainer births the default view via `createFolderEntity`'s `extra` param) + entry-mint (store.select persists the default on first entry of an empty container — the SOLE mint site, in-flight map keyed by container id; TableView's `persistView` and HiddenPane's save become adopt-only). No backfill walk, no move hook. The sentinel covers the in-flight render beat.
- **Serialization (log G-2):** the three `views:*` handlers are the only sidecar read-modify-writes without `serializeOnFile` (verified at index.ts:439/454/470) — they wrap, and the per-machine pointer writes (`writeActiveViews`, `writeViewOrders` — same unlocked read-merge-write shape, verified in io/activeViews.ts) wrap in the same pass.
- Views are id-keyed at every consumer (activeViews maps container→view id; reorder matches ids; saveView upserts by id; pickView finds by id) — duplicate names are purely cosmetic, so Duplicate keeps the name verbatim.

### II. The Menu-CSS Refactor — Concrete Map

Grounded by full reads of `menu/menu.css.ts` (117 lines), `menu/Menu.tsx`, `menu/MenuSurface.tsx` + `menuSurface.css.ts`, `Components/Detail/viewPane.css.ts` (401 lines), `PickerMenu/pickerMenu.css.ts`, and all three consumer panes (`ViewPane.tsx`, `PropertiesPane.tsx`, `HiddenPane.tsx`).

#### What Exists Where Today

- **menu.css.ts** already owns the row grammar: `item` (28px row, 8px-radius hover pill), `itemSelected`, `heading` (13px Semibold label-secondary), `side` (the glyph cluster, label-secondary via the stable CSS var), `titleWrap`/`titleText`/`subLabel`, `detail` (footnote-emphasized), `separator`/`separatorLine`/`separatorFlush`, `flushAffordance`/`flushTrailing`, `topRow`, `caption`, `menu`.
- **menuSurface.css.ts** owns the shell: `MENU_GUTTER` (10px, matching the sidebar gutter), the radius-12 surface with `--notch-h`-aware top padding, `overflow: hidden`, `minWidth: 225px`.
- **viewPane.css.ts** hoards everything else: the COLOR/SIZE/PAD/OPTION/ICON knob blocks, the toolbar dropdown `anchor` (+ `--dropdown-origin`), the title header (`header`/`iconButton`/`titleField`/`dashIcon`), the TopRow rhythm (`topRowPad`/`paneSeparator` on the single `PAD.topRowBlock` knob), **five clone icon-buttons**, the All-Properties block, the Visibility styles, drag chrome, the option editor, and the link editor. Eleven files import it.
- **pickerMenu.css.ts** is a separate family — its `anchor`/`anchorUp`/`layer`/`backdrop` are body-portal machinery and its `option` is a text-row button, not an icon button. It stays its own file, untouched.

#### The Five Clones (the duplication, verbatim from the code)

`topRowAction` (:134) · `rowPlus` (:182) · `optionsAdd` (:291) · `eyeButton` (:224) · `paletteButton` (:353) all repeat the identical recipe — fixed box, `display:flex` + centered, `border:none` / `background:none` / `padding:0`, `cursor:default`, `color: COLOR.actionLabel` (label-tertiary), `borderRadius: 5px`, `transition: background duration.fast easing.standard`, hover → `state.hover` fill — and differ ONLY in:

- **Box size** — 20px width-only (topRowAction) · 16px (rowPlus, eyeButton, paletteButton) · 20px (optionsAdd).
- **Rest opacity** — eyeButton rests at `var(--state-ghost)` and un-ghosts on hover; paletteButton rests at 0 and reveals at ghost on row-hover, full on own-hover; the others rest solid.
- **The `&&` tone override** — topRowAction (:147) and groupAdd (:317) need `'&&': { color: … }` to out-rank the `.app-toolbar button` control-tone rule (specificity 0,1,1). `groupAdd` (:310) composes optionsAdd into a sixth variant (hidden-until-group-hover).

#### The Refactor, Move by Move

1. **`AccessoryButton` primitive → menu.css.ts** (Nathan's name — the TopRow/BottomRow trailing buttons: ellipsis, plus, eye, palette…). One base class carrying the shared recipe with the box size as a CSS var (**default 14px** per Nathan), the tone written through the `&&` form by default so no consumer can be silently out-toned by the toolbar rule. Two rest-state variants: ghost-rest (eye) and hidden-rest (palette/groupAdd, parent-row reveal). The five clones + groupAdd collapse to the primitive + one-line size/variant compositions in the surface file.
2. **Tone roles → menu.css.ts.** Row titles default **`label-control`** (view titles, leaf rows) as a **dropdown-scoped default** — the `item` primitive also serves the sidebar, so the control tone rides the dropdown surfaces, never a global `item` flip. `headingLabel` (label-secondary) and `actionLabel` (label-tertiary) + the hover fill/radius become exported row defaults — per Nathan: menu.css handles the existing pane's **coloring, spacing, and fills as shared row defaults**. viewPane.css's COLOR block shrinks to the genuinely surface-local entries (`dragHighlight`, `eyeHidden`, `allRow`).
3. **TopRow rhythm → menu.css.ts.** `topRowPad` + `paneSeparator` (one `topRowBlock` knob) hoist into the composed TopRow scheme, carrying the CURRENT ViewPane values verbatim — the `label.secondary` tone + the `topRowBlock: 2` rhythm; the scheme reuses existing colors and sizes, never re-tunes. This removes a load-order dependency: today `topRowPad`'s color beats `flushAffordance`'s only because viewPane.css happens to load after menu.css — post-hoist the scheme owns its tone directly.
4. **BottomRow → menu.css.ts, net-new.** The footer scheme mirroring TopRow (nothing exists today beyond `flushAffordance`'s geometry): `+` at the left gutter edge, `…` at the right. The ViewPane's footer is its first consumer.
5. **The `anchor` hoists to the menu home.** Today `Toolbar.tsx:7` imports the ENTIRE 401-line knob file just to reach `anchor` — post-hoist it imports the menu home. The ViewDropdown's own anchor consumes the same export with its own inset.
6. **The TSX header scheme consolidates — ratified as the menu's general TopRow scheme.** The `MenuTopRow + MenuSeparator(flush, paneSeparator)` pair is hand-assembled FIVE times across the panes (ViewPane's `pendingPane` + root, PropertiesPane's `backHeader` + `actionHeader`, HiddenPane inline). One composed TopRow component (‹ chevron · heading · optional trailing AccessoryButton) replaces all five, and the footer gets the same treatment as **BottomRow**; ViewSettings and the new ViewPane are born on both.
7. **The file splits, then renames.** What stays surface-local moves to `settingsPane.css.ts` (the renamed file): the title header block, ICON size map (per-surface glyph sizes stay Nathan's knobs), the All-Properties block, Visibility styles (`hiddenRow`/`hiddenZone` + the `rowDragging` composition), drag chrome, the option editor, the link editor. The freed `viewPane.css.ts` name goes to the new ViewPane; the button gets `viewDropdown.css.ts`. Rename runs FIRST in the build order.
8. **A code-only before/after line diff is reported** (comments + blanks excluded) when the refactor lands.

#### Side Findings From the Pane Reads

- **Root-entry icons bypass the registry:** `ViewPane.tsx:2` imports `Server, Eye, LayoutDashboard, Layers, ListFilter, ArrowUpDown` directly from lucide-react instead of the curated `Icon` registry. The rename pass should route the SettingsPane's root entries through the registry (where Configuration's `sliders-horizontal` already lives and Layout's `layout-panel-left` registers).
- **Meta-commentary to blank on contact** (the UI-Copy hard rule): `ViewPane.tsx:114` (`"${label} — pending"`), `PropertiesPane.tsx:376` (`"…options — pending"`), `Toolbar.tsx:81` (`"No navigation yet."`). Genuine runtime copy that STAYS: `"Schema unavailable."`, `"Property not found."`, `"No properties yet."`.
- **HiddenPane's sentinel adoption** (`HiddenPane.tsx:167-177`: `wasSentinel` → save → `activeViews.set` adopt) is the pattern that generalizes into G-1's adopt-only rule; TableView's `persistView` (fire-and-forget, no adoption — verified at TableView.tsx:364) is the writer that must join it.
- **PaneSlider floors:** both existing panes pass `minWidth={225} minHeight={245}` (ViewPane root adds `maxHeight={375}`) — the C-6 shared min-max for ViewPane/ViewSettings has its precedent numbers here, and `menuSurface.css.ts` floors the shell at the same 225.

### III. Resolved This Session (the calls, compact)

1. The ViewPane's options block is **gone** — pure navigation menu; row click switches + closes.
2. Presentation toggles → the button's **right-click native context menu** (Show/Hide Title · Style ▸ Dropdown/Toolbar); native-only; Nathan verifies manually.
3. **Open In → SettingsPane Configuration leaf, first content, this cycle**; Collection-owned proxy on Sets; enum renames with read coercion.
4. The editor is **ViewSettings** — one shared component, two doors (full with ⋮, flat without); back labels ‹ Views / ‹ Settings.
5. Grid tiles: **rounded rectangles ~4:3** (per Figma), glyph-only, accent border on selected; Lucide **`table` is THE table glyph everywhere** — one glyph per concept.
6. Format row stays in ViewSettings for Tables (Standard/Compact, persists `format`, visually inert until Compact CSS) — **dual-wired**: native menu on macOS + PickerMenu so non-mac gets a picker.
7. Duplicate: name verbatim (id-keyed, verified safe), lands after the original; Delete mutes on the last view.
8. `activeViews`/`viewOrders` writes join the `serializeOnFile` wrap.
9. Card-like row fills **rejected** — plain glass; the Figma frame's wrap fills and "Table Settings" title are non-canonical.
10. Title's glyph work is **additive** (`text-align-justify` + a Title entry in `PROPERTY_TYPES` — no "T" exists anywhere in React today).
11. The log reformatted: §H dissolved, sections A–I, sequential numbers, every tag `[confirmed]`.

### IV. Review Status

- The Decision Log is **review-certified**: a fresh adversarial round attacked the full log — cross-reference integrity (~90 citations traced), every file:line claim grounded, coverage against Core/Success, the context-menu write-path wiring, and mint-beat interaction windows — and its verdict is folded. Every decision stands `[confirmed]`; the log and this report share one vocabulary (ViewDropdown · ViewPane · ViewSettings · SettingsPane · AccessoryButton · TopRow/BottomRow · returning-picker · adopt-only writer class).
- Next: Nathan's ratification → the **implementation plan** (superpowers:writing-plans) against the log, with this report as the planner's companion grounding; then `/handoff`.
