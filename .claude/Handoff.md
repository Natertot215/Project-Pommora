## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary — Cards view: prototype → ratified plan → executed + hardened

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026 → 07-19-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 9
**Connectors:** none
**Commands:** /compact · /code-review · /handoff
**Agents:** build-breaking-agent (review ×2) · code-simplifier (×2) · Explore (grounding) · general-purpose
**Skills:** studio-brainstorm · superpowers:writing-plans · superpowers:systematic-debugging · coderabbit:code-review · handoff · project-context

**What Started:** This long-running session (same ID since 07-14) shipped Multi-Tab Nexus, Page Previews, and Unified Subfield + Scan-Promote to **v0.5.0**, restructured the project docs, then brainstormed + ratified the **Cards view** and built it visuals-first as a prototype. It resumed post-compaction on the ratified [[Cards View — Implementation Plan]] (V4) with one directive: execute all 8 phases inline on `cards-view`, hardening the prototype into the complete renderer. Nathan then went to bed mid-run with a standing brief — do it as perfectly as possible without hand-rolling, commit the intentional doc reorg, live-test the value interaction on the real Ideas nexus, and report at the end.

**What Happened Along the Way:** Executed the plan phase-by-phase, each green + committed with explicit paths: P1 hardening, P2 value interaction (right-click value menu reusing the lifted `cellMenuContextFor`, add-picker panes for date/number/url/checkbox, inert heading-"+", property-picker grouping per Nathan's mid-flight spec — pane-kinds on top), P6 per-type icon, P4 Sort-by-Location flatten, P5 Set-Card drag via `moveSet`, P3 native card menu + `viewFormatMenu` retirement. Two plan claims proved softer than written and were folded honestly rather than manufactured: the `card_size` non-finite guard was already enforced by **Zod 4's `z.number()`** (shipped as an invariant test), and the manual-order "read gap" matched the table verbatim (extracted `resolveManualOrder`, kept the gate). Mid-execution Nathan live-reported the real blocker — clicking a card value/breadcrumb did nothing. Root-caused via CDP against real Ideas: the whole card is a drag handle and the drag engine **pointer-captures on pointerdown** (`engine.tsx:387`), retargeting every inner click to `.page-card`, so it opened the page instead of the picker. Fixed by stopping pointerdown on the interactive zones (containers only on their own empty space, so the title still drags); **verified live** — the Status picker opens. Closed with a code-simplifier pass (single-sourced the page-meta menu into `@shared/pageMenu.ts`) and a build-breaker pass that caught **F1** — `manualOverride` leaking across a cards→cards view switch (the reset sat in the `[source.path]` effect, not `[view.id]`, and two cards views share the instance) — folded, plus F3 (empty add-picker guard).

**What It Ended With:** The Cards view is complete + hardened on `cards-view` (**HEAD `b7e6df1b`**): all 8 phases shipped, the critical pointer-capture bug fixed + live-verified, the build-breaker's MED blocker folded, the [[Cards]] feature doc written + Views.md reconciled, the intentional doc reorg committed. Gates green — typecheck clean, **1719 tests**, build exits 0. The persistent thumbnail cache (B-6) had shipped earlier this session (`81ab02d7`). VERIFIED live: value-click → picker (screenshot). ASSUMED (built + model-tested, not live-driven): the native card menu (Rename/Change Icon/Add Property), Compact styling, and the add-flow click-through — CDP can't drive OS-level menus or the settings-pane toggles.

**Next Session:** (1) Nathan's UIX sign-off on Compact (Phase 7), the native card menu, and the add-flow feel — then merge `cards-view` → main. (2) The a11y pass — replace the cards' `biome-ignore noStaticElementInteractions` stubs with roles/keyboard. (3) Optional F2 — the Set-Card drag flashes (no optimistic reorder, ratified v1); add an optimistic `sets` override if the snap bugs him.

**Session Pointers**

- **Cards renderer:** `Detail/Views/Cards/` — CardsView · CardValue · CardAddPicker · `cardsOrder.ts` · `cardValueInput.ts` · `cardsBand.ts` (the pure seams are unit-tested). The shared menu model lives in `@shared/cellMenu.ts` (`cellMenuContextFor`, lifted from TableView) + `@shared/cardMenu.ts` + `@shared/pageMenu.ts` (the single-sourced page-meta block).
- **Sort-by-Location:** `location_flatten` field (`shared/views.ts`) → `locationFlat` wrapper (`pipeline/group.ts`) → gated on `flattenStructural` in `resolveView.ts` so it can't touch a table; the SortingPane switch is cards-gated.
- **CDP live-drive harness:** scratchpad `cdp.mjs` (Node's global `WebSocket` → `:9222`, `Runtime.evaluate` + `Input.dispatchMouseEvent` + `Page.captureScreenshot`); launch an isolated instance via `--user-data-dir=<scratch>` with a seeded `pommora.json` pointing `lastNexusPath` at the real nexus (no single-instance lock, so it coexists with the dev app).
- **Docs:** [[Cards]] is the new feature doc; [[Views]] reconciled to Table+Cards drawing.

**Landmines**

- **`FrameworkPM.md` mirror-script bug** (Nathan: "don't worry") — reappears untracked in `.claude/`; never commit it.
- **CDP-driving the cards pickers commits to real frontmatter** (same class as the editor-autosave rule in `Context.md`) — revert what you set, or point the isolated instance at `~/Test`.

**User Feedback**

- **"do it as perfectly as possible while not handrolling anything you dont have to"** — reuse over reinvent drove the whole run (the `cellMenuContextFor` lift, IconPicker/TextPicker reuse, the `.group-add` pattern, the Switch row).
- **"commit the doc deletions + changes (those are intentional)"** — the parallel doc reorg was authorized; committed it (Design→DesignPM, Deployment→Resources).
- **"test... my live nexus in Ideas... apply them across a row so you can compare... read them instead of senduserfile — i cannot see senduserfile on mobile, only read."** — live-verify on real data; Read screenshots yourself, never SendUserFile on mobile.
- **Property-picker order:** pane-kinds (status/select/multi-select/context) to the top, the simpler kinds below, property order within each group; the native Add-Property menu reads the same.

**Uncertain**

- The native card menu (Rename/Change Icon/Add Property), Compact styling, and the compact/breadcrumb add-flow feel are built + model-tested but **not live-verified** — CDP can't drive OS menus or the settings toggles. Nathan's manual pass is the confirmation.
- `Pommora/scripts/make-icon.mjs` deletion sits uncommitted in the tree (parallel session, not a doc) — left untouched.
- `Compactions: 9` is best-effort across this multi-day session.

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
