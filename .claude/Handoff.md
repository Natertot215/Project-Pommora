## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system (Phases 1-3).** The full cell-gesture matrix (title navigates · status/select/multi/context open the PickerMenu `PropertyPicker` · numbers inline-edit · urls/files open through IPC · right-click always menus). Per-view looks/formats persist in the SavedView's `column_styles`. Group bands drag to reorder; the reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Status property — an open group model.** Each group is a stable `id` with a user-editable label, color, and options; three calendar-phase defaults (Open / Active / Done). An option's `value` IS its label; a rename cascades onto every assigning page's `$status`. The grouped editor edits in place. → `Features/Properties.md`.

- **7-2 ViewPane Properties assign-flow.** Assigned rows over a bottom-pinned **All Properties** disclosure; promote by `+`/drag, drag-out **Removes** (strip-and-cache, restored against the DECLARED type). The global **Delete** lives only in a property's own editor pane. → `Features/Properties.md`.

- **Link/URL property pane (07-04).** `resolveFieldValue` coerces plain-string kinds to the column's DECLARED type post-cache; `link-title` mode fetches the page `<title>` (main owns `net` + parse + `.nexus/linkTitles.json` cache), an alias always wins, stored markdown-native as `[alias](url)`. Nathan's pin: the surface he expected to be simplest cost 8+ hours because the codec, render pipeline, and shared caret/picker/input machinery all converge on one cell.

- **Chips · Overflow · Perf.** Chips are shape primitives with an opacity-only hover-× melt (a Chromium dropped-repaint family forces the shape → `Guidelines/Build-Gotchas.md §Chip Melt`); the no-empties rule in `applyPropertyValue` deletes null/empty keys but keeps `false`/`0` and tier `area: []`. `OverflowScroll.tsx` is THE truncate-hover-scroll box. Hot paths are cached/memoized (mtime-gated walk cache, WeakMap value-parse cache, `React.memo` rows, var-driven column drag).

- **Session B — mobile future-proofing (07-04, separate session `164497e3`).** A `studio-brainstorm` ratified a **Capacitor iOS companion** spec (reuse the renderer in a WebView, re-host main natively, iCloud app-container sync, most-recent-wins) under `.claude/Mobile/` (`MobileSpec` + 6 siblings, mirrored to `II. Mobile`); a scoped **port, not a rewrite**. Four behavior-preserving desktop pre-paves shipped (`02bb4e11`): a standalone browser Vite target (`npm run dev:app`), one shared `assetUrl.ts`, a `DEVICE_LOCAL_NEXUS_FILES` set in `paths.ts`, and iOS soft-keyboard input attrs on MarkdownPM. Parked — no build commitment.

### Session Summary — Multi-View Scaffolding

**Session ID:** c3e6af60-f1ea-4e19-9507-08776f15d04a
**Dates:** 07-05 → 07-06-2026
**Model:** Opus 4.8
**Connectors:** Electron CDP (live screenshots + UI drive — built app on `:9222`, not MCP)
**Agents:** build-breaking-agent, code-simplifier, general-purpose (adversarial spec/plan reviews)
**Skills:** studio-brainstorm; `superpowers:writing-plans`; handoff

Built the per-container **multi-view switcher stack** end-to-end through the full discipline — decision log → 14-task plan (three review rounds folded) → inline per-task execution → CDP verification. The feature is committed per-task on `main` (`3094e8ce` → `0fc5de98`).

**The surfaces.** A standalone **ViewDropdown** button sits left of the toolbar trio, rendering only on a Collection or depth-1 Set (`isDepth1Set`, `Scope.ts`); its glyph is the active view's icon, click opens the **ViewPane** (a row per saved view + a footer BottomRow), right-click opens a native presentation menu (Show/Hide Title · Style). A view row's chevron pushes into **ViewSettings** — the shared per-view editor with two doors: the *full* door (ViewPane chevron; ⋮ Duplicate/Delete + the Layout leaf) and the *flat* door (SettingsPane → Layout; no ⋮, no Layout row). The old `ViewPane` was renamed **SettingsPane** (Configuration/Open In + the flat Layout door), freeing the name.

