## Handoff — Pommora React

**Session ID:** 64346d76-0499-4a65-93e3-71db53bf4d32
**Date(s):** 26-06-2026
--

**Date:** 26-06-2026
**Model:** Opus 4.8
**Connectors:** Playwright (attempted — `browser_navigate` errored on the local showcase; CDP driven directly via Node instead)
**Commands:** `/handoff`
**Agents:** Explore (×6 — MarkdownPM list internals · PommoraDND mechanics · fill-token ramp · drag-inhibitor audit · canvas internals · adversarial review), general-purpose (×6 — canvas research ×4 + JSONCanvas-lib survey + list-drag builder), code-simplifier (×1)
**Skills:** `superpowers:brainstorming` (canvas), `handoff`

> ⚡ **Cornerstone — carry into every window, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

#### Session Summary

A long build session across three fronts: the shipped **list drag-to-reorder** feature (built by an agent, then live-debugged against the running app over CDP), a parked **in-page canvas** design pass, and a committed **product-principle** refinement.

**List drag-to-reorder, shipped (`924b346`):** Bullet / ordered / checkbox items reorder by grabbing their glyph: the sidebar's PommoraDND *feel* (grab cursor, in-place dim, an accent insertion line that follows the target's indent out to the gutter) but driven against CM line geometry and committed as a **source-line move**, not a DOM reflow. The dragged item carries its nested sub-block; dropping beside a shallower item re-nests it; ordered runs renumber — all one undo step. The killer bug, found only by live CDP debugging after two reasoning rounds failed: **`WidgetType.ignoreEvent` defaults to true**, so the bullet replace-widget swallowed pointerdown ("dragging doesn't work"). Then a jank fix (measure candidates once, not per-pointermove), slot-tracking + gutter-line + no-ghost + tint-dim polish, and re-nesting. Closed with simplifier + line-walk dedup + adversarial review (one real finding fixed, rest verified false positives). → `History.md`, `Features/MarkdownPM.md` § Lists.

**In-page canvas, designed then parked:** A full brainstorm → external+internal research → spec pass for embedded interactive canvases in MarkdownPM: JSONCanvas-shaped `.canvas` files (filename = name, ULID inside, in `.nexus/canvases/`), v1 = text-blocks + free-draw + lines/shapes, a **full-SVG scene with `<foreignObject>` text-blocks**, build-your-own (verified: the JSONCanvas ecosystem ships only viewers/readers, no editor). Net-new → React-first, so the format is the cross-build contract Swift later adopts. Spec written V2, **pending review, parked** at `Planning/6-26 - Canvas Spec.md` — > Nathan: "i think we may be getting ahead of ourselves." Resume from the spec + its first-step adversarial review.

**Agent-legibility principle, refined + committed (`e98d46a`):** The root product principle "persistent *immediate* legibility for agents" relaxed to **convention-aware** (a `[[wikilink]]` abstracts a lookup yet stays legible once you know the convention) and running-code-independence dropped from a hard bar to a **strong preference** — firm line stays: no user data in a binary blob or held only in the index. Updated in root `CLAUDE.md` / `Architecture.md` / `PommoraPRD.md` / `History.md`. Prompted by the canvas file-per-canvas storage question.

**Next Session**

- **Close out the list-drag debug rig:** the dev server is still running with `--remoteDebuggingPort=9222` and a background Node CDP logger (`/tmp/cdp.log`) — restore a plain `npm run dev` + kill the logger.
- **Canvas:** resume from `Planning/6-26 - Canvas Spec.md`; its first step is the adversarial review, then a `writing-plans` plan. Confirm the `border` token (grey-30%, ratified) lands when canvas builds.
- **Carryover editor work:** Subfield reorder (drag items via PommoraDND — order already persisted), the real Icon Picker, Inspector content, `::` callouts + image/latex render seams. → `Framework.md`.

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

- > Nathan: "use tint since it already does the opacity and is DRY" — reach for an existing scale before adding a parallel token family.
- > Nathan: "fix them all minimally; see if removing guards or limits would fix them instead of adding more code" — triage by removal first; most "findings" were non-issues.
- > Nathan: "dont use darken; use tint" + "the darken happens on the background when it should only happen on the text" — the dragged item dims its **text** (opacity), not a background fill.

**Uncertain**

- Re-nest with **mixed tab/space indent** is now graceful (strip-by-length) but not pixel-perfect; Pommora's own input never emits mixed indent, so it's untested against real mixed docs.
- The `<foreignObject>` editable-text bet in the parked canvas spec is reasoned, not prototyped — flagged there as a 30-min spike before any deep build.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload, **but CM6 widget/extension code needs a full ⌘R / `Page.reload`** (only CSS hot-swaps), and a freshly-added module sometimes needs one reload past HMR. Don't ⌘Q it.
- **Main-process edits need a dev-server restart**; a stale main can silently drop a mutation.
- Runs against a **test nexus** (`~/test`) — a *managed* nexus (carries `.nexus/`) so reorder/settings persist. The running app opens its `lastNexusPath`, not `TEST_NEXUS_PATH`.
- The agent **can** screenshot + drive the React UI headlessly via Electron + CDP (`--remoteDebuggingPort` → `Page.captureScreenshot` / `Input.dispatchMouseEvent`), but Nathan is the primary visual verifier.
- **Parallel sessions happen** — never bundle or revert unattributed changes; **stage explicit paths** (`git add <paths>`), never `-A`.

### Pending Focuses

- **Canvas (new)** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; the `.canvas` format is the cross-build contract.
- **Caret customization (app-wide) — deferred to a proper pass.** Match macOS/Swift's smooth fade (not Chromium's hard blink) across every editor surface via a drawn caret per surface (`caret-color: transparent`, no `drawSelection` — it's all-or-nothing). Tried + reverted once.
- **Subfield reorder + live-stats + custom items** — registry/order/persistence are the seams; `Features/Subfield.md` § Roadmap.
- **Icon picker** — build the real `Components/IconPicker` + wire the icon's frontmatter save (Swift `IconPicker` is the spec; wants a shared dropdown-animation primitive).
- **Real design-system Components** (Button / Menu / Label / Separator) from the token layer — prerequisite for replacing one-offs (notably the inline-rename `<input>`).
- **Radius + spacing tokens** — still ad-hoc literals; lift from Figma.
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface (labels + accent + `subfield`).
- **One-time Biome normalization** — the format-on-write hook keeps touched files clean, but a whole-tree `npm run check` pass hasn't run (defer to a tree with no parallel uncommitted edits).
- **Doc mirror** — a launchd watcher mirrors these docs into the Obsidian vault; keep them current.

### Fix Log

- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** — no input handling for the rendered link inside a cell; proposed single-click navigate + right-click edit.

### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **One window per session in the new format.** Append a new `### <Label>` window next session (carry still-open Pending Focuses); push spec/decision content to its canonical home (`History.md` / `Features/*` / `Framework.md`).
- **Markdown only, no new folder** (per Nathan) — this doc stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.
