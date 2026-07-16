## Multi-Tab Nexus — Decision Log

> Status: **RATIFIED — review-certified, ready to build.** Grounded against real code and hardened across adversarial review (a grounding pass, a 3-agent plan-attack — internals + visuals/interaction + simplification — and a final confirmation pass), every load-bearing claim verified in code. This opens the Navigation log's deferred **B-1** (single-pane-replace vs top-bar tabs). Implementation → `Multi-Tab Nexus — Implementation Plan.md`; all visual knobs live in the plan's knob block.

### Frame

- **Purpose:** Give Pommora **warm, state-preserving tabs** in the toolbar — a working set of open entities you flip between like browser tabs, each holding its own view state (scroll, editor undo, its own Back/Forward) — superseding single-pane-replace as the navigation model.
- **Core Value:** Hold several entities open at once and switch between them instantly *without losing your place in any of them* — what single-pane-replace and the temp-pin "fake tabs" can't deliver.
- **Success Criteria:** (1) opening entities builds an ordered, warm tab set in the toolbar; (2) switching a tab restores its scroll + undo with only one view mounted; (3) pinned vs unpinned tabs govern replace-vs-spawn on navigate; (4) the tab set persists per-nexus and **syncs cross-device**, reusing the shipped nav layer (recents/pins) rather than duplicating it; (5) it holds the perf rules — no N-views-mounted, no expensive work on every switch.

### Surface Naming

Three wayfinding surfaces over the one shared nav-state layer:

- **NavWindow** — the summoned, movable floating glass overlay: search + recents + pins + a favorites rail. (Shipped today.)
- **NavPane** — the toolbar Navigation-button dropdown: a compact form of the same data. (Placeholder today.)
- **NavView** — the new-tab page: a full-window gallery + search that is the empty/new-tab state.

Plus **Toolbar Tabs** — the tab bar itself and the multi-tab model this log specs.

### Sources

- `.claude/Features/Navigation.md` — the shipped nav layer; Toolbar Tabs supersede the temp-pin "open tabs feel" and single-pane Back/Forward it describes.
- `.claude/Planning/Navigation — Decision Log.md` (RATIFIED) — defers this tabs paradigm as **B-1**; the nav layer was built UI-agnostic to feed a tab bar. The layer is **shipped, not just spec'd**: recents/favorites slices + synced sidecars + the `.nexus/pins/` per-pin store. Recents = `RecentEntry = NavTarget & { pinned? }` (the flag migration-only); **pins are their own durable store** — `PinEntry = NavTarget & { order, deleted? }`, one file per pin, `pins` slice + `pinTarget`/`unpinTarget`/`reorderPin`, resolved live via `navResolve` (`buildResolveIndex`), render-prune never storage-prune.
- `.claude/Features/Structure.md` — Settings singleton (`.nexus/settings.json`, `personalization` block) is the home for the tab-bar setting.
- **Code map (verified):**
  - `store.ts` — `selection: SelectionState` is a **single value** (`:135`), one "what's open" pointer; `pageStatus`/`pageDetail`/`liveBody` singular (`:135–141`). `select(target, opts?)` (`:545–607`) sets `selection` synchronously then fetches page detail via IPC (`:591–604`). `navStack`/`navIndex` (`:147–148`) = a single in-memory Back/Forward. `applyTree` (`:345–346`) reconciles **only the singular `selection`** against the tree. `reconcileSelection` (`selection.ts:44–66`) re-resolves a stored ref.
  - **Mount model (the constraint):** `DetailPane.tsx` `DetailView` is a `switch(selection.kind)`; the page editor force-remounts via `key={pageDetail.path}` (`PageView.tsx:88`), the table via `key={source.id}`. The CM6 `EditorView` builds in a mount-once `useEffect([])` and is fully destroyed on unmount (`MarkdownPM/index.tsx:109–246`) — no EditorState cache. The `readOnly` compartment-reconfigure (`:251–262`) proves the file can reconfigure a live view without remounting — the seam warm state builds on.
  - **CM6 serialization:** `historyField` is a real export (`@codemirror/commands`) with round-tripping `toJSON`/`fromJSON`. `foldField` is a module-private `StateField` (`MarkdownPM/editor/folding.ts:188`) with no `toJSON` — folds persist instead to per-page `folds.json` and re-apply on mount (`applySavedFolds`, `PageView.tsx:105`).
  - **Table:** hand-rolled, un-virtualized (every row mounts) — mounting N tables warm is N× DOM.
  - **Context menus:** native Electron menus (main, IPC) for the Sidebar (`contextMenu.ts`, push-back via `webContents.send`) and TableView (`cellMenu.ts` title branch); in-renderer `PickerMenu` for the NavWindow list (`NavRowMenu`). The NavWindow gallery has no menu. `ContextTarget = {kind, path, title}` (`shared/mutate.ts:95`) — no `id`.
  - **Persistence template:** `navState.ts` — a debounced main-side writer (`scheduleRecentsWrite`/`flushRecents`), drained at both `before-quit` (`index.ts:1656`) and `adoptNexus` (`:398`, awaited before the root swaps). Synced = in `NEXUS_CONFIG_FILES`, absent from `DEVICE_LOCAL_NEXUS_FILES` (`paths.ts`).
  - **Drag engine:** two engines behind one seam (`shared.ts:3-7`) — single-zone in-place reflow (`engine.tsx`, `SortableZone`; what the NavWindow gallery uses) and a cross-list engine (`group.tsx`, `DragGroup`/`GroupZone`) that is vertical-only + portal-overlay (`indexAt` by Y, `translate3d(0,dy,0)`, dragged item hidden).
  - **Capture:** `useNavThumbnails` fires on `[selection, pageStatus, navOpen, bumpThumb]` with no per-navKey guard — a plain selection change re-shoots a full-window `capturePage` + a synced thumbnail write.

