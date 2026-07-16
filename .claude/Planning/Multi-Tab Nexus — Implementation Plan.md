# Multi-Tab Nexus Implementation Plan — V2

> **V2 (review-hardened).** Rewritten after a 3-agent plan-attack (internals + visuals/interaction + simplification), every finding verified against code. Changes from V1 are tagged `[rev]`. **For agentic workers:** implement task-by-task, gate between phases, re-read the plan against what landed after each green commit. Steps use `- [ ]`. **Source of truth:** `Multi-Tab Nexus — Decision Log.md` (decision IDs cited inline). Where this plan names an exact value it's a starting knob — ground the literal at build time.

**Goal:** Replace single-pane-replace with warm, state-preserving tabs — a persisted, cross-device-synced working set of open entities, pinned + unpinned, each keeping its own scroll/undo within a session and its own Back/Forward.

**Architecture:** A `tabs` slice sits *above* the singular `selection`; the active tab's target drives the existing `select()`/detail path. One view mounted; inactive tabs hold a serialized `historyField`+scroll cache, rehydrated by seeding a fresh CM6 mount. **The "consumers untouched" claim holds for RENDER consumers only** — tree reconciliation and warm-instant switching each require deliberate `applyTree`/`select` awareness `[rev, I-2a/B-3]`. The tab *set* (unpinned tabs + active; **`isPinned` is derived, not stored** `[rev, C-6]`) syncs; pinned identities ride `.nexus/pins/`.

**Tech Stack:** Electron 42 · React 19 · TypeScript · Zustand · CodeMirror 6 · the in-house drag engine · narrow contextBridge IPC.

## Global Constraints

- Main owns fs; renderer never touches Node; IPC returns `{ ok } | { ok:false, error }`; `shared/types.ts` is the contract.
- Never expensive-on-every-X: a tab switch mounts ONE view and MUST NOT re-shoot a thumbnail `[rev, F7]`; persistence writes debounce in main.
- DRY the real mechanisms: pins = `pinTarget`/`unpinTarget`/`reorderPin`; within-zone reorder = single-zone `SortableZone` reflow `[rev, I-13]`; motion = `--duration-slow`+`--ease-standard` (the sidebar/ribbon easing) `[rev, J-6]`; `historyField` = `@codemirror/commands`; persistence = `navState`'s debounce+drain.
- One approved keybinding: `Ctrl`+`Tab`/`Ctrl`+`Shift`+`Tab` (I-11). No others.
- Gate = `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npm run test` green (read the summary line). Main changes ride the electron restart; CM6 extension changes need a full `⌘R`.

---

## File Structure

**New:** `Tabs/tabsModel.ts` (pure list logic; unit-tested) · `Tabs/warmCache.ts` (session-only `historyField`+scroll cache) · `Tabs/TabBar.tsx`+`tabBar.css` · `Tabs/TabContextMenu.tsx` · `Tabs/NewTabPage.tsx`+`newTabPage.css` · `main/io/tabsState.ts` (synced sidecar).
**Modified:** `shared/types.ts` (`Tab`, `TabSet`, the personalization bool; **extend `ContextTarget` with `id`** `[rev, F11]`) · `store.ts` (tabs wiring **inline — no `tabsSlice.ts`** `[rev, F4]`; active-tab→`select`; **reconcile every tab in `applyTree`** `[rev, I-2a]`; **warm-tab refetch short-circuit** `[rev, B-3]`) · `Detail/DetailPane.tsx` (**`'none'` branch → new-tab page** `[rev, E-2]`) · `MarkdownPM/index.tsx` (warm seam, `historyField` only) · `Toolbar/Toolbar.tsx` · `main/contextMenu.ts`+`cellMenu.ts`+`shared/cellMenu.ts`+`NavList.tsx`+`NavGallery.tsx` (4 menu points) · `main/index.ts` (IPC + **extend both `before-quit` AND `adoptNexus` drains** `[rev, F6]`) · `preload/index.ts` · `main/paths.ts` (`NEXUS_CONFIG_FILES += tabs.json`, **synced**) · `useNavThumbnails.ts` (**capture gate** `[rev, F7]`).
**Deleted (Phase 6):** `Toolbar/TabBarPreview.tsx`+`tabBarPreview.css` (its scroll-edge-fade CSS migrates to `tabBar.css`).

---

## Phase 0 — Tab Model + Store Wiring (no UI, tests-first)

### Task 0.1 — `Tab` contract + pure model
**Files:** modify `shared/types.ts`; create `Tabs/tabsModel.ts` + `.test.ts`.

