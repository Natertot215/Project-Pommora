## Page Previews — Decision Log

### Frame

- **Purpose:** Ship the parked "B-8 preview surface" — the routing target for `open_in: 'page-preview'`, letting a Collection's Pages open as a lightweight preview instead of replacing the main pane.
- **Core Value:** A Page can be *peeked* — read (and possibly edited) in place — without navigating: no selection change, no tab churn, no Back/Forward pollution.
- **Success Criteria:** A `page-preview` Collection's title click opens the preview; dismissing it lands you exactly where you were; the main pane, tabs, and history are untouched throughout.

### Status — Post-Compact Continuation

Phase C (interrogation) is live: four questions are with Nathan, hypotheses attached — **A-1** (surface form; hypothesis: floating window), **C-2** (editability; hypothesis: editable), **B-2** (sidebar trigger scope; hypothesis: sidebar honors the routing too), **D-2** (singleton vs multiple; presented multiple as the out-there option, core designed as "a list of one" either way). Fold his answers into the tagged entries below, then run phases E→J (pressure-test remainder, core/prospects split, converge, self-review, adversarial review, pass to planning + /handoff). Grounding is complete and spot-verified; Sources below are the re-grounding list.

### Sources

- `Pommora/src/shared/types.ts:193` — `OpenIn = 'full-page' | 'page-preview'`; the type's own comment says "full-view or a hovering preview window. Collection-owned."
- `Pommora/src/shared/schemas.ts:23` — `OPEN_IN_LEGACY` coerces Swift-era `window | compact` on read.
- `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx:110` — "Open In has no payload target until the preview surface ships (B-8)" — the config UI exists and writes; nothing routes on it.
- `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx:671` — the ONLY navigate (A-7): title-cell click → `select(...)` unconditionally; no `openIn` branch anywhere in the renderer. `:957` context-menu `title:newtab`.
- `Pommora/src/main/crud/containerConfig.ts:39` — a Set-level `open_in` write is refused (Collection-owned; Sets proxy).
- `Pommora/src/renderer/src/Embeds/PageEmbed.tsx:19` — THE G-11 seam: a real Page as a read-only CM6 portal, in-place edit flip (no remount), 400ms-debounced autosave to the page's own file via `openPage`/`updatePageBody` directly — zero store/nav involvement. Props: `path, editing, onBeginEdit, connections, locked`. Header chrome (banner/title) parked.
- `Pommora/src/main/index.ts:619` — `page:open` is a pure read; `store.ts:1199 reloadPage` proves navigation-free reads are established.
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

- **A-1:** [open] ← blocking, with Nathan. What the preview IS. Three real shapes on the table:
  **(1) Floating movable window** — GlassPane + the NavWindow chrome pattern (move/resize/persisted size); park-it-beside-your-work, edit-friendly, the NSPanel heritage and the types.ts "hovering preview window" wording. *Recommended.*
  **(2) Anchored compact card** — PickerMenu chassis at the click point; ephemeral, dismiss-on-anything, read-leaning, the stale docs' "compact preview card" wording.
  **(3) In-pane slide-over** — a panel sliding over the detail pane edge; rejected-leaning (it occupies the main pane it exists to avoid disturbing; logged for completeness).
  Layout/visual specifics are Figma territory once the form locks.

- **A-2:** [assumed] Motion: the preview opens on the Bloom primitive (`dropdown-menu` + `useExitPresence`), per the Interaction.md one-DRY-source law — no bespoke keyframes.

- **A-3:** [assumed] Material: `GlassPane` (the NavWindow/frost tier), not `GlassControls`.

#### B — Triggers & Routing