### Decisions

#### A — Scope / Framing
- **A-1:** [confirmed] The deferred **B-1** paradigm cycle — Toolbar Tabs supersede single-pane-replace as the navigation model.
- **A-2:** [confirmed] **Build now** — multi-tab reprioritizes ahead of the remaining Views work; `Framework.md` slots it as the active cluster (G-6).

#### B — The Warm-State Mechanism (load-bearing)
- **B-1:** [confirmed] **One view mounted; a per-tab serialized cache, rehydrated on switch.** N live views (Option A) is rejected — it forces `selection`/`pageDetail` off their singular shape across ~15 consumers AND keeps N un-virtualized tables alive (perf hard-rule violation). Rehydrate-on-switch also re-reconciles each tab against the live tree — fresher than a stale live view for a file-canonical app.
- **B-2:** [confirmed] **Warmth = scroll + undo + heading-fold**, session-scoped. The warm cache serializes **`historyField` (undo) + scrollTop only**; heading folds are NOT cached — they persist per-page to `folds.json` and re-fold on mount, so fold-warmth is free and survives both switch and relaunch. Scroll + undo reset on quit.
- **B-3:** [confirmed] Implementation:
  - **Seed the fresh mount from a cached `EditorState` serializing `historyField` only**, restore scrollTop post-mount. `foldField` is unexported/non-serializable — never touched; folds ride `folds.json`.
  - **Freeze `(tabId, navKey)` at the CM6 mount** (in the `[]`-effect / a set-once ref); the unmount capture writes under those frozen values, never live `activeTabId` — `select` sets selection synchronously before the `openPage` await, so a capture reading live state would write under the *next* tab's id.
  - **A warm switch short-circuits the refetch** — for a warm, unchanged tab, `activateTab` reuses the cached `pageDetail` and skips `openPage` + the loading placeholder, so there's no flash. A change-invalidated tab (I-4) refetches — the only flash, and only when the file genuinely changed. `select()` is warm-aware by design.

