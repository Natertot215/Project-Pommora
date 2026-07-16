# Multi-Tab Nexus Implementation Plan

> **For agentic workers:** implement task-by-task, gate between phases, re-read the plan against what landed after each green commit (Planning Discipline). Steps use `- [ ]`. **Source of truth:** `Multi-Tab Nexus — Decision Log.md` (decision IDs cited inline, e.g. `[D-8]`). Where this plan names an exact value it's a **starting knob** — ground the literal against real code at build time; docs name, code holds exacts.

**Goal:** Replace single-pane-replace with warm, state-preserving tabs in the toolbar — a persisted working set of open entities, pinned + unpinned, each keeping its own scroll/undo/fold within a session.

**Architecture:** A `tabs` store slice sits *above* the singular `selection` — the active tab's target drives the existing `select()`/detail-pane path unchanged, so ~15 selection consumers don't move `[B-1]`. Only the active tab is mounted; inactive tabs hold serialized warm state, rehydrated on switch by seeding a fresh CM6 mount from a cached `EditorState` `[B-3]`. The tab *set* (structure, no warm state) persists to a **synced** sidecar that travels cross-device `[D-8/D-8a]`; pinned identities ride the existing synced `.nexus/pins/` store `[C-1]`. The empty/no-target state IS the new-tab page — no blank placeholder `[E-2]`. Back/Forward is **per-tab** `[D-7]`.

**Tech Stack:** Electron 42 · React 19 · TypeScript · Zustand (`useSession`) · CodeMirror 6 (MarkdownPM) · the in-house drag engine (`design-system/interactions/drag`) · narrow contextBridge IPC.

## Global Constraints

- **Main owns fs; renderer never touches Node.** New persistence goes through a narrow typed IPC bridge; handlers return `{ ok: true, … } | { ok: false, error }`.
- **`src/shared/types.ts` is the cross-process contract** — the `Tab`/tab-set types live there.
- **Never expensive-on-every-X.** Tab switch mounts ONE view; persistence writes are debounced in main; no O(N) re-walk on switch `[B-1]`.
- **Colors from `design-system/tokens` as hex.** No hand-rolled tokens.
- **DRY the existing mechanisms, don't re-roll:** chip × = `ChipRemoveButton` `[J-1]`; new-tab + = `.group-add` `[J-2]`; drag = `SortableZone`/`useDragItem` reflow `[D-4b]`; motion = `Interaction.md` primitives; pins = `pinTarget`/`unpinTarget`/`reorderPin`.
- **No keybindings beyond `Ctrl`+`Tab`/`Ctrl`+`Shift`+`Tab`** (the one signed-off binding, `[I-11]`).
- **Gate = `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npm run test`** green; read the summary line, never a piped exit code. Main-process changes ride the electron restart; renderer HMRs (CM6 extension changes need a full `⌘R`).

---

## File Structure

**New:**
- `src/renderer/src/Tabs/tabsModel.ts` — pure tab-list logic (open/close/activate/reorder/pin/unpin/cycle placement + the MRU stack); unit-tested with no store/DOM.
- `src/renderer/src/Tabs/tabsSlice.ts` — the Zustand slice wiring `tabsModel` to `select()` + persistence (or fold into `store.ts` if the slice pattern there prefers it — match the existing store shape).
- `src/renderer/src/Tabs/warmCache.ts` — the per-tab serialized warm-state cache (scroll/undo/fold) + capture/restore helpers; the ~20 cap `[I-7]`.
- `src/renderer/src/Tabs/TabBar.tsx` + `tabBar.css` — the real tab bar (replaces `TabBarPreview`).
- `src/renderer/src/Tabs/TabContextMenu.tsx` — the tab's own right-click menu `[I-12]` (in-renderer `PickerMenu`).
- `src/renderer/src/Tabs/NewTabPage.tsx` + `newTabPage.css` — the full-window gallery start page `[E-1]`.
- `src/main/io/tabsState.ts` — the device-local tab-set sidecar (mirror `io/activeViews.ts`).

