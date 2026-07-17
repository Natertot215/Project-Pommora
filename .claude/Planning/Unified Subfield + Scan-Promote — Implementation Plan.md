# Unified Subfield + Scan-Promote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Ratified spec: `Unified Subfield + Scan-Promote — Decision Log.md` (same folder).

**Goal:** The floating page preview grows a real, scoped Subfield footer (location + live word/char/line, own collapse); NavView grows the detail-pane Subfield's List/Gallery toggle; list-mode rows in NavView + NavWindow get view-like insets; and (deferred) the shared toolbar's Open promotes NavWindow → NavView.

**Architecture:** The Subfield is a props-less global-store consumer today (sole mount `DetailPane.tsx:151`, reads `selection`). We give it ONE optional `scope` prop (`{ target, body } | undefined`): scoped, the footer describes the scope's page and counts from the scope's body; unscoped, it behaves exactly as today. Only one surface passes it (the preview), so it's a plain prop, not a context. Preview stats come from the preview window's OWN local state — `PageEmbed` exposes a controlled `body`/`onBody`, `PreviewWindow` debounces it into local state and passes it down; the global `liveBody` slot is never touched (it's a single-owner slot — a second writer would evict the main pane's live count to its saved snapshot). NavView is a detail-pane resident, so it just adds a `viewType` toggle item to the existing `none` registry entry driven by a new persisted store slice. View modes are TWO separate persisted slices (`navWindowMode`, `navViewMode`) per DF-2, stored under a standalone settings key.

**Tech Stack:** Electron 42 · React 19 · TypeScript · Zustand (`useSession`) · Vitest · CodeMirror 6 (MarkdownPM) · vanilla-extract + plain CSS · Biome (format-on-write hook).

## Global Constraints

- **`npm run typecheck` is the ONLY type gate** — the build strips types unchecked. Run it every task.
- **Gate between phases:** `set -o pipefail && npm run typecheck 2>&1 | tail -3 && npx vitest run 2>&1 | grep -E "Tests|FAIL" && npm run build 2>&1 | tail -1`.
- **Colors are hex from `design-system/tokens` only** — never `rgb()`/`rgba()`, never hand-rolled; consume via the `--label-*`/`--surface-*`/`--state-*` CSS vars.
- **Biome formats on write** (single-quote, no semicolons) — never hand-align; an Edit failing on whitespace means Biome reformatted, so re-read + retry.
- **Main owns the filesystem** — any new persistence goes through a narrow typed IPC envelope (`{ ok, … } | { ok:false, error }`); the renderer never touches `fs`.
- **Most-recent-wins is the app philosophy** — two editors on one file is by-design; add NO exclusion guard.
- **Visual/mount tasks are CDP-verified, not unit-tested** — launch `env -u ELECTRON_RUN_AS_NODE npx electron-vite dev -- --remote-debugging-port=9333 --remote-allow-origins='*'`, drive via `window.__pommora.getState()`, screenshot via CDP `Page.captureScreenshot`, Read the PNG. Store/model logic IS unit-tested (Vitest).

---

## File Structure

