## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system (Phases 1-3).** The full cell-gesture matrix (title navigates · status/select/multi/context open the PickerMenu · numbers inline-edit · urls/files open through IPC · right-click always menus). Per-view looks/formats persist in the SavedView's `column_styles`. Group bands drag to reorder; the reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Status + Link/URL property panes.** Status: an open group model (stable-id groups, value=title cascade, in-place grouped editor). Link/URL: `resolveFieldValue` coerces plain-string kinds to the DECLARED type post-cache; `link-title` fetches the page `<title>` (main owns `net` + `.nexus/linkTitles.json`); alias always wins, stored `[alias](url)`. → `Features/Properties.md`.

- **7-2 Properties assign-flow.** Assigned rows over a bottom-pinned **All Properties** disclosure; promote by `+`/drag, drag-out **Removes** (strip-and-cache against the DECLARED type). Global **Delete** lives only in a property's own editor pane.

- **Multi-View Scaffolding (07-05→06, committed `3094e8ce`→`0fc5de98`).** The per-container view switcher stack end-to-end: a standalone **ViewDropdown** button left of the trio (Collection / depth-1 Set only), the **ViewPane** dropdown, the two-door shared **ViewSettings** editor, and the old ViewPane renamed **SettingsPane**. The **G-1 invariant** (views never empty where views can be seen) rides two write sites — creation-seed (`mutate.ts`) + entry-mint (`store.select`→`ensureContainerView`, `viewMint.ts`), all adopt-only through `saveViewAdopting` with a double-mint guard; the store gained an `activeViews` slice. Container keys `view_button`/`view_style`/`format` + `open_in` legacy coercion; menu plumbing consolidated (`AccessoryButton`/`MenuPaneTopRow`/`MenuBottomRow`/`popReturningMenu`). Six view types modeled, only Table buildable. → `Features/Views.md` + `History.md`.

- **Mobile iOS companion (parked — session B, 07-04).** A ratified **Capacitor** spec under `.claude/Mobile/`; a scoped port, 4 desktop pre-paves shipped (`02bb4e11`). No build commitment.

### Session Summary — ViewPane Interactions + the Date & Time and Checkbox Editors (Built)

**Session ID:** c3e6af60-f1ea-4e19-9507-08776f15d04a
**Dates:** 07-05 → 07-06-2026
**Model:** Opus 4.8
**Compactions:** 3
**Connectors:** none called (CDP is DOWN this arc — Nathan runs his own dev on the debug port; he verifies UI visually)
**Commands:** /compact · /handoff
**Agents:** Explore (4x - grounding), build-breaking-agent (2x - spec review + killed impl review), code-simplifier (2x - cleanup)
**Skills:** using-superpowers · studio-brainstorm · `superpowers:writing-plans` · `superpowers:executing-plans` · handoff

Three arcs: ViewPane interaction polish (`fc305967`→`e3ec5c5a`), the **Date & Time property editor built + shipped** (`bc9c4522`→`15bd913f`), then a live **icon pass** Nathan drove — column icons, view-type glyphs, timestamp glyphs, and the type-grid aliasing fix (`e032dcdf`→`7605c3a3`). He verified each visually (CDP down) and called it a day.

**ViewPane interaction polish (compressed).** PaneSlider went intrinsic + DRY'd to every pane (one `open` boolean; MenuScrollFrame owns cap/scroll/footer), the fake slide-OUT jitter got a `useExitPresence` latch, rows gained drag-reorder + a per-view Rename/Edit-Icon/Delete native menu + an active-row ring + flush inline rename, and the row chevron/context-menu tone+scoping were fixed with the `&&` (0,2,0) defeat. `fc305967`→`e3ec5c5a`. → `History.md`.

**Date & Time editor built.** The blank `datetime` branch became a **Format** section (Date · a conditional weekday **Day** · Time PickerMenu rows), a second discoverable surface writing the same per-view `column_styles` the column-header Style menu already did. Weekday split out of `full` into its own decoupled dimension (`full` reshaped weekday-free); a new **Relative** format is Time-gated ("Today at 3:30 PM" within a week, else "2 Weeks from now"), with the CalendarPicker entry boundary coercing `relative → short` so a date being entered never reads relative. **The load-bearing plumbing (Set-divergence):** for a depth-1 Set, PropertiesPane gets the ancestor's `collectionPath` but must write the *selected* container's view — threaded `source = node` + `useActiveView` through `saveViewAdopting`, pinned by a passing write-path test. Tasks 1–3 landed as one commit (the `'relative'` union gate). `bc9c4522`·`3903a20b`·`9f5265e7`. → `Properties.md` + `Views.md` + `History.md`.

