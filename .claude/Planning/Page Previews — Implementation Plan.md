# Page Previews Implementation Plan

> **For agentic workers:** execute inline, task-by-task, per the Phase Protocol below. Steps use checkbox (`- [ ]`) syntax for tracking. The certified spec is `Page Previews — Decision Log.md` (same folder) — every task cites its decision ids; on any ambiguity the log wins.

**Goal:** Build the Page Previews remainder onto the shipped shell — the in-preview tab system, durable per-origin persistence, the unified side-pane with a live front-matter inspector, connections routing (B-6/B-7), the engulf promotion, and the NavWindow flavor.

**Architecture:** A `previewTabs` slice (tabsModel reuse + its own active-detail orchestration) drives a tab strip inside the shipped floating window; one synced sidecar persists both flavors' tab sets; a shared side-pane shell serves the NavWindow rail and the preview inspector; all motion DRYs from `tabBar.css` and the `--io` contract.

**Tech Stack:** React 19 + TypeScript (renderer), Electron main IPC, Zustand, CM6 via MarkdownPM/PageEmbed, Vitest.

## Global Constraints

- **Nathan's planning requirements (verbatim law):** every phase ends with gates green (`npm run typecheck` + `npx vitest run` + `npm run build`, pipefail, background) → a review-agent pass → code-simplifier + comment-killer. Re-assess the plan between green phases; rewrite drifted downstream tasks. Doc reconciliation lands WITH the code, committed. Every design choice is confirmed inline as made AND restated in the final report. **The final report comes at the END OF THE PLAN, nowhere else** — every knob (name · file · default), every design decision, every assumption taken/deferred, what Nathan must eyeball live. Standard Agent dispatches only, never the Workflow tool. Phases, never dates. Ping Nathan's phone at each phase gate.
- Tab-neutrality (D-1): the preview slice never touches app `selection`/`tabs`/history/recents/warm entries.
- Colors as hex via design-system tokens only; all motion from existing tokens (`--duration-*`, `--ease-standard`, `--disclosure`); Biome hook owns formatting; typecheck is the only type gate.
- No keyboard shortcuts beyond ⌘N-in-preview (I-20) without Nathan's sign-off.
- The shipped shell (Decision Log → "Shipped Shell") is not re-planned; tasks extend it.
- `TEST_NEXUS_PATH` steers tests only. CM6 extension changes need a full renderer reload to verify live.

## Phase Protocol (every phase)

1. Execute the phase's tasks in order (TDD where a task carries model/store logic).
2. Gates: `set -o pipefail; npm run typecheck && npx vitest run && npm run build` (background, read the summary lines).
3. Dispatch `build-breaking-agent` scoped to the phase's diff; verify each finding at its citation; fix real ones.
4. Dispatch `code-simplifier` then `comment-killer-agent` on the phase diff; re-run gates if they touched code.
5. Commit (explicit paths), push, ping Nathan's phone, re-read the plan and rewrite drifted downstream tasks before the next phase.

---

## Phase 1 — The Preview Tab Model (store)

Decision ids: H-1, H-2 (sentinel), H-5, H-6, H-7, H-11, D-1, D-2, I-1, I-5.

### Task 1.1: The `navwindow` sentinel target kind

**Files:**
- Modify: `Pommora/src/shared/types.ts` (the `TabTarget` union)
- Test: `Pommora/src/renderer/src/Tabs/tabsModel.test.ts` (existing suite still green is the test — the sentinel is additive)

**Interfaces:**
- Produces: `TabTarget` gains `{ kind: 'navwindow' }` — the NavWindow flavor's tab-1 sentinel (H-2), serialized as-is in the sidecar (Phase 3), exempt from warmth (Phase 4).

- [x] **Step 1:** In `types.ts`, extend the tab-target union where `{ kind: 'newtab' }` is declared:

```ts
/** The NavWindow flavor's tab-1 sentinel — the gallery itself; no id/path, never warmed. */
export type PreviewTabTarget = SelectTarget | { kind: 'navwindow' }
```

(Keep the app-tab `TabTarget` untouched — app tabs never hold a navwindow tab. The preview model uses `PreviewTabTarget`.)

- [x] **Step 2:** `npm run typecheck` → PASS (additive type). Commit with Task 1.2.

### Task 1.2: The `previewTabs` slice