**Modify:**
- `Detail/Subfield/Subfield.tsx` — accept an optional `scope?: SubfieldScope` prop; when present, describe the scope's target + force the page item set, else the store-driven default (unchanged).
- `Detail/Subfield/subfieldItems.tsx` — define `SubfieldScope`; add the `viewType` item id + a `ViewTypeItem`; `PageStatsItem` takes an optional `body`; add `viewType` to the `none` `DEFAULT_ITEMS` entry.
- `Detail/Subfield/crumbs.ts` — `subfieldCrumbs` accepts an explicit target (for the preview scope) instead of only `selection`.
- `Detail/DetailPane.tsx` — un-gate `showSubfield` for `none && tree`.
- `PagePreview/PreviewWindow.tsx` — hold the preview editor body in local state; mount `<Subfield scope={…}/>` at the window bottom + its own session-only collapse toggle/reveal.
- `PagePreview/PreviewInspector.tsx` + `previewWindow.css` — remove the `pgpreview-insp-subfield` location footing.
- `Embeds/PageEmbed.tsx` — expose the editor body via a controlled `body`/`onBody` prop (opt-in; PageView-hosted embeds don't pass it). Never writes the global `liveBody`.
- `store.ts` — add TWO persisted slices `navWindowMode` + `navViewMode` (standalone settings key, NOT `SubfieldConfig`); migrate NavWindow's `savedViewMode` module var to `navWindowMode`.
- `Tabs/NavView.tsx` + `navView.css` — add list mode branch driven by `navViewMode`.
- `NavWindow/NavWindow.tsx` — read `navWindowMode` from the store (replace the module var).
- `Navigation/NavList.tsx` + `navList.css` — list-mode view-like insets.
- `shared/types.ts` — add the nav view-mode settings key type.
- `main/settings.ts` — round-trip the nav view-mode key.
- Docs: `Features/Subfield.md`, `Features/Navigation.md`, `Features/PagePreview.md`, `History.md`.

---

## Phase A — Enabler + Preview Subfield (P1)

### Task A1: Scope-aware Subfield (optional `scope` prop) + scope-aware crumbs + stats

**Files:**
- Modify: `Detail/Subfield/subfieldItems.tsx` (define + export `SubfieldScope`; item components take a `scope`; `PageStatsItem` prefers `scope.body`), `Detail/Subfield/crumbs.ts` (explicit-target entry path), `Detail/Subfield/Subfield.tsx` (accept the `scope` prop).
- Test: `Detail/Subfield/crumbs.test.ts` (extend if present, else create).

**Interfaces:**
- Produces: `export interface SubfieldScope { target: { id: string; path: string; title: string }; body: string }`. `Subfield` gains `scope?: SubfieldScope`. Item registry components take `{ scope?: SubfieldScope }`; `PageStatsItem` counts `scope.body` when scoped.
- Consumes (later tasks): A3 passes the controlled preview body into `scope.body`; A3's mount passes `scope` to `<Subfield/>`.

- [ ] **Step 1: Read `subfieldItems.tsx`** — confirm the registry shape (`SubfieldItemId`, `DEFAULT_ITEMS`, `isSubfieldItemId`, the item components `PageStatsItem`/`AddMenuItem`) and how `Subfield` renders items. The item components are props-less today; we thread ONE props bag.

- [ ] **Step 2: Define the scope type + prop-thread the items** — in `subfieldItems.tsx`:

```tsx
export interface SubfieldScope {
  target: { id: string; path: string; title: string }
  /** The scope's live editor body (for word/char/line); '' before any content. */
  body: string
}
export interface SubfieldItemProps {
  scope?: SubfieldScope
}
```
Change each registry component to accept `SubfieldItemProps` (existing items ignore it; only `PageStatsItem` reads `scope`).

- [ ] **Step 3: Make `PageStatsItem` scope-aware** — when scoped, count `scope.body`; else the current `liveBody`-vs-`pageDetail` logic verbatim:

```tsx
function PageStatsItem({ scope }: SubfieldItemProps): React.JSX.Element {
  const pageDetail = useSession((s) => s.pageDetail)
  const liveBody = useSession((s) => s.liveBody)
  const body = scope
    ? scope.body
    : liveBody && liveBody.path === pageDetail?.path
      ? liveBody.body
      : (pageDetail?.body ?? '')
  const stats = useMemo(() => computeStats(body), [body])
  // …unchanged render…
}
```

- [ ] **Step 4: Scope-aware crumbs** — read `crumbs.ts` (`subfieldCrumbs(tree, selection, trail, onSelect)`); add a param so a caller can pass an explicit `{ id, path }` page target (the preview's page) instead of `selection`, resolving the chain from the tree the same way. Keep the `selection`-based call working. Write a failing test asserting an explicit target resolves that target's container chain (mirror the existing `crumbs.test.ts` fixtures); implement; PASS.

- [ ] **Step 5: Make `Subfield` accept `scope`** — when scoped, crumbs from `scope.target`, force the page item set, pass `scope` into each rendered item; else the current `selection`-driven path verbatim:

```tsx
export function Subfield({ scope }: { scope?: SubfieldScope }): React.JSX.Element {
  // …existing store reads (tree/trail/select/order) …
  const crumbs = scope
    ? subfieldCrumbs(tree, { kind: 'page', id: scope.target.id, path: scope.target.path }, trail, (t) => void select(t))
    : subfieldCrumbs(tree, selection, trail, (t) => void select(t))
  const kind = scope ? 'page' : selection.kind
  const items = (order[kind] ?? DEFAULT_ITEMS[kind] ?? []).filter(isSubfieldItemId)
  // render each item as <Comp scope={scope} />
}
```
Gate the `useEffect` trail-recording on `!scope` — the preview is tab-neutral and must not write the trail.

- [ ] **Step 6: Run `npx vitest run` for the subfield tests + `npm run typecheck`.** Both green.

- [ ] **Step 7: Commit** — `git commit -m "feat(subfield): optional scope prop — scope-aware crumbs + stats"`.

### Task A2: `PageEmbed` exposes a controlled body (no `liveBody` write)

**Files:**
- Modify: `Embeds/PageEmbed.tsx` (opt-in `body`/`onBody` controlled prop off the editor's change).

**Interfaces:**
- Consumes: `PageEmbed`'s existing `MarkdownEditor` onChange; `Detail/PageView.tsx:97-99,131` as the debounce pattern to mirror (timer shape only — NOT the `setLiveBody` call).
- Produces: `PageEmbed` accepts `onBody?: (body: string) => void`; when passed, it fires on editor change. PageView-hosted embeds don't pass it. **Never touches the global `liveBody` slot.**

- [ ] **Step 1: Read `Embeds/PageEmbed.tsx`** — find its editor `onChange`/change wiring and how it currently reports content upward (if at all).

- [ ] **Step 2: Implement** the opt-in `onBody?: (body: string) => void` callback fired on editor change (raw — the debounce lives in the PreviewWindow consumer, A3, mirroring PageView's timer). No store write, no `liveBody`.

- [ ] **Step 3: Typecheck** → green. (No unit test — editor wiring is CDP-verified in A3.)

- [ ] **Step 4: Commit** — `git commit -m "feat(embed): PageEmbed opt-in controlled body callback"`.

### Task A3: Mount the scoped Subfield in the preview (local body + session collapse) + drop the inspector footing

**Files:**
- Modify: `PagePreview/PreviewWindow.tsx` (local body state fed by A2's `onBody`; mount `<Subfield scope={…}/>` + own session-only collapse toggle/reveal at the window bottom), `previewWindow.css` (footer layout + reveal that clears the BR resize corner), `PagePreview/PreviewInspector.tsx` (remove `pgpreview-insp-subfield`) + its `previewWindow.css` rules.

**Interfaces:**
- Consumes: A1 `Subfield`/`SubfieldScope`, A2 `PageEmbed onBody`, the preview's active page target (id/path/title), the preview's saved body (from `usePreviewWarm`) as the initial `scope.body` before any edit.

- [ ] **Step 1:** Remove the `pgpreview-insp-subfield` block from `PreviewInspector.tsx` + its CSS (the location breadcrumb + subfield divider) — it's superseded.
- [ ] **Step 2:** In `PreviewWindow.tsx`, hold the preview editor body in local state — seed it from the active tab's saved/warm body, update it (debounced, `STATS_DEBOUNCE_MS` timer like `PageView.tsx:97-99,131`) from A2's `onBody` off the preview `PageEmbed`; clear the timer on unmount. Build the scope: `target` = the active page tab (id/path/title), `body` = that local body. Render `<Subfield scope={scope}/>` at the window bottom.
- [ ] **Step 3:** Add the preview's own collapse chevron + reveal, backed by a **session-only** `useState` (NOT persisted — DF-3). Trigger the reveal off the chevron's own hover box (NOT a fixed BR rectangle) so it clears `FloatingResizeCorners` (`NavWindow.tsx:345` pattern) + the inspector `--io` edge (DF-6).
- [ ] **Step 4:** Layout the footer at the window bottom (below the one-scroller body; coexisting with the right inspector overlay) — pin it, `subline` scale, matching the detail-pane Subfield look.
- [ ] **Step 5: CDP-verify** — open a page preview and confirm ALL of: (a) the footer shows the preview page's location + live word/char/line that tracks keystrokes as you drive edits; (b) editing a preview of a *different* page than the detail selection does NOT change the main-pane footer's live count (the F2 regression this design exists to prevent); (c) the collapse chevron toggles it; (d) the reveal doesn't block the resize corner; (e) the inspector's old location footing is gone. Screenshot + Read.
- [ ] **Step 6: Gate** (typecheck + vitest + build) + **commit** — `git commit -m "feat(preview): scoped Subfield footer replaces the inspector location footing"`.

**Phase A gate + docs:** update `Features/PagePreview.md` (inspector no longer holds the location footing; the window has a real Subfield sourced from local body) + `Features/Subfield.md` (the `scope` prop seam). Commit docs.

---

## Phase B — NavView Subfield + View-Type Toggle (P2)

### Task B1: Two persisted view-mode slices (`navWindowMode` + `navViewMode`)

**Files:**
- Modify: `store.ts` (add `navWindowMode` + `navViewMode`, each `'list' | 'gallery'`, with `setNavWindowMode`/`setNavViewMode`, both persisted), `shared/types.ts` + `main/settings.ts` (a STANDALONE settings key for the two modes — NOT inside `SubfieldConfig`, whose `setSubfield*` setters rebuild `{order, expanded}` and would clobber an added field), `NavWindow/NavWindow.tsx` (replace the `savedViewMode` module var with `navWindowMode`).
- Test: `store.test.tsx` (or a focused new test) — each slice defaults + persists independently.

**Interfaces:**
- Produces: `navWindowMode` + `navViewMode` (default `'list'`, matching NavWindow's current default) + `setNavWindowMode(m)` / `setNavViewMode(m)`, persisted per-nexus under one standalone key (e.g. `navViewModes: { window, view }`). They are SEPARATE per surface (DF-2) — flipping one must not flip the other.

- [ ] **Step 1: Write failing tests** — `setNavWindowMode('gallery')` sets `navWindowMode` + persists AND leaves `navViewMode` untouched; symmetric for `setNavViewMode`.
- [ ] **Step 2: Add the settings key** — `shared/types.ts`: a `navViewModes?: { window: 'list'|'gallery'; view: 'list'|'gallery' }` field on the settings shape; `main/settings.ts`: round-trip it through the existing settings IPC (mirror how the `subfield` key is read/written, but as its OWN key).
- [ ] **Step 3: Add the slices** — in `store.ts`, add both fields + setters (mirror `setSubfieldExpanded`'s persist-IPC pattern at `store.ts:945`, but writing the `navViewModes` key); load both on nexus open alongside the subfield config (`store.ts:662`).
- [ ] **Step 4: Migrate `NavWindow.tsx`** — delete `let savedViewMode` (`:35`) + the local `useState`/`toggleViewMode` module-var logic (`:138-143`); read `navWindowMode`/`setNavWindowMode` from the store instead. Run tests → PASS.
- [ ] **Step 5: CDP-verify** NavWindow's toggle still flips list/gallery, persists across relaunch, and does NOT move any NavView state.
- [ ] **Step 6: Commit** — `git commit -m "feat(nav): separate persisted navWindowMode + navViewMode slices; NavWindow reads navWindowMode"`.

### Task B2: The `viewType` Subfield item + un-gate `none`

**Files:**
- Modify: `Detail/Subfield/subfieldItems.tsx` (`SubfieldItemId` gains `'viewType'`; a `ViewTypeItem` button reading/writing `navViewMode`; `DEFAULT_ITEMS.none = ['viewType']`; `ALL_ITEM_IDS`), `Detail/DetailPane.tsx` (`showSubfield` includes `none && tree`).
- Test: `subfieldItems` registry test (the `viewType` id validates; `none` default includes it).

**Interfaces:**
- Consumes: B1 `navViewMode`/`setNavViewMode`.
- Produces: `ViewTypeItem` (a List⇄Gallery toggle in the footer's right slot).

- [ ] **Step 1: Write failing test** — `isSubfieldItemId('viewType')` true; `DEFAULT_ITEMS.none` = `['viewType']`.
- [ ] **Step 2: Implement** the id + `ALL_ITEM_IDS` + `DEFAULT_ITEMS.none`; the `ViewTypeItem` (a `subfield`-styled button, `chevrons-up-down` + `{mode==='list'?'List':'Gallery'}`, `onClick` flips `navViewMode` — reuse the exact tone/markup of NavWindow's `navwindow-style-toggle` so it reads identically).
- [ ] **Step 3: Un-gate DetailPane** — `showSubfield` becomes `collection || set || page || (none && tree)` (F4: `none && tree` NOT bare `none` — `case 'none'` also renders the no-nexus prompt, `DetailPane.tsx:22-31`). `selectionKind === 'none'` alone would mount the footer under the blank prompt.
- [ ] **Step 4:** Run tests + typecheck → green.
- [ ] **Step 5: Commit** — `git commit -m "feat(subfield): viewType toggle item; footer shows for NavView"`.

### Task B3: NavView list mode

**Files:**
- Modify: `Tabs/NavView.tsx` (branch on `navViewMode` — render `NavList` in list mode, `NavGallery` in gallery), `navView.css` (list-mode layout).
- CDP-verified.

**Interfaces:**
- Consumes: B1 `navViewMode`, `Navigation/NavList.tsx` (mirror NavWindow's list branch at `NavWindow.tsx:298-324`), the same `resolvedRecents`/`resolvedPins`/`go` from `useNavData`.

- [ ] **Step 1:** In `NavView.tsx`, read `navViewMode`; when `'list'` render `<NavList pins={…} items={…} reorderable onReorderRecent onSelect onOpenNewTab/>` (the NavWindow list branch shape), else the current `<NavGallery/>`. Keep search results rendering as-is.
- [ ] **Step 2: CDP-verify** — open NavView (new tab / empty state), flip the footer's viewType toggle → NavView switches list⇄gallery; the toggle drives it reactively (proves the store-slice-not-module-var fix). Screenshot.
- [ ] **Step 3: Gate + commit** — `git commit -m "feat(navview): list mode driven by the subfield viewType toggle"`.

**Phase B docs:** update `Features/Navigation.md` (NavView gains list mode + the footer toggle) + `Features/Subfield.md` (the `viewType` item, the `none` kind now shows). Commit.

---

## Phase C — List-Mode Insets (P3)

### Task C1: NavWindow list-mode view-like insets (ships independently)

**Files:**
- Modify: `Navigation/navList.css` (`.nav-item-pin` gutter + `.nav-item-main` padding in list mode), possibly a list-mode marker class.
- CDP-verified.

- [ ] **Step 1:** The squish: `.nav-item-pin` sits at `left: calc(var(--navwindow-inset,12px)/2)` (`navList.css:~21`) crowding the leading `EntityGlyph`; `.nav-item-main` pads at `--navwindow-inset`. Retarget list rows to the view/surface inset regime (`--surface-inset*` — the tokens NavView's gallery already lands on) so the pin + lead glyph get breathing room. Gallery mode + the banner search-field inset stay untouched.
- [ ] **Step 2: CDP-verify** in NavWindow list mode — pinned rows no longer squished; gallery unchanged; screenshot + Read (crop + 3× zoom for the pin gutter).
- [ ] **Step 3: Commit** — `git commit -m "fix(nav): view-like list-mode insets so pinned icons breathe"`.

### Task C2: Confirm the insets carry into NavView list mode

- [ ] **Step 1:** Since NavView now uses `NavList` (B3), C1's list-mode inset rules apply automatically. CDP-verify NavView list mode shows the same un-squished insets. If NavView's zeroed gallery tokens (`navView.css:11-12`) interfere in list mode, scope the inset fix so it wins there too.
- [ ] **Step 2: Commit** if any adjustment — else fold the confirmation into C1.

---

## Phase D — Scan-Promote to NavView (P4 · PROSPECT · deferred)

> **Deferred.** Build only after Core (A–C) is proven. Separable — depends only on NavView + `navViewMode` existing.

### Task D1: The shared toolbar's Open targets NavView on the map flavor

**Files:**
- Modify: `NavWindow/NavWindow.tsx` (`promote()` handles the map flavor), `navWindow.css:86-90` (scan visibility no longer `is-page-tab`-only).

**Interfaces:**
- Consumes: `closeNav()`, `openNewTab()` (`tabsModel.ts:132-138` — already dedups to the existing NavView), `navWindowMode` + `setNavViewMode` (B1).

- [ ] **Step 1:** Relax `promote()`'s `if (!pageTarget) return` guard (`NavWindow.tsx:161`): on the map flavor (no `pageTarget`), promote = `closeNav()` + `openNewTab()` (focuses the existing NavView or opens one). Un-gate ONLY `.navwindow-actions-lead`'s `is-page-tab`-only visibility (`navWindow.css:86-90`) so the scan shows on the map flavor — NOT the shared `.navwindow-actions` (that would wrongly surface the inspector/settings pair on the map flavor). Scan stays fixed top-left (no engulf motion).
- [ ] **Step 2:** One-time-copy the view mode at promote — read NavWindow's `navWindowMode` and `setNavViewMode(it)` once (the slices are SEPARATE per DF-2, so this copy is real and one-shot; afterward the two modes are independent again).
- [ ] **Step 3: CDP-verify** — from NavWindow's map tab, click the scan/Open → NavWindow closes, a NavView tab opens/focuses in NavWindow's current mode; then flip NavView's mode and confirm NavWindow's persisted mode is unaffected; re-clicking with a NavView already open focuses it (no duplicate). Screenshot.
- [ ] **Step 4: Gate + commit** — `git commit -m "feat(nav): scan-promote NavWindow → NavView via the shared Open action"`.

**Phase D docs:** `Features/PagePreview.md` + `Features/Navigation.md` (the shared Open promotes NavWindow → NavView). Commit.

---

## Self-Review

**Spec coverage:** scope-aware Subfield (prop, not context) + scope crumbs/stats → A1; preview stats from LOCAL body via `PageEmbed onBody` (never the `liveBody` slot — F2) → A2 + A3; preview own session-only collapse + reveal-clears-corner + mount + drop inspector footing → A3; NavView shares the detail-pane Subfield via the `none` registry + `none && tree` gate → B2; NavView list mode → B3; TWO separate persisted view-mode slices, not a module var and not one shared slice (F2 + DF-2) → B1; NavWindow module-var migration → B1; list insets NavWindow-first, NavView rides P2 → C1/C2; scan-promote deferred, lead-only un-gate + real one-time mode copy → D1. Out-of-scope items (shell merge, NavWindow Subfield, same-page exclusion) carry no task — correct.

**Placeholder scan:** the load-bearing store/model tasks carry real code + tests; the visual/mount tasks (A3, B3, C1, D1) are CDP-verified per Pommora convention and point at exact file:line patterns to mirror rather than inventing UI code blind — acceptable for this codebase (UI is screenshot-verified, not unit-tested). No "TBD"/"handle edge cases".

**Type consistency:** `SubfieldScope` (A1) is consumed in A3's mount; `SubfieldItemProps.scope` (A1) threads to `PageStatsItem`; `PageEmbed onBody` (A2) consumed in A3; `navWindowMode`/`navViewMode` + their setters (B1) consumed in B2/B3/D1; `SubfieldItemId` gains `'viewType'` in B2 and `DEFAULT_ITEMS.none` matches.

**Known follow-through for the executor:** (1) A3's local body must seed from the same saved/warm source the stats expect so the count is correct before the first keystroke — verify in A3's CDP pass that it both starts right AND tracks keystrokes, and that the main-pane footer is untouched while editing a different-page preview. (2) NavView's footer view-type toggle is inert during an active search (same as NavWindow today) — acceptable, not a regression; noted so it isn't mistaken for a bug in B3's CDP pass.