- **B-1:** [confirmed] The routing branch lives at the title-click navigate (TableView A-7, the app's only navigate): `open_in === 'page-preview'` → open preview instead of `select`. Collection-owned; Sets proxy the parent's value.

- **B-2:** [open] ← with Nathan. Whether sidebar page rows (and NavWindow rows) of a `page-preview` Collection also route to the preview, or sidebar/nav always goes full-page. Hypothesis: they honor the Collection's routing — one rule, no per-surface exceptions.

- **B-3:** [confirmed] "Open in New Tab" (the context-menu action) always bypasses the preview — it's an explicit full-page ask; the preview never has a tab.

- **B-4:** [confirmed] The NavWindow peek (ratified tab-neutral) is this same surface summoned from a NavWindow row; its deferred "preview mode toggle" ties to the page's `open_in`.

- **B-5:** [assumed] A promotion gesture exists: something on the preview opens the page for real (a full-page button routing through the normal `select`, which then closes the preview). The exact gesture/chrome is design-stage.

#### C — Content & Editability

- **C-1:** [assumed] The preview renders through the G-11 `PageEmbed` seam — a real CM6 portal, full decorations, not a dumbed-down renderer. The seam's parked header chrome means the preview needs its own lightweight header treatment (title at minimum; banner handling is a design call).

- **C-2:** [open] ← with Nathan. Read-only peek vs editable-in-place. The seam's edit flip + autosave makes editable nearly free mechanically; hypothesis: editable — the Items-era intent was *working* in small windows, not glancing.

- **C-3:** [open] Same-file double-writer hazard: the SAME page open in the main pane AND an editable preview means two debounced writers to one file (PageEmbed already creates this class on block surfaces today — how it resolves there needs a look before this locks). Options: last-write-wins (accept), or the preview refuses edit-entry when the page is the active selection. Investigate the existing embed behavior first.

#### D — Lifecycle, Focus & Layering

- **D-1:** [confirmed] Tab-neutral by construction: the preview never touches `selection`, `tabs`, history, or the warm cache — it reads via `openPage` directly (the PageEmbed pattern). No store slice beyond an open/target flag.

- **D-2:** [open] ← with Nathan. Singleton (a second open replaces the first — the NSPanel model) vs multiple coexisting previews. Either way the core is designed as "a list of one" so multiple never needs a rewrite.

- **D-3:** [assumed] Non-modal, no focus steal (the NavWindow precedent): opening a preview doesn't blur the editor behind it; its own search-less chrome takes focus only when clicked into.

- **D-4:** [open] Escape layering: NavWindow closes on window-level Escape (skipping `defaultPrevented`); a preview needs a defined order (topmost/most-recent surface closes first) so one Escape never kills two surfaces. Also: does clicking outside dismiss (card behavior) or not (window behavior)? — follows A-1.

- **D-5:** [assumed] Z-order: previews sit above the detail pane and BELOW PickerMenu popups (z 1100) so pickers opened from inside a preview layer correctly; relative order vs NavWindow needs a call if both can be open (most-recently-focused on top is the hypothesis).

- **D-6:** [open] Tree-push reconciliation: the previewed page can be renamed/moved/deleted mid-preview (the watcher pushes a new tree). The preview must re-resolve its path (rename-follow, like tabs reconcile) or close gracefully on a dead path — a stale-path autosave would write to the old file. The main-pane precedent is applyTree's reconcile; the preview needs its own tiny version keyed off the page id.

- **D-7:** [assumed] Geometry persistence (if A-1 = window): module-scoped like NavWindow's `geo` — size persists per session, opens anchored/centered per design call; nothing on disk.

#### E — Sweep Results (matrix applied; anything without evidence is logged above)

- Happy path → Success Criteria. Validation → `openPage` error envelope renders an error state in the preview, never a crash [assumed]. Persistence → no schema changes (`open_in` shipped; legacy coercion in place); no new sidecars for the core. Failure recovery → D-6 (dead path) + error envelope. Concurrency → C-3 (double-writer). Interaction inverses → open↔dismiss (D-4), enter-edit↔click-out (the seam's existing contract), promote (B-5). Reveal-stays-reachable → promotion chrome must not be hover-revealed-then-unreachable. Local vs global gestures → preview scroll owns its wheel when hovered (floating window owns its scroll — NavWindow precedent); ⌘-shortcuts pass through (no focus trap, D-3). Performance → one CM6 mount per open preview; multiple previews (D-2) multiply live editors — cap or singleton guards the perf rule. Z-order → D-5.

### Core (must-have)

- (settles after A-1 / B-2 / C-2 / D-2 resolve — expected shape: the routing branch at A-7, one preview surface on the chosen chassis rendering PageEmbed with a lightweight header, dismiss + promote, tree-push reconcile, NavWindow peek entry.)

#### Prospects (allowed later, not now)

- **Connections hover-preview** — a `mouseover` handler + `ConnectionsApi` method (the exact slot exists in `connections.ts`); don't-foreclose: the preview surface stays summonable from an arbitrary anchor, not only a table row.
- **Agenda entry preview** — Navigation.md routes Agenda search hits to "a placeholder preview window that belongs to Agenda's feature"; this surface is its natural host later.
- **Multiple simultaneous previews** (if D-2 resolves singleton) — the "list of one" core leaves the door open.
- **Drag a preview out into its own OS window** — the multi-window seams exist by design; far future.

#### Out of Scope

- QuickLook/OS-level previews (PRD: requires a companion Swift bundle — a different feature entirely).
- Body/full-text search, NavWindow content decisions — separate pending items.

#### Considered & Rejected

- **In-pane slide-over** (A-1 shape 3) — leaning rejected: it consumes the main pane the preview exists to protect; kept on the table only until A-1 locks.

#### Reconciliation (docs that go false when this ships)

- [[Collections]] :28/:63 + [[Pages]] :23/:47 + [[PommoraPRD]] :110/:196 — still say `compact | window` and "routing is unwired/Pending"; values renamed `full-page | page-preview` (History.md:67) and the routing lands with this feature. Rewrite as durable truth.
- [[Navigation]] :59 — the deferred "in-pane preview mode" line retires into the shipped behavior.
- `SettingsPane.tsx:110` — the B-8 parked comment retires.
- [[Interaction]] — gains the preview's open/close motion as a Bloom consumer (a line, not a section).
- Implementation adjacency: a second floating window justifies extracting NavWindow's move/resize engine into a shared chrome (design-system/interactions) — decide at planning, not here.

#### Lessons

- (accumulates)
