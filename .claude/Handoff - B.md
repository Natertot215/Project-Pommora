**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-28-2026 → 06-30-2026

> **Nathan (pinned):** "Check in with me before making any decisions on how things behave or look — I know damn well you don't wanna be tortured later with my tweaking requests."
> **Nathan (pinned):** Session handoffs go to THIS `Handoff - B` doc, not the dual-maintained `Handoff.md`.

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Date:** 06-30-2026
**Model:** Opus 4.8 (1M context)
**Compactions:** 2
**Connectors:** none
**Commands:** /compact · /handoff
**Worktree:** none (main)
**Agents:** general-purpose (2x — adversarial review: drag logic + DRY/tokens)
**Skills:** handoff

This session drove the **Table Views grid-rewrite plan** ([[6-30 - Table Views — Grid Rewrite + Drag-Line + Disclosure + Heading Redo]]) through the drag + disclosure tasks. Landed five commits (`b09b1a6` Task 1 grid, `7c99266` typography flatten, `3572ac3`/`5e158ee` earlier, then `3bf286a` A-4 column smooth-shift, `b1b2b8f` Nathan's tweaks, `2bbc3b2` disclosure). The recurring theme was **Nathan iterating the drag feel live** (he was home, driving the running app on CDP port 9222) — each change round-tripped through his eyes, and two of them exposed real model errors that only surfaced against a wide-column layout.

**A-4 column smooth-shift — the headline feature.** Replaced the generic `SortableZone` engine for column reorder with a table-local pointer gesture in [TableView.tsx](../src/renderer/src/Detail/Views/Table/TableView.tsx): the whole column (header + every body cell + both divider lines) slides via a per-cell `transform`; on drop `reorderColumn` commits and the transform clears in the same React batch (no snap-back flash). The dragged column reads as the **selected highlight** on an opaque `--bg-window` band — NOT a ghost. Committed in `3bf286a`.

**The drag-token model churned THREE times — a real "listen precisely" lesson.** Nathan first said "ghost the column, effect-mute: black .15 / effect-ghost: black .075" — I built black-overlay veils. Then he pivoted: column dragging should use `state-selected` (a highlight, not a ghost); "ghosting" is reserved for ROW/list reorder and should equal MarkdownPM's `.md-li-drag-source` treatment = `opacity: var(--tint-primary)`. Final model: `--state-ghost` = `var(--tint-primary)` (a 60% opacity, NOT a colour — lives in the `state` group but is consumed as `opacity:`); `--state-selected` for the lifted column; `--state-muted` (black 15%) **kept as a reserved future token** (defined, zero consumers — Nathan's explicit call, do NOT delete as dead). Also DRY'd MarkdownPM's table shift transition `0.16s → var(--duration-fast)`. Two misreads happened because I conflated his ".075" as "75%" and conflated the *motion* (screenshot) with the *dim mechanism* — separate them next time.

**The slot-detection model went boundary → closest-centre → edge-based (wide-column bug).** First shipped a far-boundary pointer hit-test (felt "not live enough"). Switched to the PommoraDND engine's closest-centre + hysteresis feel — but Nathan caught it shifting a FAR column (Topics) while the dragged one was still mid-traverse over a very wide neighbour (Title). Root cause: with wildly-varying widths, the *midpoint between a wide column's centre and its neighbour's centre falls INSIDE the wide column*, so crossing it (still visually inside Title) triggered the next shift. Fix: **edge-based** — the slot is whichever column's span the dragged centre is over, with a sticky-zone hysteresis (`COL_SHIFT_HYSTERESIS`, a tunable module const Nathan set to 25). The neighbour shift math (fixed `subjectWidth` for all in-between columns) is geometrically correct for variable widths — verified by the review.

**Adversarial review caught a real HIGH before commit.** Two read-only general-purpose agents (NOT Workflow, per Review-Discipline). DRY agent: *ship* (§G clean, all token chains resolve). Logic agent: *fix-then-ship* — `finish()` called `releasePointerCapture` first and unguarded, so a lost-capture release (pointercancel / mid-drag `columns` remount on a watcher/view-switch) would throw before the listener-cleanup + state-clear ran → stranded drag. Fixed: cleanup-first ordering + guarded release + bounds-checked indices (the exact pattern `tableDnd` already used). Plus its MED cousin + two stale comments. Everything else verified correct (variable-width shift, zoom tracking, slot extremes, resize/hide-anim non-interference, no pipeline thrash, no snap-back).

