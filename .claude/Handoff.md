## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary — v0.5.0 shipped + docs restructured, then the Cards view prototype

**Session ID:** 1968ae09-ee23-4a88-9c0d-3a665384fd8e
**Dates:** 07-14-2026 → 07-18-2026
**Model:** Opus 4.8 (1M)
**Compactions:** 8
**Connectors:** none
**Commands:** /compact · /code-review · /handoff
**Agents:** build-breaking-agent (review) · code-simplifier (simplify/cleanup) · Explore (grounding) · general-purpose (simplify)
**Skills:** studio-brainstorm · superpowers:writing-plans · coderabbit:code-review · handoff · context

**What Started:** This long-running session (same ID since 07-14) had already brainstormed, ratified, and shipped **Multi-Tab Nexus**, then **Page Previews**, then **Unified Subfield + Scan-Promote** — all green, CDP-verified against the real Nexus, recorded in `History.md`. It resumed post-compaction on the live UIX tail of the Subfield work, then turned to a directive to restructure the project docs and stand up the new Handoff/Context split.

**What Happened Along the Way:** First the UIX batch, all CDP-verified: the New Tab `+` now rides flush against the swallowing inspector cluster via one shared `--toolbar-swallow` magnitude — Nathan's "make the compression shared" instinct, proven right (float-over for the trio vs stop-at-edge for the tab-bar are *different* behaviors, not a DRY violation); the list-row pin-hover was DRY'd onto the gallery's mechanism through a shared `NavPinButton`, rest-state dimmed to `--label-tertiary`. Then the doc pass: `History.md` reframed as a **Completion Timeline (Descending)** with the `Locked`/`Ratified` decision-registry framing stripped and the four densest entries trimmed of identifier-dumps (Nathan: keep detail, but "shouldn't describe functions like the docs do"); `Framework.md`'s lost 07-04 → 07-17 milestones filled in, **SurfacePM moved into the completed arc** where it shipped, and the roadmap re-baselined off **v0.5.0**; `CLAUDE.md`'s scattered stack/electron/build facts consolidated into one **Stack & Build** section, the design-token rule enhanced, and a verified **Design-System Map** code-pointer added (tokens → `theme-vars.css.ts`/`tokens/*`, components, surfaces, the Bloom pane-open primitive). A code-simplifier pass over the last 10 commits came back clean — the recent work was already lean. Then the session's main event, the **Cards view**: brainstormed from 14 upfront decisions through a 3-round adversarial review into a ratified [[Cards View — Decision Log]] — first mis-named "Gallery," corrected to **Cards** (gallery stays a separate reserved ViewType) — then built **visuals-first on the `cards-view` branch** as a deliberately un-reviewed prototype: the renderer seam (both ViewSettings doors + `ViewEmbedBlock`), the Set Cards row, flattened disclosure bands, the breadcrumb-as-add-input, in-band drag, per-value interaction (`CardValue`, reusing the PropertyEditing leaves), the two-stage add-picker, and a DRY design-system `Slider`; a view-save double-walk and a hover-pop jitter got fixed en route.

**What It Ended With:** The v0.5.0 work + doc restructuring are committed + pushed to `main` through `d0a0bb60` (v0.5.0 = rebuild-complete baseline; Page Previews + Subfield unification closed the React rebuild of the Swift paradigm). The **Cards prototype** is on the `cards-view` branch (commits `dd6f6d1b` → `b530d097`), gates green at the last full run (1681 tests, typecheck clean) — but it's a **visuals-first proof, not the hardened build**, and **nothing covers CardsView itself**. The carry-forward deliverable is [[Cards View — Implementation Planning Checklist]] (`83107b7b`) — pre-work, don't-forgets, quality gates, open decisions — written to feed the proper implementation-planning phase. One dangling uncommitted cards tweak sits in the tree: `slider.css.ts`'s `--slider-knob-scale` default 1→0.75.

**Next Session:** (1) Decide the `cards-view` prototype's fate — harden in place or rebuild against the plan — then run the implementation-planning phase off the checklist. (2) The prototype still owes its code-simplifier + build-breaking + post-functional UIX pass (held off to avoid churning files mid-live-drive). (3) **The persistent thumbnail cache (B-6) is decided but NOT built** — Preview covers still evict, so Preview mode reads as done but is half-true until the amend-only cache lands.

**Lessons Learned**

- **Shared magnitude beats a per-surface transform.** The `+` and the trio ride ONE `--toolbar-swallow` var on `.app-toolbar`; the tab-bar reads it as `margin-right`, the cluster as a `translateX`. Float-over vs stop-at-edge are two behaviors off one number, not duplication.

- **CDP clip math breaks under non-integer dpr (1.7 here).** `Page.captureScreenshot` clip + `scale:2` misframes; measure rects and trust the DOM, or crop the full-frame PNG with PIL. Non-integer dpr is the tell.

