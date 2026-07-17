## Page Previews — Decision Log

### Frame

- **Purpose:** Ship the parked "B-8 preview surface" — the routing target for `open_in: 'page-preview'`, letting a Collection's Pages open as a lightweight preview instead of replacing the main pane.
- **Core Value:** A Page can be *peeked* — read (and possibly edited) in place — without navigating: no selection change, no tab churn, no Back/Forward pollution.
- **Success Criteria:** A `page-preview` Collection's title click opens the preview; dismissing it lands you exactly where you were; the main pane, tabs, and history are untouched throughout.

### Status — Continuation

Phase C is nearly closed. Settled: floating window on window-background (A-1/A-3), fully editable (C-2), singleton (D-2), per-source routing — sidebar follows the Collection, NavWindow overrides with its own toggle (B-2), promotion via fullscreen + engulf (B-5/A-4), toolbar inventory + in-line titles (F-1/F-2), in-preview wiki-nav with NavWindow-return chevron (H-1/H-3), double-writer accepted as non-issue (C-3). Two light confirmations outstanding with Nathan: **B-6** (connections-in-preview logged as first Prospect — unobjected recommendation) and **G-1's phase** (inspector functional in core vs immediate follow-up; the toggle treatment itself is confirmed as the ToolbarTrio glass-swap). Then phases E→J.

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

- **B-6:** [assumed] Connections-in-preview — a user config making inline `[[Connection]]` clicks open the target as a preview instead of navigating (`connections.ts:16` — the `api.open` slot is the branch point). Logged as the **first Prospect**, not core: the window plus its internal nav is the plate; the branch point makes this a cheap follow-up. (Recommended and unobjected — flag if it was meant core.)

- **B-3:** [confirmed] "Open in New Tab" (the context-menu action) always bypasses the preview — it's an explicit full-page ask; the preview never has a tab.

- **B-4:** [confirmed] The NavWindow peek (ratified tab-neutral) is this same surface summoned from a NavWindow row; its deferred "preview mode toggle" ties to the page's `open_in`.

- **B-5:** [confirmed] Promotion: the toolbar's **fullscreen** button (F-1) opens the page for real — routes through the normal `select`, closes the preview, and rides the A-4 engulf animation.

#### C — Content & Editability

- **C-1:** [assumed] The preview renders through the G-11 `PageEmbed` seam — a real CM6 portal, full decorations, not a dumbed-down renderer. The seam's parked header chrome means the preview needs its own lightweight header treatment (title at minimum; banner handling is a design call).

- **C-2:** [confirmed] **Fully editable** — the preview is a working surface, not a glance. Rides the seam's existing edit flip + debounced autosave.

- **C-3:** [confirmed] Same-file double-writer: **non-issue by reachability** (Nathan's call) — the sidebar can't re-open the already-open page, and NavWindow interactions on the current page open nothing new, so the main-pane + preview same-page state doesn't arise through normal triggers. The one residual path (in-preview wiki-nav landing on the main-pane's page) inherits the contract block-surface embeds already live under — `PageView.tsx:44` + `PageEmbed.tsx:53` are both debounced last-write-wins writers, no live cross-sync. No guard built.

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

- **G-1:** [confirmed, phase open] The preview carries its **own inspector** — separate from the DetailView inspector — as the front-matter/metadata editing surface, the mechanism the Swift build's front-matter inspector used. **Fully toggle-able**, reusing the existing inspector toggle's treatment verbatim: the ToolbarTrio glass-swap (`ToolbarTrio.tsx` — the glass pill voids as the inspector swallows the trio, icons ride onto the inspector's glass, driven by `--io` in toolbar.css) and the same swap animation. Whether it lands functional in the core ship or as the immediate follow-up phase is the one open sub-call.

- **G-2:** [confirmed] The inspector's layout gets a **Figma design pass**; the Swift build's inspector (archived at `The Studio/Archive/Pommora`) is the reference — it already mostly looks the way Nathan wants.

#### H — In-Preview Navigation

- **H-1:** [confirmed] A wiki-link ([[Connection]]) clicked **inside** a preview opens its target **in the same preview, overtaking** the current page — never a second surface, never a main-pane navigate.

- **H-2:** [assumed] That implies a **preview-local back stack**: the back-chevron walks it; back-only (no forward) for the core; the stack dies with the preview. Completely separate from tab history — the tab-neutral law (D-1) holds.

- **H-3:** [confirmed] A NavWindow-summoned preview's back-chevron **returns to the NavWindow** (reopens it).

- **H-4:** [assumed] Chevron precedence when both meanings apply: the chevron walks the in-preview stack first (H-2); the NavWindow return (H-3) fires only at the bottom of the stack — one button, stack-then-origin.

#### E — Sweep Results (matrix applied; anything without evidence is logged above)

- Happy path → Success Criteria. Validation → `openPage` error envelope renders an error state in the preview, never a crash [assumed]. Persistence → no schema changes (`open_in` shipped; legacy coercion in place); no new sidecars for the core. Failure recovery → D-6 (dead path) + error envelope. Concurrency → C-3 (double-writer). Interaction inverses → open↔dismiss (D-4), enter-edit↔click-out (the seam's existing contract), promote (B-5). Reveal-stays-reachable → promotion chrome must not be hover-revealed-then-unreachable. Local vs global gestures → preview scroll owns its wheel when hovered (floating window owns its scroll — NavWindow precedent); ⌘-shortcuts pass through (no focus trap, D-3). Performance → one CM6 mount per open preview; multiple previews (D-2) multiply live editors — cap or singleton guards the perf rule. Z-order → D-5.

### Core (must-have)

- (near-final shape; settles fully after B-2/B-6, G-1, H-3, C-3): the routing branch at A-7 → a **singleton floating movable window** (NavWindow chrome, window-background material) rendering the page through **PageEmbed, fully editable**, with the F-1 toolbar (back-chevron · promote · exit · inspector · settings) and F-2 title treatment; in-preview wiki-nav with a local back stack; promote-to-full via the A-4 engulf; tree-push reconcile (D-6); NavWindow peek entry; tab-neutral throughout.

#### Prospects (allowed later, not now)

- **Connections-in-preview (B-6, the first Prospect)** — a user config routing inline `[[Connection]]` clicks to a preview instead of a navigate; the `api.open` slot in `connections.ts:16` is the branch point. Don't-foreclose: the preview stays summonable from an arbitrary anchor, not only a table row.
- **Connections hover-preview** — a `mouseover` handler + `ConnectionsApi` method (the exact slot exists in `connections.ts`); follows B-6.
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