**Files:**
- Create: `Pommora/src/renderer/src/PagePreview/previewTabs.ts`
- Modify: `Pommora/src/renderer/src/store.ts` (replace the bare `previewTarget` slot; keep `openPreview`/`closePreview` signatures working)
- Test: `Pommora/src/renderer/src/PagePreview/previewTabs.test.ts`

**Interfaces:**
- Consumes: `Tabs/tabsModel.ts`'s `reconcileTabs` + its Tab/target *shapes* only — the dedup/spawn/close bodies are bespoke (`closeTab`'s last-tab NavView reseed is wrong for the null-on-empty window, H-6; `openTab`'s pinned arg has no preview meaning, H-5). Plus `PreviewTabTarget`.
- Produces (the store's preview API — all downstream phases consume exactly these):

```ts
export interface PreviewTab { id: string; target: PreviewTabTarget }
export interface PreviewState {
  /** null = window closed. flavor 'page' | 'nav'; originId keys the durable set (H-3/H-6). */
  preview: { flavor: 'page' | 'nav'; originId: string; tabs: PreviewTab[]; activeTabId: string } | null
}
// store actions
openPreview(target: { id: string; path: string }): void   // summon/overtake (D-2) — loads the origin's set
openNavPreview(): void                                     // the NavWindow flavor (Phase 8 wires the UI)
openPreviewTab(target: { id: string; path: string }): void // in-preview wiki-click (H-1, dedup-focus)
activatePreviewTab(id: string): void                       // stamps previewSlide (Task 1.3)
closePreviewTab(id: string): void                          // H-6 re-parent; last tab closes the window
closePreview(): void
```

- [x] **Step 1: Failing tests first** (`previewTabs.test.ts`):

```ts
import { describe, expect, it, beforeEach } from 'vitest'
import { useSession } from '../store'

const page = (id: string) => ({ id, path: `Notes/${id}.md` })

beforeEach(() => useSession.setState({ preview: null }))

describe('previewTabs — the tab model (H-1/H-5/H-6/H-7)', () => {
  it('summon opens a single-tab window; re-summon of the same origin is a no-op (I-1)', () => {
    useSession.getState().openPreview(page('x'))
    const p1 = useSession.getState().preview
    expect(p1?.tabs.map((t) => t.target)).toEqual([{ kind: 'page', id: 'x', path: 'Notes/x.md' }])
    useSession.getState().openPreview(page('x'))
    expect(useSession.getState().preview).toBe(p1)
  })
  it('a wiki-click adds a deduped tab and focuses on re-click (H-1)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    expect(useSession.getState().preview?.tabs).toHaveLength(2)
    useSession.getState().activatePreviewTab(useSession.getState().preview!.tabs[0].id)
    useSession.getState().openPreviewTab(page('y')) // dedup: focus, not spawn
    const p = useSession.getState().preview!
    expect(p.tabs).toHaveLength(2)
    expect(p.tabs.find((t) => t.id === p.activeTabId)?.target).toMatchObject({ id: 'y' })
  })
  it('closing the origin re-parents to the left-most survivor; last close kills the window (H-6)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    useSession.getState().closePreviewTab(p.tabs[0].id)
    const p2 = useSession.getState().preview!
    expect(p2.originId).toBe('y')
    useSession.getState().closePreviewTab(p2.tabs[0].id)
    expect(useSession.getState().preview).toBeNull()
  })
  it('a new summon overtakes — swaps to the new origin single-tab set (D-2)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    useSession.getState().openPreview(page('z'))
    const p = useSession.getState().preview!
    expect(p.originId).toBe('z')
    expect(p.tabs).toHaveLength(1)
  })
  it('never touches app tabs/selection (D-1)', () => {
    const { tabs, activeTabId, selection } = useSession.getState()
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const s = useSession.getState()
    expect(s.tabs).toBe(tabs)
    expect(s.activeTabId).toBe(activeTabId)
    expect(s.selection).toBe(selection)
  })
})
```

- [x] **Step 2:** Run → FAIL (`openPreviewTab` undefined).
- [x] **Step 3:** Implement `previewTabs.ts` as pure helpers (mirror `tabsModel`'s shapes; ids via the store's `makeTabId`) + the store slice: `openPreview` builds `{ flavor:'page', originId, tabs:[origin], activeTabId }` (same-origin re-summon short-circuits; overtake replaces after Phase 3 restores the remembered set); `openPreviewTab` dedups by target id then spawns; `closePreviewTab` splices, re-parents `originId` to the new left-most page tab, nulls on empty; keep D-8 wiring (`openPreview` still sets `navOpen:false`; `openNav`/`toggleNav`/`openVia` clear `preview`). Migrate the shipped guards: `applyTree`'s reconcile + D-9's adopt-close now operate on `preview` (reconcile every tab like the app-tab branch; a dead active tab falls to its left neighbor; dead origin re-parents). **Keep `previewTarget` as a derived state field** mirroring the active page tab's target (`preview && activeTab.target.kind === 'page' ? activeTab.target : null`) — PreviewWindow and its imports keep working unchanged until Task 2.2 rewires them.
- [x] **Step 4:** All new tests + the existing D-6 store test (rewrite it to the slice shape) PASS.
- [x] **Step 5:** Commit `feat(preview): previewTabs slice — tab model, dedup, re-parent, reconcile (H-1/H-5/H-6, D-6/D-9 migrated)`.

### Task 1.3: The preview's own switch orchestration

**Files:**
- Modify: `Pommora/src/renderer/src/store.ts` (previewSlide stamp), `Pommora/src/renderer/src/PagePreview/PreviewWindow.tsx` (consume active tab; slide on switch)
- Test: extend `previewTabs.test.ts`

**Interfaces:**
- Produces: `previewSlide: { dir: 'back' | 'fwd'; seq: number } | null` — stamped by `activatePreviewTab` (strip-order direction, the app-tab rule) and `openPreviewTab` (always 'fwd'); consumed by Phase 2's strip + body slide. The preview does NOT reuse `navSlide` (H-11 — one global slot fences the main pane).

- [x] **Step 1: Failing test:** activating a tab left of the current stamps `dir:'back'`, right stamps `'fwd'`, monotonically increasing `seq`.
- [x] **Step 2:** Implement the stamp in the two actions (mirror `navSlide`'s stamping shape; module `previewSlideSeq` counter).
- [x] **Step 3:** PASS → gates → **Phase Protocol steps 2–5** (review, simplify, commit, ping, plan re-read).

---

## Phase 2 — The Tab Strip UI + Morph + Pane Push

Decision ids: F-1, F-4, F-5, H-9 (both variants), G-4, I-16, A-2.

### Task 2.1: Extract the container-agnostic tab motion layer

**Files:**
- Create: `Pommora/src/renderer/src/Tabs/tabStrip.css` (the pure motion layer moved out of `tabBar.css`: `.tab`, `.tab-seg`, `.tab-x`, `.tab-icon`, `.tab-label`, `.nav-slide-back/-fwd` keyframes, `@starting-style` blocks — verbatim, store-free)
- Modify: `Pommora/src/renderer/src/Tabs/tabBar.css` (imports/retains only the toolbar skin: `.tab-bar` app-region/flex, knobs, `.tab-pinned*`, `.tab-scroll/.tab-strip`, the `:has()` reveal chain, `.tab-plus`)

- [ ] **Step 1:** Move the rules; `tabBar.css` keeps its knob block (the moved rules read the same `--tab-*` vars, now defaulted in `tabStrip.css` with `var(--tab-…, fallback)` so a foreign container works without the toolbar's knob block).
- [ ] **Step 2:** Gates + eyeball the app toolbar via CDP screenshot (Read the PNG): tabs open/close/hover unchanged. No TabBar.tsx restructure (Reconciliation 2 — only as far as the strip needs).
- [ ] **Step 3:** Commit `refactor(tabs): container-agnostic tab motion layer (F-4) — toolbar skin stays put`.

### Task 2.2: The preview tab strip + title↔tab morph

**Files:**
- Create: `Pommora/src/renderer/src/PagePreview/PreviewTabStrip.tsx`
- Modify: `PreviewWindow.tsx` (mount strip in the toolbar's center region; body slide on `previewSlide` via WAAPI — the DetailPane pattern, `duration.fast`/`easing.standard`, ±14px), `previewWindow.css`

**Interfaces:**
- Consumes: `preview.tabs`/`activeTabId`, `activatePreviewTab`, `closePreviewTab`, `openPreviewTab`, `previewSlide`.
- Produces: single-tab bannerless state renders the centered breadcrumb (shipped `pgpreview-title`); on tab #2's birth the title collapses left into a standard icon-leading tab in a left-aligned strip (H-9 — the strip mounts, the centered title unmounts, both on the shared tab-open motion; the banner'd origin simply grows its tab, no slide-collapse); per-tab hover ×; labels caption-sized (`--pgpreview-tab-size`).

- [ ] **Step 1:** Build the strip on `tabStrip.css` classes (`.tab`, `.tab-seg`, `.tab-x`) with preview wiring only — no pins, no +, no divider (H-5); the strip gets its **own overflow-x scroll wrapper with the shared edge-fade** (the toolbar's `.tab-scroll` affordance stays toolbar-only — mirror it, don't import it). Tab icons: page's resolved icon; map icon reserved for Phase 8. **Rewire `PreviewWindow.tsx`'s `ConnectionsApi.open` from `openPreview` to `openPreviewTab` (H-1)** — the shipped `open: openPreview` overtakes, which would leave the tab system green-but-dead.
- [ ] **Step 2:** Morph: `PreviewWindow` renders `tabs.length > 1 ? <PreviewTabStrip/> : <NavCrumbs …/>` inside one container whose swap rides the tab-open transition (the entering tab's `@starting-style` growth is the motion; the title fades/slides left on the same tokens — one clean read, no bespoke keyframes).
- [ ] **Step 3:** G-4 pane push: when a tab switch lands with the inspector open, the body slide's direction pushes the pane — drive the shipped `.pgpreview-inspector` transform from the same WAAPI moment (translate the pane by the slide delta, settling back — verify `PaneSlider` composes first; if it doesn't read as collide-and-push, animate the pane's transform directly off the same stamp). **Confirm the exact read via CDP screenshots at design; log the choice inline.**
- [ ] **Step 4:** Gates → CDP-verify against `~/test` (open preview, wiki-click a second tab, screenshot: strip + morph + slide) → Phase Protocol 2–5.

---

## Phase 3 — Durable Persistence (the sidecar)

Decision ids: H-3, H-6 (re-key), H-10, D-9, I-24.

### Task 3.1: Extract the shared debounced-sidecar helper

**Files:**
- Create: `Pommora/src/main/io/debouncedSidecar.ts`
- Modify: `Pommora/src/main/io/tabsState.ts`, `Pommora/src/main/io/navState.ts` (rebase both onto it — same debounce/pending-with-root/in-flight/flush contract, behavior-identical)
- Test: existing `tabsState.test.ts` + `navState.test.ts` stay green (that IS the test); add one helper test for the drain contract.

- [ ] **Step 1:** Lift the shared machine (schedule/write/flush/pending-carries-root) parameterized by `{ file, debounceMs, serialize }`; each module keeps its own validation + shape.
- [ ] **Step 2:** Gates green (the two suites prove behavior parity). Commit `refactor(io): one debounced-sidecar machine — tabsState + navState rebase (H-10)`.

### Task 3.2: `page-previews.json`

**Files:**
- Create: `Pommora/src/main/io/previewState.ts` + `previewState.test.ts`
- Modify: `Pommora/src/main/paths.ts` (entry), `Pommora/src/main/index.ts` (IPC pair `previews:load/save` with the `adopting` guard + drain hookups at adopt/quit), `Pommora/src/preload/index.ts` (bridge), `Pommora/src/shared/types.ts` (persisted shape)

**Interfaces:**
- Produces the persisted shape (per H-10 + Nathan's "which preview is opened"):

```ts
export interface PreviewSetRecord { tabs: { target: PreviewTabTarget }[]; activeIndex: number }
export interface PreviewsFile {
  navSet: PreviewSetRecord | null              // the NavWindow flavor's one set
  origins: Record<string, PreviewSetRecord>    // per-origin page-preview sets, keyed by origin page id
  open: { flavor: 'page' | 'nav'; originId: string } | null  // which preview is open (no auto-summon on launch)
}
```

- [ ] **Step 1: Failing io tests:** lenient read (garbage → empty file shape), round-trip, re-key rename (`origins.x` → `origins.y`), drain-at-quit.
- [ ] **Step 2:** Implement on the Task 3.1 helper. PASS.
- [ ] **Step 3:** Renderer wiring in the slice: on summon, load the origin's remembered set **and reconcile it against the live tree before showing** (dead paths drop, renamed re-path — the `reconcileTabs`-equivalent; an emptied set falls back to `[origin]`); every mutation schedules a save (re-key on re-parent writes both the retirement and the new key); `open` mirrors the slice; adopt drains via the existing `Promise.all` hookups.
- [ ] **Step 4: Failing store tests:** summon restores + reconciles; re-parent re-keys; retired origin re-summons fresh. PASS → gates → Phase Protocol 2–5.

---

## Phase 4 — Warmth

Decision ids: H-8, C-4 (kept), I-10.

### Task 4.1: PageEmbed opt-in warm hooks

**Files:**
- Modify: `Pommora/src/renderer/src/Embeds/PageEmbed.tsx` (optional `warm?: { restore: () => WarmEntry | undefined; capture: (state: WarmEntry) => void }` — the MarkdownEditor already accepts this contract; PageEmbed threads it + uses a restored `pageDetail` body to mount synchronously instead of the blank `pgembed` div), `PagePreview/previewTabs.ts` + `store.ts` (the warm Map is a **slice-owned module** mirroring `warmCache.ts` per H-11 — never component-local; `closePreviewTab` calls its drop, nexus adopt clears it), `PreviewWindow.tsx` (passes the warm hooks keyed by **preview-tab id**)
- Test: a store-level test that capture/restore round-trips per preview-tab id; block tiles (no `warm` prop) unchanged.

- [ ] **Steps:** failing test → implement → PASS → gates → CDP-verify a tab switch restores scroll instantly → Phase Protocol 2–5. (`key={path}` stays; warmth is restore-on-mount, per the log. **`closePreviewTab` evicts the closed tab's warm entry** — the Map never grows unbounded within a session.)

---

## Phase 5 — The Unified Side-Pane + Live Inspector

Decision ids: G-1, G-2, G-3, F-6, I-13, I-14, E (front-matter writes).

### Task 5.1: `SidePane` — the shared shell

**Files:**
- Create: `Pommora/src/renderer/src/design-system/components/SidePane/SidePane.tsx` + `sidePane.css`
- Modify: `NavWindow/NavWindow.tsx` + `navWindow.css` (the SOURCE: the `.navwindow-rail` GlassWindow + `.navwindow-rail-resize` strip + rail width state extract INTO the component, and NavWindow rebases onto it here — Nathan's directive: SidePane IS the NavWindow sidebar component, not a parallel build), `PreviewWindow.tsx` + `previewWindow.css` (the shipped `.pgpreview-inspector` + resize strip + `--io` wiring dissolve into a `<SidePane side="right">` mount; the module `inspectorW` var retires)

**Interfaces:**
- Produces: `<SidePane windowId side="left"|"right" open bounds={{min,def,max}} onIoVar>` — GlassWindow + `state-muted` veil, 6px inner padding, inset ring, `--io` slide (no own transition), edge-drag resize with pause-during-drag, children injected (G-3: ONE component, both windows mount it; flavor bodies injected). Phase 8 then only rebases NavWindow's chrome (FloatingWindow) — its rail is already SidePane after this task.

- [ ] **Steps:** extract from the NavWindow rail (both windows re-mount it, no behavior change — CDP screenshot parity on BOTH before/after) → gates → commit.

### Task 5.2: The front-matter inspector body

**Files:**
- Create: `Pommora/src/renderer/src/PagePreview/PreviewInspector.tsx`
- Modify: `PreviewWindow.tsx` (mount as the SidePane's body)

**Interfaces:**
- Consumes: the active preview tab's page — `openPage` detail (frontmatter + the collection schema via `findCollectionForSet`/collection lookup); property writes through the EXISTING live path: **`PropertiesPane.tsx`'s editors + `mutate({ op: 'setProperty', … })`** (the PropertyPanel/PropertiesPulldown stubs stay untouched — zero call sites, not the live wiring).
- Produces: the Swift front-matter-inspector mechanism — the page's properties listed and editable (typed inputs per PropertyValue kind), title + icon rows (I-13 title edit renames via `mutate rename`, flushing the pending body first — the D-6 self-rename plan item), banner change/remove (I-14, the existing banner mutate).

- [ ] **Steps:** failing store-level test for the write path → implement fields per type (reuse the app's existing pickers/inputs — PickerMenu, checkbox, text — never hand-rolled) → PASS → gates → CDP screenshot the open inspector with real properties (Read for Nathan) → Phase Protocol 2–5. **Layout follows the Swift reference; a Figma pass (G-2) refines later — log every layout call inline.**

---

## Phase 6 — Connections Routing (B-6 · B-7 · modifiers)

Decision ids: B-6, B-7, I-19, I-20, H-11 (the one handler branch).

### Task 6.1: B-6 — the Personalization key + SettingsPane row

**Files:**
- Modify: `Pommora/src/shared/types.ts` (`Personalization` gains `connectionsOpenInPreview?: boolean`), `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx` (a toggle row beside Open In), the three `ConnectionsApi` construction sites (`Detail/PageView.tsx`, `Blocks/BlockSurface.tsx`, `PagePreview/PreviewWindow.tsx`): `open` branches on `store.personalization.connectionsOpenInPreview` → `openPreview(page)` instead of `select` (PreviewWindow's already opens preview tabs — H-7's behind-the-window gate lives there).
- Test: store test — with the key on, the PageView-shaped `open` routes to `openPreview`; off → `select`.

### Task 6.2: I-19 connections ⌘-bypass + ⌘N

**Files:**
- Modify: `Pommora/src/renderer/src/MarkdownPM/connections/index.ts` (`ConnectionsApi` gains optional `bypass?: (page) => void`), `MarkdownPM/editor/connections.ts` (the ONE branch: `event.metaKey && api.bypass ? api.bypass(res.page) : api.open(res.page)`), the three hosts (bypass = `select(target, { newTab: true })`; from inside the preview it's additive — the preview stays), `PreviewWindow.tsx` (⌘N keydown: promote the active tab to a new app tab, close that tab — the window only when last; no-op on the nav sentinel).
- Test: extend previewTabs tests for the ⌘N action semantics.

### Task 6.3: B-2 — the sidebar rows honor the Collection's routing

**Files:**
- Modify: `Pommora/src/renderer/src/Sidebar/Sidebar.tsx` — the page-row click site (`onSelectPage`) gets the same owner-resolution branch TableView carries; the sidebar row resolves its **owning collection from the page's tree position** (walk via `findCollection`/`findCollectionForSet` against the row's parent container — the sidebar has no `source` prop) → `openIn === 'page-preview'` → `openPreview`, ⌘-click bypass to new tab. Embedded view tiles need nothing: they render TableView, whose shipped branch already resolves per-collection (I-3).
- Test: none new (the branch is the shipped TableView shape); CDP-verify a sidebar click on a preview-collection page opens the window.

### Task 6.4: B-7 — the hover trigger + blank pane

**Files:**
- Create: `Pommora/src/renderer/src/Embeds/ConnectionHoverCard.tsx` (PickerMenu chassis, blank body)
- Modify: `MarkdownPM/connections/index.ts` (`hover?: (page, rect) => void`), `editor/connections.ts` (mouseover/mouseout with a hover-intent delay knob `CONN_HOVER_INTENT_MS = 450`, anchor rect from `posAtCoords`), hosts wire `hover` → mount the card; dismiss = pointer-leave with a 200ms grace + Escape (the placeholder contract; full mechanics post-plan).

- [ ] **Steps per task:** failing test where logic-bearing → implement → PASS. Gates → Phase Protocol 2–5. (CM6 extension change: verify live only after a full renderer reload.)

---

## Phase 7 — The Engulf + Close Reasons

Decision ids: A-4, B-5, I-23, F-1 (scan).

### Task 7.1: Close-reason threading + the detail-pane rect

**Files:**
- Modify: `store.ts` (`closePreview(reason?: 'dismiss' | 'engulf')` stored transiently for the exit), `PreviewWindow.tsx` (exit class `closing` vs `engulfing`), `Detail/DetailPane.tsx` (export a rect ref — a module `getDetailPaneRect()` reading the pane element), `previewWindow.css` (the engulf keyframe: FLIP from the window's geometry rect to the detail-pane rect, opacity crossfade, `--duration-base`/`--ease-standard`; a named primitive — `preview-engulf`)
- Promote paths (scan button, ⌘N when it closes the window) pass `'engulf'`; X/Escape pass `'dismiss'`.

- [ ] **Steps:** implement → gates → CDP-record: promote plays the engulf (screenshot mid-flight + settled), dismiss plays the scale-out → Phase Protocol 2–5. **Motion treatment is design-stage — build the FLIP, screenshot, log the exact values inline for Nathan's morning tune.**

---

## Phase 8 — The NavWindow Flavor

Decision ids: H-2, H-4, B-2 (override), F-7, G-3/G-4 (rail mount), I-4, Reconciliation 1 (rebase).

### Task 8.1: NavWindow rebases onto the shared chrome

**Files:**
- Modify: `design-system/interactions/FloatingWindow.tsx` (grow: an optional x-knob drag mode for the rail width + injected close callback), `NavWindow/NavWindow.tsx` (drop the inlined engine; consume `useFloatingWindow('navwindow', …)`; the rail becomes a `SidePane side="left"` mount with its width migrated), `navWindow.css` (chrome classes collapse onto the shared ones where identical)
- Behavior parity is the gate: CDP screenshots before/after (open, drag, resize, rail-resize).

### Task 8.2: The NavWindow flavor's tabs

**Files:**
- Modify: `store.ts` (`openNavPreview()` — flavor `'nav'`, tab 1 the `navwindow` sentinel; NavWindow row "Open in Preview" adds page tabs to THIS window per B-2's override toggle — a NavWindow-chrome control persisted in `PreviewsFile`), `NavWindow/NavWindow.tsx` (mount the strip; the whole body is the map tab's content — page tabs swap it away with the G-4 sidebar push; map tab icon-only, non-orderable, H-4 icon normalization for page tabs whose icon is `map`), `previewState.ts` (navSet round-trip already shaped)
- F-7: the search row nudges down only when `tabs.length > 1`, height transition on `--ease-standard`.

- [ ] **Steps:** failing slice tests (nav flavor spawn, sentinel exempt from ⌘N/promote, H-4 normalization) → implement → PASS → gates → CDP-verify the full flavor → Phase Protocol 2–5.

---

## Phase 9 — Reconciliation + The Final Report

### Task 9.1: Doc reconciliation (the log's Reconciliation section, verbatim scope)

- Modify: `Features/Collections.md`, `Features/Pages.md`, `PommoraPRD.md` (`full-page | page-preview`, routing now real), `Features/Navigation.md` (the deferred preview-mode line retires; the flavor documented), `Features/Interaction.md` (the floating-window in/out + engulf as named primitives), `SettingsPane.tsx` (the B-8 comment retires), `Features/` — a new `PagePreview.md` spec written fresh (the react-docs convention), `History.md` entry, `Handoff.md` via `/handoff`.
- All rewritten as durable truth — no correction framing.

### Task 9.2: THE FINAL REPORT (end of plan, nowhere else)

Deliver in-chat, exhaustively:
- **Every knob:** name · file · default (the `--pgpreview-*` set, `--tab-*` fallbacks, `WIN`/`INSPECTOR` bounds, `CONN_HOVER_INTENT_MS`, engulf values, F-7 nudge height, EMBED zoom).
- **Every design decision made across the whole cycle** (brainstorm + live-driving + execution), each with its decision id.
- **Every assumption taken/deferred** — explicitly the [assumed] set: H-9 banner'd variant, H-2 map-tab content model, I-25 nav-row in-renderer carve-out, H-10 no-auto-summon, B-6 SettingsPane row shape, B-7 placeholder dismiss, D-2 seam scope, G-2 Figma pass pending.
- **What Nathan must eyeball live:** the morph, the pane push, the engulf, inspector layout, warm restore feel, F-7 nudge.
- Ping the phone: plan finished.

---

## Self-Review (run before ratifying this plan)

1. **Spec coverage:** every Core bullet of the certified log maps to a phase (tab system → 1–2; persistence → 3; warmth → 4; side-pane + inspector → 5; B-6/B-7/⌘ → 6; engulf → 7; NavWindow flavor + rebase → 8; reconciliation + report → 9; shipped shell → excluded by design).
2. **Placeholder scan:** no TBDs; every logic task carries test-first steps; design-stage items are explicitly deferred-with-owner, not vague.
3. **Type consistency:** `PreviewTabTarget`/`PreviewSetRecord`/`previewSlide`/`SidePane` names used identically across phases.
