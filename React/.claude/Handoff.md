## Handoff — Pommora React

Two parallel sessions on the same day, one labeled block each (A = the earlier list-drag / canvas / agent-legibility session; B = the bullet + table-heading-column + handoff-format session). The top matter + footer below are shared; each session block is its own.

**Session A ID:** 64346d76-0499-4a65-93e3-71db53bf4d32
**Session B ID:** 7db4f952-e547-415f-b861-af8dd1a1e30b
**Dates:** 06-26-2026


> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary - A

**Date:** 26-06-2026
**Model:** Opus 4.8
**Connectors:** Playwright (attempted — `browser_navigate` errored on the local showcase; CDP driven directly via Node instead)
**Commands:** `/handoff`
**Agents:** Explore (×7 — MarkdownPM list internals · PommoraDND mechanics · fill-token ramp · drag-inhibitor audit · canvas internals · adversarial review · inspector/trio/glass chrome map), general-purpose (×6 — canvas research ×4 + JSONCanvas-lib survey + list-drag builder), code-simplifier (×1)
**Skills:** `superpowers:brainstorming` (canvas), `handoff`

> ⚡ **Cornerstone — carry into every window, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

A long build session across three fronts — the shipped **list drag-to-reorder**, a parked **in-page canvas** pass, a committed **product-principle** refinement — then a post-compaction continuation that shipped **arrow/`+` list flavors** + a **drawn caret/cursor** and built the **inspector "swallow"** chrome animation (the session's longest thrash), all live-debugged over CDP.

**List drag-to-reorder, shipped (`924b346`):** Bullet / ordered / checkbox items reorder by grabbing their glyph: the sidebar's PommoraDND *feel* (grab cursor, in-place dim, an accent insertion line that follows the target's indent out to the gutter) but driven against CM line geometry and committed as a **source-line move**, not a DOM reflow. The dragged item carries its nested sub-block; dropping beside a shallower item re-nests it; ordered runs renumber — all one undo step. The killer bug, found only by live CDP debugging after two reasoning rounds failed: **`WidgetType.ignoreEvent` defaults to true**, so the bullet replace-widget swallowed pointerdown ("dragging doesn't work"). Then a jank fix (measure candidates once, not per-pointermove), slot-tracking + gutter-line + no-ghost + tint-dim polish, and re-nesting. Closed with simplifier + line-walk dedup + adversarial review (one real finding fixed, rest verified false positives). → `History.md`, `Features/MarkdownPM.md` § Lists.

**In-page canvas, designed then parked:** A full brainstorm → external+internal research → spec pass for embedded interactive canvases in MarkdownPM: JSONCanvas-shaped `.canvas` files (filename = name, ULID inside, in `.nexus/canvases/`), v1 = text-blocks + free-draw + lines/shapes, a **full-SVG scene with `<foreignObject>` text-blocks**, build-your-own (verified: the JSONCanvas ecosystem ships only viewers/readers, no editor). Net-new → React-first, so the format is the cross-build contract Swift later adopts. Spec written V2, **pending review, parked** at `Planning/6-26 - Canvas Spec.md` — > Nathan: "i think we may be getting ahead of ourselves." Resume from the spec + its first-step adversarial review.

**Agent-legibility principle, refined + committed (`e98d46a`):** The root product principle "persistent *immediate* legibility for agents" relaxed to **convention-aware** (a `[[wikilink]]` abstracts a lookup yet stays legible once you know the convention) and running-code-independence dropped from a hard bar to a **strong preference** — firm line stays: no user data in a binary blob or held only in the index. Updated in root `CLAUDE.md` / `Architecture.md` / `PommoraPRD.md` / `History.md`. Prompted by the canvas file-per-canvas storage question.

**Arrow (`->`) + plus (`+`) list flavors, shipped (`11a3e42`):** Two new list-marker kinds keeping their own character as the literal glyph (like the ordered number) with the full bullet behavior set; `→` (typed `->`, auto-converted by `dashArrow`) is a Pommora render directive on disk, `+` stays portable CommonMark. Only detection + render-intent + the backspace regex needed touching — continuation/backspace fell out of the existing bullet path. → `History.md`, `Features/MarkdownPM.md` § Lists.

