## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — detail lives in `Features/*` + `History.md`.

- **Navigation Surface + NavPane redesign + gallery (shipped, on `nav-gallery-pins`).** The per-Nexus nav-state layer (recents/pins/favorites in synced sidecars + `.nexus/pins/` per-pin store, resolved live via `navResolve`, render-prune-never-storage-prune), a `useNavData` read side both surfaces share, client-side fuzzy search, the movable `GlassPane` NavPane (now renamed **NavWindow**), and its Figma gallery card form + list rows + inset pin marker + thumbnail-capture pipeline. → [[Navigation]] + `History.md`.

- **Block Surfaces — SurfacePM (shipped + merged to main).** Host-agnostic block/tile system: split-tree layout, window-style edge resize, PommoraDND feel, markdown/page/view tiles behind the BlockHost seam, CM6-portal page embeds, block `[[links]]` as edges, geometry-only homepage lock, per-block Scale. → [[SurfacePM]] + `History.md`.

- **App-wide auto-scroll (shipped, on main).** One shared `interactions/autoscroll.ts` singleton rAF loop drives every drag's edge-scroll — one fixed scroller resolved once, px/sec × dt (ProMotion-safe), distance-accel + direction-intent. → [[PommoraDND]] §II. Autoscroll.

- **Tables · PropertiesV2 · Multi-View · Icon Picker + Sidebar Ribbon.** The cell-gesture matrix + per-view looks + band drag + grouping/sorting + borderless toggle; nexus-wide property registry; ViewDropdown/Pane/Settings; full-Lucide picker; ribbon + mode-switched sidebar. → [[TableView]] · [[Views]] · [[Properties]] · [[Icons]] · [[Sidebar]].

### Session Summary — Multi-Tab Nexus: Brainstormed → Ratified → SHIPPED

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026 → 07-16-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 5
**Connectors:** none
**Commands:** /compact · /handoff
**Agents:** build-breaking-agent (11x - review) · code-simplifier (3x - simplify) · Explore (4x - grounding) · feature-dev:code-explorer (1x - warm-trace) · general-purpose (1x - simplify)
**Skills:** studio-brainstorm · superpowers:writing-plans · handoff

The session ran the full arc: the navigation model's deferred paradigm fork (**B-1**) was brainstormed, ratified, and then **built end-to-end** — all six plan phases shipped green with per-phase review folds, a final full-diff review (two build-breakers + a simplifier), and a live CDP pass against an isolated test nexus. The feature is on `nav-gallery-pins`, pushed to origin; the full morning report (divergences + the dangling sweep + the knob table + screenshots) closed the session.

**The spec arc (first half):** Warm, state-preserving Toolbar Tabs, grounded against real code, ratified through three review rounds — the phantom `foldField` serialization, the capture-identity race, and the two-drag-engines reality all caught pre-code. **One view mounted, a per-tab serialized cache** (seed a fresh CM6 mount from a cached `historyField`; folds ride `folds.json`); pins ARE the pinned-tab set (`isPinned` derived, never stored); the set persists + syncs (`tabs.json`); per-tab Back/Forward; one `openTab` predicate. → `Planning/Multi-Tab Nexus — Decision Log.md`.