**The G-1 invariant** ("views never empty where views can be seen") has two write sites: creation-seed (`createContainer` in `mutate.ts` seeds the default view on disk) and entry-mint (`store.select` is the SOLE mint site via `ensureContainerView`, `viewMint.ts`). All writers adopt-only through `saveViewAdopting`; an in-flight map keyed on container id guards a double-mint (HIGH-1: the guard survives a failed refetch). The store gained an `activeViews` slice + `setActiveView` (hydrated in `load()`); `useActiveView` is a pure store-selector hook (no fetch effect).

**Container config + menus.** New sidecar keys `view_button` · `view_style` · `format` (both allowlist sides); `open_in` renamed `full-page`/`page-preview` with legacy coercion (`coerceOpenIn`/`coerceViewButton`/`coerceViewStyle`, `schemas.ts`). Menu plumbing consolidated into one home — `AccessoryButton`, `MenuPaneTopRow`, `MenuBottomRow`, `popReturningMenu`, all dropdown title tones DRY'd to `label-control` at `MenuSurface`. The type roster is six (Table · Cards · List · Gallery · Calendar · Timeline; Board dissolved) — only Table is buildable this cycle, the rest render at full weight but inert.

**Build-breaker findings** (all fixed): HIGH-1 double-mint on failed refetch, HIGH-2 depth-1 violation via Back-nav, MED-3 empty ViewPane list during the mint beat, MED-4 missing maxHeight cap, LOW-5 duplicate mis-position.

**Closing UIX polish (uncommitted at handoff — awaiting Nathan's go):**

- **ViewDropdown title slide.** Show/Hide Title now morphs one stable `SegmentedButton` (was a `SegmentedSymbol`↔`SegmentedButton` swap that unmounted the label): the title rides a grid track collapsing `1fr → 0fr`, sliding in/out at content-width. DRY'd to a new `titleReveal` token in `animations.css.ts` (the panes' Bloom curve on the `dropdown` duration). Verified 69↔32px on a clean ease.

- **ViewSettings entry bounce, fixed.** The pane snapped open from `auto` because `slotB` (ViewSettings) is `null`/unmeasured until a chevron click. Fixed in `ViewPane.tsx` with a two-phase push — mount the detail first, flip `active` on the next frame once measured — so height animates in lockstep with the slide (sampled 93→268, no overshoot). Measuring the slot *during* the flip is the wrong fix (reading `offsetHeight` at `auto` locks the transition baseline).

- **ViewPane square minimum.** The pane reserves a `PANE_SQUARE` (225) floor — a sparse list no longer collapses; rows fill it top-down with the footer pinned to the bottom (`vd.rowsFill`), and only past the square does it grow. The default active-view row highlight was removed.

- **Footer padding knob.** `--bottom-row-block` on `bottomRow` (`menu.css.ts`) — 0 by default, a consumer loosens the +/… bar off the surface edge.

- **Table glyph.** A native-SVG redraw was tried and reverted per Nathan — `TableWide` stays the real Lucide Table CSS-rotated 90° (`customGlyphs.tsx`).

### Lessons Learned

- **A transition can't animate from `auto`, and measuring at `auto` poisons its baseline.** A slot that mounts on the same render that flips it is unmeasured (`0`→`auto`); forcing an `offsetHeight` read there locks the resolved size in as the from-value, so the target equals it and nothing moves. Measure the incoming slot a frame *before* the flip, never during.

- **When Nathan says "just rotate the real glyph," a hand-drawn look-alike is a miss.** He'd rather keep a real-icon rotation (even with a faint rasterization tell) than a bespoke SVG that reads subtly off next to the Lucide set. Rotate the source glyph; don't substitute geometry.

- **CDP drive-then-read races the invocation gap.** Arming a sampler in one `cdp eval` and triggering the action in the next loses ~200-400ms of process startup — the transition finishes before the sampler starts. Arm the rAF sampler AND fire the click in a single `eval`.

- **`grid-template-columns` `1fr`↔`0fr` animates in Electron 42's Chromium** — a real content-width collapse both directions, the right tool for a label that must slide in/out without a fixed width.

### Next Session — filling the multi-view stubs

The scaffolding shipped; the panes and renderers behind it are stubs.

1. **The non-Table view renderers** — Cards · List · Gallery · Calendar · Timeline. The type grid selects them but only Table renders; each needs its container renderer (the `PropertyEditing/` surfaces were built table-agnostic for exactly this reuse).