#### C — Tabs and the Nav Layer
- **C-1:** [confirmed] **The shipped `.nexus/pins/` store IS the pinned-tabs set.** Pinning a tab = `pinTarget(target)`, unpinning = `unpinTarget(key)`, reordering pinned tabs = `reorderPin` (fractional `order`) — the same calls the NavWindow gallery uses. The pin set is one working set surfaced in two places (the tab bar + the NavWindow gallery), rendered off the same `pins` slice.
- **C-2:** [confirmed] **Pinned tabs dock LEFT.** Existing pins appear there immediately — zero migration, the `.nexus/pins/` store already holds them; pinned-tab reorder writes the same fractional `order` as the gallery.
- **C-3:** [confirmed] Tiers: **Recents** (history stream, feeds the NavWindow gallery + NavView) · **Pinned tabs** (the pin set, persisted, left-docked) · **Unpinned tabs** (session scratch, right of the pins) · **Favorites** (durable bookmarks).
- **C-4:** [confirmed] Surfacing a pin in two places (a left-docked tab AND pins-on-top in the NavWindow gallery) is intentional — one working set, two views.
- **C-5:** [confirmed] **Recording semantics.** A recent records on a genuine navigation (opening an entity into a tab, or navigating within one), NOT on activating an already-open tab — a switch is re-surfacing, not a new nav, so `activateTab` calls `select` with `record:false` (mirroring how Back/Forward suppresses recording).
- **C-6:** [confirmed] **`isPinned` is DERIVED, never stored.** `isPinned(tab, pins) = pins.some(p => navKey(p) === navKey(tab.target))`, computed on read. The synced `tabs.json` stores **only unpinned tabs + `activeTabId`**; pinned tabs render off the `pins` slice (identity + fractional `order`). On load, drop any `tabs.json` tab whose `navKey` is in the pins set. Storing `isPinned` in a second synced file would re-introduce the whole-array-LWW desync the per-file `.nexus/pins/` store was built to dodge; I-1 (≤1 tab per entity) guarantees the derivation has no conflict.

#### D — Tab Behavior
- **D-1:** [confirmed] **Unpinned tab = scratch** — navigating to another entity replaces its content in place (unless "Open in New Tab"). One browsing tab gets reused; no junk-tab accumulation.
- **D-2:** [confirmed] **Pinned tab = protected** — navigating while a pinned tab is active opens a new tab instead of replacing. Pinning is the explicit "keep this open" gesture.
- **D-3:** [confirmed] **"Open in New Tab"** = a right-click item across the Sidebar, NavWindow, and views — forces a new tab regardless of pin state. (Four menu touch points, two across IPC.)
- **D-3b:** [confirmed] **One primitive, one predicate.** `openTab(target, { newTab })`: dedup first — if `target` is already in a tab, focus it and stop (I-1); else `newTab = explicitOpenInNewTab || activeTab.isPinned` decides replace-active vs spawn. "Open in New Tab," "the active tab is pinned so don't clobber it," and "Back/Forward off a pinned tab" (I-6) all funnel through the one boolean.
- **D-4:** [confirmed] Pinned tabs show a pin icon on the left; a hover `×` on the right closes (J-1); create/remove use one DRY'd animation (J-6).
- **D-4b:** [confirmed] **Within-zone reorder drag** = the single-zone `SortableZone` in-place reflow, run per zone (pinned-among-pinned, unpinned-among-unpinned). Not a new drag mechanism (I-13).
- **D-5:** [confirmed] **New-tab `+`** = a hover-icon right of the rightmost tab; when tabs span the full toolbar width it parks at the trailing end and overlays the tab beneath it (J-2/J-4).
- **D-6:** [confirmed] **A single open tab → the toolbar can stay blank** (no strip until ≥2, or until a pin).
- **D-7:** [confirmed] **Per-tab Back/Forward** — each tab owns its own history; `navStack`/`navIndex` live in the active tab, the toolbar arrows act on it. Matches browser muscle memory; Back never teleports across tabs.
- **D-8:** [confirmed] **The full tab set persists across restart — closing Pommora never resets tabs.** Both pinned and unpinned tabs, their order, the active tab, and each tab's current target + Back/Forward *targets* survive quit/relaunch. On relaunch every tab reopens in order, at its last-viewed entry, **cold** (warm view-state is session-only, B-2). The structure persists; the warmth doesn't.
  - **D-8a:** [confirmed] **The tab-set sidecar syncs cross-device.** It holds the ordered tab list (unpinned targets + `activeTabId` + per-tab history targets) — no warm state. Canonical/synced (not device-local): churny writes debounced in main (the recents pattern), last-writer-wins, single-user so concurrent live edits are outside the threat model. Open tabs travel across devices; pinned identities ride the already-synced `.nexus/pins/`.

