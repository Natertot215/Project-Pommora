## Page Previews — Decision Log

### Frame

- **Purpose:** Ship the parked "B-8 preview surface" — the routing target for `open_in: 'page-preview'`, letting a Collection's Pages open as a lightweight preview instead of replacing the main pane.
- **Core Value:** A Page can be *peeked* — read (and possibly edited) in place — without navigating: no selection change, no tab churn, no Back/Forward pollution.
- **Success Criteria:** A `page-preview` Collection's title click opens the preview; dismissing it lands you exactly where you were; the main pane, tabs, and history are untouched throughout.

### Status — Continuation

**Interrogation is closed** — the tab-model pivot landed and every question resolved: one floating window total across both flavors (D-8), multi-session durable tab sets for both — per-origin for page-previews (H-3), warm for both (H-8), one sidecar for all durable state (H-10), the title-collapse motion specced (H-9), origin-close re-parenting (H-6). Both grounding reuse maps are folded (chrome extraction points, tabBar.css split, tabsModel reuse, ConnectionsApi closure swap, `--bg-window` material, the liquid-glass-in-transformed-ancestor constraint → F-6). **Early-build directive is live:** the window shell + tab strip get built now (shared chrome hook + `PagePreview/`) ahead of functionality so Nathan can live-drive UIX — the brainstorm's no-code gate is explicitly waived for the chrome shell only. Remaining phases: self-review → adversarial review → planning + /handoff.

### Sources

- `Pommora/src/shared/types.ts:193` — `OpenIn = 'full-page' | 'page-preview'`; the type's own comment says "full-view or a hovering preview window. Collection-owned."
- `Pommora/src/shared/schemas.ts:23` — `OPEN_IN_LEGACY` coerces Swift-era `window | compact` on read.
- `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx:110` — "Open In has no payload target until the preview surface ships (B-8)" — the config UI exists and writes; nothing routes on it.
- `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx:671` — the ONLY navigate (A-7): title-cell click → `select(...)` unconditionally; no `openIn` branch anywhere in the renderer. `:957` context-menu `title:newtab`.
- `Pommora/src/main/crud/containerConfig.ts:39` — a Set-level `open_in` write is refused (Collection-owned; Sets proxy).
- `Pommora/src/renderer/src/Embeds/PageEmbed.tsx:19` — THE G-11 seam: a real Page as a read-only CM6 portal, in-place edit flip (no remount), 400ms-debounced autosave to the page's own file via `openPage`/`updatePageBody` directly — zero store/nav involvement. Props: `path, editing, onBeginEdit, connections, locked`. Header chrome (banner/title) parked.
- `Pommora/src/main/index.ts:619` — `page:open` is a pure read; `store.ts:1199 reloadPage` proves navigation-free reads are established.
- `Pommora/src/renderer/src/Detail/PageView.tsx:44` + `PageEmbed.tsx:53` — the only two page-body writers; both debounced `updatePageBody`, last-write-wins, no live cross-sync — the existing contract C-3 inherits.
- `Pommora/src/renderer/src/Embeds/embedScale.ts` — the G-10 zoom knob (`EMBED_SCALE`/`EMBED_ZOOM`), the F-3 seam.
- `Pommora/src/renderer/src/Toolbar/ToolbarTrio.tsx` — the inspector-toggle glass-swap G-1 reuses: the glass pill voids as the inspector swallows the trio, icons ride onto the inspector's glass, driven by `--io` (toolbar.css).
- `Pommora/src/main/settings.ts` — `.nexus/settings.json` handling: the serialized read-modify-write primitive (foreign keys preserved) the B-6 config writes through.
- `Pommora/src/main/index.ts:447` + `paths.ts:64` — app tabs persist via the synced `tabs.json` sidecar; the pattern H-3's NavWindow tabs follow.
- `Pommora/src/renderer/src/Tabs/warmCache.ts` — in-memory map of serialized editor state + scrollTop + PageDetail, 20-cap per tab, KB-scale; proves warmth is cheap (H-8) — mounted editors are the cost, not cached state.
- `Pommora/src/renderer/src/NavWindow/NavWindow.tsx:139` — the floating-chrome reference: pointer-captured move/rail/corner-resize engine (`startDrag`), module-scoped geometry persistence, `useExitPresence`, bare-surface drag allow-list (`DRAG_SURFACES`), Escape-close skipping `defaultPrevented`. Inlined in NavWindow, not extracted.
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