**Disclosure + member inset (Task 2), ratified.** Wrapped each headered group's members in the shared `Reveal` (`0fr↔1fr` on `--disclosure`, chevron already synced via `.twisty.open`, collapsed rows leave DOM). A-2's per-row `--cols` grid keeps columns aligned through the wrapper. Also added the **group-member inset**: a headered group's rows sit one `--row-indent` step inside their header (via `indent(depth+1)` in `renderRows`) so you can see what's within a disclosure; the ungrouped root band stays flush. Nathan confirmed "yup looks good." Committed `2bbc3b2`.

**Property cleanup + Nathan's tweaks folded.** `5e158ee` (earlier this session) renamed `relation→context` + deleted the `date` type outright (no normalize layer). This turn: folded Nathan's uncommitted `columnWidths.ts` retune (tier 140, number 100, last-edited/created 120, fallback 140) + updated `columnWidths.test.ts` to follow (`b1b2b8f`/`3bf286a`), plus his CLAUDE.md + Properties.md + subfield.css tweaks (`b1b2b8f`).

**Lessons Learned**
- **Separate motion from dim when a screenshot is cited.** Nathan's "make it move like this MarkdownPM drag" was about the *smooth-shift motion*, not the dim treatment — conflating them caused a wrong build. When a reference image is given, ask which property it's demonstrating.
- **Closest-centre collision breaks on wildly-varying item sizes.** The midpoint rule assumes comparable sizes; a wide column swallows its neighbour's midpoint. Edge-based (span-containment) is correct for variable widths. The shared engine's HYSTERESIS=6 is tuned for skinny sidebar rows — wide table columns want their own, stickier knob.
- **`releasePointerCapture` throws on already-lost capture** — always guard it AND run listener/state cleanup *before* it, so a throw can't strand the gesture. `tableDnd` already did this; the new gesture didn't until review.
- **A deliberate value change makes its test red — update the test to follow, don't revert the value.** columnWidths retune is intentional; the test encoded the old numbers.

**Key Files & Insights**
- [TableView.tsx](../src/renderer/src/Detail/Views/Table/TableView.tsx) — `startColumnDrag`/`colTransform` (the gesture), `COL_SHIFT_HYSTERESIS` (tunable module const = 25), `renderRows` (group-member inset via `itemDepth` + the `Reveal` wrapper), `ColumnHeader`/`DataRow`.
- [tableDnd.tsx](../src/renderer/src/Detail/Views/Table/tableDnd.tsx) — the row drop-line; width now ends at `.cell-filler` (content edge, not the full row into the filler).
- [Table.css](../src/renderer/src/Detail/Views/Table/Table.css) + [table-tokens.css](../src/renderer/src/Detail/Views/Table/table-tokens.css) — `.col-dragging` (opaque band + `--col-highlight` gradient + `border-left`); §G token layer is clean (every value aliased).
- [color.css.ts](../src/renderer/src/design-system/tokens/color.css.ts) / [theme-vars.css.ts](../src/renderer/src/design-system/tokens/theme-vars.css.ts) — `state.muted` (black 15%, reserved), `--state-ghost` = `var(--tint-primary)` (opacity).
- [Reveal.tsx](../src/renderer/src/design-system/components/Reveal.tsx) — the disclosure primitive; mounts children on open, unmounts after collapse.

**Landmines**
- **`state.muted` is reserved, not dead** — defined (black 15%) with ZERO consumers on purpose. Don't let the cleanup agent delete it.
- **`--state-ghost` is an OPACITY, not a colour** — it's `var(--tint-primary)` = `60%`. `background: var(--state-ghost)` would render an invalid bare `60%`. It's flagged in its own inline comment; consume it only as `opacity:`.
- **`--drag-muted` (table row ghost) vs `--state-muted` (reserved black)** — mild naming collision across layers/types. The cleanup agent should consider renaming the table token to `--row-ghost`.
- **`Reveal`'s `overflow: hidden` may clip a column drag pulled far past the LEFT edge — but only on grouped (Reveal-wrapped) rows.** Untested edge case; if Nathan sees it, make the table's disclosure clip vertical-only. Ungrouped rows are unaffected.

