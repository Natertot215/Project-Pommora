# Unified Subfield + Scan-Promote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Ratified spec: `Unified Subfield + Scan-Promote — Decision Log.md` (same folder).

**Goal:** The floating page preview grows a real, scoped Subfield footer (location + live word/char/line, own collapse); NavView grows the detail-pane Subfield's List/Gallery toggle; list-mode rows in NavView + NavWindow get view-like insets; and (deferred) the shared toolbar's Open promotes NavWindow → NavView.

**Architecture:** The Subfield is a props-less global-store consumer today (sole mount `DetailPane.tsx:151`, reads `selection`). We add an OPTIONAL scope via a `SubfieldScope` React context (mirroring `Embeds/ViewEmbedScope.tsx`): in-scope the footer describes the scope's page + reads a scope-provided live body; out-of-scope it behaves exactly as today. Preview stats reuse the EXISTING single `liveBody` store slot (no reshape — readers guard on `liveBody.path === selection.path`, so a preview-page write is invisible to main-pane readers). NavView is a detail-pane resident, so it just adds a `viewType` toggle item to the existing `none` registry entry driven by a new persisted store slice.

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

**Create:**
- `src/renderer/src/Detail/Subfield/SubfieldScope.tsx` — the scope context + `useSubfieldScope()` hook + `SubfieldScopeProvider`. One responsibility: carry the optional per-mount scope (target page + live-body source + collapse state) so `Subfield` can describe something other than the global selection.

**Modify:**
- `Detail/Subfield/Subfield.tsx` — read the scope when present, else the store (unchanged default).
- `Detail/Subfield/subfieldItems.tsx` — add the `viewType` item id + a `ViewTypeItem`; scope-aware `PageStatsItem`; add `viewType` to the `none` `DEFAULT_ITEMS` entry.
- `Detail/Subfield/crumbs.ts` — `subfieldCrumbs` accepts an explicit target (for the preview scope) instead of only `selection`.
- `Detail/DetailPane.tsx` — un-gate `showSubfield` for `none && tree`.
- `PagePreview/PreviewWindow.tsx` — mount the scoped `Subfield` + its own collapse toggle/reveal; provide the scope.
- `PagePreview/PreviewInspector.tsx` + `previewWindow.css` — remove the `pgpreview-insp-subfield` location footing.
- `Embeds/PageEmbed.tsx` — write the debounced `liveBody` on the preview editor's change (guarded so only the preview embed does it).
- `store.ts` — add `navViewMode` persisted slice + `previewSubfieldExpanded`; extend `SubfieldConfig` persistence; migrate NavWindow's `savedViewMode`.
- `Tabs/NavView.tsx` + `navView.css` — add list mode branch driven by `navViewMode`.
- `NavWindow/NavWindow.tsx` — read `navViewMode` from the store (replace the module var).
- `Navigation/NavList.tsx` + `navList.css` — list-mode view-like insets.
- `shared/types.ts` — extend `SubfieldConfig`; `PreviewsFile` gets `subfieldExpanded`.
- `main/settings.ts` — round-trip the extended `SubfieldConfig`.
- Docs: `Features/Subfield.md`, `Features/Navigation.md`, `Features/PagePreview.md`, `History.md`.

---

## Phase A — Enabler + Preview Subfield (P1)

### Task A1: The `SubfieldScope` context

**Files:**
- Create: `src/renderer/src/Detail/Subfield/SubfieldScope.tsx`
- Test: `src/renderer/src/Detail/Subfield/SubfieldScope.test.tsx`

**Interfaces:**
- Produces: `interface SubfieldScopeValue { target: { id: string; path: string; title: string }; body: string; expanded: boolean; setExpanded: (e: boolean) => void }`; `SubfieldScopeProvider` (the context Provider); `useSubfieldScope(): SubfieldScopeValue | null` (null out of scope).

- [ ] **Step 1: Write the failing test** — `useSubfieldScope` returns null with no provider, the value inside one.

```tsx
// @vitest-environment jsdom
import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { SubfieldScopeProvider, useSubfieldScope } from './SubfieldScope'

function Probe() {
  const s = useSubfieldScope()
  return <span>{s ? `${s.target.title}:${s.body}:${s.expanded}` : 'none'}</span>
}

describe('SubfieldScope', () => {
  it('is null with no provider', () => {
    render(<Probe />)
    expect(screen.getByText('none')).toBeTruthy()
  })
  it('exposes the scope value inside a provider', () => {
    render(
      <SubfieldScopeProvider
        value={{ target: { id: 'x', path: 'p/x.md', title: 'X' }, body: 'hi', expanded: true, setExpanded: () => {} }}
      >
        <Probe />
      </SubfieldScopeProvider>,
    )
    expect(screen.getByText('X:hi:true')).toBeTruthy()
  })
})
```