**Modified:**
- `src/shared/types.ts` — `Tab`, `TabSet`, `NewTabKind`, the `personalization` boolean.
- `src/renderer/src/store.ts` — mount the tabs slice; active-tab → `select()`; nexus-switch reset; personalization key.
- `src/renderer/src/Detail/DetailPane.tsx` (`DetailView`) — **replace** the `'none'` placeholder with the `'newtab'` (new-tab page) branch `[E-2]`.
- `src/renderer/src/MarkdownPM/index.tsx` — the warm rehydration seam (seed from cached `EditorState`, restore scroll).
- `src/renderer/src/Toolbar/Toolbar.tsx` — render `TabBar` (drop `TabBarPreview`).
- `src/main/contextMenu.ts` + `src/main/cellMenu.ts` (+ `src/shared/cellMenu.ts`) + `NavList.tsx` + `NavGallery.tsx` — the 4 "Open in New Tab" touch points `[D-3]`.
- `src/main/index.ts` + `src/preload/index.ts` — IPC for `tabsState` + the `open-in-new-tab` push-back.
- `src/main/paths.ts` — `NEXUS_CONFIG_FILES += tabs.json` (**synced — NOT in `DEVICE_LOCAL_NEXUS_FILES`** `[D-8a]`).
- `src/main/readNexus.ts` — coerce `revealTabBarOnHover` `[F-1]`.

**Deleted (Phase 7):** `Toolbar/TabBarPreview.tsx` + `tabBarPreview.css` `[G-2]` (its scroll-edge-fade CSS migrates into `tabBar.css` `[J-5]`).

---

## Phase 0 — Tab Model + Store Slice (no UI, tests-first)

The data spine. Everything downstream calls into this; it never imports React or fs.

### Task 0.1 — The `Tab` contract + pure model

**Files:**
- Modify: `src/shared/types.ts`
- Create: `src/renderer/src/Tabs/tabsModel.ts`
- Test: `src/renderer/src/Tabs/tabsModel.test.ts`

**Interfaces (Produces):**
```ts
// shared/types.ts
export interface Tab {
  id: string                    // stable tab id (ids.ts)
  target: NavTarget | { kind: 'newtab' }   // the entity, or the start page [E-2]
  isPinned: boolean
  navStack: (NavTarget | { kind: 'newtab' })[]  // per-tab history [D-7]
  navIndex: number
}
export interface TabSet { tabs: Tab[]; activeTabId: string | null }
```
`tabsModel.ts` exports **pure** functions over `TabSet` (no store): `openTab(set, target, { newTab, isPinnedActive }) → TabSet`, `closeTab`, `activateTab`, `reorderTab(set, fromId, toIndex, toZone)`, `pin`/`unpin(set, id, { dropIndex? })`, `cycle(set, dir)`. An MRU list (ids, most-recent-first) travels alongside for close-focus `[D-9]`.

**Placement rules to encode (test each):**
- `openTab` **dedup-first** `[I-1/D-3b]`: if `navKey(target)` matches an existing tab → return set with that tab active, no new tab.
- else `newTab = explicitNewTab || isPinnedActive` `[D-3b]`: true → insert a new unpinned tab (append RIGHT of the unpinned zone `[D-12]`); false → replace the active tab's `target` (push old onto its `navStack`).
- `closeTab(active)` → new active = MRU top `[D-9]`; closing the last tab → a lone `newtab` tab `[I-5]`.
- `unpin` (click/menu) → promote to unpinned **position 1**, or **position 2** if the active tab is currently position 1 `[D-11]`. `unpin` (drag, `dropIndex` given) → land at `dropIndex` `[I-13]`.
- `cycle` wraps, spans pinned+unpinned `[I-11]`.

