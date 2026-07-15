## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — detail lives in `Features/*` + `History.md`.

- **Block Surfaces — SurfacePM (shipped + merged to main).** The host-agnostic block/tile system: split-tree layout, window-style edge resize, PommoraDND feel, markdown/page/view tiles behind the BlockHost seam (locked read-merge-writes), CM6-portal page embeds (every prose tile a read-only MarkdownPM view), block `[[links]]` as first-class edges, geometry-only homepage lock, homepage/context identity settings, and per-block Scale (view-agnostic). → [[SurfacePM]] + `History.md`.

- **App-wide auto-scroll (shipped, on main).** One shared `interactions/autoscroll.ts` singleton rAF loop drives every drag's edge-scroll — one fixed scroller resolved once at drag start, px/sec × dt (ProMotion-safe), distance-based acceleration + direction-intent, an instance-scoped stopper, tokens read off the drag element. Migrated the 3 existing consumers, deleted the block-drag duplicate loop, retrofitted 3 surfaces that never had it (sidebar, table rows, table bands). The axis-aware `findScroller` was the enabler. → [[PommoraDND]] §II. Autoscroll + `History.md`. Live drag-feel gut-check still open (below).

- **Tables — cell + group system + grouping/sorting + Hide Borders.** The cell-gesture matrix, per-view looks/formats in `column_styles`, band drag, the reusable editors in `Detail/Views/PropertyEditing/`, grouping + sorting end-to-end, and the borderless-table toggle with on-demand structure reveals. → [[TableView]] + [[Views]].

- **PropertiesV2 · Multi-View scaffolding · Icon Picker + Sidebar Ribbon.** Nexus-wide property registry (`.nexus/properties.json` + per-collection assignment ids, `readNexus` joins); ViewDropdown · ViewPane · two-door ViewSettings + per-type editor panes; full-Lucide picker in the shared PickerMenu; ribbon + mode-switched sidebar. → [[Views]] · [[Properties]] · [[Icons]] · [[Sidebar]].

### Session Summary — Navigation Surface: Feature → Redesign, + SurfacePM Polish

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 2
**Connectors:** none
**Commands:** /compact · /handoff
**Agents:** build-breaking-agent (2x - review)
**Skills:** handoff

The Navigation surface came up from persistence plumbing to a live command-palette-shaped NavPane, then a visual redesign, closed out alongside three SurfacePM handle-menu fixes.

**Navigation feature (Phases 1–4, committed `9f6e0eed` → `ede4519f`):** the nav-state layer landed in four phases — a per-Nexus synced persistence layer (`navRecents.json` / `navFavorites.json`; recents as MRU + pin flag, favorites, all resolved live against the tree, render-prune-never-storage-prune), a renderer nav-state store + client-side fuzzy search, the NavPane mini-shell (a movable glass surface), and the NavMenu dropdown over a shared `useNavData` read side that both surfaces render from. → [[Navigation]].

**NavPane redesign (`c8f091ec`, approved live + green):** reshaped the NavPane into an always-centered `GlassPane` command surface. Rows read (icon)(title … chevron-joined path), title + path each eclipse-scrolling under the shared `OverflowScroll`; the resolver builds ONE `ResolveIndex` per tree push (icons + container-crumb chains) that recents / favorites / search all read (a review fold — single walk). Search rides the body type token, the pane resizes from four corners + a rail split, and both the rail and main lists carry the shared `scroll-edge-fade` for lists longer than the pane. Row actions (pin / favorite / remove) deferred to future context-menu actions; the NavMenu dropdown is stripped to a blank placeholder pending its content decision. `WIN` / `RAIL` consts (NavPane.tsx:14–15) + `--navpane-inset` / `--navpane-rail` (navpane.css:10, :54) are the live size knobs.

**SurfacePM handle-menu fixes (`4f7b3f55`, all three confirmed — Nathan: "Visuals on animation and picker are great"):** three block-surface corrections. (a) The accent tint moved OFF the Scale dropdown (dropped its `accentOutline`) ONTO the handle menu's page+location "Open In" field — the openable embed identity now wears the same accent-@-tint-secondary border as the embed on the surface (`handleMenu.css.ts` `titleField`). (b) View tiles now animate their per-block Scale on the standard beat like page tiles — the deliberate snap guard (`is-view-tile { --block-zoom-anim: 0s }`) was removed after Nathan confirmed the grid relayout is acceptable BECAUSE it's bounded to the ~200ms one-shot transition, not a per-frame trigger; the dead `--block-zoom-anim` indirection + orphaned `is-view-tile` class went with it. (c) Borderless tiles keep their chassis while the handle menu is open (`:not(.handle-pinned)`), matching reveal-on-hover; the page-embed accent rule was class-doubled to hold above the borderless-hide rule independent of source order (a folded build-breaker Low). → [[SurfacePM]].

**Lessons Learned**

- **A bounded one-shot relayout is NOT the "expensive work on every X" trap.** The view-scale animation relayouts the non-virtualized grid each frame, but only for the transition's ~200ms — Nathan explicitly accepted it (`> "if it rerenders only on the animation, that's fine"`). The hard rule targets *continuous / high-frequency* triggers (drag, scroll, resize), not a discrete user action's settle. Confirm the trigger's cadence before treating a relayout as forbidden.

- **Ground a design-directive's premise before implementing it.** "Move the accent off the scale picker onto the page border + location" only made sense after opening the code: the accent leak was `accentOutline` (identical treatment to the real page-embed border), and the intended new home was the `titleField` — neither obvious from the words alone. The instruction's premise was a hypothesis until `grep accent` proved where it actually lived.

