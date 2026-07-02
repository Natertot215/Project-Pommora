# Tables Phase 1 (Cells + Menus + Styles) Implementation Plan

> **Execution mode (Nathan): IN-LINE via superpowers:executing-plans — no subagent implementers; the executing agent verifies each task itself.** Steps use checkbox (`- [ ]`) syntax for tracking.
> **Status: DRAFT — pending the review-revise loop; IMPLEMENTATION STARTS POST-COMPACT.** Spec: `7-1 - Tables Next-Parts (Cells + Group Drag + Styles) — Decision Log.md` (RATIFIED). Phases 2 (band drag) + 3 (chips) are separate plans.

**Goal:** Every table cell becomes directly manipulable per the ratified gesture matrix — single-click acts, right-click opens a menu, per-view `column_styles` drives how each type renders.

**Architecture:** Pure resolvers + formatters first (the `alignFor` pattern), then the render wiring in `Cell.tsx`'s one type-aware switch, then the native meta menus (extending `columnMenu.ts`'s three-layer pattern), then the PickerMenu value dropdowns + inline editors committing through `setProperty` with the optimistic `valueOverride` patch. Row-click narrows to the title last, once every cell owns its gesture.

**Tech Stack:** React 19 renderer, native Electron menus over IPC, `PickerMenu` (first consumers), Vitest (node for pure units; per-file jsdom + `createRoot`/`act` + `window.nexus` stub for DOM tests — no testing-library).

## Global Constraints

- **ZERO styling regression** (Nathan, at ratify): the coupled elastic-title mechanism (`minmax` title + reflow-floored grid `min-width` + heading both-side padding), the full-bleed heading band, the between-rows collapse-aware divider model, sticky group headers, col-drag `zoom` compensation (`Features/TableView.md`). Task 10's CDP visual pass gates closeout.
- **All cells keep arming row-drag past `ACTIVATION`** (spec A-1 guard; the whole-row `{...handle}` at `TableView.tsx:618` stays) — cell gestures own only the sub-threshold press-release.
- **Right-click always opens a menu, never fires an action** (spec A-13). Native menus for meta; `PickerMenu` for values (F-1).
- **Styles/formats persist per-VIEW in `SavedView.column_styles`** (B-3) — a deliberate divergence from Swift's def-level keys; the def-level riders (`display_as`, `date_format`, `number_format`, `time_format`) come out of the fixtures + the rider comment.
- **Every persist routes through `persistView` → `mergeOverrides`** with its own override state, folded per the align pattern (`TableView.tsx:203-206`) — patch carries the not-yet-committed value.
- **Every value write pairs `setValueOverride` (optimistic) with `mutate({op:'setProperty'})`** (`loadValues` never re-runs mid-session — `TableView.tsx:357-371`).
- **Edit model (A-12):** Enter = confirm · click-out = save · Esc = revert and exit. Link/file validate via `shared/links`.
- TDD; each task an independent green commit (`npx vitest run` + `npm run typecheck`); Biome auto-formats — don't hand-format.

---

## File Structure