**Steps:**
- [ ] Write `tabsModel.test.ts` covering every rule above + edge cases (empty set, single tab, dedup of a pinned target while on a scratch tab → focuses the pin).
- [ ] Run it — fails (module absent).
- [ ] Implement `tabsModel.ts` (pure, uses `navKey` from `Navigation/navRecents`).
- [ ] Run — green. Commit.

### Task 0.2 — Slice + active-tab → `select()`

**Files:** `src/renderer/src/Tabs/tabsSlice.ts` (or `store.ts`), `store.ts`, test.

**Interfaces (Produces):** store fields `tabs: Tab[]`, `activeTabId`, actions `openTab(target, opts?)`, `closeTab(id)`, `activateTab(id)`, `reorderTab(...)`, `pinTab(id)`/`unpinTab(id)`, `cycleTab(dir)`. `activateTab` and target-changing ops call the existing `select(activeTab.target, { record })` — **`record:false` on a plain tab-activate** so switching doesn't pollute recents `[C-5]`; `record`-normal on a genuine open/navigate. Per-tab Back/Forward: `goBack`/`goForward` operate on the **active tab's** `navStack`/`navIndex` `[D-7]`; a Back/Forward while the active tab `isPinned` spawns one new inheriting tab `[I-6]`.

**Steps:**
- [ ] Test: activating a tab sets `selection` to its target with `record:false`; opening a fresh entity records; Back/Forward walks the active tab's stack; pinned-tab Back spawns.
- [ ] Run — fails.
- [ ] Implement the slice; migrate `navStack`/`navIndex` off the global store into the active tab (keep `goBack`/`goForward` names for `Toolbar`).
- [ ] Run — green. Commit.

**Gate 0:** `typecheck` + `test` green. No UI yet — the tab set drives selection headlessly.

---

## Phase 1 — Persisted Tab-Set Store (device-local sidecar + IPC)

Closing NEVER resets tabs `[D-8]`. The *structure* persists; no warm state to disk.

### Task 1.1 — The `tabs.json` synced sidecar (main)

**Files:** `src/main/io/tabsState.ts` (create — lenient read absent→empty, serialized read-merge-write via `serializeOnFile` + `writeJson`), `src/main/paths.ts` (`NEXUS_CONFIG_FILES += tabs: 'tabs.json'`; **synced — do NOT add to `DEVICE_LOCAL_NEXUS_FILES`** `[D-8a]`), `src/main/index.ts` (`tabs:get`/`tabs:set` handlers), `src/preload/index.ts` (bridge). **Write cadence:** tabs are churny (every open/switch/close) + synced → **debounce the write in MAIN + flush on `before-quit`**, mirroring the *recents* pattern (E-1 in the nav log), NOT the un-debounced `activeViews` write.

**Persisted shape:** `{ tabs: {id, target, isPinned, navTargets, navIndex}[], activeTabId }` — **no scroll/undo/fold** `[B-2a]`. Pinned tabs store their target like any tab; the pin *state* is still authoritative in `.nexus/pins/` — on load, reconcile a persisted `isPinned` against the live pins set.

**Steps:**
- [ ] Test `tabsState.ts` (absent→empty; write-then-read round-trips; foreign keys preserved).
- [ ] Run — fails. Implement. Run — green.
- [ ] Wire IPC + preload bridge; confirm the envelope shape.
- [ ] Commit (rides the electron restart).

### Task 1.2 — Load / persist / nexus-switch (renderer)

**Files:** `store.ts` (load on nexus open beside `activeViews` at the existing load site; **fire-on-change fire-and-forget — MAIN debounces** per 1.1; **wholesale in-memory reset on nexus switch** `[E-11/I-10]`), test.

**Steps:**
- [ ] Test: load seeds `tabs`/`activeTabId`; a tab mutation schedules a debounced persist; nexus switch replaces the set from the new nexus's sidecar (returning restores it).
- [ ] Run — fails. Implement. Run — green.
- [ ] Manual: open tabs, quit, relaunch → the full set reopens in order, **cold** (scroll top, undo empty). Commit.