- **A-2:** [assumed] Open/close motion: the Bloom primitive (`dropdown-menu` + `useExitPresence`), per the Interaction.md one-DRY-source law — no bespoke keyframes.

- **A-3:** [confirmed] Material: the **window-background** treatment (Nathan's call) — the preview reads as a mini window, not a frost pane; exact token/recipe lands at design stage against `design-system/tokens`.

- **A-4:** [confirmed] Promote-to-full animation: opening the previewed page in the full view **zooms/engulfs** — the preview expands into the detail pane rather than blinking away. A new motion distinct from Bloom; its exact treatment is design-stage and must reconcile with the Interaction.md one-source law (a named primitive, not ad-hoc keyframes).

#### B — Triggers & Routing

- **B-1:** [confirmed] The routing branch lives at the title-click navigate (TableView A-7, the app's only navigate): `open_in === 'page-preview'` → open preview instead of `select`. Collection-owned; Sets proxy the parent's value.

- **B-2:** [confirmed] Per-source routing: **sidebar rows follow the Collection's `open_in` config**; **NavWindow has its own override** — its own preview toggle (the Navigation.md:59 deferred "preview mode toggle" becomes real) that wins over the Collection's setting for NavWindow-originated opens.

- **B-6:** [confirmed] Connections-in-preview is **core** (Nathan: "that has to be in it"): a user config making inline `[[Connection]]` clicks open the target as a preview instead of navigating — `connections.ts:16`'s `api.open` slot is the branch point. The config lives in the nexus **`.nexus/settings.json`**, written through `main/settings.ts`'s serialized read-modify-write primitive (foreign keys preserved).

- **B-7:** [confirmed] **Connections hover-card** (Nathan: "Obsidian does this great"): hovering a `[[Connection]]` summons a **dropdown pane of the page itself — scrollable, never editable**. A second, lighter surface distinct from the preview window: the anchored-card chassis rejected for A-1 finds its home here (PickerMenu positioning + read-only PageEmbed). **This phase ships the trigger + a blank dropdown pane** — the interaction mechanics and its data-level role — while the embedded-page UIX inside it lands post-plan.

- **B-3:** [confirmed] "Open in New Tab" (the context-menu action) always bypasses the preview — it's an explicit full-page ask; the preview never has a tab.

- **B-4:** [confirmed] The NavWindow peek (ratified tab-neutral) is this same surface summoned from a NavWindow row; its deferred "preview mode toggle" ties to the page's `open_in`.

- **B-5:** [confirmed] Promotion: the toolbar's **fullscreen** button (F-1) opens the page for real — routes through the normal `select`, closes the preview, and rides the A-4 engulf animation.

#### C — Content & Editability

- **C-1:** [assumed] The preview renders through the G-11 `PageEmbed` seam — a real CM6 portal, full decorations, not a dumbed-down renderer. The seam's parked header chrome means the preview needs its own lightweight header treatment (title at minimum; banner handling is a design call).

- **C-2:** [confirmed] **Fully editable** — the preview is a working surface, not a glance. Rides the seam's existing edit flip + debounced autosave.

- **C-3:** [confirmed] Same-file double-writer: **non-issue by reachability** (Nathan's call) — the sidebar can't re-open the already-open page, and NavWindow interactions on the current page open nothing new, so the main-pane + preview same-page state doesn't arise through normal triggers. The one residual path (in-preview wiki-nav landing on the main-pane's page) inherits the contract block-surface embeds already live under — `PageView.tsx:44` + `PageEmbed.tsx:53` are both debounced last-write-wins writers, no live cross-sync. No guard built.

- **C-4:** [confirmed] **The preview keys PageEmbed by path** (`key={path}` → remount per page). Grounded hazard: PageEmbed's pending autosave flushes to the *current* `path` prop (`PageEmbed.tsx:53`), and block surfaces never swap the path on a mounted embed — but the preview does (overtake, wiki-nav). An in-place swap would aim the outgoing page's unsaved body at the incoming page's file; keying by path makes the unmount flush fire with the outgoing closure, writing to the correct file.

- **C-5:** [assumed] PageEmbed has no watcher subscription — the preview's view of *external* edits (main pane, parallel process) is stale until the page reloads in it. Accepted for the core alongside C-3's last-write-wins; a live-refresh subscription is a Prospect-grade hardening.

#### D — Lifecycle, Focus & Layering

- **D-1:** [confirmed] Tab-neutral by construction: the preview never touches `selection`, `tabs`, history, or the warm cache — it reads via `openPage` directly (the PageEmbed pattern). No store slice beyond an open/target flag.

- **D-2:** [confirmed] **Scope single-preview only** — one page-preview window; a new summon overtakes (swaps to the new origin's tab set, H-3). But the **plumbing is built for multiple** (the single-window-now/multi-window-ready posture) so multi-preview can be **A-B tested** post-ship without a rewrite. UX ships singleton; architecture ships plural.

- **D-8:** [confirmed] **One floating window total, across both flavors** — the NavWindow flavor and a page-preview window can never coexist; summoning one swaps the other out (both restore losslessly from H-3's durable tab sets). Inside the windows, the only preview-summoning surfaces are: NavWindow rows (add a tab in place) and connection links inside a preview (add a tab, H-1). A PagePreview has no other navigable surface.

- **D-3:** [assumed] Non-modal, no focus steal (the NavWindow precedent): opening a preview doesn't blur the editor behind it; its own search-less chrome takes focus only when clicked into.

- **D-4:** [open] Escape layering: NavWindow closes on window-level Escape (skipping `defaultPrevented`); a preview needs a defined order (topmost/most-recent surface closes first) so one Escape never kills two surfaces. Also: does clicking outside dismiss (card behavior) or not (window behavior)? — follows A-1.

- **D-5:** [assumed] Z-order: previews sit above the detail pane and BELOW PickerMenu popups (z 1100) so pickers opened from inside a preview layer correctly; relative order vs NavWindow needs a call if both can be open (most-recently-focused on top is the hypothesis).

- **D-6:** [open] Tree-push reconciliation: the previewed page can be renamed/moved/deleted mid-preview (the watcher pushes a new tree). The preview must re-resolve its path (rename-follow, like tabs reconcile) or close gracefully on a dead path — a stale-path autosave would write to the old file. The main-pane precedent is applyTree's reconcile; the preview needs its own tiny version keyed off the page id.

- **D-7:** [confirmed] **NavWindow and PagePreview unify their open-in-size defaults** — one shared default geometry for the floating chrome. Per-session persistence may *differ* per flavor (each remembers its own size/position separately); module-scoped like NavWindow's `geo`, nothing on disk.

#### F — Chrome, Toolbar & Titles

- **F-1:** [confirmed] The toolbar's action inventory: the **tab bar** (H — which also hosts the single-tab centered title, H-9), **fullscreen/promote** (B-5, rides the A-4 engulf), **Exit** (the shared X, right-most), **Inspector** toggle (G), **Settings**. No chevrons (H retired them). Keeping it uncluttered is Figma territory.

- **F-4:** [confirmed] **One tab-motion source: NavWindow + Toolbar + PagePreview all DRY from `tabBar.css`.** Switching preview/NavWindow tabs uses the *same* tab-bar and detail slide animations the app tabs use — hover X, tab-label-color-slide, tab open/close motion, the directional view slide. No parallel keyframes anywhere.

- **F-5:** [confirmed] Flavor-difference icons animate on the tab slide: the right-side icons that differ between the NavWindow flavor and a preview tab **slide in/out with the tab motion** — left-side icons enter from the left, right-side from the right — falling behind / emerging from the **shared X's right-most position**. And in the NavWindow flavor, switching to a page tab slides the NavWindow's sidebar closed: the tab slides in and *pushes the sidebar out in one continuous motion* (candidate primitive: `PaneSlider` — "the one slide primitive every pane rides," measure-then-flip, already composes with `useExitPresence`).

- **F-6:** [confirmed] The trio inside the preview renders **bare buttons on the frost (`glass={false}`)** — real liquid glass inside a `position: fixed`, scale-animated ancestor is exactly the case `ToolbarTrio.tsx` documents as rendering soft and re-initing on mount. The glass-swap *animation* (G-1) is unaffected; only the material mode changes.

- **F-7:** [confirmed] In the NavWindow flavor, the search bar's row **nudges down to make room for the tab strip only when more than one tab is open** — a single-tab (NavWindow-only) state keeps today's exact layout. The re-height **animates on `--ease-standard`** like everything else; no snap.

- **F-2:** [confirmed] In-line titles, two states. **With banner:** banner + title heading render as usual — nothing special. **Without banner:** the page body starts with no heading-divider, and the title renders **in the toolbar area** the way tabs render theirs, as a filepath breadcrumb — `Collection > Set > Page Name` — in the same label color the navigation filepaths use, at **caption** size (for now).

- **F-3:** [assumed] Embedded zoom: reuse the existing G-10 knob — `EMBED_SCALE`/`EMBED_ZOOM` in `Embeds/embedScale.ts`, already consumed by PageEmbed. One knob, no new zoom system; whether the preview wants its own value through that knob is a design-stage tune.

#### G — Preview Inspector

- **G-1:** [confirmed] The preview carries its **own inspector, in core** — separate from the DetailView inspector — as the front-matter/metadata editing surface, the mechanism the Swift build's front-matter inspector used. It opens and closes on the preview surface **animating and looking exactly as the real inspector does**: the ToolbarTrio glass-swap (`ToolbarTrio.tsx` — the glass pill voids as the inspector swallows the trio, icons ride onto the inspector's glass, driven by `--io` in toolbar.css) and the same swap animation, reused verbatim.

- **G-2:** [confirmed] The inspector's layout gets a **Figma design pass**; the Swift build's inspector (archived at `The Studio/Archive/Pommora`) is the reference — it already mostly looks the way Nathan wants.

#### H — The Tab System (in-preview navigation is tabs, not history)

The preview is **semi-multi-tabbed — a mini-app**. There are **no back/forward chevrons anywhere**; tabs replaced them. App-level tab history stays untouched (the tab-neutral law, D-1, holds throughout).

- **H-1:** [confirmed] A wiki-link ([[Connection]]) clicked inside a preview opens its target as a **new tab in the same window** — never a second window, never a main-pane navigate. Connection navigation is the *only* way a page-preview grows tabs.

- **H-2:** [confirmed] Two summon flavors share one chrome. **NavWindow-flavored:** tab 1 is the NavWindow itself — perma-pinned left-most, non-orderable, icon-only with the **map icon** (the app-level pinned-tab look); page-opens from it add tabs beside it, and switching to a page tab slides the NavWindow's sidebar closed (F-5). **PagePreview-flavored:** tab 1 is the summoned page.

- **H-3:** [confirmed] Persistence: **both flavors persist multi-session.** NavWindow keeps its one tab set; page-previews keep **per-origin tab sets** — keyed by the origin page, so summoning page X restores X's remembered connection-opened tabs + order while page Y keeps its own. (Upgraded from per-session once the cost proved trivial — Nathan: "a real Pommora plus, no other app does it.") Tab *lists* are durable; warm editor state stays session-scoped (H-8).

- **H-4:** [confirmed] Icon normalization: a page tab in the NavWindow flavor whose icon is *also* the map icon renders its **type icon** instead (file-text, grid, …) so nothing masquerades as the pinned NavWindow tab. Known accepted edge: a type whose icon is itself set to map — not worth fighting.

- **H-5:** [confirmed] Neither flavor allows pinned tabs, and neither allows manual tab creation (no hover `+`). Tabs are born from navigation only.

- **H-6:** [confirmed] Closing the origin tab never closes the window: the left-most surviving tab becomes the window's new parent/identity (the per-origin tab-set keying re-parents with it). The window closes only when its last tab does.

- **H-7:** [confirmed] A connection click targeting the page active **behind** the preview (the main pane's current page) simply doesn't fire — it's already in view.

- **H-8:** [confirmed] **Warm for both flavors** — the investigation showed warmth is nearly free (`warmCache.ts`: an in-memory map of serialized editor state + scrollTop + PageDetail, 20-cap per tab, KB-scale entries, no mounted editors; mounted CM6 instances are the only real cost, and inactive tabs don't mount). Warm state is session-scoped and dies with the session; the durable layer is the tab lists (H-3).

- **H-9:** [confirmed] The title ↔ tab morph, with its motion: a single-tab bannerless preview shows the centered breadcrumb (F-2) in the shared tab bar; on the second tab's birth, the **new tab enters from the right** (appended after the origin tab, the standard tab-open animation) while the **centered title slides left, collapsing into a standard icon-leading tab in the normal left-aligned strip** — one motion, all from the shared tab animations (F-4).

- **H-10:** [confirmed] Storage: **one synced sidecar** (e.g. `.nexus/page-previews.json`) cloning the `tabs.json` pattern end-to-end — a `paths.ts` entry, an `io/` read/validate/debounced-write/flush module, an IPC pair with the `adopting` guard, preload bridge, drain hookup at nexus-switch + quit. It holds the NavWindow tab set and the per-origin preview tab sets + order (H-3). No main-process session memory needed — durable state is on disk, warm state stays in the renderer.

- **H-11:** [confirmed] Reuse spine (grounded): the `Tabs/tabsModel.ts` pure-function layer and the `Tab` record are stateless and reusable wholesale by a `previewTabs` slice — which needs its **own active-detail state**, never the singular `selection` (the main strip and the preview each want an independent active target). The pins derivation drops (H-5: no pinned tabs). Wiki-clicks route by swapping one closure: `ConnectionsApi` is prop-injected at both consumers, so the preview passes `open: → openPreviewTab(...)` instead of `select(...)` — zero changes to the CM6 click handler or PageEmbed.

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
- **I-19:** [confirmed] ⌘-click is the explicit full-page bypass on preview-routed clicks (connections with B-6 on, preview-collection titles) — it opens a **new app tab**.

- **I-25:** [confirmed] **"Open in Preview" is a right-click action** on wikilinks and navigation items (Nathan's directive, shipped in the shell): wikilinks via an optional `menu` hook on `ConnectionsApi` (a CM6 `contextmenu` handler hands the resolved page + click point to the host, which mounts a PickerMenu — the NavRowMenu anchor pattern); nav rows/cards via a page-only item in the shared NavRowMenu. The **sidebar's** context menu is native (main-process `contextMenu`) — adding it there is a main change, pending Nathan's call.

**Keyboard & focus**

- **I-20:** [confirmed] No preview-scoped keyboard commands beyond one: **⌘N while focused in a preview opens the active preview tab's page in a new app tab** — a promotion variant that closes the preview (Nathan's yes); [assumed] with multiple preview tabs it closes just the promoted tab, the window only when it was the last. ⌘W keeps its normal meaning (the app tab), Escape keeps D-4's (the topmost surface).
- **I-21:** [assumed] Escape order within the preview: open inspector closes first, then the preview — topmost-first (D-4), one press never kills two layers.
- **I-22:** [assumed] Editing shortcuts (⌘B, etc.) go to whichever editor holds focus; app-global shortcuts pass through — the preview never traps focus (D-3).

**Close & promote**

- **I-23:** [assumed] Close and promote both flush pending edits first (the seam's existing exit-edit flush); promote's engulf animates the preview rect into the detail pane rect — treatment design-stage.
- **I-24:** [assumed] App quit/reload rides the existing unmount flush; nothing new needed.

#### E — Sweep Results (matrix applied; anything without evidence is logged above)

- Happy path → Success Criteria. Validation → `openPage` error envelope renders an error state in the preview, never a crash [assumed]. Persistence → `open_in` shipped with legacy coercion; the B-6 config is one new settings.json key through the existing primitive — no new sidecars. Failure recovery → D-6 (dead path) + error envelope. Concurrency → C-3 (closed); the preview inspector's front-matter writes ride the existing property-update path, and the same reachability argument covers a main-pane + preview inspector pair [assumed]. Interaction inverses → open↔dismiss (D-4), enter-edit↔click-out (the seam's existing contract), promote (B-5), inspector open↔close (G-1). Singleton composition → a `[[Connection]]` click (B-6) or title-click while a preview is open **overtakes** the current preview (D-2 + H-1 agree: one window, contents swap) [assumed]. Reveal-stays-reachable → promotion chrome must not be hover-revealed-then-unreachable; the conditional chevron (H-2) appearing/disappearing must not reflow the toolbar out from under the pointer [assumed]. Local vs global gestures → preview scroll owns its wheel when hovered (floating window owns its scroll — NavWindow precedent); ⌘-shortcuts pass through (no focus trap, D-3). Performance → one CM6 mount per open preview; singleton (D-2) guards the perf rule. Z-order → D-5.

### Core (must-have)

- The routing branch at A-7 → a **single page-preview window** (plural-ready plumbing, D-2) on the shared floating chrome: window-background material, NavWindow-pattern move/resize, unified size defaults (D-7).
- **The tab system** (H): wiki-links open as tabs in-window; the NavWindow flavor with its perma-pinned map tab + sidebar slide-out; persistence tiers (NavWindow multi-session, page-preview per-session); all tab motion DRY'd from `tabBar.css` (F-4/F-5).
- Pages render through **PageEmbed, fully editable, keyed by path** (C-4), with the F-2 title/breadcrumb ↔ tab morph (H-9).
- **The preview inspector** (G-1): front-matter/metadata editing, opening/closing via the ToolbarTrio glass-swap exactly as the real inspector does.
- **Connections-in-preview** (B-6) via settings.json, plus the **hover-card trigger with a blank pane** (B-7 — embed UIX post-plan).
- Promote-to-full via the A-4 engulf (+ ⌘N and ⌘-click variants, I-19/I-20); tree-push reconcile (D-6); per-source routing (B-2); tab-neutral throughout (D-1).

#### Prospects (allowed later, not now)

- **Multiple simultaneous previews** — elevated by D-2: the core *ships the ability* (list-of-one architecture, no singleton assumptions baked in) and multi-preview gets **A-B tested** post-ship; if it wins, the chevron's NavWindow-return retires. First in line.
- **Connections hover-card** (B-7) — if resolved fast-follow rather than core: the `mouseover` slot in `connections.ts` + PickerMenu chassis + read-only PageEmbed.
- **Preview live-refresh** (C-5) — a watcher subscription so external edits repaint an open preview.
- **Agenda entry preview** — Navigation.md routes Agenda search hits to "a placeholder preview window that belongs to Agenda's feature"; this surface is its natural host later.
- **Drag a preview out into its own OS window** — the multi-window seams exist by design; far future.
- **Banner repositioning** — doesn't exist anywhere in the app yet; an app-wide prospect that lands in main views and previews together, owned elsewhere.

#### Out of Scope

- QuickLook/OS-level previews (PRD: requires a companion Swift bundle — a different feature entirely).
- Body/full-text search, NavWindow content decisions — separate pending items.

#### Considered & Rejected

- **In-pane slide-over** (A-1 shape 3) — rejected: it consumes the main pane the preview exists to protect.
- **Anchored compact card** (A-1 shape 2, the PickerMenu chassis) — rejected in favor of the floating window; the ephemeral read-leaning card fights the fully-editable, park-it-beside-your-work intent (C-2).
- **A new double-writer guard for C-3** — not built: PageView + PageEmbed already share the last-write-wins contract on block surfaces; the preview inherits rather than hardens (pending Nathan's nod).

#### Reconciliation (docs that go false when this ships)

- [[Collections]] :28/:63 + [[Pages]] :23/:47 + [[PommoraPRD]] :110/:196 — still say `compact | window` and "routing is unwired/Pending"; values renamed `full-page | page-preview` (History.md:67) and the routing lands with this feature. Rewrite as durable truth.
- [[Navigation]] :59 — the deferred "in-pane preview mode" line retires into the shipped behavior.
- `SettingsPane.tsx:110` — the B-8 parked comment retires.
- [[Interaction]] — gains the preview's open/close motion as a Bloom consumer (a line, not a section).
- Implementation adjacencies (grounded by the reuse maps): **(1)** the floating chrome extracts from NavWindow's inlined engine (`NavWindow.tsx:139-195` + `geo`/`clampGeo`) into a shared hook — three injection points: the drag-surface allow-list becomes a prop, the close callback injects, geometry keys per-window (the module singleton can't serve two windows); NavWindow rebases onto it during implementation. **(2)** `tabBar.css` splits: the pure motion layer (`.tab`, `.tab-seg`, `.tab-x`, nav-slide keyframes — store-free) becomes container-agnostic; the toolbar skin (app-region, the `:has()` reveal chain, `winDragBy`) stays toolbar-only; `TabBar.tsx` splits into a presentational strip + wiring layers. **(3)** the preview needs its own slide stamp (the global `navSlide` is a single app-wide slot) and its own active-detail state — `tabsModel.ts` pure functions reused wholesale (H-11). **(4)** the preview window's material is `--bg-window` (`shared/theme.ts` → the token bridge), the NotchedPane/PickerMenu "solid" precedent — not GlassPane-only frost.

#### Lessons

- (accumulates)