**Types `[rev]`:** `Tab = { id; target: NavTarget | NewTabSentinel; navStack; navIndex }` — **no `isPinned` field** (derived, C-6). `NewTabSentinel = { kind: 'newtab' }` is a tab-target sentinel, NOT a `SelectionState` kind. `TabSet = { tabs: Tab[]; activeTabId }`. Derived: `isPinned(tab, pins) = pins.some(p => navKey(p) === navKey(tab.target))`.

`tabsModel.ts` — pure functions over `(TabSet, pins)`: `openTab`, `closeTab`, `activateTab`, `reorderWithinZone(fromId, toIndex)` `[rev — within a zone only, I-13]`, `cycle(dir)`, an MRU id list for close-focus.
- `openTab` dedup-first (I-1) → else `newTab = explicit || isPinned(activeTab)` → new unpinned tab appended right (D-12) or replace active target.
- `closeTab(active)` → MRU top, else **spatial neighbor when MRU empty** `[rev, F10]`; last tab → a lone newtab tab (I-5).
- Unpin placement = D-11 promote-to-front (affordance/menu only; no drag-to-pin, I-13).

**Steps:** write tests (every rule + dedup-of-pinned-while-on-scratch focuses the pin) → fail → implement → green → commit.

### Task 0.2 — Wire inline in `store.ts` + newtab routing
**Files:** `store.ts` (inline, no slice file), test.
- Store: `tabs`, `activeTabId`, actions calling `tabsModel`. `activateTab`/target-change → `select(target, {record})` — **`record:false` on plain activate** (C-5).
- **Newtab routing `[rev, F4]`:** `activateTab` on a newtab-sentinel target sets `selection:{kind:'none'}` directly and **does NOT call `select()`** (select has no newtab case).
- **Per-tab Back/Forward (D-7):** migrate `navStack`/`navIndex` into the active tab; `goBack`/`goForward` walk the active tab's stack; a pinned-tab Back spawns one inheriting tab (I-6).

**Steps:** tests (activate sets selection w/ record:false; newtab→'none'; Back/Forward per active tab; pinned-Back spawns) → fail → implement → green → commit.

**Gate 0:** typecheck + test green. Headless — the model drives selection with no UI.

---

## Phase 1 — Synced Tab-Set Persistence

### Task 1.1 — `tabs.json` synced sidecar (main) `[rev]`
**Files:** create `main/io/tabsState.ts` — **reuse `navState`'s debounced-writer shape** (`scheduleRecentsWrite`/`flushRecents` pattern, root carried in the pending payload) rather than a fresh copy `[rev, F5]`; `main/paths.ts` (`NEXUS_CONFIG_FILES += tabs.json`, **synced — NOT device-local**); `main/index.ts` handlers; `preload` bridge.
- **Persisted shape `[rev, C-6]`:** `{ tabs: {id, target, navTargets, navIndex}[], activeTabId }` — **unpinned tabs + active only; no `isPinned`.** Pinned tabs render off the `pins` slice + its `order`.
- **Drain at BOTH sites `[rev, F6]`:** add `hasPendingTabsWrites`/`flushTabsWrites`; extend the `before-quit` guard (`Promise.all` with `flushNavWrites`) AND `await flushTabsWrites()` at the top of `adoptNexus` (before the root swaps) — else the last change before quit/switch is lost or lands against the wrong nexus.

**Steps:** test (round-trip; foreign keys; drain), IPC + bridge, commit.

### Task 1.2 — Load / merge-pins / persist / switch (renderer)
**Files:** `store.ts`, test.
- On nexus open: load `tabs.json`, **drop any tab whose `navKey` ∈ the pins set** (C-6), order pinned-from-`pins`, unpinned-from-stored. Seed one newtab tab if empty (E-2).
- Persist on change (fire-and-forget; main debounces). Nexus switch = wholesale in-memory reset (E-11/I-10) backed by the synced sidecar.

**Steps:** test (load derives pinned from pins; empty→newtab; switch round-trips), implement, manual quit/relaunch → full set reopens cold, commit.

**Gate 1:** the set survives quit/relaunch + nexus round-trips; pinned derived, never dual-stored.

---

## Phase 2 — Warm State (the load-bearing seam) `[rev — heavily corrected]`

Ship in two steps to de-risk the highest-risk phase `[rev, simplification-F2]`.

### Task 2.1 — Flat current-tab warm cache
**Files:** create `Tabs/warmCache.ts`, test.
- **`WarmEntry = { editorState?; scrollTop? }`** — **NO `mtime`** `[rev, F3]` (invalidation rides the change bus, not a stamp). Flat `Map<tabId, WarmEntry>` for the active-content warmth first `[rev, F2-stage]`.