- [ ] **Step 2: Run it, verify it fails** — `npx vitest run src/renderer/src/Detail/Subfield/SubfieldScope.test.tsx` → FAIL (module not found).

- [ ] **Step 3: Implement** (mirror `Embeds/ViewEmbedScope.tsx`'s createContext/Provider/hook shape):

```tsx
import { createContext, useContext } from 'react'

/** Optional per-mount scope for the Subfield: when present, the footer describes THIS target/body
 *  instead of the global selection, and collapses with THIS flag. Out of scope (null) the Subfield
 *  behaves exactly as before — the detail-pane footer over the active selection. */
export interface SubfieldScopeValue {
  target: { id: string; path: string; title: string }
  /** The scope's live editor body (for word/char/line); '' before any content. */
  body: string
  expanded: boolean
  setExpanded: (expanded: boolean) => void
}

const Ctx = createContext<SubfieldScopeValue | null>(null)
export const SubfieldScopeProvider = Ctx.Provider
export const useSubfieldScope = (): SubfieldScopeValue | null => useContext(Ctx)
```

- [ ] **Step 4: Run it, verify PASS.**

- [ ] **Step 5: Commit** — `git add` the two files; `git commit -m "feat(subfield): add optional SubfieldScope context"`.

### Task A2: Scope-aware crumbs + stats

**Files:**
- Modify: `Detail/Subfield/crumbs.ts` (add an explicit-target entry path), `Detail/Subfield/subfieldItems.tsx` (`PageStatsItem` reads the scope body), `Detail/Subfield/Subfield.tsx` (consume the scope).
- Test: `Detail/Subfield/crumbs.test.ts` (extend if present, else create).

**Interfaces:**
- Consumes: `useSubfieldScope()` from A1.
- Produces: `Subfield` renders scope-driven crumbs + stats when scoped; `PageStatsItem` prefers `scope.body`.

- [ ] **Step 1: Read `crumbs.ts`** (`subfieldCrumbs(tree, selection, trail, onSelect)`), confirm it derives the chain from `selection`. Add an overload/param so a caller can pass an explicit `{ id, path }` page target (the preview's page) instead of `selection` — the chain resolves from the tree the same way. Keep the existing `selection`-based call working (out-of-scope path).

- [ ] **Step 2: Write a failing test** — `subfieldCrumbs` with an explicit target resolves that target's container chain (not the active selection's).

```ts
// mirror the existing crumbs.test.ts fixtures; assert the chain for an explicit page target
```

- [ ] **Step 3: Implement crumbs** — thread the explicit target; when given, resolve the chain from it.

- [ ] **Step 4: Make `PageStatsItem` scope-aware** — read `useSubfieldScope()`; when scoped, `body = scope.body`; else the current `liveBody`-vs-`pageDetail` logic (verbatim from `subfieldItems.tsx:33-35`).

```tsx
function PageStatsItem(): React.JSX.Element {
  const scope = useSubfieldScope()
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

- [ ] **Step 5: Make `Subfield` scope-aware** — when scoped, use `scope.target` for crumbs and force the `page` item set (`['pageStats']`); else the current `selection`-driven path verbatim.

```tsx
const scope = useSubfieldScope()
const crumbs = scope
  ? subfieldCrumbs(tree, { kind: 'page', id: scope.target.id, path: scope.target.path }, trail, (t) => void select(t))
  : subfieldCrumbs(tree, selection, trail, (t) => void select(t))
const kind = scope ? 'page' : selection.kind
const items = (order[kind] ?? DEFAULT_ITEMS[kind] ?? []).filter(isSubfieldItemId)
```
(Leave the `useEffect` trail-recording gated on `!scope` — the preview is tab-neutral and must not write the trail.)

- [ ] **Step 6: Run `npx vitest run` for the subfield tests + `npm run typecheck`.** Both green.

- [ ] **Step 7: Commit** — `git commit -m "feat(subfield): scope-aware crumbs + stats"`.

### Task A3: Preview editor writes `liveBody`

**Files:**
- Modify: `Embeds/PageEmbed.tsx` (add the debounced `liveBody` write on editor change, guarded to the preview host).

**Interfaces:**
- Consumes: store `setLiveBody(path, body)` (`store.ts:1000`), `PageEmbed`'s existing `MarkdownEditor` onChange.
- Produces: while a preview embed is being edited, `liveBody` = `{ path: previewPath, body }`.

- [ ] **Step 1: Read `Embeds/PageEmbed.tsx` + `Detail/PageView.tsx:97-99,131`** — replicate PageView's debounced `pushLiveBody` pattern (a `STATS_DEBOUNCE_MS` timer that calls `setLiveBody(path, body)`), wired to PageEmbed's editor `onChange`. Gate it so only the PREVIEW usage writes (pass a prop e.g. `feedsLiveBody?: boolean` from PreviewWindow; PageView-hosted embeds don't set it — PageView already owns `liveBody`).

- [ ] **Step 2: Implement** the debounced writer in PageEmbed behind the `feedsLiveBody` prop; clear the timer on unmount.

- [ ] **Step 3: Typecheck** → green. (No unit test — editor wiring is CDP-verified in A5.)

- [ ] **Step 4: Commit** — `git commit -m "feat(preview): preview embed feeds liveBody for stats"`.

### Task A4: Preview collapse persistence (`page-previews.json`)

**Files:**
- Modify: `shared/types.ts` (`PreviewsFile` gains `subfieldExpanded?: boolean`), `store.ts` (`previewSubfieldExpanded` derived from `previewsFile` + a setter that mirrors), any `previewsFile` writer.
- Test: `PagePreview/previewTabs.test.ts` (extend — the previews-file round-trip is already tested there).

**Interfaces:**
- Produces: `previewSubfieldExpanded: boolean` (default true) + `setPreviewSubfieldExpanded(e)` persisting into `page-previews.json` via the existing `mirrorPreviews()`/`savePreviewsFile` path.

- [ ] **Step 1: Write failing test** — toggling `setPreviewSubfieldExpanded(false)` persists into `previewsFile.subfieldExpanded`.

- [ ] **Step 2–4: Implement** — extend the `PreviewsFile` type + the mirror; add the store field + setter (follow `setNavOverride` at `store.ts:1287` as the persisting-into-previews-file precedent). Run the test → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(preview): persist the preview subfield collapse flag"`.

### Task A5: Mount the scoped Subfield in the preview + drop the inspector footing

**Files:**
- Modify: `PagePreview/PreviewWindow.tsx` (mount `<SubfieldScopeProvider value={…}><Subfield/></SubfieldScopeProvider>` + collapse toggle/reveal at the window bottom), `previewWindow.css` (footer layout + reveal that clears the BR resize corner), `PagePreview/PreviewInspector.tsx` (remove `pgpreview-insp-subfield`), `previewWindow.css` (remove its rules).

**Interfaces:**
- Consumes: A1 provider, A2 Subfield, A3 `feedsLiveBody`, A4 collapse flag, `usePreviewWarm` body for `scope.body`, the preview's active page target.

- [ ] **Step 1:** Remove the `pgpreview-insp-subfield` block from `PreviewInspector.tsx` + its CSS (the location breadcrumb + subfield divider) — it's superseded.
- [ ] **Step 2:** In `PreviewWindow.tsx`, build the scope value: `target` = the active page tab (id/path/title), `body` = the preview editor's live buffer (from `usePreviewWarm`/the embed's current body), `expanded` = `previewSubfieldExpanded`, `setExpanded` = the A4 setter. Wrap the window's footer `<Subfield/>` in the provider.
- [ ] **Step 3:** Add the preview's own collapse toggle chevron + reveal — trigger the reveal off the chevron's own hover box (NOT a fixed BR rectangle) so it clears `FloatingResizeCorners` (`NavWindow.tsx:345` pattern) + the inspector `--io` edge (DF-6). Pass `feedsLiveBody` to the preview `PageEmbed`.
- [ ] **Step 4:** Layout the footer at the window bottom (below the one-scroller body; coexisting with the right inspector overlay) — pin it, `subline` scale, matching the detail-pane Subfield look.
- [ ] **Step 5: CDP-verify** — open a page preview, confirm: the footer shows the preview page's location + live-updating word/char/line as you drive edits via the store; the collapse chevron toggles it; the reveal doesn't block the resize corner; the inspector's old location footing is gone. Screenshot + Read.
- [ ] **Step 6: Gate** (typecheck + vitest + build) + **commit** — `git commit -m "feat(preview): scoped Subfield footer replaces the inspector location footing"`.

