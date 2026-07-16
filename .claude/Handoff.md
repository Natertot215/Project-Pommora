## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — detail lives in `Features/*` + `History.md`.

- **Navigation Surface + NavPane redesign + gallery (shipped, on `nav-gallery-pins`).** The per-Nexus nav-state layer (recents/pins/favorites in synced sidecars + `.nexus/pins/` per-pin store, resolved live via `navResolve`, render-prune-never-storage-prune), a `useNavData` read side both surfaces share, client-side fuzzy search, the movable `GlassPane` NavPane (now renamed **NavWindow**), and its Figma gallery card form + list rows + inset pin marker + thumbnail-capture pipeline. → [[Navigation]] + `History.md`.

- **Block Surfaces — SurfacePM (shipped + merged to main).** Host-agnostic block/tile system: split-tree layout, window-style edge resize, PommoraDND feel, markdown/page/view tiles behind the BlockHost seam, CM6-portal page embeds, block `[[links]]` as edges, geometry-only homepage lock, per-block Scale. → [[SurfacePM]] + `History.md`.

- **App-wide auto-scroll (shipped, on main).** One shared `interactions/autoscroll.ts` singleton rAF loop drives every drag's edge-scroll — one fixed scroller resolved once, px/sec × dt (ProMotion-safe), distance-accel + direction-intent. → [[PommoraDND]] §II. Autoscroll.

- **Tables · PropertiesV2 · Multi-View · Icon Picker + Sidebar Ribbon.** The cell-gesture matrix + per-view looks + band drag + grouping/sorting + borderless toggle; nexus-wide property registry; ViewDropdown/Pane/Settings; full-Lucide picker; ribbon + mode-switched sidebar. → [[TableView]] · [[Views]] · [[Properties]] · [[Icons]] · [[Sidebar]].

### Session Summary — Multi-Tab Nexus: Brainstormed → Ratified → Build-Ready

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026 → 07-15-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 4
**Connectors:** none
**Commands:** /compact · /handoff
**Agents:** build-breaking-agent (6x - review) · Explore (3x - grounding) · feature-dev:code-explorer (1x - warm-trace) · general-purpose (1x - simplify)
**Skills:** studio-brainstorm · superpowers:writing-plans · handoff

The session's later arc turned the navigation model's long-deferred paradigm fork (**B-1**: single-pane-replace vs tabs) into a **ratified, review-hardened spec + implementation plan** — no code yet; the next session executes it.

**Multi-Tab Nexus, brainstormed to ratified:** Warm, state-preserving Toolbar Tabs replace single-pane-replace. Grounded against real code first (three explorers mapped the mount model, context menus, gallery reuse), then built the decision log through live back-and-forth with Nathan on every fork. The load-bearing call: **one view mounted, a per-tab serialized cache** (seed a fresh CM6 mount from a cached `historyField`; folds ride the durable `folds.json`) — N-live-views was rejected on the perf hard-rule (N un-virtualized tables) + a ~15-consumer blast radius. → `Planning/Multi-Tab Nexus — Decision Log.md`.

**The pins graduate; the set persists AND syncs:** The shipped `.nexus/pins/` store IS the pinned-tabs set — `isPinned` is *derived* from it, never stored (a second synced copy would re-introduce whole-array-LWW desync). The full tab set persists cross-restart AND syncs cross-device (closing never resets tabs; they reopen cold; warm view-state is session-only). Per-tab Back/Forward won A/B over a single shared history. One `openTab` predicate absorbs replace-vs-spawn (dedup-first, then `newTab = explicit || activeTab.isPinned`).