**The build arc (second half):** Six phases, each gated (typecheck + full vitest) and review-folded before the next: the surface rename (`NavPane`→NavWindow, `NavMenu`→NavPane) · the pure `tabsModel` + tab-aware `select` (zero caller churn — every genuine nav maintains the set; `record:false` re-selects don't) · the synced `tabs.json` sidecar with lenient sanitize + both drains · the warm seam (a 20-per-tab LRU keyed `(tabId, navKey)`; `pageDetail` captured at switch-initiation, editorState/scroll at unmount under mount-frozen identity; warm-instant renders with no fetch and no flash) · the four stateful "Open in New Tab" points · the tab bar (pinned compact icons + accent pin badge, min/pref/max strip + edge fade, chip-× plain fade, trailing +, within-zone drag per zone, Ctrl+Tab cycling, ghost-based width-collapse close, reveal-on-hover setting) · NavView (the new-tab page = the empty state, full-window gallery + search; a NavView tab reads "New Tab" under the copy glyph) · the thumbnail capture gate.

**Review folds that earned their keep:** the Back/Forward target-lockstep fence (a stale `tab.target` mis-deduped the next click, destroying the Forward stack); the main-side `adopting` gate (a mid-adopt renderer save could land in the NEW nexus's synced sidecars — recents had the same hole); the stale-fetch fence (warm-instant made an old benign fetch race deterministically clobber the shown page — reproduced against the real store); C-6's live twin (`graduatePinCovered` — pinning an open entity from ANY surface graduates its tab instead of duplicating, synced-in pins included); store-first ghost close (the 350ms animate-then-mutate limbo let a dying tab be dedup-focused and cycled into); the capture-gate markers dying with evicted files.

**Live verification (isolated):** the built app ran against `~/Test` with Nathan's `pommora.json` backed up and restored byte-identical. Verified live: NavView as the fresh-nexus empty state; the bar blank at one tab (D-6); menu spawns appending right; warm switch with `loading:false`; pin graduation + the divider; ×-close MRU focus; the `+` → NavView; and the D-8 headline — **quit → relaunch restored the pinned tab + both unpinned tabs + the active pointer, cold**. `tabs.json` on disk matches the contract exactly (unpinned only).

**Lessons Learned**

- **Ground a "reuse" claim in the actual mechanism before budgeting it as free** — all three named DRY reuses (drag / chip-× / group-+) transferred only partially; the spec's phrasing survived because the reviews traced what each component actually does.

- **Verify every agent finding in code — and the reviews keep earning it.** Eleven build-breaker dispatches across the session; every fold was self-verified at the cited `file:line` first. The heavy Phase-2 pass reproduced its HIGH against the real store (not a hypothesis); the final pair found the two-writers desyncs (`pinTarget` vs `pinTab`, marker vs file) no single-phase review could see.

- **Two writers for one fact is THE recurring defect class this feature bred:** tab.target vs navStack cursor, the tab set vs the pins set, the capture marker vs the thumbnail file, the store vs the closing animation. Every real MED+ finding reduced to one of these; the fix was always "one writer, or a lockstep rule."

- **CDP synthetic clicks don't fire PickerMenu MenuItems** (they hit the right element per elementFromPoint but the onClick never runs; tab/row/button clicks work fine) — drive menu items via `el.click()` in `Runtime.evaluate`. Same harness-quirk family as the chip-melt CDP lessons.

**Key Files & Insights**

- **The feature lives under `Tabs/`:** `tabsModel.ts` (pure, 30+ tests) · `warmCache.ts` (session LRU) · `TabBar.tsx`+`tabBar.css` (every visual knob in the `.tab-bar` block) · `TabContextMenu.tsx` · `NavView.tsx`. Store wiring inline in `store.ts`; the sidecar in `main/io/tabsState.ts`.
- **`select` is the one nav entry:** the record path maintains the tab set via the pure model; `record:false` (activate/Back/refetch) only refreshes the shown detail. The warm-instant short-circuit + stale-fetch fence live in its page case.
- **`applyTree` reconciles every tab** off ONE `buildReconcileIndex` (`selection.ts` split into index + `reconcileWith`); deleted entities close unpinned tabs and render-hide pinned ones.
- **Persistence:** `tabs.json` synced (in `NEXUS_CONFIG_FILES`, deliberately NOT device-local), debounced main-side, drained at `before-quit` + `adoptNexus`, sanitized on read (`readTab` enforces every store invariant for the cross-version file).

**User Feedback**

- Nathan drip-feeds mid-turn design calls — fold each immediately; his effect-words are literal. This session's morning drops: the NavView tab wears the lucide `copy` icon; the Homepage tab wears the nexus photo (home glyph only when unset); pinned-tab Back/Forward is simply disabled (ratifying my flag).
- Documents correct errors traceless; the final report must disclose every divergence + the knob table.
- Point to UIX knobs, don't tune — all tab-bar values sit in `tabBar.css`'s `.tab-bar` block.

**Uncertain**

- Nathan's "'New Tab' uses lucide copy icon" was read as the NavView **tab's** icon (built that way, verified live); if he meant the trailing `+` affordance too, it's a one-line swap in `TabBar.tsx` (the `+` renders `plus`).
- `Compactions: 5` is best-effort; may be off by one.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Plain `.css` DOES HMR reliably.

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit unless authorized. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Isolated live runs:** back up `~/Library/Application Support/pommora-react/pommora.json`, point `lastNexusPath` at `~/Test`, launch the BUILT app with `--remote-debugging-port`, restore byte-identical after. CDP synthetic clicks work on tabs/rows/buttons but NOT on PickerMenu MenuItems — drive those via `el.click()` in `Runtime.evaluate`. Native menus BLOCK headless (never pop one via CDP).

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Read the summary line, never a piped exit code. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's. **main is ahead of origin, unpushed** — Nathan pushes in batches; merge ≠ push. *(This session pushed `nav-gallery-pins` to origin per explicit instruction — a deliberate exception.)*

### Next Session

**Multi-Tab Nexus shipped — the next session starts with Nathan's live drive.** He runs the real app against the bar (the session-report screenshots preview it) and tunes the knobs himself: every visual value sits in `tabBar.css`'s `.tab-bar` block (+ `navView.css` for the new-tab page). The §J repass values were built as best-record starting points — expect nudges to `--tab-pref`/`--tab-max`, the pinned width, and the `+` gutter.

- **Design calls awaiting his eye (all disclosed in the session report):** the active-tab treatment is a color-fade, not the prototype's clip-slide (interactive ×s fight the duplicate-track pattern); pinned name-on-hover is a native tooltip; the `+` parks at the trailing edge even when the strip is sparse; the pinned zone clips (no collapse UI) past its width.
- **Deferred with eyes open:** a failed mid-adopt leaves a short window where an old-nexus save could land in the new nexus's sidecars (LOW; the error screen blocks most paths); NavWindow's list-mode Remove on a pinned row is a pre-existing no-op quirk.
- **Prospects unlocked, not built:** cross-divider drag-to-pin, drag-reorder recents, per-window tab sets, tab tear-out, `⌘1–9`/`⌘W`/`⌘T` (need per-shortcut sign-off).

**Nav surface follow-ups (lower priority):** NavPane (the toolbar dropdown) content is still an open call — what a compact nav dropdown holds vs the fuller NavWindow.

### Pending Focuses

- **Multi-Tab UIX repass (Nathan-driven)** — the live knob-tuning drive over the shipped bar; fold his nudges, then close the arc.

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