### Task 2.2 — CM6 rehydration seam
**Files:** `MarkdownPM/index.tsx`, `Detail/PageView.tsx`, `Detail/DetailScaffold.tsx`, manual.
- **Seed from cached `EditorState` serializing `historyField` ONLY** (`@codemirror/commands`, verified exported/round-trips) + restore scrollTop post-mount. **Do NOT touch `foldField`** (unexported, would throw) — folds already persist via `folds.json`/`applySavedFolds`, free `[rev, F1]`.
- **Freeze `(tabId, navKey)` at mount** (in the `[]`-effect closure); the unmount cleanup captures under those frozen values, never live `activeTabId` `[rev, F2]`.
- **Warm-instant `[rev, F8/B-3]`:** `activateTab` on a warm unchanged tab reuses cached `pageDetail` + skips `openPage` and the `loading` placeholder — kills the flash. A change-bus-invalidated tab (I-4) refetches. `select()` gains this warm-awareness deliberately.
- **Invalidation via the change bus `[rev, I-4]`:** `nav:changed`/tree-refresh for an entity drops its warm cache; no mtime poll.
- Container/context tabs: warm = `.detail-scroll` scrollTop only (I-14).

**Steps:** confirm `historyField` export; implement freeze + seed + scroll + short-circuit + bus-invalidation; manual on a throwaway page (scroll+undo restore on switch-back; no flash; external edit → fresh); commit (`⌘R` to test).

### Task 2.3 — Warm back-stack (follow-on) `[rev]`
Once 2.2 is trusted: extend to `Map<tabId, Map<navKey, WarmEntry>>` with **~20-cap per-tab eviction** (I-7). Back/Forward restores each entry warm; beyond the cap → cold.

**Gate 2:** warm round-trip on pages (scroll+undo) + containers (scroll); no flash on warm switch; disk-change invalidates; the ~20 back-stack cap holds. **Carries its own build-breaking pass** before Phase 3.

---

## Phase 3 — The Tab Bar UI (+ the reveal setting)

> **UIX-REPASS GATE (Nathan, §J):** before building, repass §J against the real toolbar — sizing (min/pref/max), the `+`-vs-`×` trailing-corner conflict `[rev, F3]`, the pinned-zone overflow rule `[rev, F4]`, the plain-`×`-fade treatment `[rev, F2]`. Confirm treatment (Figma/screenshot), don't build from prose.