**Session Pointers**
- CDP self-verify pattern works here: Nathan's live dev session runs with `--remote-debugging-port=9222`; attach passively (screenshot + DOM probe) without touching his window. `scratchpad/*.mjs` has the harness (`drag-test.mjs`, `disclosure-shot.mjs`).
- Column-drag CDP note: `setPointerCapture` DOES drive under CDP here (unlike the MarkdownPM table widget, which is blocked by CM6 virtualization).

**User Feedback**
- **Check in before behaviour/look decisions** — the pinned directive; surfaced forks (ghost mechanism, dim scope) rather than guessing, and it paid off.
- **Point to the knob, don't iterate** — `COL_SHIFT_HYSTERESIS` was made a named tunable const with a disclosed default rather than me hand-tuning.
- **Keep reserved tokens** — `state.muted` stays for future use even with no consumer.
- **Future (memory saved [[project-row-drag-from-title-area]]):** when the in-line-editing interaction pass happens, row reorder must ALSO arm by dragging the title cell, not only the gutter grip.

**Uncertain**
- Whether the `Reveal` far-left column-drag clip is a real problem — not yet driven. Cheap to fix if it is.
- Whether the group-member inset amount (`--row-indent`, 16px) matches the Swift look, or wants a dedicated `--group-inset` token independent of Set-nesting depth (offered; Nathan reused the shared one).

---

### Working Notes
- **Gate = real output, not exit code.** `npm run typecheck` is `tsc:node && tsc:web` — the `&&` short-circuits the web pass if node fails; run both separately and grep for `error TS`. Vitest from real output too.
- **Biome auto-formats on every TS/CSS/JSON write** (PostToolUse hook). Don't hand-format; re-read on a whitespace Edit failure. Markdown is NOT formatted.
- **Run the app:** `env -u ELECTRON_RUN_AS_NODE POMMORA_DEBUG_PORT=9222 npm run dev`. src/main + preload changes need a full restart; CM6-extension changes need ⌘R; CSS + React components Fast-Refresh.
- **Stray screenshots** `overview.png` / `zoom-bottom-before*.png` at repo root are Nathan's, untracked — left alone (not repo assets).

### Next Session
- **Task 4 — Heading row + `--border-heading`.** A GLOBAL 2px heading-hairline token (heading↔body seams across the table heading, `Banner.css`, `.mdpm-banner`) + `--fill-primary` segment dividers on the heading row ONLY. Nathan has comment-markers parked in `Table.css` (~line 46) and MarkdownPM `Styles.css` (`.mdpm-banner`). This one reaches beyond the table (editor + banner) — start it fresh.
- **Task 5 — Column alignment + native Align menu.** E-5/E-6/E-7: per-type default alignment (center: checkbox/status/select/multi_select/context/tier; left: everything else), the native Align submenu on `columnMenu.ts`, and `column_alignments` persistence in SavedView. **Includes the chip-centering Nathan flagged** (chips read left today) AND the inset↔centre interplay: a centered chip in an indented lead cell needs thought (E-1: the group glyph stays left-flush even when cells centre).
- **Task 6 — `--border-heading` DRY + banner fix (LAST).** Bind every heading↔body border to `--border-heading`; F-1 banner divider `#FFFFFF1A → --separator-border`.
- **Final cleanup agent** — de-scaffold dead/post-application code (HARD DRY, no dead code); bind all ghost/mute usages (incl. MarkdownPM `.md-li-drag-source`) to `--state-ghost`; consider `--drag-muted → --row-ghost` rename. Keep `state.muted`.

### Pending Focuses
- Reveal far-left column-drag clip — verify, fix if real.
- Group-member inset value — confirm `--row-indent` (16px) reads right vs the Swift inset; split a `--group-inset` token only if Nathan wants it independent.
- Context.md system still doesn't exist (the current-state companion to this handoff) — Nathan should build it; nag standing.

### Fix Log
- (clean — the review's HIGH lost-capture strand + MED index-guard were fixed before commit `3bf286a`; no known open bugs.)

### Handoff Rules
- This doc (`Handoff - B`) supersedes the dual-maintained `Handoff.md` for THIS session's continuity, per Nathan. Update this block in place across compactions (bump Compactions), don't spawn a second block unless a genuine parallel session joins.