**Drawn caret + custom hover cursor, shipped (`bf7bbd9`):** The page editor's native caret replaced by a CM-`layer`-drawn one (over `caret-color: transparent`, native selection untouched — NOT `drawSelection`'s all-or-nothing, which sank the earlier app-wide attempt): a rounded body-sized bar with a smooth symmetric fade (equal on/off) vs Chromium's hard blink, + a custom I-beam hover cursor (inward double-chevron, black + white outline), knobs in `Styles.css`. Built + tuned entirely over live CDP screenshots — the OS cursor can't be captured, so its SVG was rendered into the page to show it. → `History.md`, `Features/MarkdownPM.md`.

**Inspector "swallow" + chrome polish (uncommitted):** Opening the Inspector swallows the toolbar trio — the pill rides the pane's leading edge to its left corner, its glass voiding so the bare icons land on the inspector glass (no double-glass), all off one `@property --io`. The thrash: voiding Liquid Glass can't be done in place (its `backdrop-filter` displacement is a dynamic SVG filter id CSS can't reconstruct or fade), so the void is a **two-layer trio** (fading glass layer + solid bare cover) — Nathan chose the smooth two-layer over a single-control hard cut, accepting it re-inits glass on **dev HMR only**. Plus `--label-control` promoted to one global token (both clusters; mute only on a disabled Back/Forward), the swallowed-icon dimming fixed (hide the glass layer's duplicate glyphs), and a page-header fix (banner-page first line + first-line-heading top-padding → consistent gap below the divider). → `History.md`, `Features/Design.md`.

**Callouts hardened — delete-guard + grip DRY (post-compaction continuation, uncommitted):** Closed the last callout break — Shift+Delete (and every Cmd/Alt/forward combo) eroding a body line's hidden `> ` prefix out of the box. An `atomicRanges` pass alone only made it *cleanly* de-callout (still a break); the real fix is a `transactionFilter` (`editor/calloutGuard.ts`) that cancels any change eroding a body prefix *in place* while letting joins, content-deletes, and intentional head-removal through — proven on a bare `EditorState` (no DOM, 12 tests) and verified live across the full delete matrix (628 green). The hand-rolled callout hover-grip was swapped to the **exact** lucide `grip-vertical` the table-row grips use (`Styles.css` mask mirrors the `<GripVertical>` geometry 1:1 — a CM line decoration can't mount the React icon; confirmed pixel-identical live). The whole saga — every break Nathan found *after* Claude called it "bulletproof" — is catalogued in `Guidelines/Adversarial-Review-Log.md` as the seed for a future break-things skill.

**Lessons Learned**

- **`WidgetType.ignoreEvent` defaults to TRUE** — a CM6 widget swallows every DOM event from its own DOM; a replace-widget glyph that needs to be interactive (pointerdown, click) must override `ignoreEvent → false`. The checkbox already did; the bullet didn't — that one missing override was the whole "drag doesn't work."
- **Live-debugging the React editor over CDP works and is worth it.** Restart dev with `env -u ELECTRON_RUN_AS_NODE npm run dev -- --remoteDebuggingPort=9222` (electron-vite supports the flag), attach via Node (global `fetch` + `WebSocket` → `http://localhost:9222/json`), stream `Runtime.consoleAPICalled` + `Runtime.exceptionThrown` to a file, screenshot via `Page.captureScreenshot`, drive input via `Input.dispatchMouseEvent` (it generates pointer events too). Caveat: a synthetic press on an **off-screen** target silently no-ops — filter candidates to `getBoundingClientRect` within the viewport first.
- **Editor-extension changes need a full renderer reload (`Page.reload` / ⌘R), not HMR** — only CSS hot-swaps. CDP `Page.reload` is the cheap way to apply an extension edit for a live retest.
- **Overlay drag inside CM: measure once.** The doc is static during a drag, so collect candidate line rects at drag-start; per-pointermove `lineBlockAt` / `coordsAtPos` is synchronous layout thrash (the jank). A `position:fixed` overlay lives in viewport coords — it dodges the scroll-container ambiguity an absolute child of `.cm-scroller` has (whether it scrolls depends on the positioned ancestor).
- **The tint scale IS the opacity system** — CSS `opacity` accepts a percentage, so `opacity: var(--tint-secondary)` reuses it. Don't add a parallel "darken" token family for a dim (a black-overlay token can't darken *text* anyway — transparent-black text is invisible).

