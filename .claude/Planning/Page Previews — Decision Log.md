## Page Previews — Decision Log

### Frame

- **Purpose:** Ship the parked "B-8 preview surface" — the routing target for `open_in: 'page-preview'`, letting a Collection's Pages open as a lightweight preview instead of replacing the main pane.
- **Core Value:** A Page can be *peeked* — read (and possibly edited) in place — without navigating: no selection change, no tab churn, no Back/Forward pollution.
- **Success Criteria:** A `page-preview` Collection's title click opens the preview; dismissing it lands you exactly where you were; the main pane, tabs, and history are untouched throughout.

### Status — Continuation

Phase C (interrogation) is live, round two. Round one settled the frame: **A-1** floating movable window on the window-background material, **C-2** fully editable, **D-2** singleton for now. Nathan also opened five new surfaces — the preview inspector (G), the preview toolbar + in-line titles (F), in-preview wiki-link navigation (H), the promote-to-full engulf animation (A-4), and the embedded zoom level (F-3). Open questions with Nathan: **B-2/B-6** (exact trigger-config shape), **G-1** (inspector: functional in core vs slot reserved), **H-3** (what the NavWindow back-chevron means), **C-3** (accept the existing last-write-wins contract). Fold his answers, then phases E→J.

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

- **B-2:** [open] ← with Nathan (narrowed). His direction: **multiple trigger sources, governed by config** — per-collection `open_in` for container views, plus a user config like "open connections in preview." Still to pin down: whether sidebar/NavWindow rows honor the per-collection routing (hypothesis: yes — one rule per source class), and where each config lives (per-collection sidecar vs nexus-level setting).

- **B-6:** [open] Connections-in-preview: a user config making inline `[[Connection]]` clicks open the target as a preview instead of navigating (`connections.ts:16` — the `api.open` slot is the branch point). Nathan raised it as real scope; whether it's core or the first Prospect is a scope call to settle.

- **B-3:** [confirmed] "Open in New Tab" (the context-menu action) always bypasses the preview — it's an explicit full-page ask; the preview never has a tab.

- **B-4:** [confirmed] The NavWindow peek (ratified tab-neutral) is this same surface summoned from a NavWindow row; its deferred "preview mode toggle" ties to the page's `open_in`.

- **B-5:** [confirmed] Promotion: the toolbar's **fullscreen** button (F-1) opens the page for real — routes through the normal `select`, closes the preview, and rides the A-4 engulf animation.

#### C — Content & Editability

- **C-1:** [assumed] The preview renders through the G-11 `PageEmbed` seam — a real CM6 portal, full decorations, not a dumbed-down renderer. The seam's parked header chrome means the preview needs its own lightweight header treatment (title at minimum; banner handling is a design call).

- **C-2:** [confirmed] **Fully editable** — the preview is a working surface, not a glance. Rides the seam's existing edit flip + debounced autosave.

- **C-3:** [assumed] Same-file double-writer: this class **already exists in the app** — `PageView.tsx:44` (main pane) and `PageEmbed.tsx:53` (block-surface embeds) are both debounced writers to the same file with last-write-wins and no live cross-sync. The preview inherits that established contract; no new guard. Needs Nathan's nod that inheriting (not hardening) is right for the core.

#### D — Lifecycle, Focus & Layering

- **D-1:** [confirmed] Tab-neutral by construction: the preview never touches `selection`, `tabs`, history, or the warm cache — it reads via `openPage` directly (the PageEmbed pattern). No store slice beyond an open/target flag.

- **D-2:** [confirmed] **Singleton for now** (a second open replaces the first — the NSPanel model); the core stays designed as "a list of one" so multiple slots in later without a rewrite.

- **D-3:** [assumed] Non-modal, no focus steal (the NavWindow precedent): opening a preview doesn't blur the editor behind it; its own search-less chrome takes focus only when clicked into.

- **D-4:** [open] Escape layering: NavWindow closes on window-level Escape (skipping `defaultPrevented`); a preview needs a defined order (topmost/most-recent surface closes first) so one Escape never kills two surfaces. Also: does clicking outside dismiss (card behavior) or not (window behavior)? — follows A-1.

- **D-5:** [assumed] Z-order: previews sit above the detail pane and BELOW PickerMenu popups (z 1100) so pickers opened from inside a preview layer correctly; relative order vs NavWindow needs a call if both can be open (most-recently-focused on top is the hypothesis).

- **D-6:** [open] Tree-push reconciliation: the previewed page can be renamed/moved/deleted mid-preview (the watcher pushes a new tree). The preview must re-resolve its path (rename-follow, like tabs reconcile) or close gracefully on a dead path — a stale-path autosave would write to the old file. The main-pane precedent is applyTree's reconcile; the preview needs its own tiny version keyed off the page id.

