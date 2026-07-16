# Multi-Tab Nexus Implementation Plan

> **For agentic workers:** implement task-by-task, gate between phases, re-read the plan against what landed after each green commit. Steps use `- [ ]`. **Source of truth:** `Multi-Tab Nexus — Decision Log.md` (decision IDs cited inline). Where this plan names an exact value it's a starting knob — ground the literal at build time. **Per-phase review discipline is mandatory:** after each phase ships green, dispatch a `build-breaking-agent` (attack the phase against real code) and a `code-simplifier` pass, verify their findings yourself, fold, then gate. The Phase 4 tab-bar build additionally runs the §J UIX-repass and a post-functional UIX review.

**Goal:** Replace single-pane-replace with warm, state-preserving tabs — a persisted, cross-device-synced working set of open entities, pinned + unpinned, each keeping its own scroll/undo within a session and its own Back/Forward.

**Architecture:** A `tabs` slice sits above the singular `selection`; the active tab's target drives the existing `select()`/detail path. One view mounted; inactive tabs hold a serialized `historyField`+scroll cache, rehydrated by seeding a fresh CM6 mount. The "consumers untouched" property holds for RENDER consumers only — tree reconciliation (every tab reconciles in `applyTree`) and warm-instant switching are deliberate `applyTree`/`select` changes. The tab set (unpinned tabs + active; `isPinned` derived from the pins store, never stored) syncs cross-device; pinned identities ride `.nexus/pins/`.

**Tech Stack:** Electron 42 · React 19 · TypeScript · Zustand · CodeMirror 6 · the in-house drag engine · narrow contextBridge IPC.

## Global Constraints

- Main owns fs; renderer never touches Node; IPC returns `{ ok } | { ok:false, error }`; `shared/types.ts` is the contract.
- Never expensive-on-every-X: a tab switch mounts ONE view and must NOT re-shoot a thumbnail; persistence writes debounce in main.
- DRY the real mechanisms: pins = `pinTarget`/`unpinTarget`/`reorderPin`; within-zone reorder = single-zone `SortableZone` reflow; motion = `--duration-slow`+`--ease-standard`; undo = `historyField` (`@codemirror/commands`); persistence = `navState`'s debounce+drain.
- One approved keybinding: `Ctrl`+`Tab` / `Ctrl`+`Shift`+`Tab`. No others.
- **All visual values live in the knob block below** (and, at build, one `tabBar.css` `:root` var block) — no inline magic numbers.
- Gate = `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npm run test` green (read the summary line). Main changes ride the electron restart; CM6 extension changes need a full `⌘R`.

## Surface Naming

`NavWindow` = the floating wayfinding overlay (currently `NavPane`). `NavPane` = the toolbar nav dropdown (currently `NavMenu`). `NavView` = the new-tab page. `NavGallery`/`NavList` (the gallery/list views inside NavWindow) keep their names. Phase 0 renames the existing code.

---

## Visual Knob Block (all tab-bar tunables — one place)

Starting values; sourced from the DRY components and the prototype (`tabBarPreview.css`). At build these become `tabBar.css` `:root` vars so the whole bar tunes in one spot. **The final report discloses this table.**