**Key Files & Insights**

- `MarkdownPM/editor/listDrag.ts` — the CM6 extension: pointerdown gesture, 5px activation, `mousedown` guard (CM starts selection on mousedown, which `preventDefault` on pointerdown can't cancel), the imperative overlay (position:fixed accent line, no floating ghost), `collectCands` (measure-once), `slotFrom` (nearest-boundary snap), a shared `forEachLine` helper.
- `MarkdownPM/editor/listDragModel.ts` — pure source-line logic, unit-tested standalone (`listDragModel.test.ts`, 16 tests): `subBlockAt`, `reindentBlock` (strip-by-length, tab/space-robust), `moveBlockChanges`, `renumberOrderedRun` (from the run's min digit), `dropChanges` (move + renumber → one `diffAsSingleReplace`).
- `MarkdownPM/editor/decorations.ts` — `BulletWidget` / `CheckboxWidget` both `ignoreEvent → false`; shared `GLYPH_CLASS` (`md-li-glyph`) on bullet + checkbox widgets and (via `intent.ts`) the ordered-number mark.

**Landmines**

- **Debug rig still live:** dev server launched with `--remoteDebuggingPort=9222` + a Node CDP logger background process. Restore a normal launch + kill the logger before walking away.
- **Parallel session ran all session** on the Swift/`modified_at` work — touched root `.claude/*`, `Pommora/**.swift`, and `React/src/main/{crud,index}`. Never bundle or revert its edits; **stage explicit paths**, never `-A`.

**Session Pointers**

- The list-drag review surfaced three "HIGH" findings; on verification two were false positives (the ordered-renumber and diff-overlap claims — the diff already guards overlap with `suf < max - pre`). Only the mixed-tab/space re-indent was real, and the fix was a *guard removal*. Verify agent findings before acting (> Nathan: "see if removing guards or limits would fix them instead of adding more code").

**User Feedback**

- "Use tint since it already does the opacity and is DRY" — reach for an existing scale before adding a parallel token family.
- "Fix them all minimally; see if removing guards or limits would fix them instead of adding more code" — triage by removal first; most "findings" were non-issues.
- don’t use darken; use tint" + "the darken happens on the background when it should only happen on the text" — the dragged item dims its **text** (opacity), not a background fill.

**Uncertain**

- Re-nest with **mixed tab/space indent** is now graceful (strip-by-length) but not pixel-perfect; Pommora's own input never emits mixed indent, so it's untested against real mixed docs.
- The `<foreignObject>` editable-text bet in the parked canvas spec is reasoned, not prototyped — flagged there as a 30-min spike before any deep build.

### Session Summary - B

**Date:** 06-26-2026
**Model:** Opus 4.8
**Compactions:** 0
**Connectors:** Playwright (attempted — `browser_navigate` blocked on `file://`); headless Chrome + CDP-over-Node directly for isolated repros, live measurement, and screenshots
**Commands:** `/handoff`, `/skill-creator`
**Worktree:** main checkout (NOT the `pommora-react` worktree — Nathan: "commit alongside" the live parallel session)
**Agents:** feature-dev:code-reviewer (×1 — table heading-column perf/correctness), code-simplifier (×1 — heading-column simplify)
**Skills:** `superpowers:systematic-debugging` (bullet-wrap bug), `skill-creator` (handoff redesign), `handoff`

A focused MarkdownPM session alongside Session A: a bullet-wrap bug chased down then parked, a full table **heading-column** feature shipped with a review + perf pass, then a redesign of the `/handoff` skill itself.

**Bullet single-word wrap, fixed-then-reverted, parked as a known issue:** A bullet on the page's first line that wraps pushed its text down. The first hypothesis (the `•` glyph's 1.25em line-height swelling the first wrapped line) was real but not the cause; Nathan diagnosed the actual trigger — a **single unbroken word**: the line-breaker takes the soft break at the space between bullet and content rather than force-breaking the word, so the whole word drops below the bullet (multi-word text fits the first word beside the bullet and hides it). A faithful headless-Chrome repro confirmed it. The fix (hide the inter-marker space like the ordered/checkbox lists + restore the gap via the glyph margin) worked in plain HTML but **didn't survive CM6's `Decoration.replace` (zero-width hide)** in the live editor, so per Nathan it was reverted — keeping only the `line-height` cap — and logged as a known issue (the `+` / `→` flavors share it). → `Features/MarkdownPM.md` § Known issues.

**Table heading column, shipped:** "Make Heading Column" on the first column's grip menu (column 0 only) styles that column's body cells like the header row (`fill-quinary` + emphasized); the header row's `fill-tertiary` stays on top at the corner because the column fill is scoped to `tbody`. The menu item sits below Align, grouped with the Inserts, as a checkbox with a state label ("Heading Column" with a checkmark when on, "Make Heading Column" when off). Empty table cells also rendered a line-height shorter than filled ones — fixed with a `:empty::before` zero-width placeholder line box.

**Heading column is a Pommora-only `.nexus/` visual (paradigm decision):** GFM has a header *row*, never a header *column*, so the on-disk `.md` stays a plain portable table; the on/off state persists in `.nexus/tableHeadingColumns.json` keyed by page id → that page's heading-column table indices, mirroring the folds store + IPC end-to-end (StateField + toggle effect → widget rebuild → persist; mount reloads). > Nathan: "the paradigm decision should just be a memory" — recorded in agent memory, NOT `History.md`. Index-keying carries the folds store's fragility (a stale index mis-styles whatever table now sits at it).

**Toggle perf, fixed after review:** The code-review agent flagged that a toggle rebuilt every table's decoration. > Nathan: "full rebuild on toggle is not acceptable if it can be fixed" — so the toggle now swaps ONLY the toggled table's widget in place (`set.update({filterFrom, filterTo, filter, add})`, reusing the existing widget's parsed text/model), with a full rebuild only on the once-per-page mount-time load. Simplifier pass after: one safe cleanup, the rest a faithful folds/CM6 mirror left alone. → 61 table/storage tests green, typecheck clean.

**`/handoff` skill redesigned (this session):** Reworked `~/.claude/commands/handoff.md` from a context-window model to a **session** model — one block per session, updated in place, with **compactions tracked as a `Compactions:` count** instead of new sections; metadata gains `Worktree:`; the pinned-message + **Cornerstone top matter is hoisted above all blocks** (shared once, not per block); parallel sessions share one file as `### Session Summary - A/B`, and the doc now spells out that the agent running `/handoff` is the **newcomer** taking the next free letter (A = the block already in the file). Three-way filename (`Handoff` solo-uncompacted / `Session` solo-compacted / `Sessions` parallel); new-doc-vs-continue still keyed on session ID so multi-day sessions continue. This block is the first written in the new format. → `~/.claude/commands/handoff.md`.

**Lessons Learned**

- **A faithful headless repro can still mislead at the editor layer.** Hiding the inter-marker space fixed the single-word drop in plain HTML, but CM6's `Decoration.replace` doesn't behave like deleting the text node — the soft-break opportunity persisted in the real editor. Validate editor-layer fixes IN the editor, not just an HTML model.
- **Main-process changes need a full dev restart** (native menus, IPC, preload) — not HMR, not ⌘R. A new menu item won't appear until the dev process restarts. → agent memory.
- **A `Decoration` exposes its spec** (`cursor.value.spec.widget`), enough to find + swap a single block widget in a `DecorationSet` via `set.update({filterFrom, filterTo, filter, add})` without re-decoding the whole doc.

**Key Files & Insights**

- `MarkdownPM/Tables/widget.tsx` — `headingColField` StateField + `toggle` / `set` effects; `buildWidgetDecorations` stamps a `headingColumn` flag per `TableWidget` (folded into `eq()` so only the toggled table re-renders); `widgetField.update` partial-swaps on toggle, full rebuild only on mount-load.
- `main/io/tableHeadingColumns.ts` (+ IPC handlers in `main/index.ts`, bridge in `preload/index.ts`) — the `.nexus/tableHeadingColumns.json` store, a faithful mirror of `io/folds.ts`.
- `MarkdownPM/Tables/widget.css` — `.mdpm-tbl-heading-col` (tbody-scoped fill-quinary + emphasis) and the `:empty::before` cell-height fix.

**Landmines**

- **Session A ran concurrently this window** (live caret + docs work). All my commits staged **explicit paths**, never `-A`; `Styles.css` + `intent.ts` overlapped A's caret work, but A committed first so my hunks landed clean. Keep staging explicit.
- **Dev server is live with `--remoteDebuggingPort=9222`** (rebooted several times to pick up the main-process menu) — same debug-rig state Session A flagged; restore a plain launch before walking away.

**User Feedback**

- "Full rebuild on toggle is not acceptable if it can be fixed" — fix the perf, don't comment around it.
- On the bullet bug: revert the editor-layer fix that didn't land, keep the safe sizing change, and log the remainder as a known issue rather than piling on speculative fixes.

**Uncertain**

- The toggle's live behavior (the partial-rebuild swap actually re-rendering the one table) is reasoned + typecheck-green but not yet confirmed by a real in-app toggle.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload, **but CM6 widget/extension code needs a full ⌘R / `Page.reload`** (only CSS hot-swaps), and a freshly-added module sometimes needs one reload past HMR. Don't ⌘Q it.
- **Main-process edits need a dev-server restart**; a stale main can silently drop a mutation.
- Runs against a **test nexus** (`~/test`) — a *managed* nexus (carries `.nexus/`) so reorder/settings persist. The running app opens its `lastNexusPath`, not `TEST_NEXUS_PATH`.
- The agent **can** screenshot + drive the React UI headlessly via Electron + CDP (`--remoteDebuggingPort` → `Page.captureScreenshot` / `Input.dispatchMouseEvent`), but Nathan is the primary visual verifier.
- **Parallel sessions happen** — never bundle or revert unattributed changes; **stage explicit paths** (`git add <paths>`), never `-A`.

### Next Sessions

- **Carryover editor work:** **Callouts** are functionally hardened — delete-guard shipped + a full adversarial fuzz pass done (`Guidelines/Adversarial-Review-Log.md`); remaining: tables-inside-callouts (deferred, noted in both reliant docs) + fold-chevron gutter alignment (inner-padding groundwork laid, the chevron itself still needs prefix-aware folding). Create unicode up-down + back-forth auto-transform syntax for <> and ><. Add paired auto-deletion for backspace on auto-paired syntax. Add “Styles” to tables → style = column would remove gutter padding and hide table lines to essentially solve the markdown column problem.

- **Live-verify the heading-column toggle end-to-end:** the menu → toggle → persist → reload path is unit-tested + typecheck-clean and the dev server's been restarted (the native menu lives in `src/main`, needs a full restart), but a real in-app toggle styling + persisting across reload hasn't been confirmed by hand yet.

### Pending Focuses

- **Break-things skill (new, Nathan-requested)** — build a reusable adversarial-fuzzing skill from `Guidelines/Adversarial-Review-Log.md`: a break-attempt taxonomy (input transforms · the deletion/caret combo matrix · nesting · adjacency · layout edges · fix-induced regressions) + the "toddler" method (every input/combo/position, screenshot each, no deferred findings) + a combinatorial `{keys}×{positions}×{nesting}×{adjacency}` generator, producing a break→repro→fix catalog before any UI feature is called done. The functional-layer counterpart to `// The Studio //.claude/rules/Review-Discipline.md` (which governs docs).

- **Canvas (new)** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; the `.canvas` format is the cross-build contract. Confirm the `border` token (grey-30%, ratified) lands when canvas builds.
- **Caret on the other editor surfaces.** The drawn caret + custom hover cursor **shipped on the page editor** (`editor/caret.ts` — CM `layer` over `caret-color: transparent`, leaving native selection alone; see `History.md`). Extending the drawn caret to table cells + the inline-rename input is the remainder.
- **Subfield reorder + live-stats + custom items** — registry/order/persistence are the seams; `Features/Subfield.md` § Roadmap.
- **Icon picker** — build the real `Components/IconPicker` + wire the icon's frontmatter save (Swift `IconPicker` is the spec; wants a shared dropdown-animation primitive).
- **Real design-system Components** (Button / Menu / Label / Separator) from the token layer — prerequisite for replacing one-offs (notably the inline-rename `<input>`).
- **Radius + spacing tokens** — still ad-hoc literals; lift from Figma.
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface (labels + accent + `subfield`).
- **One-time Biome normalization** — the format-on-write hook keeps touched files clean, but a whole-tree `npm run check` pass hasn't run (defer to a tree with no parallel uncommitted edits).
- **Unsorted bin → folder + sidecar (paradigm, ratify first)** — Nathan's looking into moving "unsorted" off a config file and onto a real `Unsorted/` folder carrying an `_unsortedconfig.json` sidecar (the folder-with-sidecar pattern the rest of the model uses). The win is interop: another Markdown-based app with its own unsorted bin could point at the same folder and share it, rather than each app hiding the list in a private config. Cleaner now that `Class: item` vs `page` is no longer a discriminator (PagesV2 collapse) — the bin holds plain entities, no kind to sort by. On-disk shape, so ratify before building.

### Fix Log

- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** — no input handling for the rendered link inside a cell; proposed single-click navigate + right-click edit.
- **Bullet single-word wrap drops the word below the marker** — a `-` / `•` (and `+` / `→`) item whose content is one long unbroken word drops the whole word to the next line; the marker-space hide that would fix it didn't survive CM6's replace decoration. Only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known issues.
- Recents submenu on the “Open Nexus” menu allows trashed folders to appear; pulls them out of trash when 

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here (Pending Focus, Landmine, Uncertain, Fix Log) is genuinely done, push its real outcome to the canonical doc (`History.md` / `Features/*` / `Framework.md`) and delete the line — no `(Resolved)` / `(Superseded)` tombstones. A stale-but-tagged line is still a false line the next agent re-reads and discounts; deleting what's no longer true beats annotating it. In parallel, you may delete a resolved Landmine/Uncertain from another session's block (removal only, on real resolution) even though the rest of their block stays frozen.
- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **One block per session, updated in place.** A session keeps one block; compactions bump its `Compactions` count, they don't add sections. Push spec/decision content to its canonical home (`History.md` / `Features/*` / `Framework.md`); carry still-open Pending Focuses forward to a fresh *sequential* session.
- **Markdown only, no new folder** (per Nathan) — this doc stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir, regardless of the skill's `Handoff`/`Session`/`Sessions` filename shapes.
- **Parallel sessions share this one doc.** Each concurrent session gets its own labeled block (`### Session Summary - A`, `- B`, …) with its own metadata + sections; the pinned-message + Cornerstone **top matter is shared above all blocks, written once** (not per block). List every session ID in the header. The agent running `/handoff` is the newcomer (next free letter; A = the block already in the file) — never edit another session's block, only write/refresh your own. The footer (Working Notes / Next Sessions / Pending Focuses / Fix Log / Handoff Rules) is shared: carry, add, and retire across all sessions, tagging session-specific Next/Pending/Fix items with the block letter where it helps. **Next Session lives once in the footer** (→ `### Next Sessions` when parallel), never per block.