- **D-7:** [assumed] Geometry persistence (if A-1 = window): module-scoped like NavWindow's `geo` — size persists per session, opens anchored/centered per design call; nothing on disk.

#### F — Chrome, Toolbar & Titles

- **F-1:** [confirmed] The toolbar's action inventory: **back-chevron** (in-preview navigation, H), **fullscreen/promote** (B-5, rides the A-4 engulf), **Exit** (close), **Inspector** toggle (G), **Settings**. The *arrangement* — keeping it uncluttered, and the chevron-vs-fullscreen adjacency problem (both reasonably sit trailing-left; either leading makes the other look off) — is Figma territory, flagged unresolvable in text.

- **F-2:** [confirmed] In-line titles, two states. **With banner:** banner + title heading render as usual — nothing special. **Without banner:** the page body starts with no heading-divider, and the title renders **in the toolbar area** the way tabs render theirs, as a filepath breadcrumb — `Collection > Set > Page Name` — in the same label color the navigation filepaths use, at **caption** size (for now).

- **F-3:** [assumed] Embedded zoom: reuse the existing G-10 knob — `EMBED_SCALE`/`EMBED_ZOOM` in `Embeds/embedScale.ts`, already consumed by PageEmbed. One knob, no new zoom system; whether the preview wants its own value through that knob is a design-stage tune.

#### G — Preview Inspector

- **G-1:** [open] The preview carries its **own inspector** — separate from the DetailView inspector — as the front-matter/metadata editing surface, the mechanism the Swift build's front-matter inspector used. Scope question with Nathan: functional in the core, or the chrome slot reserved with the inspector following?

- **G-2:** [confirmed] The inspector's layout gets a **Figma design pass**; the Swift build's inspector (archived at `The Studio/Archive/Pommora`) is the reference — it already mostly looks the way Nathan wants.

#### H — In-Preview Navigation

- **H-1:** [confirmed] A wiki-link ([[Connection]]) clicked **inside** a preview opens its target **in the same preview, overtaking** the current page — never a second surface, never a main-pane navigate.

- **H-2:** [assumed] That implies a **preview-local back stack**: the back-chevron walks it; back-only (no forward) for the core; the stack dies with the preview. Completely separate from tab history — the tab-neutral law (D-1) holds.

- **H-3:** [open] ← with Nathan. "Back-chevrons for opening a preview in NavWindow" — the intended meaning needs pinning: a chevron that returns a NavWindow-summoned preview *to* the NavWindow, or something else.

#### E — Sweep Results (matrix applied; anything without evidence is logged above)

- Happy path → Success Criteria. Validation → `openPage` error envelope renders an error state in the preview, never a crash [assumed]. Persistence → no schema changes (`open_in` shipped; legacy coercion in place); no new sidecars for the core. Failure recovery → D-6 (dead path) + error envelope. Concurrency → C-3 (double-writer). Interaction inverses → open↔dismiss (D-4), enter-edit↔click-out (the seam's existing contract), promote (B-5). Reveal-stays-reachable → promotion chrome must not be hover-revealed-then-unreachable. Local vs global gestures → preview scroll owns its wheel when hovered (floating window owns its scroll — NavWindow precedent); ⌘-shortcuts pass through (no focus trap, D-3). Performance → one CM6 mount per open preview; multiple previews (D-2) multiply live editors — cap or singleton guards the perf rule. Z-order → D-5.

### Core (must-have)

- (near-final shape; settles fully after B-2/B-6, G-1, H-3, C-3): the routing branch at A-7 → a **singleton floating movable window** (NavWindow chrome, window-background material) rendering the page through **PageEmbed, fully editable**, with the F-1 toolbar (back-chevron · promote · exit · inspector · settings) and F-2 title treatment; in-preview wiki-nav with a local back stack; promote-to-full via the A-4 engulf; tree-push reconcile (D-6); NavWindow peek entry; tab-neutral throughout.

#### Prospects (allowed later, not now)

- **Connections hover-preview** — a `mouseover` handler + `ConnectionsApi` method (the exact slot exists in `connections.ts`); don't-foreclose: the preview surface stays summonable from an arbitrary anchor, not only a table row. (Connections *click*-in-preview is B-6 — possibly core, pending the scope call.)
- **Agenda entry preview** — Navigation.md routes Agenda search hits to "a placeholder preview window that belongs to Agenda's feature"; this surface is its natural host later.
- **Multiple simultaneous previews** (if D-2 resolves singleton) — the "list of one" core leaves the door open.
- **Drag a preview out into its own OS window** — the multi-window seams exist by design; far future.

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
- Implementation adjacency: a second floating window justifies extracting NavWindow's move/resize engine into a shared chrome (design-system/interactions) — decide at planning, not here.

#### Lessons

- (accumulates)