**Three review rounds hardened it, each verified in code:** a light grounding pass (2 folds: pins are the shipped store, delete render-hides pinned tabs), a 3-agent plan-attack (internals + visuals/interaction + simplification), and a final confirmation pass. The attack caught real holes: the warm seam's fold-serialization was a phantom (`foldField` is unexported/would throw — folds already persist via `folds.json`); the capture-identity races the switch (freeze `(tabId,navKey)` at mount); `applyTree` reconciles only the singular selection so inactive tabs would error on activate; the marquee drag "reuse" is actually two engines (single-zone reflow vs vertical portal-overlay), so cross-divider drag-to-pin is bespoke — deferred to a Prospect, within-zone reorder ships. Every finding was opened in the code before folding.

**Nathan's late calls, folded:** within-zone reorder drag only; plain `×` hover-fade (the chip melt needs a solid fill glass tabs lack); warm-instant switching (short-circuit the refetch — kills the flash, makes `select()` warm-aware, accepted); tab set must sync cross-device; the empty/`'none'` state IS the new-tab page; open/close animation on `--duration-slow` + the sidebar/ribbon easing.

**Traceless clean rewrite + surface rename:** Both planning docs + `Navigation.md` (restructured to §II. NavWindow / Toolbar Tabs / NavPane / NavView) + a `History.md` paradigm entry + the `Framework.md` roadmap slot were rewritten to read as durable truth — every `[rev]`/review-scar removed (Nathan: "correct errors without a trace they were ever made"). **Surface rename (settled):** `NavPane`→**NavWindow** (the floating overlay), `NavMenu`→**NavPane** (the toolbar dropdown), + **NavView** (the new-tab page). The code rename is Phase 0 Task 0.0.

**Also this session (earlier):** committed the gallery `.hover-pop` scale tuning (1.0175) + a `Navigation.md` note that list-mode reorder uses insertion-line drag while galleries displace. The throwaway `TabBarPreview` is the visual seam the real tab bar grows from (deleted in Phase 6).

**Lessons Learned**

- **Ground a "reuse" claim in the actual mechanism before budgeting it as free.** The plan named three DRY reuses (drag / chip-× / group-+); all three transferred only partially — the drag was two separate engines (one vertical + portal-overlay), the chip melt needs a `--chip-fill` glass lacks, the group-+ gives only glyph+fade. "It's the same component" is a hypothesis until you trace what it actually does.

- **Verify every agent finding in the code — even a build-breaker's.** The 3-agent attack produced ~24 findings; opening each `file:line` confirmed the load-bearing ones (foldField unexported at `folding.ts:188`, the synchronous selection-set before the openPage await) AND caught one agent overstating (the simplification agent read cross-zone drag as drop-in; the visuals agent's deeper trace proved it vertical-only). Two agents disagreed; the code adjudicated.

- **A summary layer drifts after folds land.** After folding corrections into the decision entries, the log's Core recap still described the pre-fold world (stored `isPinned`, fold-in-cache, cross-zone drag). Sweep the recap/overview sections whenever a decision changes — the "source of truth" is exactly what a shape-building implementer reads.

**Key Files & Insights**

- **The three planning docs:** `Planning/Multi-Tab Nexus — Decision Log.md` (ratified spec, decision IDs) · `— Implementation Plan.md` (6 phases + a consolidated visual-knob block) · `— Implementation Kickoff Prompt.md` (the compact-then-execute prompt).
- **Warm seam grounding:** `MarkdownPM/index.tsx:109-246` (mount-once, destroy-on-unmount) + `:251-262` (the readOnly compartment-reconfigure — the reconfigure-without-remount precedent) · `folding.ts:188` (`foldField` private, unexported) · `historyField` is the real serializable export.
- **Persistence template:** `navState.ts` (debounced writer + drain at `before-quit` `index.ts:1656` AND `adoptNexus` `:398`) — the tabs sidecar reuses this shape, synced (in `NEXUS_CONFIG_FILES`, not `DEVICE_LOCAL_NEXUS_FILES`).
- **Drag reality:** two engines behind `interactions/` — single-zone `engine.tsx` (`SortableZone`, in-place reflow, what the gallery uses) vs cross-list `group.tsx` (`DragGroup`/`GroupZone`, vertical + portal-overlay). Within-zone reorder is the safe reuse.