- **`:not()` additions silently consume specificity margins.** Adding `:not(.handle-pinned)` to the borderless-hide rule lifted it to an exact tie with the page-embed accent rule — correct only by source order until class-doubled. Any `:not()` you bolt onto a rule that competes with another for the same property can flip a tie; re-count both.

**Key Files & Insights**

- `Navigation/` — `navResolve.ts` (the `ResolveIndex` + crumb builder), `useNavData.ts` (the one shared read side), `NavList.tsx` + `navList.css` (the row); `NavPane/` — the glass mini-shell + its knobs; `Toolbar/NavMenu.tsx` — the placeholder dropdown, content TBD.
- Reuse over hand-roll: `design-system/scroll-edge-fade.css` (the vertical list fade — rides on any `overflow-y:auto` box via the class), `OverflowScroll` (row eclipse), `color-mix(in srgb, var(--accent) var(--tint-secondary), transparent)` (THE canonical accent-tint border — page-embed, table, NotchedPane, now the titleField).
- Knobs Nathan tunes live: NavPane `WIN`/`RAIL` (NavPane.tsx:14–15) + `--navpane-inset`/`--navpane-rail` (navpane.css) · `--tile-border` / `--grip-size` (surfacepm.css) · `EMBED_SCALE` · per-block Scale animates via the registered `@property --block-zoom`.

**User Feedback**

- Nathan live-drives and drip-feeds mid-turn corrections — fold each immediately, batch-commit, bundle his tunes; his effect-words are literal.
- Confirm the layer before fixing (UIX vs data), and ask before any design / interaction call — but when a directive's premise is checkable in code, ground it first, then confirm.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`; relaunch with `-- --remote-debugging-port=9222` to keep CDP.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Plain `.css` DOES HMR reliably.

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit unless he authorizes it. Note: block Scale + borderless style are PERSISTED block entries — demoing them mutates his real homepage. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's, left uncommitted on purpose. **main is ahead of origin, unpushed** — Nathan pushes in batches; merge ≠ push.

- **Detail insets split by surface kind:** block surfaces run tight `--surface-inset` (8px body) + `--surface-banner-inset` (12px banner) via an `is-surface` class (`isSurfaceKind`, `Detail/Scope.ts`); page/table views keep `--content-inset` + `--fold-gutter`.

### Next Session

**Finish the NavPane look — the pin / current-item treatment on the inset.** The temp-pin (or the current item) should read as a **pin-icon in the `--navpane-inset` gutter** of its row (the left inset lane the icon + row content align to). It's the visual marker for a pinned recent / the active entity; scope it to the NavList row, reusing the row's existing inset rather than adding a new lane. → [[Navigation]].

**Decide what the sidebar (rail) and the NavMenu dropdown actually hold.** Both are currently stubs: the rail renders favorites + a List/Gallery Style toggle (viewMode is a local stub — the gallery layout is Figma-pending); the NavMenu dropdown is a blank beak-glass placeholder. Neither's content is settled — figure out what each surface is *for* before building into it (the dropdown especially: is it a compact recents peek, a full nav, something else?).

**Then: finalize the list layout + look, and move onto the gallery.** The gallery is the Figma-designed card form of the recents (the Style toggle's other mode) — the row list's sibling presentation. Build it against the settled `useNavData` / `NavList` seam once the list look is locked.

**Still-open live verifications (lower priority, not this arc's work):** auto-scroll drag-feel gut-check across all six surfaces (distance-accel + direction-intent felt on surfaces that had none before — esp. "grab the last table row, drag down to extend"; six tokens in `autoscroll.css`) · the two date-clear fixes (click a selected calendar date to clear; right-click filled vs empty date cell). Neither is unit-verifiable — jsdom stubs pointer-capture.

### Pending Focuses

- **Navigation continuation** — the pin-on-inset look, the sidebar + NavMenu content decisions, the list finalize, then the gallery (above). This is the active arc.

- **SurfacePM post-merge polish (not blocking):** page banners on embeds (+ per-tile lock home) · the Insert menu (G-9) + Link-Page search pane + shared recents (G-16, pairs with Navigation) · the shared debounced-save hook (`MarkdownBlock` ↔ `PageEmbed`) · robustness adds (per-tile error boundary, lazy-mount embeds, layout undo).

- **User Sections CRUD (the "Add Heading" feature).** Collections render user sections but there's no way to make one (`mutate.ts` has zero section ops). Own brainstorm→plan→build. → `Sidebar.md`.

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deferred (→ [[Views]]; `flat` GroupConfig kind stays reserved).

- **(Perf) Standing debt:** no row virtualization (every row MOUNTS — bites at thousands); external VALUE edits don't live-refresh an open table. Container-surgical reconcile is the designed escalation at scale.

- **Number editor eyeball items (tune, not bugs):** decimals "Hidden", fraction wording, bar clamp edges, strokeless bar, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build. Free-placement drawing inside Pages; distinct from Block Surfaces.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the code is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **iCloud-sync readiness (future):** `serializeOnFile` can't coordinate with the iCloud daemon (last-writer-wins); `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 a `window.nexus` bridge shim + native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore`.

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED)** — a visual inset, not a stored char.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → [[MarkdownPM]].

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it — a fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count; a merged arc compresses into Recent Work. Carry still-open Pending + Fix Log forward.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another's block.
