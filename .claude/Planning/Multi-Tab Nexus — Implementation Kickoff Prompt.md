# Multi-Tab Nexus — Implementation Kickoff Prompt

> Nathan: after compacting, paste the block below as the fresh prompt to start the build. It's self-contained — it carries the standing directives + the task so nothing depends on the pre-compaction context.

---

## Compact Instructions (must survive compaction)

You are implementing the **Multi-Tab Nexus** feature for Pommora. The spec and plan are ratified and review-hardened:

- **Decision Log:** `.claude/Planning/Multi-Tab Nexus — Decision Log.md` (the source of truth — decision IDs like `[B-3]`, `[I-13]`).
- **Implementation Plan:** `.claude/Planning/Multi-Tab Nexus — Implementation Plan.md` (task-by-task, with the visual-knob block).
- **Feature doc:** `Features/Navigation.md` (§II. Toolbar Tabs / NavView / NavWindow / NavPane).

**Standing directives (do not violate):**

1. **Review discipline is mandatory, per phase.** After each phase ships green, dispatch a `build-breaking-agent` (attack the phase against real code) AND a `code-simplifier` pass. **Verify every agent finding against the code yourself before folding — agent claims are hypotheses until you've read the `file:line`.** Fold, re-gate. Never call a phase done on an agent's word.
2. **The warm feel is the point.** Switching a warm tab must be instant — no loading flash, no refetch when the file is unchanged (`[B-3]` short-circuit). If you catch yourself reintroducing a flash, stop.
3. **DRY to the named mechanisms, never re-roll:** pins = `pinTarget`/`unpinTarget`/`reorderPin`; undo = `historyField`; persistence = `navState`'s debounce+drain; within-zone drag = single-zone `SortableZone`; close-`×` = `ChipRemoveButton` (plain fade, not the melt); new-tab `+` = `.group-add` glyph+fade; open/close motion = `--duration-slow`+`--ease-standard` (the sidebar/ribbon easing).
4. **Simplicity first.** The plan is already trimmed; don't add unrequested complexity, speculative flexibility, or a mechanism the codebase already has.
5. **Point to knobs, don't tune.** All visual values live in the plan's knob block → one `tabBar.css` `:root` block. When a value needs a human eye, surface the exact `file:line` + knob for Nathan; don't iterate the value yourself.
6. **UIX gates:** the tab-bar build (Phase 4) runs the §J UIX-repass *before* building and a post-functional UIX review *after* — screenshot-verify against the real bar; functional-green ≠ done.
7. **Don't break shipped behavior.** Gate each phase: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npm run test` green (read the summary line, never a piped exit code). Main-process changes ride the electron restart; CM6 extension changes need a full `⌘R` to test (CSS HMRs).
8. **Docs + commits:** commit each phase green; keep docs true to what shipped; correct any doc error traceless (durable truth, no "fixed"/"corrected" scars). Update `/handoff` at session end.
9. **Naming is settled:** `NavWindow` (floating overlay, rename from `NavPane`), `NavPane` (toolbar dropdown, rename from `NavMenu`), `NavView` (new-tab page). Phase 0 Task 0.0 does the code rename first.

## The Task

Implement the plan **phase by phase, in order**, honoring the per-phase review discipline above. Re-read the plan against what landed after each green commit (Planning Discipline) — if a task surfaced a wrong assumption, rewrite the affected later tasks before dispatching the next.

- **Phase 0** — surface rename (Task 0.0) + the pure tab model + inline store wiring (tests-first, headless).
- **Phase 1** — the synced `tabs.json` sidecar + load/derive-pins/persist + **reconcile-every-tab in `applyTree`**.
- **Phase 2** — the warm seam (staged: flat current-tab warmth → then the ~20-cap back-stack). **Highest risk** — its per-phase review is the heavy one; do it before Phase 3.
- **Phase 3** — the four "Open in New Tab" menu points.
- **Phase 4** — the tab bar UI (UIX-repass gate first; the knob block; plain-`×` fade; within-zone drag; cycling; the reveal setting).
- **Phase 5** — NavView (the new-tab page + empty state).
- **Phase 6** — capture gate, cleanup, docs, the mandatory post-functional UIX review.

Start with **Phase 0, Task 0.0**. Confirm the plan against the code as you go; if the first task surfaces something the plan got wrong, flag it and fix the plan before proceeding. Work autonomously through the phases; surface a decision only when it's genuinely Nathan's to make (a UIX value, a design ambiguity the log doesn't settle).

Before writing any code, take one pass to re-justify the load-bearing design choices against the real code with explicit reasoning (warm-seam seed-from-`historyField`, the `applyTree` reconcile, the `isPinned` derivation, the newtab→`'none'` routing) — confirm they still hold, and flag any that don't.