2. **The ViewSettings sibling panes** — Layout · Group · Sort · Filter ship blank-leafed; wire them to the already-shipped `GroupConfig` / `SortCriterion[]` / `FilterGroup` seams. The Layout leaf (order + visibility) is the deferred Figma redesign.

3. **The rest-of-properties per-type editor panes** — Number, Date, and the remaining value-type editors, riding the same nested-slide + pane-beat plumbing the option editors used (6-28 spec §Pending). The naming/duplicate-title work (§H of the 7-3 decision log; value=title + reserved-char auto-disambiguate across Select/Multi/Status, absorbing the legacy-data migration) is the headline that follows.

Build discipline: every pane push rides the nested PaneSlider; TopRows name their DESTINATION; the ViewDropdown/ViewSettings CSS are KNOB files (sizes are Nathan's, never re-tune).

### Pending Focuses

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table (`loadValues` runs per container-open; the tree carries structure, not values). The mtime-gated walk is fine; the container-surgical reconcile stays the designed escalation if a measured wall appears at real scale.

- **Add-to-group:** the `+` glyph next to a set's grouping label in a view doesn't create anything.

- **Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts, the box-nesting guard table, cross-container re-prefix.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** an in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device edits are last-writer-wins (atomic temp+rename prevents corruption). `.nexus/index.db` needs sync-exclusion; the walk must skip evicted `.icloud` placeholders.

- **Mobile iOS companion (parked — session B):** spec at `.claude/Mobile/MobileSpec.md` (+ 6 siblings); 4 pre-paves shipped (`02bb4e11`). Step 1 is the gate — a `window.nexus` bridge shim + a native iCloud Swift plugin. No commitment to build.

### Fix Log

- **`.nexus/activeViews.json` isn't gitignored (open — now live).** Neither it nor its per-machine siblings (`folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles`) are ignored in the Nexus repo — using the multi-view pane on a fresh container creates a would-sync file. Add these to the Nexus `.gitignore` (or have the app scaffold it) — matters more now that the switcher ships.

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed character (frontmatter byte-clean, `.value` carries no space, survives backspace, async title never the key). Likeliest future quick look: the field's own left padding in `TextPicker`, or `nativeCaret`'s position-only blind spot (a pane re-center with no resize doesn't trigger the ResizeObserver). Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either half corrupts the document (`MarkdownPM/editor/blockModel.ts` — test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md` §Known Issues.

- **Context sidebar crud** — you still cannot actually create a Context via the sidebar.

- **Outliner rails on ordered / arrow / `+` lists deferred** — scoped to dash-bullets + checkboxes; ordered/arrow need per-glyph centring (~30 min), parked over shipping misaligned. → `Features/MarkdownPM.md`.

### Working Notes

- UI iteration runs in **dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R** and **`src/main`/preload need a dev-server restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev` (no CDP). For a Claude-inspectable session: a built app on `:9222` after `npm run build`, launched `env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron . --remote-debugging-port=9222`. A component change needs a rebuild + `location.reload()` over CDP.

- **HMR is NOT trustworthy for two change classes:** (1) vanilla-extract `*.css.ts` — a style edit can keep serving stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often doesn't re-apply it. Do a FULL kill + relaunch before concluding a CSS-in-TS or handler change failed. → Build-Gotchas §Toolchain.

- **The dev app runs against Nathan's REAL Nexus.** Value writes via the UI are his data; automated CDP must open + Esc only, never pick/commit — unless Nathan authorizes a mutating gesture with the standing condition that state is restored exactly (drop → verify on disk → reverse).

- **CDP tooling** in the scratchpad: `cdp.mjs` (eval/click/tapxy/taptext/shot). Reading a screenshot surfaces it to Nathan. Multi-line `eval` must be wrapped in an IIFE (a bare statement block throws); pretty-printed JSON output spans lines, so don't `tail -1` it.

- **Parallel sessions** — stage explicit paths, never `-A` (a dir-level add sweeps a concurrent session's edits, and a worktree's symlinked `node_modules` escapes the gitignore).

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so — silently fix what contradicts it; don't narrate the reversal or version the mistake. A fresh agent should never be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry here is genuinely done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending Focuses + Fix Log forward to a fresh session.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; the Cornerstone + footer are shared; never edit another session's block.
