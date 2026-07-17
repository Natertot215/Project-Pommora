## Page Previews — Decision Log

### Frame

- **Purpose:** Ship the "B-8 preview surface" as a **semi-multi-tabbed floating mini-app** — the routing target for `open_in: 'page-preview'` plus the NavWindow's tabbed evolution, on one shared chrome.
- **Core Value:** A Page can be *worked on* beside your work — opened, edited, and wiki-navigated in a floating window — without ever touching the main pane's selection, tabs, or history.
- **Success Criteria:** (1) A `page-preview` Collection's title click opens the preview; dismissing lands you exactly where you were, app tabs/history untouched throughout. (2) A wiki-link inside a preview opens as an in-window tab; tabs switch/close on the shared tab motions; closing the origin re-parents. (3) Quitting and relaunching restores any origin's remembered tab set (per-origin, durable) and the NavWindow's. (4) The NavWindow flavor works as tabs beside its perma-pinned map tab, sidebar sliding away on page tabs. (5) The inspector opens/closes on the `--io` contract with front-matter editing live. (6) B-6 routes connection clicks to the preview when configured; promote engulfs into the detail pane.

### Planning Requirements (Nathan's, carried INTO the plan verbatim)

- Every phase ends with: gates green (typecheck + full vitest + build, pipefail, background) → a review agent pass → code-simplifier + comment-killer. Re-assess the plan between green phases; rewrite drifted downstream tasks.
- Doc reconciliation (this log's Reconciliation section) lands WITH the code, committed.
- **Every design choice gets confirmed inline as it's made AND restated in the final report.**
- **The final report comes at the END OF THE PLAN, nowhere else**: every knob (name · file · default), every design decision (exhaustive), every assumption/consideration taken or deferred, and what Nathan must eyeball live.
- Standard Agent dispatches only — never the Workflow tool. Phases, never dates.
- Ping Nathan's phone at each task/phase completion; don't stop until the plan is finished.

### Status — Continuation

The cycle is live (Nathan's overnight directive): **spec attack → certify → plan → certify → post-compact execution prompt → inline execution**, phone pings at each phase gate. Round 1 of the spec attack (four lenses + a transcript miner) is folded into this V2. The interactive shell is **shipped on main** (see Shipped Shell below) — the plan builds the remainder onto it, never re-plans it.

### Shipped Shell (don't re-plan — build onto)

Commits `532b84d7..f327ba4f` + the hardening guards. Files: `PagePreview/PreviewWindow.tsx` + `previewWindow.css`, `design-system/interactions/FloatingWindow.tsx` (+ css), `Embeds/connectionMenu.ts`, `main/connMenu.ts`, edits in `TableView.tsx` (B-1 branch at the title click, ⌘-click new-tab bypass), `store.ts` (`previewTarget`/`openPreview`/`closePreview`, D-8 mutual close), `MarkdownPM` (connections `menu` hook + native `conn-menu` IPC), `main/contextMenu.ts` (sidebar Open in Preview), `NavList.tsx` (nav-row item), icon registry (`scan`, `app-window`). Working behaviors: floating chrome (move/corner-resize, per-window-keyed geometry, opens centered, size persists per session), edge-to-edge frost + tint knobs, floating transparent toolbar with the pane-aligned glyph row (scan left; settings · panel-right · X right; the settings+inspector pair rides the `--io` swallow), centered two-tone breadcrumb title, body-owns-scroll model with the toolbar edge-fade, fully editable PageEmbed keyed by path, resizable rail-material inspector pane (empty scaffold), Escape inspector-first, promote via `select`, right-click Open in Preview on wikilinks (native) / sidebar (native) / nav rows (in-renderer). Knobs live at the top of `previewWindow.css` (`--pgpreview-*`) and the `WIN`/`INSPECTOR` blocks in `PreviewWindow.tsx`.

### Sources

- `Pommora/src/shared/types.ts:193` — `OpenIn = 'full-page' | 'page-preview'`; the type's own comment says "full-view or a hovering preview window. Collection-owned."
- `Pommora/src/shared/schemas.ts:23` — `OPEN_IN_LEGACY` coerces Swift-era `window | compact` on read.
- `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx:110` — "Open In has no payload target until the preview surface ships (B-8)" — the config UI exists and writes; nothing routes on it.
- `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx` (~:681) — the ONLY navigate (A-7), now carrying the SHIPPED B-1 branch: `openIn === 'page-preview'` → `openPreview`, ⌘-click → new tab. Context-menu `title:newtab` nearby.
- `Pommora/src/main/crud/containerConfig.ts:39` — a Set-level `open_in` write is refused (Collection-owned; Sets proxy).
- `Pommora/src/renderer/src/Embeds/PageEmbed.tsx:19` — THE G-11 seam: a real Page as a read-only CM6 portal, in-place edit flip (no remount), 400ms-debounced autosave to the page's own file via `openPage`/`updatePageBody` directly — zero store/nav involvement. Props: `path, editing, onBeginEdit, connections, locked`. Header chrome (banner/title) parked.
- `Pommora/src/main/index.ts:619` — `page:open` is a pure read; `store.ts:1199 reloadPage` proves navigation-free reads are established.
- `Pommora/src/renderer/src/Detail/PageView.tsx:44` + `PageEmbed.tsx:53` — the only two page-body writers; both debounced `updatePageBody`, last-write-wins, no live cross-sync — the existing contract C-3 inherits.
- `Pommora/src/renderer/src/Embeds/embedScale.ts` — the G-10 zoom knob (`EMBED_SCALE`/`EMBED_ZOOM`), the F-3 seam.
- `Pommora/src/renderer/src/Toolbar/ToolbarTrio.tsx` — the inspector-toggle glass-swap G-1 reuses: the glass pill voids as the inspector swallows the trio, icons ride onto the inspector's glass, driven by `--io` (toolbar.css).
- `Pommora/src/main/settings.ts` — `.nexus/settings.json` handling: the serialized read-modify-write primitive (foreign keys preserved) the B-6 config writes through.
- `Pommora/src/main/index.ts:447` + `paths.ts:64` — app tabs persist via the synced `tabs.json` sidecar; the pattern H-3's NavWindow tabs follow.
- `Pommora/src/renderer/src/Tabs/warmCache.ts` — in-memory map of serialized editor state + scrollTop + PageDetail, 20-cap per tab, KB-scale; proves warmth is cheap (H-8) — mounted editors are the cost, not cached state.
- `Pommora/src/renderer/src/NavWindow/NavWindow.tsx:139` — the floating-chrome origin: pointer-captured move/rail/corner-resize engine (`startDrag`), module geometry, `useExitPresence`, `DRAG_SURFACES`, Escape skipping `defaultPrevented`. The engine is now SHARED at `design-system/interactions/FloatingWindow.tsx` (drag-surfaces prop, per-window geometry map); NavWindow still runs its inlined copy until its rebase (Reconciliation 1).
- `Pommora/src/renderer/src/design-system/components/PickerMenu/PickerMenu.tsx:24` — the body-portal top-layer primitive (z 1100, escapes clipping/transformed ancestors, re-measures on scroll/resize) — the anchored-card alternative's chassis.
- `Pommora/src/renderer/src/Tabs/warmCache.ts:28` — warm cache keyed by tabId; a tab-less preview has no natural key (it bypasses the cache; `openPage` is cheap).
- `Pommora/src/renderer/src/MarkdownPM/editor/connections.ts:16` — connection click navigates via `api.open` (PageView + BlockSurface both wire it to `select`); hover is greenfield.
- [[Navigation]] :23/:59 — ratified: "A **preview** peek from NavWindow is tab-neutral — it opens no tab and doesn't touch any tab's Back/Forward"; deferred: "NavWindow's in-pane page preview mode (a toggle tied to the page open-in setting)."
- [[Interaction]] — the motion law: dropdown Bloom is THE pane-open primitive; a new floating surface mounts to it, never its own keyframes.
- [[SurfacePM]] — two framework laws with reach here: popups escape the tile (body portal), and scroll is caret-priority.
- [[PommoraPRD]] :212 — the per-collection open mode (preview vs full) is what absorbed Items into Pages — this feature carries the item-like feel.
- `History.md:116` — Swift heritage: PagePreview was a real `NSPanel` (v0.4.0). `History.md:67` — `open_in` renamed `full-page | page-preview` with legacy coercion.

### Decisions

#### A — Surface Form

- **A-1:** [confirmed] A **floating movable window** — the NavWindow chrome pattern (move/resize/persisted size); park-it-beside-your-work, the NSPanel heritage. Anchored card and in-pane slide-over → Considered & Rejected. Layout/visual specifics are Figma territory.

- **A-2:** [confirmed] Open/close motion: the **floating-window in/out** — scale-in from 0.95 with opacity on `--disclosure` (the NavWindow's treatment; shipped as `pgpreview-in/out`, Nathan live-approved: "Love the opening animation"). Both floating windows share this one named motion; it enters Interaction.md as the floating-window primitive (NOT a Bloom consumer).

- **A-3:** [confirmed] Material, settled live: **GlassPane frost, edge-to-edge** — no inset ring, content clips to the radius — with the tint knobs `--pgpreview-bg` (default `--bg-window`) + `--pgpreview-bg-a` (Nathan-tuned; exact values live in code). Never liquid glass inside the scale-animated window (F-6).

- **A-4:** [confirmed] Promote-to-full animation: opening the previewed page in the full view **zooms/engulfs** — the preview expands into the detail pane rather than blinking away. A named motion primitive per the Interaction.md one-source law. Grounded build items: `closePreview` gains a **close reason** (`'engulf' | 'dismiss'`) threaded into the exit presence so promote never plays the dismiss motion (today `promote()` → `closePreview()` plays the scale-out); a **rect handoff** — the preview's rect (the geometry store) + a measurable detail-pane rect ref, captured at one instant for the FLIP.

#### B — Triggers & Routing

- **B-1:** [confirmed, SHIPPED] The routing branch lives at the title-click navigate (TableView A-7, the app's only navigate): `open_in === 'page-preview'` → open preview instead of `select` — live at `TableView.tsx` (~:681) with the ⌘-click bypass. Collection-owned; Sets proxy the parent's value.

- **B-2:** [confirmed] Per-source routing: **sidebar rows follow the Collection's `open_in` config** (to build — the sidebar click site gets the same branch); **NavWindow has its own override** — its own preview toggle (the Navigation.md:59 deferred "preview mode toggle" becomes real) that wins over the Collection's setting for NavWindow-originated opens. [assumed] The override's control lives in the NavWindow's own chrome; exact placement is design-stage.

- **B-6:** [confirmed] Connections-in-preview is **core** (Nathan: "that has to be in it"): a user config making inline `[[Connection]]` clicks open the target as a preview instead of navigating. Grounded mechanism: the config is a **`Personalization` key** — it rides the existing free read path (`settings.json` → `tree.personalization` → the store) with `main/settings.ts`'s serialized RMW as the write; the **branch lives at each `ConnectionsApi` construction site** (PageView, BlockSurface, PreviewWindow — where `open` is bound), not inside the CM6 handler. [assumed] Its Settings UI surface is a SettingsPane row; default off until toggled.

- **B-7:** [confirmed] **Connections hover-card** (Nathan: "Obsidian does this great"): hovering a `[[Connection]]` summons a **dropdown pane of the page itself — scrollable, never editable**. A second, lighter surface distinct from the preview window (PickerMenu positioning + read-only PageEmbed). **This phase ships the trigger + a blank dropdown pane** (Nathan's call — interaction testing + the data-level role); the embedded-page UIX lands post-plan. Grounded build items (the "mouseover slot" is greenfield): a new CM6 `mouseover`/`mouseout` handler mirroring the click chain, a **hover-intent delay knob**, the hovered link's client rect for anchoring, and a `hover(page, rect)` slot on `ConnectionsApi`. [assumed] Placeholder dismiss for this phase: pointer-leave with a grace window + Escape; full mechanics land with the embed UIX.

- **B-3:** [confirmed] "Open in New Tab" (the context-menu action) always bypasses the preview — it's an explicit full-page ask; the preview never has an app tab.

- **B-4:** [confirmed] The NavWindow "peek" (ratified tab-neutral) is the NavWindow flavor's page tab (H-2/I-4): a row opened in preview becomes a tab beside the map tab. The deferred "preview mode toggle" is B-2's override.

- **B-5:** [confirmed] Promotion: the toolbar's **fullscreen** button (F-1) opens the page for real — routes through the normal `select`, closes the preview, and rides the A-4 engulf animation.

#### C — Content & Editability

- **C-1:** [assumed] The preview renders through the G-11 `PageEmbed` seam — a real CM6 portal, full decorations, not a dumbed-down renderer. The seam's parked header chrome means the preview needs its own lightweight header treatment (title at minimum; banner handling is a design call).

- **C-2:** [confirmed] **Fully editable** — the preview is a working surface, not a glance. Rides the seam's existing edit flip + debounced autosave.

- **C-3:** [confirmed] Same-file double-writer: **non-issue by reachability** (Nathan's call) — the sidebar can't re-open the already-open page, and NavWindow interactions on the current page open nothing new, so the main-pane + preview same-page state doesn't arise through normal triggers. The one residual path (in-preview wiki-nav landing on the main-pane's page) inherits the contract block-surface embeds already live under — `PageView.tsx:44` + `PageEmbed.tsx:53` are both debounced last-write-wins writers, no live cross-sync. No guard built.

- **C-4:** [confirmed] **The preview keys PageEmbed by path** (`key={path}` → remount per page). Grounded hazard: PageEmbed's pending autosave flushes to the *current* `path` prop (`PageEmbed.tsx:53`), and block surfaces never swap the path on a mounted embed — but the preview does (overtake, wiki-nav). An in-place swap would aim the outgoing page's unsaved body at the incoming page's file; keying by path makes the unmount flush fire with the outgoing closure, writing to the correct file.

- **C-5:** [assumed] PageEmbed has no watcher subscription — the preview's view of *external* edits (main pane, parallel process) is stale until the page reloads in it. Accepted for the core alongside C-3's last-write-wins; a live-refresh subscription is a Prospect-grade hardening.

#### D — Lifecycle, Focus & Layering

- **D-1:** [confirmed] Tab-neutral means **app-level state is untouched**: the preview never reads or writes the app's `selection`, `tabs`, history, recents, or warm entries. The preview owns its **own** slice (the `previewTabs` model, its active-detail state, its warm keys — H-11), invisible to the app-tab system.

- **D-2:** [confirmed] **Scope single-preview only** — one page-preview window; a new summon overtakes (swaps to the new origin's tab set, H-3). The not-foreclose seam for the multi-preview A-B is **already satisfied and stays this small**: the window reads its target as a prop and the store holds one swappable slot — pluralizing the slot later is the entire upgrade. No plural rendering, z-arbitration, or N-window machinery ships now.

- **D-8:** [confirmed] **One floating window total, across both flavors** — the NavWindow flavor and a page-preview window can never coexist; summoning one swaps the other out (both restore losslessly from H-3's durable tab sets). Inside the windows, the only preview-summoning surfaces are: NavWindow rows (add a tab in place) and connection links inside a preview (add a tab, H-1). A PagePreview has no other navigable surface.

- **D-3:** [assumed] Non-modal, no focus steal (the NavWindow precedent): opening a preview doesn't blur the editor behind it; its own search-less chrome takes focus only when clicked into.

- **D-4:** [confirmed] Escape layering, topmost-first (shipped): open picker/menu (defaultPrevented) → inspector → the floating window. Clicking outside never dismisses — window behavior, per A-1.

- **D-5:** [confirmed] Z-order (verified in the shell): floating windows at z 1000, PickerMenu popups at 1100 — pickers opened from inside a preview layer correctly. The two floating windows never coexist (D-8), so they share the z.

- **D-6:** [confirmed] Tree-push reconciliation, by page id: `applyTree` gains a preview branch — **re-path on rename/move; on delete, close the preview and discard the pending autosave** (a dead path is never written). Ships immediately as a shell guard for `previewTarget`; the tab phases extend the same reconcile to the **active origin's tab set** on live pushes, and to **cold per-origin sets lazily at summon** (a `reconcileTabs`-equivalent runs on every restore before the set is shown — the accepted staleness window is a cold set between pushes).

- **D-9:** [confirmed] **Nexus adopt closes the preview** — `openVia` clears `previewTarget` at adopt START (the unmount flush lands the pending body under the OLD root) and the post-adopt state clear includes it. Without this, the preview survives the switch showing the old nexus's page and its debounced autosave lands under the new root. Ships immediately as a shell guard.

- **D-7:** [confirmed] **NavWindow and PagePreview unify their open-in-size defaults** — one shared default geometry for the floating chrome. Per-session persistence may *differ* per flavor (each remembers its own size/position separately); module-scoped like NavWindow's `geo`, nothing on disk.

#### F — Chrome, Toolbar & Titles

- **F-1:** [confirmed, settled live] The toolbar's inventory AND placement: **scan** (Open Full Page / promote) at the window's top-LEFT; the **tab bar** (H — hosts the single-tab centered title, H-9) centered; right cluster **settings (`sliders-horizontal`) · inspector (`panel-right`) · X right-most**. The glyph row aligns to the inspector's box (padding tracks the pane inset). **Ride scope: only the settings + inspector pair flows on the `--io` swallow; scan and the X hold home.** No chevrons anywhere.

- **F-4:** [confirmed] **One tab-motion source: NavWindow + Toolbar + PagePreview all DRY from `tabBar.css`.** Switching preview/NavWindow tabs uses the *same* tab-bar and detail slide animations the app tabs use — hover X, tab-label-color-slide, tab open/close motion, the directional view slide. No parallel keyframes anywhere.

- **F-5:** [confirmed] Flavor-difference icons animate on the tab slide: the right-side icons that differ between the NavWindow flavor and a preview tab **slide in/out with the tab motion** — left-side icons enter from the left, right-side from the right — falling behind / emerging from the **shared X's right-most position**. (The pane-push half of this law lives in G-4 — one mechanism, written once.)

- **F-6:** [confirmed] The trio inside the preview renders **bare buttons on the frost (`glass={false}`)** — real liquid glass inside a `position: fixed`, scale-animated ancestor is exactly the case `ToolbarTrio.tsx` documents as rendering soft and re-initing on mount. The glass-swap *animation* (G-1) is unaffected; only the material mode changes.

- **F-7:** [confirmed] In the NavWindow flavor, the search bar's row **nudges down to make room for the tab strip only when more than one tab is open** — a single-tab (NavWindow-only) state keeps today's exact layout. The re-height **animates on `--ease-standard`** like everything else; no snap.

- **F-2:** [confirmed] In-line titles, two states. **With banner:** banner + title heading render as usual — nothing special. **Without banner:** the page body starts with no heading-divider, and the title renders **in the toolbar area** as a filepath breadcrumb — `Collection › Set › Page Name` — **two-tone** (Nathan's correction): the trail reads `label-tertiary`, the page crumb (icon + name) reads `label-control`; caption-ramp font sized independently of the toolbar glyphs, crumb glyphs at 11.

- **F-3:** [assumed] Embedded zoom: reuse the existing G-10 knob — `EMBED_SCALE`/`EMBED_ZOOM` in `Embeds/embedScale.ts`, already consumed by PageEmbed. One knob, no new zoom system; whether the preview wants its own value through that knob is a design-stage tune.

#### G — Preview Inspector

- **G-1:** [confirmed] The preview carries its **own inspector, in core** — separate from the DetailView inspector — as the front-matter/metadata editing surface, the mechanism the Swift build's front-matter inspector used. It opens and closes on the preview surface **animating and looking exactly as the real inspector does**: the ToolbarTrio glass-swap (`ToolbarTrio.tsx` — the glass pill voids as the inspector swallows the trio, icons ride onto the inspector's glass, driven by `--io` in toolbar.css) and the same swap animation, reused verbatim.

- **G-3:** [confirmed] **One side-pane component across both flavors** (Nathan's closing law): the NavWindow's sidebar/rail and the PagePreview's inspector are **the same component** — the shared piece is the pane **shell** (the GlassWindow + `state-muted` veil, the resize edge with clamps, the slide, the G-4 push hook), mounted left in the NavWindow flavor and right in the PagePreview flavor, with each flavor **injecting its own body** (favorites rail vs front-matter inspector). No parallel pane implementations. The shell's open flag + width key **per window id** (the geometry-store pattern — never a bare module singleton; the shipped `inspectorW` module var migrates in). The NavWindow's `geo.rail` width migrates into the same component's state at its rebase.

- **G-4:** [confirmed] **The tab-slide pushes the side pane** — THE pane-push law, both flavors, written once: when a tab change's view slide lands, it visually collides with the open side pane and pushes it aside (sidebar in the NavWindow flavor, inspector in the PagePreview flavor), reading as one continuous motion. Candidate primitive: `PaneSlider` (measure-then-flip); verify it composes into the collide-and-push read before committing — else the pane rides the same slide stamp directly.

- **G-2:** [confirmed] The inspector's layout gets a **Figma design pass**; the Swift build's inspector (archived at `The Studio/Archive/Pommora`) is the reference — it already mostly looks the way Nathan wants.

#### H — The Tab System (in-preview navigation is tabs, not history)

The preview is **semi-multi-tabbed — a mini-app**. There are **no back/forward chevrons anywhere**; tabs replaced them. App-level tab history stays untouched (the tab-neutral law, D-1, holds throughout).

- **H-1:** [confirmed] A wiki-link ([[Connection]]) clicked inside a preview opens its target as a **tab in the same window** — never a second window, never a main-pane navigate. Connection navigation is the *only* way a page-preview grows tabs. [assumed] Clicks **dedup** like the app's `openTab`: a link to a page already open as a preview tab focuses that tab; H-7's no-fire covers the page behind the window.

- **H-2:** [confirmed] Two summon flavors share one chrome. **NavWindow-flavored:** tab 1 is the NavWindow itself — perma-pinned left-most, non-orderable, icon-only with the **map icon** (the app-level pinned-tab look); page-opens from it add tabs beside it, and switching to a page tab slides the NavWindow's sidebar closed (G-4). **PagePreview-flavored:** tab 1 is the summoned page. Grounded: the map tab needs its **own sentinel target kind** in the shared tab model (the `Tab.target` union has no gallery kind today), exempt from the warm cache (the gallery re-derives live, cheaply), with a defined sidecar representation. [assumed] The NavWindow body (search + rail + gallery) **is the map tab's content** — page tabs swap it away whole; the tab strip is persistent window chrome, and F-7's search-row nudge applies within the map tab's own layout.

- **H-3:** [confirmed] Persistence: **both flavors persist multi-session.** NavWindow keeps its one tab set; page-previews keep **per-origin tab sets** — keyed by the origin page, so summoning page X restores X's remembered connection-opened tabs + order while page Y keeps its own. (Upgraded from per-session once the cost proved trivial — Nathan: "a real Pommora plus, no other app does it.") Tab *lists* are durable; warm editor state stays session-scoped (H-8).

- **H-4:** [confirmed] Icon normalization: a page tab in the NavWindow flavor whose icon is *also* the map icon renders its **type icon** instead (file-text, grid, …) so nothing masquerades as the pinned NavWindow tab. Known accepted edge: a type whose icon is itself set to map — not worth fighting.

- **H-5:** [confirmed] Neither flavor allows pinned tabs, and neither allows manual tab creation (no hover `+`). Tabs are born from navigation only.

- **H-6:** [confirmed] Closing the origin tab never closes the window: the left-most surviving tab becomes the window's new parent/identity. The window closes only when its last tab does. [assumed] Storage keying on re-parent: the on-disk set **renames its key to the new origin** (old key retired) — a later summon of the retired origin starts a fresh `[origin]` set; the per-origin record also carries its **active-tab pointer**.

- **H-7:** [confirmed] A connection click targeting the page active **behind** the preview (the main pane's current page) simply doesn't fire — it's already in view.

- **H-8:** [confirmed] **Warm for both flavors** — warmth is nearly free (`warmCache.ts`: serialized editor state + scrollTop + PageDetail, KB-scale, no mounted editors). Warm state is session-scoped; the durable layer is the tab lists (H-3). Grounded mechanism (PageEmbed alone can't warm — it refetches per mount and renders blank while loading): **the seam gains opt-in warm hooks** like the full editor's `warm` prop — capture on unmount / restore on mount, keyed by **preview-tab id**, with the cached PageDetail making the mount body-synchronous. `key={path}` stays (C-4); warmth comes from restore-on-mount, not kept mounts.

- **H-9:** [confirmed] The title ↔ tab morph, with its motion: a single-tab bannerless preview shows the centered breadcrumb (F-2) in the shared tab bar; on the second tab's birth, the **new tab enters from the right** (appended after the origin tab, the standard tab-open animation) while the **centered title slides left, collapsing into a standard icon-leading tab in the normal left-aligned strip** — one motion, all from the shared tab animations (F-4). [assumed] The **banner'd** origin (no toolbar title at rest) simply grows its standard icon-leading tab (label = page title) via the standard tab-open animation — the slide-collapse is the bannerless-only variant.

- **H-10:** [confirmed] Storage: **one synced sidecar** (e.g. `.nexus/page-previews.json`) on the `tabs.json` pattern — a `paths.ts` entry, IPC pair with the `adopting` guard, preload bridge, drain hookups at nexus-switch + quit. It holds the NavWindow tab set, the per-origin preview tab sets + order + per-origin active pointers (H-3/H-6), and **which preview is open** (Nathan's spec; [assumed] recorded for lossless D-8 swaps — no auto-summon on cold launch, matching the NavWindow's behavior). [assumed] The io module extracts a **shared debounced-sidecar helper** from the near-identical `tabsState.ts`/`navState.ts` machines rather than minting a third copy. **Every restore reconciles against the live tree before the set is shown** (D-6's `reconcileTabs`-equivalent — drop dead paths, re-path renamed ones); the `tabs.json` pattern alone can't provide this (it has no cold sets).

- **H-11:** [confirmed] Reuse spine (grounded): the `Tabs/tabsModel.ts` pure-function layer and the `Tab` record are reusable wholesale by a `previewTabs` slice — which needs its **own active-detail state** plus its own copies of the switch orchestration the store keeps outside tabsModel: a **preview slide stamp** (the global `navSlide` is one app-wide slot), **preview-scoped fetch seq + freeze** (the module singletons fence the main pane), **preview warm keys** (H-8), and a preview MRU. The pins derivation drops (H-5). Wiki-clicks route by swapping the `open` closure at the `ConnectionsApi` construction sites — no PageEmbed changes; the **CM6 click handler gains exactly one branch** (I-19's ⌘-bypass reads `metaKey` and calls an optional bypass slot; the handler is otherwise untouched).

#### I — Interaction Matrix (the meticulous pass — every gesture × every preview state)

**Opens & summons**

- **I-1:** [confirmed] Clicking the already-previewed page's title is a **no-op** — same as the app's existing behavior for selecting the already-selected (the select same-target gate). No pulse, nothing.
- **I-2:** [confirmed] Overtake is a keyed remount (C-4): the outgoing page's pending autosave flushes to its own file before the incoming page mounts.
- **I-3:** [assumed] Embedded views route too: a view tile on a SurfacePM page shares A-7's navigate, so its title-clicks honor the same `open_in` routing — the branch lives at the navigate, not per-surface.
- **I-4:** [confirmed] The NavWindow never "closes into" a preview — it **is tab 1** of its own flavor (H-2): opening a page from it adds a tab beside it and slides its sidebar away (F-5); clicking the map tab is the return. No summon-close, no reopen mechanics.
- **I-5:** [assumed] Rapid double title-click is idempotent — the second click hits the already-open-on-this-page guard (whatever I-1 resolves to).
- **I-6:** [assumed] First-open placement is a design-stage call (centered default is the hypothesis); thereafter D-7's session geometry holds through overtakes — contents swap, the window doesn't jump.

**The world changes while it's open**

- **I-7:** [assumed] The preview outlives the main pane's life: tab switches, Back/Forward, selection changes, view changes — none close or disturb it (the tab-neutral law's inverse).
- **I-8:** [assumed] Flipping the Collection's `open_in` while a preview is open doesn't retroactively close it — routing is evaluated at open time.
- **I-9:** [confirmed] "Open in New Tab" on the previewed page stays allowed and creates the accepted double-editor state (C-3's contract); the preview's stale view of the other editor's writes is C-5's accepted staleness.
- **I-10:** [assumed] Preview edits are visible when that page's tab activates — tab activation re-fetches (the pause-on-change fetch-then-swap), so the warm cache never paints a pre-edit body for long. Planner-stage verify.
- **I-11:** [assumed] App-window resize reclamps the preview into bounds (NavWindow parity — verify NavWindow actually reclamps at planning; if it doesn't, both get it or neither).
- **I-12:** [assumed] Tree push mid-edit composes with D-6: rename/move re-aims the pending autosave at the new path (rename-follow by id); delete closes the preview and *discards* the pending write — a dead path is never written.

**Gestures inside the preview**

- **I-13:** [confirmed] The preview's title is **editable** — a rename from inside the preview renames the file and the preview self-follows (D-6's rename-follow applied to itself).
- **I-14:** [confirmed] The banner in the preview is **changeable/removable as always**. (Banner *repositioning* doesn't exist anywhere in the app yet — it's an app-wide follow-up prospect, not this feature's business.)
- **I-15:** [confirmed] The Settings button is **the same settings component the Page's toolbar trio will use** — one shared button, not a preview-specific menu. Its contents are that component's own pending design; this spec just mounts it.
- **I-16:** [assumed] Window-drag surfaces: bare toolbar areas + the title breadcrumb drag the window (the NavWindow `DRAG_SURFACES` allow-list pattern); buttons and the editor never do.
- **I-17:** [assumed] Block DND works inside the preview; drag math reads the *computed* zoom, not the token — the embed is scaled (F-3), the exact trap TableView already documents for `--zoom`-scaled tiles.
- **I-18:** [assumed] Scroll/caret follow the SurfacePM laws: the preview owns its wheel when hovered, caret-priority scrolling inside the editor, text-selection autoscroll near edges stays inside the preview.
- **I-19:** [confirmed] ⌘-click is the explicit full-page bypass on preview-routed clicks (connections with B-6 on, preview-collection titles) — it opens a **new app tab**. [assumed] From inside a preview it's **additive**: the preview stays open (unlike I-20's promotion). Connections need the one-branch handler change (H-11).

- **I-25:** [confirmed, SHIPPED] **"Open in Preview" is a right-click action** on wikilinks, navigation items, and sidebar page rows. Wikilinks pop a **native** menu (Nathan's call): the CM6 `contextmenu` handler resolves the link and hands it to the host's `ConnectionsApi.menu` hook → `conn-menu` IPC → main pops at the cursor and resolves the action (the popCellMenu contract). Sidebar page rows gained the item in the existing native `contextMenu` (an `open-in-preview` push-back, the open-in-new-tab contract). [assumed — flagged for Nathan's one-line confirm] Nav rows/cards keep their deliberate in-renderer NavRowMenu (a pre-existing ratified surface) with the item added there; his "right-click needs to be native" was read as scoping the new wikilink menu, not converting the NavRowMenu.

- **I-26:** [confirmed] The preview toolbar is a **floating layer within the content** — content scrolls beneath the transparent strip and dissolves on the shared edge-fade sized to the toolbar height; no seam anywhere (the pane is one material edge-to-edge, A-3). The scroll model that makes it work: the editor chain grows to content, the body is the one scroller, and the editor's scroller drops its `overscroll-behavior: none` inside the preview (a non-overflowing scroll container with `none` eats the wheel).

**Keyboard & focus**

- **I-20:** [confirmed] No preview-scoped keyboard commands beyond one: **⌘N while focused in a preview opens the active preview tab's page in a new app tab** — a promotion variant that closes the preview (Nathan's yes); [assumed] with multiple preview tabs it closes just the promoted tab, the window only when it was the last; **no-op when the map tab is active** (a gallery has no page — the promote button disables the same way). ⌘W keeps its normal meaning (the app tab), Escape keeps D-4's (the topmost surface).
- **I-21:** [assumed] Escape order within the preview: open inspector closes first, then the preview — topmost-first (D-4), one press never kills two layers.
- **I-22:** [assumed] Editing shortcuts (⌘B, etc.) go to whichever editor holds focus; app-global shortcuts pass through — the preview never traps focus (D-3).

**Close & promote**

- **I-23:** [assumed] Close and promote both flush pending edits first (the seam's existing exit-edit flush); promote's engulf animates the preview rect into the detail pane rect — treatment design-stage.
- **I-24:** [assumed] App quit/reload rides the existing unmount flush; nothing new needed.

#### E — Sweep Results (matrix applied; anything without evidence is logged above)

- Happy path → Success Criteria. Validation → `openPage` error envelope renders an error state in the preview, never a crash [assumed]. Persistence → `open_in` shipped with legacy coercion; B-6 rides Personalization; the tab sets ride the H-10 sidecar (reconciled on every restore). Failure recovery → D-6 (dead path) + D-9 (nexus adopt) + error envelope. Concurrency → C-3 (closed); the preview inspector's front-matter writes ride the existing property-update path, the same reachability argument covering a main-pane + preview inspector pair [assumed]. Interaction inverses → open↔dismiss (D-4), enter-edit↔click-out (the seam's existing contract), promote (B-5), inspector open↔close (G-1). Singleton composition, two distinct click contexts: a **main-editor** `[[Connection]]` click (B-6 on) or a title-click while a preview is open is a *new summon* → **overtakes** (swaps to the new origin's tab set, D-2); an **in-preview** wiki-click is H-1's *new tab* (dedup-focus). Reveal-stays-reachable → promotion chrome must not be hover-revealed-then-unreachable; the title↔tab morph (H-9) must not reflow the toolbar out from under the pointer [assumed]. Local vs global gestures → preview scroll owns its wheel when hovered; ⌘-shortcuts pass through (no focus trap, D-3). Performance → one mounted CM6 editor per open preview window (inactive tabs stay unmounted, warm via H-8); the preview's growing editor renders the full doc (no viewport virtualization) — the huge-page stance is a plan-stage decision. Z-order → D-5. Nexus adopt → D-9.

### Core (must-have; the plan SEQUENCES page-preview phases first, the NavWindow flavor as later phases)

- SHIPPED: the routing branch at A-7 → a **single page-preview window** on the shared floating chrome (A-1/A-3, D-2/D-7/D-8), the toolbar + title + inspector shell (F-1/F-2), the right-click actions (I-25).
- **The tab system** (H): wiki-links open as deduped tabs in-window; the title↔tab morph (H-9, banner'd variant included); the NavWindow flavor with its map-tab sentinel + body-as-tab-content + sidebar push (H-2, G-4); all tab motion DRY'd from `tabBar.css` (F-4/F-5).
- **Persistence**: the H-10 sidecar — per-origin multi-session sets + active pointers + open state, re-key on re-parent (H-6), reconcile-on-restore; warm for both via the seam's opt-in warm hooks (H-8).
- **The preview slice** (H-11): tabsModel reuse + its own active-detail, slide stamp, fetch fences, MRU.
- **The unified side-pane component** (G-3) with front-matter editing live in the inspector body (G-1), the ToolbarTrio glass-swap treatment.
- **Connections-in-preview** (B-6, Personalization key + SettingsPane row), plus the **hover-card trigger with a blank pane** (B-7 — embed UIX post-plan).
- Promote-to-full via the A-4 engulf with its close-reason + rect handoff (+ ⌘N and ⌘-click variants, I-19/I-20); tree-push + adopt reconcile (D-6/D-9 — guards shipped, tab-set extension in-plan); per-source routing (B-2); tab-neutral throughout (D-1).

#### Prospects (allowed later, not now)

- **Multiple simultaneous previews** — the core's not-foreclose seam (one swappable store slot, target-as-prop) is the entire upgrade path; multi-preview gets **A-B tested** post-ship. First in line.
- **The hover-card's embedded-page UIX** (B-7's payload — the core ships trigger + blank pane; the read-only PageEmbed content + full hover mechanics land here).
- **Preview live-refresh** (C-5) — a watcher subscription so external edits repaint an open preview.
- **Banner repositioning** — a **core follow-up prospect** (Nathan's priority): doesn't exist anywhere in the app yet; lands in main views and previews together.
- **Agenda entry preview** — Navigation.md routes Agenda search hits to "a placeholder preview window that belongs to Agenda's feature"; this surface is its natural host later.
- **Drag a preview out into its own OS window** — the multi-window seams exist by design; far future.

#### Out of Scope

- QuickLook/OS-level previews (PRD: requires a companion Swift bundle — a different feature entirely).
- Body/full-text search, NavWindow content decisions — separate pending items.

#### Considered & Rejected

- **In-pane slide-over** (A-1 shape 3) — rejected: it consumes the main pane the preview exists to protect.
- **Anchored compact card** (A-1 shape 2, the PickerMenu chassis) — rejected in favor of the floating window; the ephemeral read-leaning card fights the fully-editable, park-it-beside-your-work intent (C-2).
- **A new double-writer guard for C-3** — not built: PageView + PageEmbed already share the last-write-wins contract on block surfaces; the preview inherits rather than hardens (Nathan's nod given — non-issue by reachability).

#### Reconciliation (docs that go false when this ships)

- [[Collections]] :28/:63 + [[Pages]] :23/:47 + [[PommoraPRD]] :110/:196 — still say `compact | window` and "routing is unwired/Pending"; values renamed `full-page | page-preview` (History.md:67) and the routing lands with this feature. Rewrite as durable truth.
- [[Navigation]] :59 — the deferred "in-pane preview mode" line retires into the shipped behavior.
- `SettingsPane.tsx:110` — the B-8 parked comment retires.
- [[Interaction]] — gains the **floating-window in/out** as a named motion primitive (A-2) and the engulf (A-4); a few lines, not a section.
- Implementation adjacencies (grounded): **(1)** `useFloatingWindow` is SHIPPED (drag-surfaces prop + per-window geometry map); the remainder is the **NavWindow rebase** onto it (which must first grow the rail/x-knob drag mode) and an injected close callback — this lands in the NavWindow-flavor phases, not as pre-work. **(2)** `tabBar.css` splits: the pure motion layer (`.tab`, `.tab-seg`, `.tab-x`, nav-slide keyframes — store-free) becomes container-agnostic; the toolbar skin (app-region, the `:has()` reveal chain, `winDragBy`) stays toolbar-only. The `TabBar.tsx` presentational-strip extraction happens only as far as the preview strip needs — no opportunistic TabBar rewrite. **(3)** the preview's orchestration parallels are enumerated in H-11. **(4)** the side-pane component migration (G-3) subsumes the shipped `.pgpreview-inspector` and, at the NavWindow rebase, `geo.rail`.

#### Lessons

- **Back-propagate pivots immediately:** the round-1 attack's dominant finding class was the tab-model pivot living in the decision blocks while Frame/Success/Core/Sweep still asserted singleton-era law — a planner builds off whichever section they read first. When a decision flips, sweep the summary sections in the same edit.
- **"Clone the pattern" isn't a spec when the shape changes:** `tabs.json`'s pattern carries no cold-set reconcile because it has no cold sets — per-origin storage needed a mechanism the cloned pattern structurally lacks. Name what the new shape needs beyond the template.