### Task 3.1 — Shell + zones + sizing + reveal setting
**Files:** create `Tabs/TabBar.tsx`+`tabBar.css` (migrate the prototype's `tabbar-preview-scroll` edge-fade); `Toolbar/Toolbar.tsx`; `shared/types.ts`+`readNexus.ts` (the `revealTabBarOnHover` bool, folded in here `[rev, F6-merge]`).
- Pinned zone fixed-left = compact icon + pin accent, name-on-hover (I-8); **bound it** (max-width + its own overflow, or "+N" collapse) so uncapped pins don't clip/collide with `ViewDropdown` `[rev, F4]`. Unpinned zone = min/pref/max width, ellipsis, overflow-scroll (J-3/J-5); active tab scrolls into view.
- Active highlight: the prototype's clipped sliding label. Blank when a single tab (D-6). Reveal-on-hover = `useSession(personalization.revealTabBarOnHover ?? false)`.

### Task 3.2 — Close (×), new-tab (+), open/close animation `[rev]`
- **× = `ChipRemoveButton` + PLAIN hover-fade** (NOT the chip melt — no `--chip-fill` on glass, F2); only on unpinned tabs (D-10). **Reserve the `+` its own trailing gutter outside the last tab's `×` third** so they don't fight `[rev, F3]`.
- **+ = the `.group-add` GLYPH + fade token only**; author the absolute trailing-edge placement + strip-scoped reveal + full-width overlay fresh `[rev, F5]` → `openTab(newtab)`.
- Open/close = **animate tab width open/collapsed on `--duration-slow`+`--ease-standard`** + `useExitPresence` for exit; neighbors reflow. Not a new keyframe `[rev, J-6]`.

### Task 3.3 — Within-zone drag + tab menu + cycling `[rev]`
- **Within-zone reorder only** = single-zone `SortableZone` reflow, run per zone (pinned↔pinned via `reorderPin`, unpinned↔unpinned) `[rev, I-13]`. **No cross-divider drag** (Prospect).
- `Tabs/TabContextMenu.tsx` (in-renderer `PickerMenu`): Pin/Unpin · Close · Close to the Right (I-12).
- `Ctrl`+`Tab`/`Shift` → `cycle`, wraps, all tabs (I-11).

**Gate 3:** interactive tab bar; §J repass items verified; pinned overflow + `+`/`×` collision resolved.

---

## Phase 4 — "Open in New Tab" Menus (4 points) `[rev]`

Stateful: already-open → "Open" (focus); else "Open in New Tab" (I-1) — **label computed renderer-side** (main can't know the tab set) `[rev, F11]`.

### Task 4.1 — Native (Sidebar + TableView)
**Files:** `contextMenu.ts` (`webContents.send('open-in-new-tab', target)`), `preload` (`onOpenInNewTab`, mirror `onBeginRename`), `store.ts`/`App.tsx` listener → `openTab(target,{newTab:true})`, `shared/cellMenu.ts`+`cellMenu.ts`+`TableView.tsx` (title action).
- **Extend `ContextTarget` with `id`** so the push-back forms a real `NavTarget` (dedup keys off `navKey = kind:id`) `[rev, F11]`. Pass tab-membership into the invoke for the label, or always send "Open in New Tab" and let `openTab` dedup focus-if-present.

### Task 4.2 — In-renderer (NavList + NavGallery)
`NavList.tsx` (`NavRowMenu` += item), `NavGallery.tsx` (add a `PickerMenu`, reuse `NavRowMenu` if liftable) → `openTab`.

**Gate 4:** all four open/focus correctly, honoring pin-spawn vs replace.

---

## Phase 5 — New-Tab Page `[rev]`

**Files:** create `Tabs/NewTabPage.tsx`+`newTabPage.css`; `Detail/DetailPane.tsx` (**replace the `'none'` branch** with `<NewTabPage/>` — this IS the empty state, E-2).
- `useNavData()` + a search input (NavPane's `splitSearch(search(query))`) + `<NavGallery>` with bumped `--card-min`; `--main-bg` background. Picking → `openTab(target)` replaces the scratch newtab tab.
- **Separate from NavPane** — shares `NavGallery`, not a merged shell (E-3).

**Steps:** test the newtab sentinel dedups to one page (I-1); implement; screenshot-verify; commit.

**Gate 5:** `+` opens it; searching + picking replaces; a fresh/empty nexus opens onto it; no blank placeholder remains.

---

## Phase 6 — Lifecycle, Cleanup, Docs

### Task 6.1 — Entity mutation + capture gate
- **Delete (I-2):** unpinned tab actually closes (active→MRU); pinned tab render-hides, keeps the pin file. Rename/move re-resolve live — **already covered by the `applyTree` reconcile-every-tab from Task 1.2/I-2a** `[rev]`.
- **Autosave on switch/close:** verify the shipped `scheduleSave` + `beforeunload` flush already covers it (PageView never remounts; only inner CM6 does) — I-3 is **largely redundant with shipped code** `[rev, killed candidate]`; add an explicit flush only if a gap is proven.
- **Thumbnail capture gate `[rev, F7]`:** `useNavThumbnails` must NOT re-shoot on a plain tab-activation (record:false, unchanged doc) — dedup against a per-session "captured navKey at this doc version" guard. Load-bearing: warm switching is now the highest-frequency interaction.

### Task 6.2 — Cleanup + docs
- Delete `TabBarPreview.tsx`+`tabBarPreview.css`.
- Reconcile `Navigation.md` (temp-pins superseded, G-1), `History.md` (the B-1 paradigm decision), `Handoff.md`. (`Framework.md` roadmap slot already committed.)

### Task 6.3 — Post-functional UIX review (mandatory)
After functional-green, review the real working tab bar against §J — no matter how clean the build (Review-Discipline). Fold, re-screenshot, close out.

**Gate 6:** edge cases hold; throwaway gone; docs true; UIX review passed.

---

## Self-Review (V2 coverage)

- **Warm** (B) → Phase 2 (staged; `historyField`-only; freeze-at-mount; short-circuit; folds via `folds.json`). **Persistence** (D-8) → Phase 1 (synced, `isPinned` derived, both drains). **Model/lifecycle** (D, I) → Phases 0/3/6. **Menus** (D-3) → Phase 4 (`ContextTarget.id`, renderer label). **New-tab page** (E) → Phase 5 (`'none'` branch). **Setting** (F) → merged into Phase 3. **Drag** → within-zone only (I-13); drag-to-pin Prospect. **Motion** → `--duration-slow` (J-6).
- **Resolved from review:** F1 fold-serialization, F2 capture-race, F3 tab-reconcile, F4 newtab-routing, F5 navState-reuse, F6 both-drains, F7 capture-gate, F8 warm-instant, F11 ContextTarget-id; visuals F1 drag re-scope, F2 chip fade, F3 `+`/`×`, F4 pinned-overflow, F5 group-+, F6 motion.
- **Highest risk:** Phase 2 (against the `key=`-remount grain, warm-instant is a `select()` change) — its own build-breaking pass. Phase 4 crosses IPC twice — mirror `begin-rename`.
- **Residual for the UIX repass (Phase 3):** exact sizing knobs, the pinned-overflow behavior (bound vs "+N"), the `+`/`×` gutter geometry.
