## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary — Cards view: prototype → ratified plan → executed + hardened

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026 → 07-20-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 10
**Connectors:** none
**Commands:** /compact · /code-review · /handoff · /dispatching-parallel-agents
**Agents:** general-purpose (≈25 — the 8-type interaction audit, the 11-agent verification sweep, menu-bug + DRY + screenshot-opinion dispatches) · build-breaking-agent (×4) · code-simplifier (×5)
**Skills:** studio-brainstorm · superpowers:writing-plans · superpowers:systematic-debugging · coderabbit:code-review · handoff · project-context

**What Started:** This long-running session (same ID since 07-14) shipped Multi-Tab Nexus, Page Previews, and Unified Subfield + Scan-Promote to **v0.5.0**, restructured the project docs, then brainstormed + ratified the **Cards view** and built it visuals-first as a prototype. It resumed post-compaction on the ratified [[Cards View — Implementation Plan]] (V4) with one directive: execute all 8 phases inline on `cards-view`, hardening the prototype into the complete renderer. Nathan then went to bed mid-run with a standing brief — do it as perfectly as possible without hand-rolling, commit the intentional doc reorg, live-test the value interaction on the real Ideas nexus, and report at the end.

**What Happened Along the Way:** Executed the plan phase-by-phase, each green + committed with explicit paths: P1 hardening, P2 value interaction (right-click value menu reusing the lifted `cellMenuContextFor`, add-picker panes for date/number/url/checkbox, inert heading-"+", property-picker grouping per Nathan's mid-flight spec — pane-kinds on top), P6 per-type icon, P4 Sort-by-Location flatten, P5 Set-Card drag via `moveSet`, P3 native card menu + `viewFormatMenu` retirement. Two plan claims proved softer than written and were folded honestly rather than manufactured: the `card_size` non-finite guard was already enforced by **Zod 4's `z.number()`** (shipped as an invariant test), and the manual-order "read gap" matched the table verbatim (extracted `resolveManualOrder`, kept the gate). Mid-execution Nathan live-reported the real blocker — clicking a card value/breadcrumb did nothing. Root-caused via CDP against real Ideas: the whole card is a drag handle and the drag engine **pointer-captures on pointerdown** (`engine.tsx:387`), retargeting every inner click to `.page-card`, so it opened the page instead of the picker. Fixed by stopping pointerdown on the interactive zones (containers only on their own empty space, so the title still drags); **verified live** — the Status picker opens. Closed with a code-simplifier pass (single-sourced the page-meta menu into `@shared/pageMenu.ts`) and a build-breaker pass that caught **F1** — `manualOverride` leaking across a cards→cards view switch (the reset sat in the `[source.path]` effect, not `[view.id]`, and two cards views share the instance) — folded, plus F3 (empty add-picker guard). Then a live-driving pass with Nathan redirected the design: Sort-by-Location moved from a switch to standard controls — **flatten via Group By: None** (the `flat` kind, headerless) and a **Sort By: Location** entry (Order Location/Custom), the `location_flatten` field dropped; the property picker gained the **chevron-on-top** order (checkbox sinks) and a **more compact** layout; `Cards.md` → `CardView.md`. All re-verified live on real Ideas (headerless flatten, fs order, chevron order, compact picker) via a sidecar-driven relaunch — the settings-pane toggles proved un-CDP-drivable.

The back half was a hardening campaign in three waves, each agent-fanned then hand-verified. **Wave 1 — the interaction sweep** (8 read-only agents, one per property type): killed the compact chip ×-steal value-loss class, gave cards the table's alias-preserving link seam (Edit rode the alias, Rename became a real alias editor), redesigned the add menu around "list exactly what's not shown, picking reveals," and landed the perf caches (Intl formatters, tier context-options, the datetime-gate). **Wave 2 — features on top:** the number Bar look (full-width own-row, `numberDivisor` gating all four surfaces), the cross-file DRY hoists (DatetimeValuePicker, pickSemantics merge, tierWrite), body-semibold titles via one `cardTitleType`, the imageless 2-row reserve, the always-footing breadcrumb, the context-×'s own color, and one `--chip-pad-x` across every text-chip shape. **Wave 3 — the verification sweep** (11 agents: 8 types × Compact+Standard, picker-lifecycle, merge-scope, perf): its confirmed catch-list — a P0 calendar sub-menu z-burial regressed on 07-15, the dead remove-only menu, the add-pane Back blur-commit, a StrictMode spurious calendar write, compact's un-settable blank tiers — all folded. Nathan's four closing directives landed as the **Bloom architecture**: the inert-until-revealed chip ×, the ×-drop gate re-keyed on measured embed zoom, calendar sub-menu exit presence, and `CardPickerHost` — ONE grid-level home for the value/calendar/add pickers so row churn can never tear one open (dev-guard enforced in PickerMenu). Two settings-menu bugs closed the run (a shared `DragGhost` for the grouping/option/status drags that had NO lifted chip — the "behind the glass" read — and menu titles restored to the ratified label-primary a stale comment had baited to control), plus the card image band's native Add/Change/Remove Cover-or-Banner menu on the PageHeader flow.

**What It Ended With:** The Cards view is complete, hardened, and verification-swept on `cards-view` (**HEAD `6326e14c`**): the renderer, the interaction matrix for every property type in both layouts, the grid-level picker host, and the settings-menu fixes are all committed with the docs ([[CardView]] reconciled). Gates green — typecheck clean, **1738 tests**, build exits 0. VERIFIED live via the CDP harness: the full picker cycle on the host (open through the inert-× → toggle-commit stays open → animated click-out → reopen), the bar + context rendering, the compact reserve/footing. ASSUMED (built + gated, not live-driven): the banner right-click menu and menu-drag ghosts (main-process + pane surfaces land at the next full dev launch), and the label-primary restore.

**Next Session:** (1) Nathan's live pass over the new picker architecture + the banner menu + the settings-menu fixes, then merge `cards-view` → `main`. (2) The perf plan's top item — the identity-stabilization bundle (recycle ViewRows by id, stable per-band arrays, re-key the ctx memo) so one commit re-renders one card instead of the grid; then the drag shell/body split. (3) The merge-scope top-3 (the shared optimistic-values hook, PreviewInspector seam adoption — it writes unnormalized urls today, the per-type gesture map).

**Session Pointers**

- **Cards renderer:** `Detail/Views/Cards/` — CardsView · CardValue · CardAddPicker · `cardsOrder.ts` · `cardValueInput.ts` · `cardsBand.ts` (the pure seams are unit-tested). The shared menu model lives in `@shared/cellMenu.ts` (`cellMenuContextFor`, lifted from TableView) + `@shared/cardMenu.ts` + `@shared/pageMenu.ts` (the single-sourced page-meta block).
- **Flatten + location order:** Group By: None (the `flat` kind → headerless in cards) + a Sort By: Location entry (reserved `LOCATION_SORT` in `shared/views.ts`, Order Location/Custom, `locationFlat` in `pipeline/group.ts` for its fs order), both cards-gated via `flattenStructural`. This replaced the earlier `location_flatten` switch (field dropped) on Nathan's redirect.
- **CDP live-drive harness:** scratchpad `cdp.mjs` (Node's global `WebSocket` → `:9222`, `Runtime.evaluate` + `Input.dispatchMouseEvent` + `Page.captureScreenshot`); launch an isolated instance via `--user-data-dir=<scratch>` with a seeded `pommora.json` pointing `lastNexusPath` at the real nexus (no single-instance lock, so it coexists with the dev app).
- **Picker architecture:** `Cards/CardPickerHost.tsx` — the ONE grid-level home for the value picker + calendar + add menu (requests via cardApi `onOpenValuePicker`/`onOpenAddPicker`); `cardValueInput.ts` holds the pure `shownColumnsFor`/`addEntriesFor`/`addColumn` seams + `ADDABLE_TYPES`. PickerMenu dev-errors if unmounted mid-open — mount persistently, ride `open`.
- **Drag ghosts:** `Components/Detail/DragGhost.tsx` (the table-band chip recipe) rendered from `useGroupingListDrag` / `useOptionReorder` / `useStatusReorder`; the ghost coords ride each hook's `ghost` field.
- **Docs:** [[CardView]] is the feature doc (reconciled through the hardening); [[Views]] reconciled to Table+Cards drawing. The merge-scope + perf ranked plans are summarized in Next Session.

**Landmines**

- **`FrameworkPM.md` mirror-script bug** (Nathan: "don't worry") — reappears untracked in `.claude/`; never commit it.
- **CDP-driving the cards pickers commits to real frontmatter** (same class as the editor-autosave rule in `Context.md`) — revert what you set, or point the isolated instance at `~/Test`.
- **The chip remove-× is opacity-gated in JS** (`ChipRemoveButton` reads computed opacity at click time) — a CDP click can't hover-reveal it first, so drives always fall through to the picker; only a real mouse exercises the remove path.
- **A rename that re-sorts the grid can still clip the TextPicker's exit** (it rides the card; accepted edge) — the value/add pickers are host-owned and immune.

**User Feedback**

- **"do it as perfectly as possible while not handrolling anything you dont have to"** — reuse over reinvent drove the whole run (the `cellMenuContextFor` lift, IconPicker/TextPicker reuse, the `.group-add` pattern, the Switch row).
- **"commit the doc deletions + changes (those are intentional)"** — the parallel doc reorg was authorized; committed it (Design→DesignPM, Deployment→Resources).
- **"test... my live nexus in Ideas... apply them across a row so you can compare... read them instead of senduserfile — i cannot see senduserfile on mobile, only read."** — live-verify on real data; Read screenshots yourself, never SendUserFile on mobile.
- **Property-picker order:** pane-kinds (status/select/multi-select/context) to the top, the simpler kinds below, property order within each group; the native Add-Property menu reads the same.
- **"No matter what, a picker when closed must have its bloom-in/out animation"** — the Bloom law is absolute; the host + persistent mounts + the dev-guard are its enforcement, and a regroup tearing a picker was "a real issue that must not be deferred."
- **The × stays if inert** — keep the chip × everywhere once un-hovered clicks pass through; the drop-entirely gate keys on embed zoom (~0.8), "since that's where chips can get sized down."
- **Calendar sub-menu clicks should NOT ladder** — one outside click closes submenu + picker together (Escape still ladders innermost-first).

**Uncertain**

- The banner right-click menu, the settings-pane drag ghosts, and label-primary titles are built + gated but not live-verified (main-process/pane surfaces — they land at the next full dev launch).
- The ×-steal residual on short chips is closed by the inert-× in principle; the hover-reveal threshold (opacity > 0.5 at click) is untuned against real mouse feel.
- `Pommora/scripts/make-icon.mjs` deletion still sits uncommitted (parallel session) — left untouched.
- `Compactions: 10` is best-effort across this multi-day session.

---

### Recent Sessions

- 07-14 → 16 · `nav-gallery-pins` · Navigation surface + NavPane/NavWindow redesign + gallery, then Multi-Tab Nexus shipped end-to-end.
- 07-16 → 17 · `main` · Page Previews (floating tabbed mini-app) + Unified Subfield + Scan-Promote shipped; closed the rebuild at v0.5.0.
- 07-10 → 13 · `surfacepm` · SurfacePM block surfaces shipped + merged.

### Working Notes

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `… npm run build`; read the summary line, never a piped exit code (`set -o pipefail`). Biome auto-formats on write — never run it, never hand-align.
- **Cards CDP live-drive:** the reusable harness (`cdp.mjs` + isolated `--user-data-dir` on the real nexus) is in this session's scratchpad; native menus + settings-pane toggles are NOT drivable — verify those by hand.

### Rules

- Resolve = delete + route, never tag — no (resolved) / (fixed) tombstones.
- No standing content here — Pending Focuses / Fix Log / durable rules live in `Context.md`.
- One block per session, in place; parallels share the doc, never edit another's block.
- Verify before finalizing — run the no-stale-state checklist.
