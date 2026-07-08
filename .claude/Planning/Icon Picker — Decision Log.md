## Icon Picker — Decision Log

### Frame

- **Purpose:** Fill the wired-but-stubbed `IconPicker` body with the real picker — a searchable grid of every Lucide icon, a right-click Favorites row, mounted on the Homepage as a live sizing harness.
- **Core Value:** Pick any Lucide icon from a fast, searchable grid; favorite icons for quick reuse.
- **Success Criteria:** All 1,715 Lucide icons browsable + searchable without lag; right-click favorites into a reorderable row; picker anchors to its trigger with a beak that can point horizontally (sidebar) or vertically (headers); lives on the Homepage so min/max width+height can be tuned live.

### Sources

- `src/renderer/src/Components/IconPicker.tsx` — the stub: `{open,onClose}`, portal + full-screen dismiss scrim + **centered** `GlassPane` + Bloom motion (`useExitPresence`), body = placeholder text. 6 consumers (ViewPane, PropertiesPane, SettingsPane, PageView, TableView, Banner) open it but pass **no `onSelect`/`value`** — selection was never wired.
- `src/renderer/src/design-system/symbols/index.tsx` — the curated registry: `icons: Record<IconName, LucideIcon>`, **61** kebab-keyed icons + 3 custom glyphs; `Icon({name: IconName})` renderer; `asIconName`/`iconNameOr` coercion. `IconName` is a compile-time union of the 61 — an arbitrary Lucide pick is NOT a valid `IconName`.
- `lucide-react@1.18.0` — exports `icons`: **1,715** icons, keyed **PascalCase** (`ClockPlus`), not kebab. This is the full-set source (already bundled; no dynamic import needed).
- `src/renderer/src/design-system/components/PickerMenu/PickerMenu.tsx` — the beaked glass chrome: self-managed (`open`/`onDismiss`) or manual; `triggerRef` anchor; `direction: 'down' | 'up'` **only** (no horizontal); `center` straddles trigger; NotchedPane beak geometry (`notchWidth/Height/Curve`); portal to body, ResizeObserver + scroll reposition, Esc dismiss.
- `src/renderer/src/design-system/components/TextPicker/TextPicker.tsx` — PickerMenu + one `EditableInput`; `trailing` adornment; `overflow-eclipse` on the field; accent focus stroke via `--accent`. The search-field pattern to mirror.
- `src/renderer/src/Components/EditableInput.tsx` — **auto-focuses on every mount** (no opt-out); commit/cancel rename widget. Not a fit for a live-filter search field (which shouldn't grab focus on open, and filters live rather than commit-on-Enter).
- `src/renderer/src/design-system/components/OverflowScroll.{tsx,css}` — the `overflow-eclipse` scroll-driven edge-fade; gradient is `to right` (**horizontal only**). The icon grid scrolls **vertically** → needs a `to bottom` variant. `OverflowScroll` wrapper also does `slideScrollBack` on pointer-leave (the snap-back Nathan does NOT want on the favorites row).
- `src/renderer/src/design-system/interactions/drag.tsx` — the drag seam: `SortableZone` (standalone reorder; `axis`, `bounds`, `swap`), `useDragItem`, `DragGroup`/`useGroupedDragItem` (cross-list). Favorites reorder = standalone `SortableZone` — the engine's first real in-app consumer (only the sidebar's bespoke engine + the Lab use DND today).
- `src/main/contextMenu.ts` + `src/preload/index.ts:243` — right-click is **Electron-native** menus via `window.nexus.contextMenu(target)` IPC, built + popped in main. No React context-menu primitive exists.
- `src/renderer/src/Detail/HomepageView.tsx` — blank view wrapping `DetailScaffold`; the test-mount site.
- `tokens/tint.ts` (`TINT_STEPS.secondary = 40`, `tintAt`) + `theme-vars.css.ts` (`--label-control` icon color, `--fill-secondary`, `--tint-secondary`) — icon color + caret-focus outline.
- [[Icons]] / `symbols/Symbols.md` — `DashIcon` dashed-square is the intentional no-glyph fallback (the placeholders in Nathan's screenshot).
- [[Interaction]] — IconPicker documented as a Bloom consumer ("centered GlassPane, origin center") + "a stub awaiting its Figma design." **Both go false** if the container moves to PickerMenu → reconcile.

### Decisions

#### A — What We're Filling

- **A-1:** [confirmed] The IconPicker shell is a wired stub; this fills the **body** (search + all-Lucide grid + favorites), not the container from scratch.
- **A-2:** [confirmed] Icons come from the **full** `lucide-react` `icons` export (1,715), not the 61-icon curated registry. Nathan: "ALL lucide icons for the picker."
- **A-3:** [assumed] Grid is **virtualized** (TanStack Virtual, already a dep) — 1,715 SVGs can't all mount ("no expensive work on every X"). Search narrows the window.

#### B — Container & Beak

- **B-1:** [confirmed] Rebuild the picker on **`PickerMenu`** (beaked, anchored to `triggerRef`), replacing the centered-scrim `GlassPane`. Nathan: "Container should be PickerMenu."
- **B-2:** [confirmed] Add a **horizontal** (`'left' | 'right'`) direction to `PickerMenu` (today `'down' | 'up'`) — **IconPicker-only**. Nathan: "Don't give it to TextPicker or wikilink; those don't need it; those just have their notches adjust their x position." So TextPicker + autocomplete keep their existing vertical notch (x-clamped to the trigger); untouched.
- **B-2a:** [confirmed] The horizontal beak is **new `NotchedPane` geometry** — `panePath` (`NotchedPane.tsx:12`) draws the notch on the top edge only (`flip` mirrors it to the bottom); it has no vertical-edge case. A `'left'`/`'right'` `notchSide` needs an axis-swapped path variant + the matching anchor math in `PickerMenu` (pane sits beside the trigger, beak aligned to the trigger's vertical center, `--dropdown-origin` at the side beak). The one meaty engineering piece.
- **B-3:** [confirmed] Motion moves from the menu **Bloom** (`slow`) to the inline **Dropdown** token, matching every other PickerMenu surface. → reconciles [[Interaction]].
- **B-4:** [confirmed] `PickerMenu` **auto-flips to `down`** when the requested direction won't fit the viewport (a sideways pane near the screen edge, an upward pane near the top) — measured against the real pane box, guarded to skip `center`/TextPicker. Down is the terminal fallback, so flips converge. Nathan: "picker should default to going down instead of up when it's near the side."

#### C — Search Field

- **C-1:** [confirmed] Left-aligned (not centered), at the top, above a separator.
- **C-2:** [confirmed] **No auto-focus** on open — caret only when clicked in. (Rules out `EditableInput`, which force-focuses; use a plain controlled `<input>` that live-filters.)
- **C-3:** [confirmed] `tint-secondary` outline highlight on the field when the caret is in it (focus state).
- **C-4:** [confirmed] "Size-to-scale caret" = the text **cursor** scales to the compact search field (native caret follows the field's font size). Nathan: "the caret when inside the search bar sizes down to it." Not the field-grows-to-content reading.

#### D — Favorites

- **D-1:** [confirmed] Right-click an icon → the **native Electron** Favorite/Remove menu (Nathan: "favorite is a right-click native menu; dont hand roll it"). `main/iconFavoriteMenu.ts` pops it (mirroring `popOptionMenu`) via the `icon-favorite-menu` IPC, resolving `'toggle' | null`; the renderer owns the `favoriteIcons` write. Label flips Favorite ⇄ Remove from Favorites by current state.
- **D-2:** [confirmed] Favorites render as a horizontal row **below the search separator, with its own separator below it**; the row only appears once ≥1 favorite exists.
- **D-3:** [confirmed] Favorites row is **drag-to-reorder** (standalone `SortableZone`), horizontally scrollable via `overflow-eclipse`, and does **NOT** snap back on hover-off (so NOT the `OverflowScroll` wrapper's `slideScrollBack`; apply the bare class).
- **D-4:** [confirmed] Favorites persist in **`Personalization`** (`.nexus/settings.json`, `types.ts:85`) — a new `favoriteIcons?: string[]` field beside `defaultIcons`, bare kebab Lucide ids (matching the existing icon-name convention), wired through the one apply-map + one setter. Nathan: "favorites can go in the existing icons config part of nexus config."

#### E — Selection & Scope

- **E-1:** [confirmed] This build = the picker UI + a **Homepage test harness**; add `onSelect`/`value` to the component. Wiring the 6 real consumers + the arbitrary-icon **render path** (teaching `Icon`/`IconName` the full set for non-curated picks) = a separate pass. Nathan: "Scope is exactly correct."
- **E-2:** [confirmed] Selecting an icon fires `onSelect` then closes via the existing retract animation (already DRY in the shell).

### Core (must-have)

- Beaked, trigger-anchored picker (down/up/left/right) with a left-aligned, non-autofocus live-filter search over the full 1,715-icon virtualized grid; icons in `label-control`; vertical `overflow-eclipse` on the grid.
- Right-click → Favorite; conditional favorites row (own separators) with horizontal drag-reorder + horizontal eclipse, no snap-back.
- `onSelect`/`value` on the component; selection closes with the retract motion; mounted on the Homepage for live sizing.

#### Prospects (allowed later, not now)

- **Drag gallery-icon → favorites** (+ drop-target border highlight) — Nathan demoted to Prospect. Deferred: the virtualized 1,715-item gallery as a live DND source fights the measure-once snapshot; needs a bespoke lightweight pointer-drag, not `DragGroup`. Don't-foreclose: keep the favorites `SortableZone` and a stable favorites store so a drop-to-add slots in.
- **Wire the 6 real consumers + arbitrary-icon render path** — thread `onSelect`/`value`; extend `Icon`/registry to render any Lucide id, not just the 61. Don't-foreclose: store the picked id as a kebab Lucide id (on-disk convention) even in the harness.

#### Out of Scope

- Tabler / custom-glyph browsing in the picker — Lucide-only per Nathan.
- Redesigning the 61-icon curated semantic registry — untouched; the picker is a parallel full-set surface.

#### Considered & Rejected

- **Keep the centered-scrim `GlassPane` container** — rejected: Nathan's horizontal-notch requirement needs trigger-anchoring + a beak; the centered modal has neither.
- **`EditableInput` for search** — rejected: force-focuses on mount (violates C-2) and is commit/cancel, not live-filter.
- **`dynamicIconImports` / lazy per-icon** — unnecessary: the full `icons` set is already bundled in `lucide-react@1.18.0`.
- **Full `DragGroup` cross-list for gallery→favorites** — moot (now a Prospect); would have fought the virtualized gallery.

#### Lessons

- Interaction.md called IconPicker "a stub awaiting Figma" AND a "centered GlassPane" Bloom consumer — a shipped placeholder documented as canonical. Grounding caught it; reconcile on build.