**Gate 1:** tab set survives quit/relaunch and nexus round-trips. Still no tab-bar UI — verify via the running app's selection + a temporary debug readout or the store.

---

## Phase 2 — Warm State Cache + Rehydration (the load-bearing seam)

Within a session: scroll + undo + fold restore on switch `[B-2]`. Only the active tab is mounted.

### Task 2.1 — The warm cache

**Files:** `src/renderer/src/Tabs/warmCache.ts` (create), test.

**Interface (Produces):** an in-memory `Map<tabId, Map<navKey, WarmEntry>>` where `WarmEntry = { editorState?: object; scrollTop?: number; mtime?: number }`. `captureWarm(tabId, key, entry)`, `readWarm(tabId, key)`, eviction to the **~20 most-recent back-forth entries per tab** `[I-7]`, drop-on-tab-close, drop-all-on-quit (it's just memory).

**Steps:**
- [ ] Test capture/read round-trip + the 20-cap eviction (oldest back-forth entry drops).
- [ ] Run — fails. Implement. Run — green. Commit.

### Task 2.2 — CM6 rehydration seam

**Files:** `src/renderer/src/MarkdownPM/index.tsx` (the mount-once `useEffect`, ~:109-246), `Detail/PageView.tsx`, test where feasible (+ manual).

**Approach `[B-3]`:** keep the `key={pageDetail.path}` remount, but **seed the fresh `EditorState` from the cached serialized state** when present (`EditorState.fromJSON(cached, config, { historyField, foldField })`) instead of `initialBody`; else seed `initialBody` as today. On switch-*away*, before unmount, `captureWarm` the outgoing view's `state.toJSON({ history: historyField, fold: foldField })` + `.cm-scroller` scrollTop. Restore scroll post-mount (a layout effect). Verify `historyField`/`foldField` are the real exported `StateField`s in this build (ground against `MarkdownPM/editor/*`); if folding isn't a serializable field, fold-warmth degrades to Prospect and the plan notes it.

**Disk-truth invalidation `[I-4]`:** **ride the existing file-change bus** (`nav:changed` / the tree-refresh watcher) — when a change fires for an entity, **drop its warm cache** so the next visit reloads fresh. NOT a separate mtime poll; one change-detection path. (Never restore a stale doc over a divergent undo stack.)

**Container/context tabs `[I-14]`:** warm = `.detail-scroll` scrollTop only (no undo/fold). Capture/restore in `DetailScaffold`.

**Steps:**
- [ ] Confirm `historyField`/`foldField` exports (ground in `MarkdownPM/editor/`).
- [ ] Implement capture-on-switch-away + seed-on-mount + scroll restore + mtime invalidation.
- [ ] Manual (a throwaway test page, per the CDP-editor rule): open A, scroll + type + fold, switch to B, switch back → scroll/undo/fold intact; edit A's file on disk externally, switch back → reloads fresh.
- [ ] Commit (CM6 extension change → full `⌘R` to test).

**Gate 2:** warm round-trip proven on pages (scroll+undo+fold) and containers (scroll); disk-change invalidates. This is the highest-risk phase — do the `build-breaking-agent` blast-radius check here before moving on.

---

## Phase 3 — The Tab Bar UI

> **UIX-REPASS GATE (Nathan, `[§J]`):** before building this phase, run a dedicated design repass of `§J` against the *real* toolbar — the sizing knobs (min/pref/max), the `+` overlay behavior at full width, the chip-× melt reveal on a tab label, pinned compact-icon treatment. Confirm the exact treatment (Figma/screenshot) rather than building from prose. Do NOT skip this because the spec reads complete.

### Task 3.1 — Tab bar shell + zones + sizing

**Files:** `src/renderer/src/Tabs/TabBar.tsx` + `tabBar.css` (create, migrate the `tabbar-preview-scroll` inline scroll-edge-fade `[J-5]`), `Toolbar/Toolbar.tsx` (render `TabBar`, keep `TabBarPreview` until 3.x lands then delete).

**Build:** pinned zone (fixed-left) + unpinned zone (overflow-scroll); pinned = compact **icon + pin accent, name-on-hover** `[I-8]`; unpinned = min/pref/max width, ellipsis title `[J-3]`; active-tab highlight reuses the prototype's clipped sliding label. Blank when a single tab `[D-6]`.

- [ ] Build the shell reading `tabs`/`activeTabId`; wire click→`activateTab`. Screenshot-verify against the §J repass. Commit.

### Task 3.2 — Close (×), new-tab (+), open/close animation

**Files:** `TabBar.tsx`, `tabBar.css`.

- Close `X` = reuse **`ChipRemoveButton`** + the chip melt/blur label reveal `[J-1]` (pointerdown-isolated so it never arms the drag); only on unpinned tabs `[D-10]` → `closeTab`.
- New-tab `+` = reuse **`.group-add`** hover-reveal `[J-2]`; right of the rightmost tab, overlaying the trailing tab at full width `[J-4]` → `openTab({kind:'newtab'})`.
- Open/close **one DRY'd animation** `[J-6]` mounted to the `Interaction.md` primitive (not a new keyframe).

- [ ] Implement; screenshot-verify the melt reveal + the `+` overlay at full width. Commit.

### Task 3.3 — Zone-aware drag + tab context menu + cycling

**Files:** `TabBar.tsx`, `Tabs/TabContextMenu.tsx` (create, in-renderer `PickerMenu` — `Pin/Unpin · Close · Close to the Right` `[I-12]`), cycling binding.

- Drag = `SortableZone`/`useDragItem` reflow `[D-4b]`, **zone-aware**: cross-divider drag pins/unpins, landing **where dropped** `[I-13]`.
- `Ctrl`+`Tab`/`Ctrl`+`Shift`+`Tab` → `cycleTab(±1)`, wraps, all tabs `[I-11]`.

- [ ] Implement; verify drag-to-pin (lands where dropped) vs menu-unpin (promotes to front); cycling wraps. Commit.

**Gate 3:** the tab bar is fully interactive; §J repass items verified by screenshot.

---

## Phase 4 — "Open in New Tab" Context Menus (4 touch points)

Stateful: already-open → **"Open"** (focus); not-open → **"Open in New Tab"** `[I-1]`.

### Task 4.1 — Native menus (Sidebar + TableView) with push-back

**Files:** `src/main/contextMenu.ts` (add item near the rename push, `webContents.send('open-in-new-tab', target)`), `src/preload/index.ts` (`onOpenInNewTab`, mirror `onBeginRename`), `store.ts`/`App.tsx` (listener → `openTab(target, { newTab:true })`), `src/shared/cellMenu.ts` + `src/main/cellMenu.ts` (title-branch action `'title:open-new-tab'`) + `TableView.tsx` (apply the returned action).

- [ ] Implement both native paths; the item text flips Open/Open-in-New-Tab by whether the target is already a tab. Commit (electron restart).

### Task 4.2 — In-renderer menus (NavList + NavGallery)

**Files:** `NavList.tsx` (`NavRowMenu` += one `MenuItem`), `NavGallery.tsx` (add a `PickerMenu` context menu — reuse `NavRowMenu` if liftable).

- [ ] Implement; both call `openTab`. Commit.

**Gate 4:** all four surfaces open/focus a tab correctly, honoring pin-spawn vs replace.

---

## Phase 5 — New-Tab Page (also the empty state)

**Files:** `src/renderer/src/Tabs/NewTabPage.tsx` + `newTabPage.css` (create), `Detail/DetailPane.tsx` (`DetailView` — **replace the `'none'` placeholder** with the new-tab page `[E-2]`), `shared/types.ts` (the kind).

**Build `[E-1]`:** `useNavData()` + a search input replicating `NavPane`'s `splitSearch(search(query))` + `<NavGallery pins items onSelect>` with a bumped `--card-min` to fill the window; `--main-bg` background (inherited in the detail slot). Picking a result → `openTab(target)` which, on the scratch newtab tab, **replaces** it `[D-1]`. **The new-tab page IS the empty/no-target state `[E-2]`** — a nexus that opens with no persisted tabs defaults to a single new-tab page (Phase 0/1 seed this). **NavPane stays a separate surface `[E-3]`** — it shares the NavGallery component, not a merged shell; do NOT collapse them.

- [ ] Test the `'newtab'` navKey dedups to one start page `[I-1]` and that a no-tabs nexus seeds one. Implement; drop the `'none'` branch. Screenshot-verify. Commit.

**Gate 5:** `+` opens the start page; searching + picking replaces it; a fresh nexus opens onto it; no blank placeholder remains.

---

## Phase 6 — Reveal-on-Hover Setting

**Files:** `shared/types.ts` (`revealTabBarOnHover?: boolean` on `Personalization`), `src/main/readNexus.ts` (`bool(p.revealTabBarOnHover)`), `TabBar.tsx` (consume `useSession(s => s.personalization.revealTabBarOnHover ?? false)`). Write path is generic `[F-1]`. Default false. No toggle UI (matches `hideChevrons` — Prospect).

- [ ] Implement; hidden state reveals on toolbar hover without reflowing the full-bleed banner. Commit.

**Gate 6:** toggling the key in `settings.json` shows/hides the bar on hover.

---

## Phase 7 — Lifecycle, Edge Cases, Cleanup, Docs

### Task 7.1 — Entity mutation + autosave flush
- Delete `[I-2]`: unpinned tab of a deleted entity **actually closes** (active→MRU); pinned tab **render-hides, keeps the pin file** (never storage-prune — the `.nexus/pins/` render-prune rule). Rename/move re-resolve label+path live.
- Autosave flush `[I-3]`: replace/close **fires the pending autosave fire-and-forget** (no await, no input delay) before discarding warm state.
- [ ] Tests for each; implement; verify a delete-while-open doesn't orphan a tab. Commit.

### Task 7.2 — Cleanup + docs reconcile
- Delete `TabBarPreview.tsx` + `tabBarPreview.css` `[G-2]`.
- Reconcile `Navigation.md` (temp-pin "fake tabs" → superseded by real tabs `[G-1]`), `Framework.md` roadmap (slot multi-tab as the active cluster `[G-6/A-2]`), `History.md` (the locked B-1 paradigm decision), `Handoff.md`.
- [ ] Sweep + commit docs with the code `[bundle-docs rule]`.

### Task 7.3 — Post-functional UIX review (mandatory)
- [ ] After functional-green, a UIX review of the *actual working tab bar* against `§J` — no matter how clean the build `[Review-Discipline]`. Fold findings, re-screenshot, close out.

**Gate 7:** edge cases hold; throwaway code gone; docs true; UIX review passed.

---

## Self-Review (spec coverage)

- **Warm mechanism** (B) → Phase 2. **Persistence** (D-8) → Phase 1. **Tab model/predicate/lifecycle** (D, I-1…I-14) → Phase 0 + 3 + 7. **Pins-graduate** (C) → Phase 0/1 (reconcile `isPinned` against `.nexus/pins/`) + 3 (compact pinned UI). **Context menus** (D-3) → Phase 4. **New-tab page** (E) → Phase 5. **Setting** (F) → Phase 6. **UIX/DRY** (§J) → the Phase 3 repass gate + Tasks 3.1-3.3.
- **Residuals to resolve before/at their phase:** the `historyField`/`foldField` serializability grounding (Task 2.2). *(Resolved: E-2 = new-tab page subsumes `'none'`; D-8a = synced; D-7 = per-tab history; E-3 = surfaces stay separate.)*
- **Highest risk:** Phase 2 (against the `key=`-remount grain) — carries its own build-breaking pass. Phase 4 crosses the IPC boundary twice — mirror `begin-rename` exactly.