**The live UIX-regression round.** Nathan drove a rapid fix loop on the working UI (CDP down, he's the eyes). Picker exit animation: the exit was ALREADY owned by PickerMenu — my call-site `{open && …}` guard was unmounting it before it played (removed it). Picker option text rendered UA-black because the portal escapes label context — DRY'd its own `control`-tone type into the shared `option` style. Property editors gained a title divider; the Properties-pane tones settled into a hierarchy (assigned primary › unassigned secondary › section headings tertiary), which forced restructuring the All-Properties row off MenuItem so its label escapes the surface's primary `titleText` global. `f26a5120`·`7cb6af61`·`2e0dc7d7`.

**Two structural regressions surfaced + fixed at source.** (1) The All-Properties spacer stopped bottom-pinning: the MenuScrollFrame consolidation had dropped the flex-column its filling drag-box needs — restored on `scrollFrameBody`. `8c163f33`. (2) The pane height "bounced" on in-place growth: PaneSlider drove its height off a ResizeObserver with an always-on transition, so a `Reveal`/spacer animating in place made the height lag-chase a target that moved every frame — gated the height transition to nav flips only, letting the child's own animation own in-place growth. `adc39ec6`.

**Icon pass (`e032dcdf`→`7605c3a3`).** Column headers render their type glyph (tier → context, Created → `clock-plus`, Modified → `history`), gated by `hide_column_icons` — now also a **checkbox** in the column menu above the Hide divider. View-type glyphs reworked: Table → plain Lucide `Grid3x2` (the old `rotate(90deg)` Table was the aliasing source), Cards → a custom stretch-horizontal bar stack, List → a custom left-rail bar + four lines (both sized level with the Lucide glyphs), Status → Tabler `IconProgressCheck` (first `@tabler/icons-react` opt-in, scaled ~10% via `scaleTabler`). **The type-grid aliasing was the alpha color, not the glass:** a white-alpha label tone doubles where a glyph's strokes overlap → switched the tile glyph to the opaque `solid.grey` primitive. Lucide's default stroke is 2 (not 1.75) — custom glyphs + Symbols.md corrected. → `Icons.md` + `TableView.md` + `History.md`.

**Checkbox editor built + reviewed.** The blank `checkbox` branch became a **Color** chip (property-wide def-level `checkbox_color`, the Link editor's picker logic) + a **Style** picker (per-view Checkbox ⇄ Switch), sharing a `PickerControl` extracted from the datetime editor; the link `linkColorCss`/`link*` primitives generalized to `solidColorCss`/`config*`. **Locked — color is ON-state only, defaulting to the configured accent:** an empty box/off switch is neutral grey; a checked box tints its color (a set solid, else `var(--accent)`) and a switch's on-track tints — so the box matches the switch and resolves for a palette OR `system` accent (the build-breaker's three-way "Accent" mismatch, fixed). The group-header "On" box tints the same way (shared `checkboxBoxStyle`). **Column Icons flipped to default-off** (Nathan's call). Residual: the editor's "Accent" chip can't render an OS `system` accent through a palette key — noted in Properties.md Known Issues. → `Properties.md` + `TableView.md` + `History.md`.

### Lessons Learned

- **A portalled surface escapes label-tone context — it must set its OWN tone.** PickerMenu options render into a `document.body` portal, past any label-color ancestor, so with no explicit color they fell to UA-black. The fix belongs in the shared `option` style (DRY for every picker), not the caller. Same class of trap as the toolbar-button tone: when a thing renders outside its expected DOM context, don't assume inheritance.

- **Don't gate a self-managing exit component behind `{open && …}`.** PickerMenu already owns its mount → Bloom-out → unmount via `useExitPresence(open)`; wrapping it in `{open && <PickerMenu open={open}/>}` unmounts it before it can animate out. Always render it, drive by `open`. ColorPicker was the correct precedent; the bug was reintroducing the anti-pattern. Nothing to "DRY into" the component — the centralization already existed.

- **A ResizeObserver-driven height must not CSS-transition while its content is animating in place.** PaneSlider eased height toward a ResizeObserver reading, so an in-place `Reveal`/spacer animation made the transition chase a target that moved every frame (the bounce). Separate the two motions: transition height only across a discrete navigation flip; let in-place growth track content untransitioned so the child's animation owns it.

- **SVG glyph "aliasing" is often the alpha color, not the compositing.** A type-grid glyph read fuzzy; the guesses were glass backdrop + sub-pixel raster, but the real cause was the white-**alpha** label tone — where a glyph's own strokes overlap (grid crossings, bar edges) the semi-transparent strokes double, and the soft alpha edges read as aliasing. An opaque hex (`solid.grey`) composites clean. 

- **A shared `titleText → primary` global overrides row-container tones.** Nathan's `menuSurface` edit pins every dropdown row title primary via `.surface .titleText` (0-2-0), which beats a row's inherited container color — so dimming a row (unassigned → secondary) needs a 0-3-0 scope (`.surface .allRow .titleText`), not a container color. Setting color on the MenuItem alone is silently dead for its title.

- **Docs describe intent; the code is truth — the adversarial pass earns its keep on plumbing, not design.** Properties.md claimed date formats were unread foreign keys; the renderer + column menu already read/wrote them. And the reviewer caught the Set-vs-schemaCollection divergence a design read would've missed — the property editor gets the schema collection's path but must write the *selected* node's view.

- **Calibrate ceremony to the task.** The load-bearing feature (Date & Time, per-view storage, the relative-union gate) got the full brainstorm → plan → adversarial loop; the live UIX regressions Nathan drove got build-and-fix-and-verify. Both were right.

### Next Session

**1. The remaining per-type property editors.** Date & Time and Checkbox shipped this session; the last per-type pane is **Number** (its value-type editor + a number-format picker), plus the relation (context) pickers — see Properties.md Pending "Per-Type Editor Panes". The datetime/checkbox editors (`DateTimeEditor.tsx` / `CheckboxEditor.tsx` + the shared `PickerControl` + the `saveColumnStyle`/`useActiveView` plumbing in `PropertiesPane.tsx`) are the pattern to mirror.

**2. The remaining multi-view stubs** — the non-Table renderers (Cards · List · Gallery · Calendar · Timeline; the `PropertyEditing/` surfaces are table-agnostic for reuse) and the ViewSettings Group · Sort · Filter leaves (blank-leafed; wire to the shipped `GroupConfig`/`SortCriterion[]`/`FilterGroup` seams).

Build discipline: every pane push rides the (now intrinsic) PaneSlider; PickerMenu options + the section-heading tones are now DRY at the shared source (don't re-tune per-surface); main/preload changes need a full dev restart, not ⌘R.

### Pending Focuses

- **The dropdown row-title tone is `label.primary`** (`menuSurface.css` `.surface .titleText`, committed this session with Nathan's other knobs). It's load-bearing for the Properties-pane tone hierarchy — assigned rows read primary and the unassigned-row `0-3-0` override assumes it. Don't flip it back to `label.control` without re-checking the tiering.

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table (`loadValues` runs per container-open; the tree carries structure, not values). The mtime-gated walk is fine; container-surgical reconcile is the designed escalation at real scale.

- **Add-to-group:** the `+` glyph beside a set's grouping label creates nothing.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device is last-writer-wins (atomic temp+rename prevents corruption). `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 is a `window.nexus` bridge shim + a native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore` (or scaffold it).

- **"Edit Icon" opens a stub picker.** The per-view row menu's Edit Icon opens the same "coming from Figma" IconPicker stub the container icon opens — functional wiring lands app-wide when the real picker ships.

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed char (frontmatter clean, survives backspace). Likeliest: `TextPicker`'s left padding or `nativeCaret`'s position-only blind spot. Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md`.

- **Context sidebar crud** — you still can't create a Context via the sidebar.

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a dev-server restart** (a new native menu / IPC won't appear until then — bit the ViewPane row menu this session). Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Full kill + relaunch before concluding a CSS-in-TS or handler change failed.

- **The dev app runs against Nathan's REAL Nexus.** UI value writes are his data; CDP must open + Esc only, never pick/commit — unless he authorizes a mutating gesture with state restored exactly. **CDP works:** launch `env -u ELECTRON_RUN_AS_NODE npm run dev -- --remote-debugging-port=9222`, drive via a small Node built-in-`WebSocket` CDP client (`Input.dispatchMouseEvent` for real trusted clicks — synthetic React events don't open collections; `getBoundingClientRect` gives CSS coords = CDP coords; `Page.captureScreenshot` → Read the PNG). **Native OS menus (⋮ editor menu, column right-click) don't render in the DOM — CDP can't drive or screenshot them;** reach those ops through `window.nexus.*` IPC via `Runtime.evaluate` instead.

- **"Column Icons" vs "Label Icons" — cross-view naming.** The table Layout toggle is **Column Icons** (`hide_column_icons`) — accurate because table columns include metadata (Created/Modified) that aren't properties. A columnless view (Gallery/List) would surface the same flag as **"Label Icons"** (Nathan's suggestion). Decide generalize-vs-per-view-field when a second view type consumes it.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two passes, the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A` (a dir-level add sweeps a concurrent session's edits, and a worktree's symlinked `node_modules` escapes the gitignore). Nathan tunes knobs in his own editor alongside Claude — unattributed `M` files are almost always his, left uncommitted on purpose.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it. A fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending + Fix Log to a fresh session.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another session's block.