| Knob | Var | Start | Source |
|---|---|---|---|
| Tab height | `--tab-height` | 32px | prototype (button-large) |
| Tab min width | `--tab-min` | ≈ icon + ~6ch | J-3 |
| Tab preferred width | `--tab-pref` | ~180px | J-3 (browser-tab feel) |
| Tab max width | `--tab-max` | ~240px | J-3 |
| Pinned tab width | `--tab-pinned-w` | ~34px (icon + accent) | I-8, compact |
| Tab horizontal padding | `--tab-pad-x` | 12px | prototype |
| Tab inner gap (icon↔label) | `--tab-gap` | 6px | prototype |
| Entity icon size | `--tab-icon` | 14px | prototype |
| Close-`×` glyph | `--tab-x` | 11px @ strokeWidth 3 | `Chip.tsx` `ChipRemoveButton` |
| New-tab `+` glyph | `--tab-plus` | 13px | `GroupHeader.tsx` `.group-add` |
| Pin accent glyph | `--tab-pin` | ~10px | I-8 (accent on the icon) |
| Label type | — | `text.control.standard` | prototype |
| Segment divider | `--tab-divider` | 2px × 16px, `--separator-segment` | prototype |
| Overflow edge-fade | `--tab-edge-fade` | 20px | prototype |
| `+` trailing gutter | `--tab-plus-gutter` | ~28px (clears the last tab's `×`) | J-4 |
| Pinned-zone max before its own overflow | `--tab-pinned-zone-max` | TBD at UIX repass | J-5 |
| Open/close animation | `--duration-slow` + `--ease-standard` | tokens | J-6 |
| Active-highlight slide | `--duration-base` + `--ease-standard` | tokens | prototype |

*The UIX-repass (Phase 4) confirms/adjusts each against the real bar before the sizing is pinned.*

---

## File Structure

**New:** `Tabs/tabsModel.ts` (pure list logic; tested) · `Tabs/warmCache.ts` (session-only `historyField`+scroll cache) · `Tabs/TabBar.tsx`+`tabBar.css` · `Tabs/TabContextMenu.tsx` · `Tabs/NavView.tsx`+`navView.css` · `main/io/tabsState.ts` (synced sidecar).
**Renamed (Task 0.0):** `NavPane/`→`NavWindow/` (+ `NavPane.tsx`→`NavWindow.tsx`, CSS, consumers); the toolbar `NavMenu`→`NavPane`.
**Modified:** `shared/types.ts` (`Tab`, `TabSet`, the personalization bool) · `shared/mutate.ts` (**extend `ContextTarget` with `id`** — it lives here, not `types.ts`) · `store.ts` (tabs wiring inline — no slice file; active-tab→`select`; **reconcile every tab in `applyTree`**; **warm-tab refetch short-circuit**) · `Detail/DetailPane.tsx` (`'none'` branch → NavView) · `MarkdownPM/index.tsx` (warm seam, `historyField` only) · `Toolbar/Toolbar.tsx` · `main/contextMenu.ts`+`cellMenu.ts`+`shared/cellMenu.ts`+`NavList.tsx`+`NavGallery.tsx` (4 menu points) · `main/index.ts` (IPC + extend both `before-quit` AND `adoptNexus` drains) · `preload/index.ts` · `main/paths.ts` (`NEXUS_CONFIG_FILES += tabs.json`, synced) · `readNexus.ts` (`revealTabBarOnHover`) · `useNavThumbnails.ts` (capture gate).
**Deleted (Phase 6):** `Toolbar/TabBarPreview.tsx`+`tabBarPreview.css` (its scroll-edge-fade CSS migrates to `tabBar.css`).

---

## Phase 0 — Surface Rename + Tab Model (no tab UI, tests-first)

### Task 0.0 — Rename the nav surfaces
Mechanical: `NavPane/`→`NavWindow/` (+ component/CSS/consumer refs), toolbar `NavMenu`→`NavPane`. Verified by typecheck + a full grep for the old names.
- [ ] Rename, update imports/CSS classes, typecheck green, commit.

### Task 0.1 — `Tab` contract + pure model
**Files:** modify `shared/types.ts`; create `Tabs/tabsModel.ts` + `.test.ts`.
- **Types:** `Tab = { id; target: NavTarget | NewTabSentinel; navStack; navIndex }` — **no `isPinned` field**; `NewTabSentinel = { kind:'newtab' }` is a tab-target sentinel, not a `SelectionState` kind. `TabSet = { tabs; activeTabId }`. Derived: `isPinned(tab, pins) = pins.some(p => navKey(p) === navKey(tab.target))`.
- **Pure functions over `(TabSet, pins)`:** `openTab`, `closeTab`, `activateTab`, `reorderWithinZone(fromId, toIndex)`, `cycle(dir)` + an MRU id list.
  - `openTab` dedup-first (I-1) → else `newTab = explicit || isPinned(activeTab)` → append-right (D-12) or replace active target.
  - `closeTab(active)` → MRU top, else spatial neighbor when MRU empty (D-9); last tab → a lone newtab tab (I-5).
  - Unpin placement = D-11 promote-to-front (affordance/menu only; no drag-to-pin).
- [ ] Tests (every rule + dedup-of-pinned-while-on-scratch focuses the pin) → fail → implement → green → commit.

### Task 0.2 — Wire inline in `store.ts` + newtab routing
**Files:** `store.ts` (inline, no slice file), test.
- Store `tabs`, `activeTabId`, actions calling `tabsModel`. `activateTab`/target-change → `select(target, {record})`; **`record:false` on plain activate** (C-5).
- **Newtab routing:** `activateTab` on a newtab-sentinel target sets `selection:{kind:'none'}` directly and does NOT call `select()` (no newtab case in `select`).
- **Per-tab Back/Forward (D-7):** migrate `navStack`/`navIndex` into the active tab; `goBack`/`goForward` walk it; a pinned-tab Back spawns one inheriting tab (I-6).
- [ ] Tests (activate sets selection w/ record:false; newtab→'none'; per-tab Back/Forward; pinned-Back spawns) → fail → implement → green → commit.

**Gate 0:** typecheck + test green; old surface names fully gone. **Per-phase review:** build-breaker + simplifier on the model + rename.

---

## Phase 1 — Synced Tab-Set Persistence

### Task 1.1 — `tabs.json` synced sidecar (main)
**Files:** create `main/io/tabsState.ts` — **reuse `navState`'s debounced-writer shape** (root carried in the pending payload), not a fresh copy; `main/paths.ts` (`NEXUS_CONFIG_FILES += tabs.json`, synced — NOT device-local); `main/index.ts` handlers; `preload` bridge.
- **Persisted shape:** `{ tabs: {id, target, navTargets, navIndex}[], activeTabId }` — unpinned tabs + active only; no `isPinned` (C-6). Pinned tabs render off the `pins` slice + `order`.
- **Drain at BOTH sites:** add `hasPendingTabsWrites`/`flushTabsWrites`; extend the `before-quit` guard (`Promise.all` with `flushNavWrites`) AND `await flushTabsWrites()` at the top of `adoptNexus` (before the root swaps).
- [ ] Test (round-trip; foreign keys; drain), IPC + bridge, commit.

### Task 1.2 — Load / derive-pins / persist / switch + reconcile-every-tab
**Files:** `store.ts`, test.
- On nexus open: load `tabs.json`, **drop any tab whose `navKey` ∈ the pins set** (C-6), order pinned-from-`pins`, unpinned-from-stored; seed one newtab tab if empty (E-2). Persist on change (fire-and-forget; main debounces). Nexus switch = wholesale reset (I-10) backed by the sidecar.
- **Reconcile every tab in `applyTree` (I-2a):** map `reconcileSelection` over **every tab's `target` + `navStack`** on each `applyTree` (today only the singular `selection` reconciles, `store.ts:346`), applying the I-2 close-vs-render-hide split (unpinned-deleted closes; pinned-deleted render-hides, keeps the pin file).
- [ ] Tests: load derives pinned from pins; empty→newtab; switch round-trips; **a rename/move/delete of an inactive tab's entity is reflected without activating it** (the reconcile step). Implement. Manual quit/relaunch → the full set reopens cold. Commit.

**Gate 1:** the set survives quit/relaunch + nexus round-trips; pinned derived (never dual-stored); **every tab reconciles on tree change** (activating a renamed inactive tab does NOT error). **Per-phase review:** build-breaker + simplifier.

---

## Phase 2 — Warm State (the load-bearing seam)

Two steps to de-risk the highest-risk phase.

### Task 2.1 — Flat current-tab warm cache
**Files:** create `Tabs/warmCache.ts`, test.
- `WarmEntry = { editorState?; scrollTop? }` — no `mtime` (invalidation rides the change bus). Flat `Map<tabId, WarmEntry>` for the active-content warmth first.
- [ ] Test capture/read round-trip → fail → implement → green → commit.

### Task 2.2 — CM6 rehydration seam
**Files:** `MarkdownPM/index.tsx`, `Detail/PageView.tsx`, `Detail/DetailScaffold.tsx`, manual.
- **Seed the fresh `EditorState` serializing `historyField` ONLY** (`@codemirror/commands`, exported/round-trips) + restore scrollTop post-mount. **Never touch `foldField`** (unexported, would throw) — folds ride `folds.json`/`applySavedFolds`, free.
- **Freeze `(tabId, navKey)` at mount** (in the `[]`-effect closure); the unmount cleanup captures under those frozen values, never live `activeTabId`.
- **Warm-instant:** `activateTab` on a warm unchanged tab reuses cached `pageDetail` + skips `openPage` and the `loading` placeholder — no flash. A change-invalidated tab (I-4) refetches. `select()` gains this warm-awareness deliberately.
- **Invalidation via the change bus (I-4):** `nav:changed`/tree-refresh for an entity drops its warm cache; no mtime poll.
- Container/context tabs: warm = `.detail-scroll` scrollTop only (I-14).
- [ ] Confirm `historyField` export; implement freeze + seed + scroll + short-circuit + bus-invalidation; manual on a throwaway page (scroll+undo restore on switch-back; no flash; external edit → fresh); commit (`⌘R` to test).

### Task 2.3 — Warm back-stack (follow-on)
Once 2.2 is trusted: extend to `Map<tabId, Map<navKey, WarmEntry>>` with **~20-cap per-tab eviction** (I-7). Back/Forward restores each entry warm (scroll+undo; folds re-fold from `folds.json`); beyond the cap → cold.

**Gate 2:** warm round-trip on pages (scroll+undo) + containers (scroll); no flash on a warm switch; disk-change invalidates; the ~20 cap holds. **Per-phase review is the heavy one here** (against the `key=`-remount grain, and warm-instant is a `select()` change) — build-breaker + simplifier, findings verified before Phase 3.

---

## Phase 3 — "Open in New Tab" Menus (4 points)

Stateful: already-open → "Open" (focus); else "Open in New Tab" (I-1) — **label computed renderer-side** (main can't know the tab set).

### Task 3.1 — Native (Sidebar + TableView)
**Files:** `contextMenu.ts` (`webContents.send('open-in-new-tab', target)`), `preload` (`onOpenInNewTab`, mirror `onBeginRename`), `store.ts`/`App.tsx` listener → `openTab(target,{newTab:true})`, `shared/cellMenu.ts`+`cellMenu.ts`+`TableView.tsx` (title action).
- **Extend `ContextTarget` with `id`** (`shared/mutate.ts:95`) so the push-back forms a real `NavTarget` (dedup keys off `navKey = kind:id`). Pass tab-membership into the invoke for the label, or always send "Open in New Tab" and let `openTab` dedup focus-if-present.
- [ ] Implement both native paths; commit (electron restart).

### Task 3.2 — In-renderer (NavWindow list + gallery)
`NavList.tsx` (`NavRowMenu` += item), `NavGallery.tsx` (add a `PickerMenu`, reuse `NavRowMenu` if liftable) → `openTab`.
- [ ] Implement; commit.

**Gate 3:** all four open/focus correctly, honoring pin-spawn vs replace. **Per-phase review:** build-breaker + simplifier.

---

## Phase 4 — The Tab Bar UI (+ the reveal setting)

> **UIX-REPASS GATE (§J):** before building, repass §J against the real toolbar — the knob-block sizing, the `+`-vs-`×` trailing-corner gutter, the pinned-zone overflow rule, the plain-`×`-fade treatment. Confirm treatment (Figma/screenshot), don't build from prose.

### Task 4.1 — Shell + zones + sizing + reveal setting
**Files:** create `Tabs/TabBar.tsx`+`tabBar.css` (the knob-block `:root` vars; migrate the prototype's edge-fade); `Toolbar/Toolbar.tsx`; `shared/types.ts`+`readNexus.ts` (the `revealTabBarOnHover` bool).
- Pinned zone fixed-left = compact icon + pin accent, name-on-hover (I-8); **bound it** (`--tab-pinned-zone-max` + its own overflow/collapse) so uncapped pins don't clip/collide with the right cluster. Unpinned zone = min/pref/max width, ellipsis, overflow-scroll; active tab scrolls into view. Active highlight = the prototype's clipped sliding label. Blank when a single tab (D-6). Reveal-on-hover consumes the personalization bool.

### Task 4.2 — Close (×), new-tab (+), open/close animation
- **× = `ChipRemoveButton` + PLAIN hover-fade** (not the chip melt); only on unpinned tabs (D-10). **Reserve the `+` its `--tab-plus-gutter` outside the last tab's `×` zone** so they don't fight → `closeTab`.
- **+ = the `.group-add` GLYPH + fade token only**; author the absolute trailing-edge placement + strip-scoped reveal + full-width overlay fresh → `openTab(newtab)`.
- Open/close = animate tab width open/collapsed on `--duration-slow`+`--ease-standard` + `useExitPresence`; neighbors reflow.

### Task 4.3 — Within-zone drag + tab menu + cycling
- **Within-zone reorder only** = single-zone `SortableZone` reflow, per zone (pinned↔pinned via `reorderPin`, unpinned↔unpinned). No cross-divider drag (Prospect).
- `Tabs/TabContextMenu.tsx` (in-renderer `PickerMenu`): Pin/Unpin · Close · Close to the Right (I-12).
- `Ctrl`+`Tab`/`Shift` → `cycle`, wraps, all tabs (I-11).

**Gate 4:** interactive tab bar; §J repass verified; pinned overflow + `+`/`×` gutter resolved. **Per-phase review:** build-breaker + simplifier + a screenshot pass.

---

## Phase 5 — NavView (the new-tab page + empty state)

**Files:** create `Tabs/NavView.tsx`+`navView.css`; `Detail/DetailPane.tsx` (**replace the `'none'` branch** with `<NavView/>` — this IS the empty state, E-2).
- `useNavData()` + a search input (NavWindow's `splitSearch(search(query))`) + `<NavGallery>` with bumped `--card-min`; `--main-bg` background. Picking → `openTab(target)` replaces the scratch newtab tab. Separate from NavWindow — shares `NavGallery`, not a merged shell (E-3).
- [ ] Test the newtab sentinel dedups to one NavView (I-1); implement; screenshot-verify; commit.

**Gate 5:** `+` opens NavView; searching + picking replaces; a fresh/empty nexus opens onto it; no blank placeholder remains. **Per-phase review:** build-breaker + simplifier.

---

## Phase 6 — Lifecycle, Cleanup, Docs, Closeout

### Task 6.1 — Capture gate + autosave verification
- **Thumbnail capture gate:** `useNavThumbnails` must NOT re-shoot on a plain tab-activation (record:false, unchanged doc) — dedup against a per-session "captured navKey at this doc version" guard. Load-bearing (warm switching is the highest-frequency interaction).
- **Autosave:** verify the shipped `scheduleSave` + `beforeunload` flush already covers switch/close (PageView never remounts); add an explicit flush only if a gap is proven (I-3).
- Delete/rename/move behavior is already delivered by the Task 1.2 `applyTree` reconcile — confirm it (I-2).
- [ ] Tests; implement; commit.

### Task 6.2 — Cleanup + docs
- Delete `TabBarPreview.tsx`+`tabBarPreview.css`.
- Confirm `Navigation.md` (already restructured), `History.md`, `Handoff.md`, `Framework.md` are true to the shipped feature.
- [ ] Sweep + commit docs with the code.

### Task 6.3 — Post-functional UIX review (mandatory)
After functional-green, review the real working tab bar against §J + the knob block — no matter how clean the build. Fold, re-screenshot, close out.

**Gate 6:** edge cases hold; throwaway gone; docs true; UIX review passed.

---

## Self-Review (coverage)

- **Warm** (B) → Phase 2 (staged; `historyField`-only; freeze-at-mount; short-circuit; folds via `folds.json`). **Persistence** (D-8) → Phase 1 (synced, `isPinned` derived, both drains, reconcile-every-tab). **Model/lifecycle** (D, I) → Phases 0/4/6. **Menus** (D-3) → Phase 3 (`ContextTarget.id`, renderer label). **NavView** (E) → Phase 5 (`'none'` branch). **Setting** (F) → Phase 4. **Drag** → within-zone only (I-13). **Motion** → `--duration-slow` (J-6). **Naming** → Task 0.0.
- **Highest risk:** Phase 2 (against the `key=`-remount grain; warm-instant is a `select()` change) — its per-phase review is the heavy one. Phase 3 crosses IPC twice — mirror `begin-rename`.
- **UIX-repass owns (Phase 4):** the exact knob values, the pinned-overflow behavior, the `+`/`×` gutter geometry.