**Phase A gate + docs:** update `Features/PagePreview.md` (inspector no longer holds the location footing; the window has a real Subfield) + `Features/Subfield.md` (the scope seam). Commit docs.

---

## Phase B — NavView Subfield + View-Type Toggle (P2)

### Task B1: The `navViewMode` persisted store slice

**Files:**
- Modify: `store.ts` (add `navViewMode: 'list' | 'gallery'` + `setNavViewMode` persisted), `shared/types.ts` + `main/settings.ts` (persist it — extend `SubfieldConfig` or add to settings), `NavWindow/NavWindow.tsx` (replace the `savedViewMode` module var with the store slice).
- Test: `store.test.tsx` (or a focused new test) — the slice defaults + persists + drives both surfaces.

**Interfaces:**
- Produces: `navViewMode` (default `'list'`, matching NavWindow's current default) + `setNavViewMode(m)`, persisted per-nexus.

- [ ] **Step 1: Write failing test** — `setNavViewMode('gallery')` sets state + calls the persist IPC.
- [ ] **Step 2–4: Implement** — add the slice (mirror `setSubfieldExpanded`'s persist pattern at `store.ts:945`); load it on nexus open alongside the subfield config (`store.ts:662`). Migrate `NavWindow.tsx`: delete `let savedViewMode` (`:35`) + the local `useState`/`toggleViewMode` module-var logic (`:138-143`), read `navViewMode`/`setNavViewMode` from the store instead. Run test → PASS.
- [ ] **Step 5: CDP-verify** NavWindow's toggle still flips list/gallery and now persists across relaunch.
- [ ] **Step 6: Commit** — `git commit -m "feat(nav): navViewMode persisted store slice; NavWindow reads it"`.

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
- Consumes: `closeNav()`, `openNewTab()` (`tabsModel.ts:132-138` — already dedups to the existing NavView), `navViewMode`/`setNavViewMode` (B1).

- [ ] **Step 1:** Relax `promote()`'s `if (!pageTarget) return` guard (`NavWindow.tsx:161`): on the map flavor (no `pageTarget`), promote = `closeNav()` + `openNewTab()` (focuses the existing NavView or opens one). Un-gate the scan glyph's `is-page-tab`-only visibility (`navWindow.css:86-90`) so it shows on the map flavor too, fixed top-left (no engulf motion).
- [ ] **Step 2:** One-time-copy the view mode at promote — read NavWindow's current `navViewMode` and set NavView's (they share the one `navViewMode` slice, so this is already carried; if a per-surface split is ever introduced, copy here). Per DF-2 the copy is one-shot.
- [ ] **Step 3: CDP-verify** — from NavWindow's map tab, click the scan/Open → NavWindow closes, a NavView tab opens/focuses, in the same view mode; re-clicking with a NavView already open focuses it (no duplicate). Screenshot.
- [ ] **Step 4: Gate + commit** — `git commit -m "feat(nav): scan-promote NavWindow → NavView via the shared Open action"`.

**Phase D docs:** `Features/PagePreview.md` + `Features/Navigation.md` (the shared Open promotes NavWindow → NavView). Commit.

---

## Self-Review

**Spec coverage:** Enabler/scope → A1–A2; preview stats-no-reshape → A3 (`feedsLiveBody` into the single `liveBody` slot); preview own collapse + persistence → A4; preview mount + drop inspector footing + reveal-clears-corner → A5; NavView shares the detail-pane Subfield via the `none` registry + `none && tree` gate → B2; NavView list mode → B3; view-mode is a persisted store slice not a module var (F2) → B1; NavWindow module-var migration → B1; list insets NavWindow-first, NavView rides P2 → C1/C2; scan-promote deferred → D1. Out-of-scope items (shell merge, NavWindow Subfield, same-page exclusion) carry no task — correct.

**Placeholder scan:** the load-bearing store/model tasks carry real code + tests; the visual/mount tasks (A5, B3, C1, D1) are CDP-verified per Pommora convention and point at exact file:line patterns to mirror rather than inventing UI code blind — acceptable for this codebase (UI is screenshot-verified, not unit-tested). No "TBD"/"handle edge cases".

**Type consistency:** `SubfieldScopeValue` (A1) is consumed verbatim in A2/A5; `navViewMode`/`setNavViewMode` (B1) consumed in B2/B3/D1; `SubfieldItemId` gains `'viewType'` in B2 and `DEFAULT_ITEMS.none` matches; `feedsLiveBody` prop (A3) consumed in A5.

**Known follow-through for the executor:** confirm A3's preview-body source (`usePreviewWarm` vs the embed's current buffer) resolves to the SAME string the stats compute over — verify during A5's CDP pass that the count tracks keystrokes.