- **History is a changelog, not a spec.** Strip `Locked`/`Ratified` framing; describe the arc + decisions, leave function mechanics to the feature docs. Trim identifier-dumps (var/key names, gating conditions, hard test counts).

**Session Pointers**

- **Cards carry-forward:** [[Cards View — Implementation Planning Checklist]] + [[Cards View — Decision Log]] live in `Planning/`; the renderer is `Detail/Views/Cards/` (CardsView · CardValue · CardAddPicker · CardsView.css), mounted through the `ViewRenderer` seam that both `ContainerView` and `ViewEmbedBlock` consume.
- **The `+` ride:** `--toolbar-swallow` is defined on `.app-toolbar` (`Toolbar/toolbar.css`); `--trio-w` is published there by `Toolbar.tsx` (`el.closest('.app-toolbar')`); `Tabs/tabBar.css` reads it as the tab-bar's `margin-right`.
- **Shared pin toggle:** `NavPinButton` lives in `Navigation/NavList.tsx`, consumed by `NavRow` + `NavGallery`'s `GalleryCard`; hover-reveal CSS in `navList.css` / `navGallery.css`, dimmed via `--label-tertiary`.
- **The Design-System Map** (bottom of `CLAUDE.md`) points at every token + component source; shell geometry (`--content-inset`, `--io`…) is in `styles.css`, deliberately flagged as *not* a design token.

**Landmines**

- **Persistent thumbnail cache (B-6) — decided but NOT built.** Preview-mode covers evict on the recents∪pins window (`evictThumbs`); the fix retires the window-pruning, makes the cache amend-only, and moves cleanup to existence-pruning at the nexus-open hook. Real main-process work — Preview mode is half-true until it lands.
- **The `cards-view` branch is a visuals-first prototype, un-reviewed** — not the hardened build; a full quality-gate slate (CardsView tests, simplifier, build-breaker, UIX, a11y) is still owed. See the checklist.
- **`FrameworkPM.md` is an ongoing mirror-script bug** (Nathan: "don't worry") — it reappears untracked in `.claude/`; never commit it.
- **CDP editor writes autosave to Nathan's REAL Nexus** — drive the editor only on a throwaway page, never an existing file.
- **Non-integer dpr breaks CDP screenshot clips** (see Lessons) — full-frame + PIL crop is the reliable path.

**User Feedback**

- **"The most minimal fix possible"** — don't gold-plate a working solution; lock it and move to the next.
- **Docs:** History keeps detail but must not read like the feature docs — strip framing, trim excess, keep decisions. Framework past stays brief.
- **Always commit doc changes** (even a parallel session's or Nathan's own uncommitted edits), explicit-path staged — never `git add -A`.
- The **Thanos line** removed from `CLAUDE.md` was left out with the grammar fixed; restore only if he flags it accidental.

**Uncertain**

- `Compactions: 8` is best-effort across this multi-day session; may be off.
- Whether the `cards-view` prototype gets hardened in place or rebuilt against the plan — the checklist's headline open decision, Nathan's call.
- A `.claude/Context.md` now exists untracked (a context-skill run or a parallel session's doc reorg — unconfirmed which); a docs reorg is also in flight in the tree (`Design.md → DesignPM.md`, `Deployment.md → Resources/`), left untouched.

---

### Recent Sessions

- 07-14 → 16 · `nav-gallery-pins` · Navigation surface + NavPane/NavWindow redesign + gallery, then Multi-Tab Nexus (warm toolbar tabs) shipped end-to-end.
- 07-16 → 17 · `main` · Page Previews (floating tabbed mini-app) + Unified Subfield + Scan-Promote shipped; closed the rebuild at v0.5.0.
- 07-10 → 13 · `surfacepm` · SurfacePM block surfaces shipped + merged.
- 07-14 · `main` · app-wide auto-scroll primitive; Tables · PropertiesV2 · Multi-View · Icon Picker · Sidebar Ribbon in the runup.

### Working Notes

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the ONLY type gate) + `npx vitest run` + `… npm run build`; read the summary line, never a piped exit code (`set -o pipefail`). Biome auto-formats on write — never run it, never hand-align.
- **Isolated live runs:** back up `~/Library/Application Support/pommora-react/pommora.json`, point `lastNexusPath` at `~/Test`, launch the built app with `--remote-debugging-port`, restore byte-identical after. (The dev-loop + CDP + staging gotchas themselves live in `Context.md`.)

### Rules

- Resolve = delete + route, never tag — no (resolved) / (fixed) tombstones.
- No standing content here — Pending Focuses / Fix Log / durable rules live in `Context.md`.
- One block per session, in place; parallels share the doc, never edit another's block.
- Verify before finalizing — run the no-stale-state checklist.