**Create:**
- `React/src/shared/columnStyles.ts` — the `ColumnStyle` type + zod (`look`, `date_format`, `time_format`, `number_format`) + the per-type defaults + `styleFor(columnId, schema, view)` resolver (pure, mirrors `columnAlign.ts`).
- `React/src/shared/columnStyles.test.ts`
- `React/src/renderer/src/Detail/Views/Table/formatValue.ts` — `formatDate(iso, dateFormat, timeFormat)` + `formatNumber(n, numberFormat)` (pure; ports Swift's four date formats, ordinal-day, 12/24h, integer/decimal/percent/currency).
- `React/src/renderer/src/Detail/Views/Table/formatValue.test.ts`
- `React/src/renderer/src/Detail/Views/Table/statusCycle.ts` — `nextCycleValue(current, def)` for the checkbox-status 3-group cycle (empty→minus→check→empty, first-in-order option, empty groups skipped) + `cycleGlyph(value, def)` (`none | minus | check`).
- `React/src/renderer/src/Detail/Views/Table/statusCycle.test.ts`
- `React/src/renderer/src/Detail/Views/Table/CellPicker.tsx` — the PickerMenu-based value dropdown (status/select/multi), anchored at the cell, `useDismiss` + `useExitPresence`, chips as options.
- `React/src/renderer/src/Detail/Views/Table/CellEditor.tsx` — the inline text editor (number/link/file) implementing A-12.
- `React/src/renderer/src/Detail/Views/Table/cellGestures.test.tsx` — the jsdom DOM test (nexus stub + ResizeObserver stub per `MarkdownPM/Tables/cellNavigation.test.tsx`'s conventions).
- `React/src/main/cellMenu.ts` + `React/src/shared/cellMenu.ts` — the native per-cell context menus (title Rename/Change Icon/Delete; status/number Style; link/file Style + Edit), mirroring `columnMenu.ts`'s three layers.

**Modify:**
- `React/src/shared/views.ts` — `savedView` gains `column_styles` (lenient: `z.record(z.string(), columnStyle).catch({})`).
- `React/src/renderer/src/Detail/Views/Table/viewMerge.ts` — `mergeOverrides` folds `column_styles`.
- `React/src/renderer/src/Detail/Views/Table/Cell.tsx` — the switch consumes `styleFor` + `formatValue` + the gestures (click handlers per type, per-file chips).
- `React/src/renderer/src/Detail/Views/Table/TableView.tsx` — `styleOverride` state + persist; heading menu ctx gains `style`; row-click narrows to title; cell gesture plumbing (picker/editor mount state).
- `React/src/main/columnMenu.ts` + `React/src/shared/columnMenu.ts` — the heading Style submenu (per-type items).
- `React/src/main/index.ts` + `React/src/preload/index.ts` — `cellMenu` IPC + `file:open` (`shell.openPath`) handler.
- `React/src/shared/properties.ts` (rider comment) + `React/src/shared/__fixtures__/registry.json`, `collection-with-status.json` — retire `display_as`/format riders.

---

### Task 1: `ColumnStyle` — schema, defaults, resolver

**Files:** Create `shared/columnStyles.ts` + `.test.ts`; Modify `shared/views.ts`, `Detail/Views/Table/viewMerge.ts`.
**Interfaces — Produces:** `type ColumnLook = 'pill'|'capsule'|'checkbox'|'switch'|'title'|'full'|'filename'|'path'` · `interface ColumnStyle { look?: ColumnLook; date_format?: 'short'|'full'|'dayMonthYear'|'monthDayYear'; time_format?: 'none'|'twelveHour'|'twentyFourHour'; number_format?: 'integer'|'decimal'|'percent'|'currency' }` · `styleFor(columnId, schema, view): Required-defaults ColumnStyle` · `defaultLookFor(type): ColumnLook | undefined` (status→`pill`, checkbox→`checkbox`, url→`full`, file→`filename`; select/multi→`pill`).

- [ ] **Step 1: Failing test** (`shared/columnStyles.test.ts`): `styleFor` returns type defaults with no view entry (status → `{look:'pill', …}`, datetime → `{date_format:'full', time_format:'none'}`, number → `{number_format:'decimal'}`); a `view.column_styles[id]` entry overrides per-key (partial merge, not replace); unknown column → safe defaults.
- [ ] **Step 2: Run — FAIL** (`npx vitest run src/shared/columnStyles.test.ts`).
- [ ] **Step 3: Implement** `columnStyles.ts` (zod enums exactly as in Produces — Swift's sets verbatim; `columnStyle = z.looseObject({...each field optional enum with .catch(undefined)})`); add to `savedView` in `views.ts`: `column_styles: z.record(z.string(), columnStyle).catch({}).optional()` (lenient — one bad entry never sinks the view; unknown keys ride through); fold into `mergeOverrides` (`column_styles: { ...liveView.column_styles, ...styles }` with a new `styles` param defaulting `{}`; existing callers pass `{}` — update the call in `TableView.tsx:persistView` mechanically).
- [ ] **Step 4: Run — PASS**; `npm run typecheck`.
- [ ] **Step 5: Commit** `feat(table): per-view column_styles — schema, type defaults, resolver`.

### Task 2: Formatters — Swift-parity date/number rendering

**Files:** Create `Detail/Views/Table/formatValue.ts` + `.test.ts`.
**Interfaces — Produces:** `formatDate(iso: string, dateFormat, timeFormat): string` (short="March 1st" · full="Wednesday, March 1st 2026" · dayMonthYear="01/03/2026" · monthDayYear="03/01/2026"; time appended " 3:45 PM" / " 15:45" when not `none`) · `formatNumber(n: number, numberFormat): string` (integer=no fraction · decimal=locale · percent=`Intl` percent · currency=locale currency). Ordinal-day helper included (1st/2nd/3rd/nth).

- [ ] **Step 1: Failing test** — table-driven: each of the 4 date formats on `2026-03-01`, date-only vs both time formats on `2026-03-01T15:45:00`, the ordinal edge days (1,2,3,4,11,12,13,21,22,23,31), each number format on `1234.5` and `0.42` (percent semantics: `0.42 → 42%`, matching `NumberFormatter.percent`).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** with `Intl.DateTimeFormat`/`Intl.NumberFormat` parts (no dep). Keep `Cell.tsx`'s old `formatDate` untouched until Task 3 swaps it.
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): Swift-parity date/number formatters`.

### Task 3: `Cell.tsx` renders styles (looks + formats) — no gestures yet

**Files:** Modify `Cell.tsx`, `TableView.tsx` (thread `styleFor` results down as a per-column resolved style, computed beside `colAlign` — NOT via `liveView`); Create the render cases; Modify fixtures + `properties.ts` rider comment; Test additions in `cellResolve.test.ts`-style pure tests where possible.
**Interfaces — Consumes:** Task 1 `styleFor`, Task 2 formatters. **Produces:** `Cell` accepts `style: ColumnStyle`; renders: status `pill` (today's Chip) / `capsule` (Chip with `chipCapsule` — a new `chip.css.ts` variant: same recipe, filled background tint, radius 6px) / `checkbox` (the `chipCheckbox` square + `cycleGlyph`: none/`minus`/`check` Icons) · checkbox `checkbox` (today) / `switch` (the existing `Switch` component from `Components/Switches`, read-only visual) · url `full` (today's `<a>`) / `title` (same `<a>`, link-colored, showing the fetched-title-or-URL — URL until the fetch Prospect lands) · file `filename` (per-file chips — one `Chip color="default"` per `FileRef`, label = stripped basename) / `path` (per-file chips, label = full `ref.path`) · datetime/number via Task 2 formatters. **Both url looks render in the link color token.**

- [ ] **Step 1: Failing tests** — pure where possible (a `renderLabel(value, style)`-shaped helper extracted for file labels + date/number strings); jsdom smoke for the four status/checkbox looks (mount `Cell` alone — it has no nexus deps).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** — the switch branches read `style.look`/formats; `chipCapsule` added to `chip.css.ts` (tokens only, no raw hex); delete the old local `formatDate`; drop `display_as` + `date_format` from `__fixtures__/registry.json` + `collection-with-status.json`; rewrite the `properties.ts` rider comment (formats now live per-view; riders stay inert foreign keys on disk).
- [ ] **Step 4: Run full suite — PASS** (pipeline tests consume the fixtures — verify no stragglers); typecheck.
- [ ] **Step 5: Commit** `feat(table): column_styles rendering — looks + formats in the cell switch`.

### Task 4: Heading Style submenu (native)

**Files:** Modify `shared/columnMenu.ts`, `main/columnMenu.ts`, `TableView.tsx` (`openHeaderMenu` ctx + apply + `styleOverride` state + persist).
**Interfaces — Consumes:** Task 1 types. **Produces:** `ColumnMenuContext` gains `style?: { type: PropertyType | 'title'; current: ColumnStyle }`; `ColumnMenuAction` gains `` `style:${key}:${value}` `` strings (e.g. `style:look:capsule`, `style:date_format:short`); the Style submenu renders per-type radio items: status Pill/Capsule/Checkbox · checkbox Checkbox/Switch · url Title/Full Link · file Filename/Full Path · select/multi Pill/Capsule · number Integer/Decimal/Percent/Currency · datetime **Options ▸**. **Datetime menu labels show the DISPLAYED SHAPE, not format-type names (Nathan):** "March 1st" · "Wednesday, March 1st 2026" · "01/03/2026" · "03/01/2026" · separator · "None" · "12:00 PM" · "24:00" — a divergence from Swift's `displayLabel` names, rendered from a fixed sample date so the user picks what they'll see. Title gets no Style.

- [ ] **Step 1: Failing test** — `shared/columnMenu.test.ts` (new, pure): the action-string round-trip helper `parseStyleAction('style:look:capsule') → {key:'look', value:'capsule'}` + menu-item builder returns the right item set per type (extract the item-list builder into `shared/columnMenu.ts` so it's node-testable; `main/columnMenu.ts` maps it to Electron `MenuItem`s).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** — builder + main mapping (radios `checked` off `ctx.style.current`); `TableView` applies via `setColumnStyle(id, key, value)`: `styleOverride` state (reset in the `[view.id]` effect), resolved style feeds Task 3's per-column style, persist = `persistView({ column_styles: { ...view.column_styles, ...styleOverride, [id]: merged } })` — the align pattern, patch carries the uncommitted value.
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): heading Style submenu — per-type looks + formats, per-view persist`.

### Task 5: Cell context menus (native) — status/number Style, link/file Style + Edit, title menu

**Files:** Create `shared/cellMenu.ts` + `main/cellMenu.ts`; Modify `main/index.ts` (handler `cellMenu:pop`), `preload/index.ts` (`nexus.cellMenu`), `TableView.tsx`/`Cell.tsx` (`onContextMenu` per cell).
**Interfaces — Consumes:** Task 4's shared item-builder (Style items identical — one builder, two menus). **Produces:** `CellMenuContext = { kind: 'title' } | { kind: 'style-only'; type: PropertyType; current: ColumnStyle } | { kind: 'style-edit'; type: 'url'|'file'; current: ColumnStyle }`; actions: `'title:rename' | 'title:icon' | 'title:delete' | 'cell:edit' | style:*`. Title menu = Rename · Change Icon · Delete (separator-gated). Style actions persist through Task 4's `setColumnStyle` (per-view — a cell's Style menu edits its COLUMN's style). `title:rename` → the title inline editor (Task 7 wires it; until then it's plumbed but the menu item hidden), `title:icon` → opens the existing `IconPicker` shell, `title:delete` → `mutate({op:'delete', path})` via the store (the existing confirm-less delete → trash flow).

- [ ] **Step 1: Failing test** — pure builder test (item sets per `CellMenuContext` kind).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** the three layers + `onContextMenu` on the cell (stopPropagation so the row doesn't also react; `e.preventDefault()`).
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): native cell context menus — title meta, per-type Style, Edit entry`.

### Task 6: `CellPicker` — the PickerMenu value dropdown + checkbox-status cycle

**Files:** Create `CellPicker.tsx`, `statusCycle.ts` + `.test.ts`; Modify `Cell.tsx`/`TableView.tsx` (mount state: `editing: {rowId, colId, mode:'picker'} | null` lives in TableView; row-drag arming untouched).
**Interfaces — Consumes:** `PickerMenu`/`PickerOption` (as-is), `useDismiss`, `useExitPresence`, `findOption`/`chipColorFor`, `applyPropertyValue`, store `mutate`. **Produces:** single-click on status/select opens `CellPicker` (options as `Chip`s, `selected` = current); pick → optimistic `setValueOverride` + `mutate({op:'setProperty', path, propertyId, value})` → close; multi-select toggles values (stays open, chips reflect live). Checkbox-look status cells DON'T open the picker: click = `nextCycleValue` write (`statusCycle.ts`: groups in schema order, first-in-order option per group, empty groups skipped, value in Done→empty). `--dropdown-origin` set to the cell's anchor point.

- [ ] **Step 1: Failing tests** — `statusCycle.test.ts` (pure: 3-group cycle, first-in-order, empty-group skip, unknown current → first group); jsdom gesture test in `cellGestures.test.tsx` (nexus stub; click status cell → picker mounts; pick → stub's `mutate` called with the right `setProperty`; Esc dismisses; click on a checkbox-look status cell calls mutate directly, no picker).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** Click handling: cell `onClick` gated `!isDragging` (the row-select precedent, `TableView.tsx:620`), stopPropagation.
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): PickerMenu cell dropdowns + checkbox-status group cycle`.

### Task 7: `CellEditor` — inline editing (number, link, file) + title rename

**Files:** Create `CellEditor.tsx`; Modify `Cell.tsx`/`TableView.tsx` (mode `'editor'`), `shared/cellMenu.ts` (unhide `title:rename`).
**Interfaces — Consumes:** A-12 model, `isValidLink`/`normalizeLinkUrl` (`shared/links`), `mutate`. **Produces:** an input overlaying the cell (absolute within the cell, table-tokens type ramp): number → parses float, invalid = revert-on-commit-attempt (input stays, subtle shake class — no toast); url → validates/normalizes on commit; file → edits the FIRST ref's `path` (multi-file editing = the picker Prospect; Edit on a multi-file cell edits ref 0 — documented in the code); title rename → `mutate({op:'rename', path, newName})`. Enter=commit · blur=commit · Esc=revert+exit. Single-click number cells enter the editor directly (A-8); link/file enter only via the menu's Edit (A-3/A-9).

- [ ] **Step 1: Failing tests** — jsdom: number cell click mounts editor; Enter commits `setProperty {kind:'number'}`; Esc calls no mutate; blur commits; url Edit normalizes (`example.com → https://example.com`).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): inline cell editor — number/link/file + title rename, Enter/blur/Esc model`.

### Task 8: Open actions + row-click narrowing (A-7 last — every cell now owns its click)

**Files:** Modify `TableView.tsx` (`onSelect` moves from the row div to the title cell), `Cell.tsx` (file chip click), `main/index.ts` + `preload/index.ts` (`file:open` → `resolveUnderRoot` + `shell.openPath`, envelope contract).
**Interfaces — Produces:** title cell single-click = `select({kind:'page'…})` (the only navigate); url click keeps the `<a>` external-open; file chip click → `nexus.openFile(ref.path)`; every other cell's click is its Task 6/7 gesture; row background click = no-op. Row-drag arming from any cell verified intact (the jsdom test asserts `handle`'s pointerdown still spreads on the row).

- [ ] **Step 1: Failing tests** — jsdom: click title → stub `openPage` called; click row background/datetime → NOT called; file chip click → `openFile` with the ref path.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** (title cell wraps in the click target; keep the `.selected` row highlight logic).
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): row-click narrows to title; file open IPC; per-cell gestures own their clicks`.

### Task 9: Full-suite gate + docs

- [ ] **Step 1:** `npx vitest run && npm run typecheck` — everything green.
- [ ] **Step 2:** Reconcile docs per the spec's forecast: `Features/TableView.md` (gestures + menus + styles sections), `Features/Views.md` (`column_styles`), `Features/Properties.md` (riders retired), `Features/Interaction.md` (PickerMenu's first consumers). Bundle in the commit.
- [ ] **Step 3: Commit** `feat(table): Phase 1 docs reconciliation`.

### Task 10: CDP visual verification (the zero-regression gate)

- [ ] **Step 1:** With the dev app running (`POMMORA_DEBUG_PORT=9222`), capture via `scratchpad/cdp-shot.mjs`: a collection table at rest · with the inspector open (elastic title compresses, columns hold) · h-scrolled (full-bleed heading + sticky group headers) · a collapsed group (divider correctness) · each status look on a real column · an open CellPicker · an active CellEditor.
- [ ] **Step 2:** Check each against `Features/TableView.md`'s mechanism list — the elastic-title trio, full-bleed band, divider model, sticky headers, col-drag intact (drag-and-abort only — the live app is the REAL Nexus; never drop).
- [ ] **Step 3:** Read the screenshots (surfacing them to Nathan) + report pass/fail per mechanism. **Nathan is the final visual verifier** — closeout waits on his eyes.

---

## Self-Review (ran per the skill)

**Spec coverage:** A-1 (title: enter T8, menu T5, rename T7; drag guard global) · A-2/A-6 (T6 picker + cycle, T5 style menu) · A-3/A-9 (T5 menus, T7 edit, T8 opens, per-file chips T3/T8) · A-4 (T6) · A-5 (datetime read-only — no gesture task, T4/T5 give Style→Options; single-click reserved) · A-7 (T8) · A-8 (T7 + T4/T5) · A-10/A-14 (nothing — by design) · A-12 (T7) · A-13 (T4/T5 per-type Style everywhere) · B-1..B-6 (T1-T5; B-6 glyphs in T3/T6; B-7 is the sibling pane's — out of scope here) · F-1/F-2 (T5/T6) · D + E + C = Phases 2/3.
**Placeholder scan:** clean — every task carries concrete interfaces; full code bodies land at execution against the grounding pack (`tasks/ad1883bf94107537a.output` holds the verbatim current code + Swift enums).
**Type consistency:** `ColumnStyle`/`ColumnLook` (T1) consumed by T3/T4/T5; `setColumnStyle` defined T4, reused T5; `CellMenuContext` T5 only; `nextCycleValue`/`cycleGlyph` T6; `editing` state shape shared T6/T7.
**Known deviation to flag in review:** select/multi's "chip-style set" is concretized as Pill/Capsule (status-minus-checkbox) — the spec deferred contents to planning; flag to Nathan at review.