#### D′ — Tab Lifecycle
- **D-9:** [confirmed] **Closing the active tab focuses the most-recently-used tab** — an MRU focus stack (each activation pushes, closing the active pops), not the spatial neighbor. On a cold relaunch the MRU is empty, so the first close falls back to the spatial neighbor. Visual tab order stays stable on plain switching — the MRU stack governs close-focus only.
- **D-10:** [confirmed] **Pin state gates closability.** The hover-`×` shows only on unpinned tabs; a pinned tab isn't directly closable — toggling the pin off reveals the `×`.
- **D-11:** [confirmed] **Unpin placement — promote to front.** The unpinned zone's most-recent end is the LEFT (adjacent to the pins). Unpinning inserts at position 1 (leftmost) — unless the active tab is currently position 1, in which case it inserts at position 2 (directly behind it) so the active tab keeps its spot.
- **D-12:** [confirmed] **Two placement rules, intentionally asymmetric.** New tab-opens append to the RIGHT and hold fixed order (a fresh open is new work parked at the end). Unpins promote to the front-left (D-11). Plain switching never reorders; only open / unpin / close move things.

#### E — NavView (the new-tab page)
- **E-1:** [confirmed] `+` opens **NavView** = the NavWindow gallery scaled full-window, a Homepage-shared background, a search bar where the banner title sits. Low effort: the gallery is data-driven (`{pins, items, onSelect}`, `auto-fit minmax(--card-min,1fr)` so it grows to fill), `cqi`-typography scales. NavView = `useNavData()` + a search input (NavWindow's `splitSearch(search(query))`) + the gallery, `--main-bg` background inherited in the detail slot.
- **E-2:** [confirmed] **The empty state IS NavView.** `DetailView`'s blank placeholder is replaced by NavView. There is no `'newtab'` `SelectionState` kind — a newtab tab's target is a sentinel that `activateTab` maps to `selection: {kind:'none'}` (bypassing `select()`, which has no such case), and the `'none'` `DetailView` branch renders NavView. A nexus that opens with no persisted tabs defaults to one newtab tab.
- **E-2b:** [confirmed] **A NavView tab reads "New Tab" under the copy glyph** — and per D-6 it only ever appears as an actual tab once the bar shows (≥ 2 tabs or a pin); a lone NavView leaves the toolbar blank.
- **E-3:** [confirmed] **NavView and NavWindow stay separate surfaces** — they share the gallery component, not a merged shell, so the two can diverge without coupling.
- **E-4:** [confirmed] **Favorites stay a distinct tier** — a future jump-to surface, not a held-open working set; not collapsed into pins.

#### F — The Tab-Bar Setting
- **F-1:** [confirmed] **Reveal-on-hover** = a `revealTabBarOnHover` boolean in the `personalization` block of `.nexus/settings.json`, default false (always shown). Add it to `Personalization` (`shared/types.ts`) + coerce in `readPersonalization` (`readNexus.ts`); the write path (`personalization:set`) is generic; consume via `useSession(s => s.personalization.revealTabBarOnHover ?? false)`. No toggle UI yet (matches `hideChevrons`).

#### G — Adjacencies
- **G-1:** [flagged] **Navigation.md** — restructured to the four `#### II.` sections (NavWindow · Toolbar Tabs · NavPane · NavView); the single-pane-replace framing reconciles to tabs.
- **G-2:** [flagged] **`TabBarPreview.tsx` + `tabBarPreview.css`** — the throwaway prototype; deleted and replaced by the real tab bar (its scroll-edge-fade CSS migrates).
- **G-3:** [flagged] **Thumbnail capture** (`useNavThumbnails.ts`) — must be gated so a plain tab-switch doesn't re-shoot (warm switching is now the highest-frequency interaction).
- **G-4:** [confirmed] **NavWindow preview-mode coexists** — a preview is a tab-neutral peek: no tab, no Back/Forward touch.
- **G-5:** [flagged] **Multi-window seam** — tabs are per-window state; the store is per-renderer. "Drag a tab out to a new window" is a Prospect the multi-window seams enable.
- **G-6:** [flagged] **`Framework.md` + `History.md`** — the roadmap slots multi-tab as the active cluster; the locked paradigm decision routes to History.

#### I — Interaction & Edge Cases
- **I-1:** [confirmed] **No duplicate tabs.** Opening an entity already in a tab focuses that tab — each entity maps to ≤ 1 tab. The context menu is stateful: an already-open entity shows "Open" (focus), a not-open entity shows "Open in New Tab."
- **I-2:** [confirmed] **Live entity mutation.** Rename/move re-resolve a tab's label + path live. Delete splits by pin state: an unpinned tab whose entity is deleted actually closes (active → MRU-focus); a pinned tab render-hides but keeps its pin file (render-prune, never storage-prune — `navResolve.ts:104`). Auto-close never drops a pin from storage.
  - **I-2a:** [confirmed] **Every tab's target reconciles, not just the active selection.** `applyTree` today reconciles only the singular `selection`, so an inactive tab would hold a stale path and error on activation. On each `applyTree`, map `reconcileSelection` over every tab's target + navStack, applying the I-2 close-vs-render-hide split. This is deliberate tab-awareness in `applyTree` — the "consumers untouched" framing (B-1) holds for the *render* consumers, not for tree reconciliation.
- **I-3:** [confirmed] **Autosave on replace/close.** The shipped `scheduleSave` + `beforeunload` flush already cover switch-away and close (`PageView` never remounts; only the inner CM6 view does) — so no dedicated flush is needed unless a gap is proven; if one is, fire the pending write fire-and-forget (no input delay).
- **I-4:** [confirmed] **Warm yields to disk truth.** A changed file drops the warm cache and reloads fresh (never a stale doc over a divergent undo stack). Invalidation rides the existing file-change bus (`nav:changed` / tree-refresh), not a separate mtime poll.
- **I-5:** [confirmed] **Closing the last tab → NavView** (never a blank window).
- **I-6:** [confirmed] **Pinned tabs never change content in place — including Back/Forward.** On an unpinned tab, Back/Forward navigates in place. A pinned tab holds no history at all (it derives fresh from the pin set), so the arrows simply disable there — nothing to walk, nothing to clobber.
- **I-7:** [confirmed] **The back-stack is WARM, capped at ~20 back-forth entries per tab.** Open-tab count is uncapped. Back/Forward restores each history entry's warm state (scroll + undo; folds re-fold from `folds.json`); beyond the cap it re-opens cold. Warm state is serialized JSON for inactive tabs (only the active tab is mounted) — far lighter than N mounted views. History *targets* persist across restart (D-8); their warm state is session-only + capped, so a relaunched Back navigates cold. If aggregate warm memory ever bites, a global LRU trims warm depth (never closes tabs).
- **I-8:** [confirmed] **Pinned tab = compact icon** (the entity icon + the pin as an accent, no inline title; the full name reveals on hover). The pinned zone stays fixed-left; only the unpinned zone overflow-scrolls.
- **I-9:** [confirmed] **NavWindow preview-mode coexists** with tabs — an ephemeral peek that opens no tab and doesn't touch Back/Forward.
- **I-10:** [confirmed] **Nexus switch** — the current nexus's full tab set persists to its synced sidecar, the new nexus's set loads (its pinned tabs from that nexus's `.nexus/pins/`); returning restores its tabs. The in-memory reset mirrors the nav-layer's per-nexus reset, backed by the persisted set.
- **I-11:** [confirmed] **Keyboard = tab-cycling only** — `Ctrl`+`Tab` / `Ctrl`+`Shift`+`Tab` (the one signed-off binding), wraps, includes all tabs. No `⌘T`/`⌘W`/`⌘1–9`.
- **I-12:** [confirmed] **The tab's own right-click menu = Pin/Unpin · Close.** No "Close Others," no "Close to the Right," no "Duplicate" (Duplicate contradicts the no-dupes rule).
- **I-13:** [confirmed] **v1 pins via the affordance + menu only.** Within-zone reorder drag ships (D-4b); cross-divider drag-to-pin is a Prospect — the cross-zone engine is vertical + portal-overlay, so a horizontal pinned│unpinned handoff is bespoke engine work not worth blocking core. Unpin (affordance/menu) follows the D-11 promote-to-front rule.
- **I-14:** [confirmed] A container/context tab's warm state = scroll only (undo/fold are page-editor-only); close is the hover-`×` (+ tab menu) only, no middle-click.

#### J — Tab-Bar UIX (DRY sources) — REPASS BEFORE THE TAB-BAR BUILD
> A dedicated design repass against the real working UI runs before the tab-bar build (the plan's UIX-repass gate); the details below are the DRY sources + starting treatment, not final-from-prose. Exact values → the plan's knob block.

- **J-1 (hover-`×`):** [confirmed] The close-`×` reuses **`ChipRemoveButton`** (`Chip.tsx:79-94` — the glyph button, pointerdown/click `stopPropagation` so it never arms the drag) with a **plain hover-fade** (the `×` fades in on tab hover; the ellipsis title sits behind it). Not the chip melt/blur reveal — that needs a solid `--chip-fill` a frosted-glass tab has none of, and it's eclipsed on the active tab by the highlight track.
- **J-2 (hover-`+`):** [confirmed] The new-tab `+` reuses the `.group-add` glyph + fade token (`GroupHeader.tsx:164-174`); its absolute trailing-edge placement + strip-scoped reveal + full-width overlay are authored fresh (the `.group-add` reveal is row-scoped and inline, so only the glyph + fade transfer).
- **J-3 (widths):** [confirmed] Tabs take a min / preferred / max width, packed left. Pinned = compact fixed (icon + pin accent, name-on-hover); unpinned = the ranged width with an ellipsis title.
- **J-7 (tab icons):** [confirmed] Tab icons resolve live off the nav layer's index like every nav surface — the Homepage tab wears the nexus photo (the home glyph only when none is set), matching EntityGlyph's rule everywhere else.
- **J-4 (`+` placement):** [confirmed] Right of the rightmost tab; at full width the `+` parks trailing and overlays the last tab — with its own gutter reserved outside that tab's `×` zone so the two never collide.
- **J-5 (overflow):** [confirmed] The unpinned zone overflow-scrolls with the prototype's inline scroll-driven edge fade; the active tab scrolls into view on switch. The pinned zone is bounded (its own overflow/collapse past a threshold) so uncapped pins never clip or collide with the toolbar's right cluster.
- **J-6 (open/close animation):** [confirmed] A tab's width animates open/collapsed so neighbors reflow, on **`--duration-slow` + `--ease-standard`** (the sidebar/ribbon collapse easing, `Sidebar.css:55/101`), composed with `useExitPresence` for exit timing. Not a new keyframe.

### Core (must-have)
- **Tab store slice** — `tabs` (each: `id`, `target`, own `navStack`/`navIndex`; **no stored `isPinned` — derived from the pins set**, C-6) + `activeTabId`, wired inline in `store.ts`. The singular `selection`/`pageDetail`/`liveBody` stay and always mean the active tab; pinned identities come from the `.nexus/pins/` store.
- **Persisted tab-set store** (D-8/D-8a) — a synced sidecar of the ordered tab list + active + per-tab history targets (no warm state), reopening on relaunch AND traveling cross-device (debounced main-side, drained at `before-quit` and `adoptNexus`). Closing never resets; restore is cold.
- **Warm rehydration path** (B-2/B-3/I-7) — one view mounted; serialize `historyField` + scrollTop per tab-history-entry (warm back-stack ~20-capped), seed the fresh mount from it, restore scroll; folds re-fold from `folds.json`; disk-change invalidates (I-4); session-scoped.
- **The `openTab(target, {newTab})` primitive** (D-3b) — dedup-first + the `newTab` predicate, driving `select()`; per-tab Back/Forward on top (D-7).
- **The real tab bar UI** — pinned left-docked compact icons (I-8), plain `×` hover-fade close (J-1), trailing `+` (J-2/J-4), width-animate open/close (J-6), **within-zone reorder drag** (D-4b/I-13), a tab context menu (I-12), `Ctrl`+`Tab` cycling (I-11), blank when a single tab (D-6).
- **The four "Open in New Tab" touch points** (D-3) — Sidebar (native push-back), TableView (native cell action), NavWindow list (`PickerMenu` item), NavWindow gallery (new menu).
- **NavView** (E-1) — full-window gallery + `--main-bg` + a search input; also the empty state (E-2).
- **The reveal-on-hover setting** (F-1).

#### Prospects (allowed later, not now)
- Cross-restart warm state (persist scroll/undo to disk) — session-only warmth is the call; only the tab *set* persists.
- **Cross-divider drag-to-pin/unpin** (I-13) — bespoke horizontal cross-zone engine work; v1 pins via affordance + menu.
- **Drag-reorder recents** — nav-layer scope, not multi-tab: reuse the pin `SortableZone` + a `reorderRecent` that rewrites the recents array (the nudge becomes the recents order; a visit only re-fronts the one visited entry). Deferred as its own small task.
- Per-window tab sets once multi-window lands (key the sidecar per window ref).
- Drag a tab out into its own window (G-5).
- `⌘1–9` / `⌘W` / `⌘T` shortcuts — proposed separately per the no-keybinding-without-signoff rule.

#### Out of Scope
- Split panes (the third B-1 branch) — not this cycle.
- Table row virtualization — its own standing perf debt; one-view-mounted avoids needing it here.

#### Considered & Rejected
- **N live mounted views (Option A)** — perf hard-rule violation (N un-virtualized tables) + a ~15-consumer blast radius. One-view-mounted + a serialized cache wins (B-1).
- **Storing `isPinned` on each tab** — derive it from the pins set instead; a second synced copy re-introduces a cross-device LWW desync class (C-6).
- **Serializing `foldField` for warm state** — it's unexported/non-serializable, and folds already persist durably via `folds.json`; the warm cache serializes `historyField` only (B-3).
- **The chip melt/blur `×` reveal on tabs** — it needs a solid `--chip-fill` a frosted-glass tab lacks; a plain `×` hover-fade is correct on glass (J-1).
- **Reusing an engine for horizontal cross-zone drag** — the cross-zone engine is vertical + portal-overlay; within-zone reflow ships, drag-to-pin defers (I-13).
- **Persisting warm view-state to disk** — session-only; the tab *set* persists, the warmth doesn't (D-8).
- **A single shared Back/Forward history** across tabs — Back teleporting between tabs fights muscle memory; per-tab history wins (D-7).
- **A merged surface for NavView + NavWindow** — reuse the gallery, keep the shells separate to avoid coupling two things that may diverge (E-3).
- **Collapsing Favorites into pinned tabs** — favorites are a jump-to surface, not a held-open working set (E-4).

#### Lessons
- The nav layer was built UI-agnostic specifically to feed this tab bar — the reconciliation is a fulfillment, not a rewrite. Ground new features against prior decision logs, not just code.