**User Feedback**

- Nathan drip-feeds mid-turn design calls — fold each immediately; his effect-words are literal; when he says "let's try both" confirm it's actually free before promising it.
- Documents must correct errors traceless (durable truth, no scars); Considered & Rejected carries provenance, the decisions read clean.
- Point to UIX knobs, don't tune — every visual value goes in one knob block + the final report.

**Uncertain**

- The `NavWindow`/`NavPane`/`NavView` rename table (which surface got which name) — stated confidently but a rename is easy to flip; **Nathan to sanity-check in the morning**.
- `Compactions: 4` is best-effort from the transcript markers; the exact count may be off by one.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Plain `.css` DOES HMR reliably.

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit unless authorized. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Read the summary line, never a piped exit code. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's. **main is ahead of origin, unpushed** — Nathan pushes in batches; merge ≠ push. *(This session pushed the multi-tab planning to origin per explicit instruction — a deliberate exception.)*

### Next Session

**Execute the Multi-Tab Nexus plan.** Paste `Planning/Multi-Tab Nexus — Implementation Kickoff Prompt.md` after compacting — it's self-contained (standing directives + the task). Build **phase by phase, in order**, with the mandatory per-phase `build-breaking-agent` + `code-simplifier` review (verify findings in code before folding), gates between each.

- **Start: Phase 0 Task 0.0** — the surface rename (`NavPane`→`NavWindow`, `NavMenu`→`NavPane`), then the pure tab model + inline store wiring (tests-first, headless).
- **Phase 2 (the warm seam) is highest-risk** — against the `key=`-remount grain, and warm-instant is a deliberate `select()` change; its per-phase review is the heavy one. Ship it staged (flat current-tab warmth → then the ~20-cap back-stack).
- **Phase 4 (tab bar)** runs the §J UIX-repass *before* building + a post-functional UIX review *after* — screenshot-verify.

**Nathan's morning to-dos (before or during the build):** (1) sanity-check the `NavWindow`/`NavPane`/`NavView` rename table wasn't flipped; (2) eyeball the visual-knob block's starting values (`Plan` → Visual Knob Block) — tab min/pref/max widths, glyph sizes, the edge-fade, the `+` gutter.

**Nav surface follow-ups (lower priority, not the tab work):** NavPane (the dropdown, formerly NavMenu) content is still an open call — what a compact nav dropdown holds vs the fuller NavWindow. Drag-reorder recents is a logged nav-layer QOL Prospect (genuinely small — reuse the pin `SortableZone` + a `reorderRecent`).

### Pending Focuses

- **Multi-Tab Nexus build** — the active arc; execute the ratified plan (above). Everything else is subordinate until it ships.

- **NavPane dropdown content decision** — the toolbar nav dropdown (renamed from NavMenu) is a blank placeholder; settle what it's for before building into it.

- **User Sections CRUD (the "Add Heading" feature).** Collections render user sections but there's no way to make one (`mutate.ts` has zero section ops). Own brainstorm→plan→build. → `Sidebar.md`.

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deferred (→ [[Views]]; `flat` GroupConfig kind stays reserved).

- **(Perf) Standing debt:** no row virtualization (every row MOUNTS — bites at thousands); external VALUE edits don't live-refresh an open table. (The multi-tab warm-B design deliberately avoids needing table virtualization — one view mounted.)

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the code is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **iCloud-sync readiness (future):** `serializeOnFile` can't coordinate with the iCloud daemon (LWW); `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders. *(The multi-tab `tabs.json` is deliberately synced under this same LWW model — single-user, concurrent live edits out of threat model.)*

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; no build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore`. *(Note for the multi-tab build: `tabs.json` is intentionally synced, so it should NOT be added to this ignore list.)*

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED)** — a visual inset, not a stored char.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → [[MarkdownPM]].

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it — a fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count; a merged arc compresses into Recent Work. Carry still-open Pending + Fix Log forward.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another's block.
