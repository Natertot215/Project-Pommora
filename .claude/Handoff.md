## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system.** The full cell-gesture matrix, per-view looks/formats in `column_styles`, band drag, and the reusable table-agnostic editing surfaces in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Multi-View Scaffolding + per-type property editors.** The view switcher stack (ViewDropdown · ViewPane · two-door ViewSettings), the G-1 invariant (views never empty where visible), and the Date/Checkbox/Number/Status/Link editor panes. Only the relation/context pickers remain. → [[Views]] + [[Properties]].

- **Icon Picker + Sidebar Ribbon.** The full-Lucide picker in the shared PickerMenu; the ribbon + mode-switched sidebar (surface-launcher model, lazy `agenda:list`, creation via right-click). → [[Studio/Pommora/II. Features/Icons]] + [[Sidebar]].

- **The Table Grouping + Sorting (shipped + merged).** Grouping + Sorting shipped for tables end-to-end — the pane, the pipeline, Location order writing the real filesystem, and the drag surfaces — with the structural-only settings locked view-level beside `group_order`. The tableDnd frozen-closure fix (per-render `cfg` ref) rode along. → [[Views]] `### Grouping` + [[TableView]] + `History.md`.

### Session Summary — Block Surfaces: Certified Spec → Live System

**Session ID:** abc3bafe-70bc-41e4-adfd-aa052cfee424
**Dates:** 07-10-2026 → 07-12-2026
**Model:** Fable 5 → Opus 4.8 (1M)
**Compactions:** 5
**Connectors:** none
**Commands:** /clear · /handoff · /compact · /loop
**Agents:** Explore (1x - census) · general-purpose (5x - research + SurfacePM cleanup/token/DRY audits) · build-breaking-agent (14x - spec rounds + per-task reviews) · code-simplifier (2x - closeout + Task 5) · comment-killer (1x - arc sweep, came back clean)
**Skills:** studio-brainstorm · superpowers:writing-plans · superpowers:executing-plans · superpowers:systematic-debugging · handoff

One session, the whole arc: the Contexts rethink became a certified spec, the spec became SurfacePM, and SurfacePM became a live block system Nathan drove all evening.

**The spec:** `Planning/7-10 - Block Surfaces — Decision Log.md` — review-certified through three adversarial rounds, then reopened live for Section H (embed mechanics, all confirmed) and extended through G-15/H-11 as Nathan drip-fed decisions. The capability-fusion diagnosis (block dashboards reserved to tag tiers) drove the host-agnostic BlockHost design; the contexts resolution stays parked. Durable spec now lives at [[SurfacePM]].

**SurfacePM shipped from scratch** (the RGL teardown informed patterns; zero code copied — `SurfacePM/README.md` records provenance): the split-tree model (row ratios / independent column stacks / per-tile px heights), window-style edge resize (south stretch · north stack + cross-band pair · e/w splitters · alignment snap), PommoraDND feel (lift-follow-settle on Glide), the notched grip handle with its menu (Type ▸ / Style ▸ / Remove-confirmed), right-click background create with wedge fill, and pane-toggle 1:1 tracking. Consolidated engine review folded (settle interlock, snap dead band, codec salvage).

**The plumbing arc ran Tasks 0–3** of `Planning/Block Surfaces — Plumbing Plan.md` (plan itself plan-attacked; H1/H2 findings pre-empted real corruption): the block document behind the BlockHost seam (locked read-merge-writes on homepage.json, main-side patch validation, watcher ignores host dirs), markdown block tiles (ULID `.md` lifecycle, pure-body writes, trash-recoverable), and the shared page-embed framework — where Nathan redirected the static-render plan into **the CM6 portal**: every prose tile IS a read-only MarkdownPM view, editability flipped by compartment (E-4 rewritten), one `--mdpm-scale` variable sizing the whole editor, popups portaled to body (a transformed tile re-anchors `position:fixed` — H-11), gutter glyphs self-centering, caret-priority scroll.

**Continuation (07-11 → 12).** The H-5 view-embed chrome + edge-release scroll landed and were live-iterated (title row sized by markdownPM's own `.md-hN`, pill switcher with drag-reorder + create/delete slide, dropdown mode, top+bottom scroll-fade), then the arc closed its plumbing + hardening. A mid-compact **selection bug** (at-rest markdownPM embeds unselectable — `EditorView.editable.of(false)` killed native selection; fix keeps editable true, gates edits through `EditorState.readOnly` alone), the per-nexus **default view scale** (`personalization.defaultViewScale`, applied main-side on open + ⌘0, empty-state + no-flash review folded), view embeds **corner-scoping their handle while busy**, and **Task 5 — the link graph** (block `[[links]]` → first-class edges + rename heal, review-certified after folding read-only-build + mtime-safe findings). Then Nathan's four directives: both stale worktrees removed, the **`[[link]]` bracket bug fixed at source** (`pageLinkPattern` tolerates internal brackets — repairs page + block bodies at once; a trailing `]` is the one irreducible grammar ambiguity, degrades to a phantom), and the **view-embed config lock** in the SettingsPane footer (freezes config via the single `persistConfig` chokepoint, no dim; `setLocked` via unguarded `patchEntry` so you can always unlock). A SurfacePM-wide cleanup audit ran + its safe findings folded (two dead `::after` rules, `getTile` reuse, hygiene).

**Continuation (07-12) — Homepage Lock + Settings arc (Tasks 1–5 of the Homepage-Lock plan).** The Task-6 leftovers finally got their surface. A **homepage board lock — geometry-only:** it freezes drag + resize but keeps the grab-menu, content editing, and background-create live (store-synced `homepageLocked`, seeded in `applyTree` off the config readNexus already reads — no extra IPC; the handle menu goes inert + reads a muted "Locked" under it). It first shipped as a FULL freeze; its review found real F1–F3 issues, then Nathan reversed the whole thing: *"locking should NOT disable the grab-menu. It should only disable the resizing."* A **homepage + context identity SettingsPane scaffold** — the host-settings surface 6.1 was blocked on now exists (`SettingsScaffold`, routed by `viewSettingsScope`). The homepage IS the nexus, so its icon is a **photo OR glyph** set from a native `nexus:iconMenu` (Change Icon → the glyph picker · Add/Change Photo → crop), one shared `useNexusIcon` hook reused across ribbon + settings + banner (photo > glyph > house). **Hide/show the banner heading icon** landed for every banner entity (`heading_icon_hidden` via a new `setHeadingIconHidden` op): the homepage banner — icon-less before — now leads its title with the identity icon (house default so the toggle's always there, sliding in/out), and its title gained Rename (→ `renameNexus`) + a borderless inline rename. Fixed a **context-icon regression I introduced** (`8a2505a6` made `ContextRow` honor `node.icon` via raw `||`, so a Swift-era `"rectangle.stack"` sidecar won → dashed square; fixed with `iconNameOr` validate-or-default, root-caused by reading Nathan's real Nexus on disk). Closed with two review-flagged fixes: a board-locked handle menu goes fully inert, and Escape peels one popover at a time (a picker eats its own Escape, the pane it sits in stays). Commits `6a8f6423`…`0074380a`.

**Continuation (07-12, late) — closeout doc-alignment + a low-risk cleanup sweep.** A "make the bed, don't change the mattress" pass ahead of the SurfacePM finalize — no architecture touched. Docs realigned to shipped reality: [[SurfacePM]] now describes view embeds + the geometry-only host lock as built and its Pending lists only genuinely-open work; Structure/Sidebar call the homepage ribbon icon the Nexus **identity icon (photo OR glyph)**, not a profile photo; Contexts says the tiers **default to** the grid icon (a set icon overrides). Homepage's graph-view final-shape direction stays a live consideration (Nathan's call — do NOT strip it). Two read-only finder agents swept the subsystem and it came back remarkably clean: one duplicated view-config id-remint hoisted to `remintConfigIds` (`main/blocks.ts`), a few split CSS rule-blocks merged, a dead `nodeAt` export dropped, and `Banner.css`'s lone `rgba()` + a hardcoded `180ms ease` rerouted to hex + `--duration-fast`/`--ease-standard`; comment-killer found ZERO strippable comments (every one is a spec-ref/hazard/rationale). The real LOC win — a shared debounced-save hook between `MarkdownBlock` ↔ `PageEmbed` (~35 LOC) — was flagged and deliberately NOT done (a refactor across the save/flush boundary, not a tidy). Typecheck + 1486 tests green. Commits `07666190` (docs) + `456b5469` (cleanup).

**Lessons Learned**

- **A transformed ancestor breaks `position:fixed`** — SurfacePM tiles ride `translate()`, so ANY fixed-position UI inside a tile subtree misplaces + clips. Popups must portal to body; this will bite every future in-tile surface that forgets.

- **Reordering keyed DOM nodes mid-drag silently releases pointer capture** — tiles render in stable id order, never tree order (the zombie-gesture class). Same family: React batching guarantees a remove-IPC beats an unmount flush, so removal flows must suppress the flush explicitly.

- **CDP can't drive native reality:** right-click doesn't synthesize `contextmenu` in Electron, native menus block headless, and the earlier chip-melt lesson held — verify those paths with synthetic DOM dispatch + Nathan's hands, never claim them from CDP silence.

- **Dead reviewer agents are recoverable:** two build-breaking agents died silently at delivery; their findings were extracted from the subagent JSONL transcripts (`jq` over assistant text) and folded anyway. Quiet transcript + stale mtime = dead; the work isn't lost.

- **Nathan reverses load-bearing designs live — build to be reversible, hold commits until he's eyeballed.** The board lock shipped a full freeze, then flipped to geometry-only mid-session; the banner inset went 12→8→12→unified. Fold each redirect at once, batch-commit after his look. And the pipefail trap bit AGAIN: `typecheck 2>&1 | tail` returns tail's 0 and hid a red build (Task 1 shipped typecheck-red; only the adversarial review caught it) — capture the real `$?` into a file, never trust a piped exit.

- **A clean subsystem resists the sweep — that's the signal, not a miss.** The block-surfaces DRY/token/comment sweep netted ~15 LOC and zero comment strips: the code was already tokenized (`var(--…)` everywhere) and every comment load-bearing. When a cleanup pass comes back near-empty, don't manufacture churn to look thorough — the remaining LOC lived in ONE risky refactor (the shared save hook), which is a scoped task, not a tidy.

**Key Files & Insights**

- `SurfacePM/` — the engine (README = module map + invariants); `Blocks/` — the tile family; `Embeds/PageEmbed.tsx` — the shared framework, `EMBED_SCALE` is THE embed knob.
- `shared/blocks.ts` — the cross-process block contract (entries stay raw; `knownBlock` is the read lens; `blockPatchProblem` gates saves).
- `main/blocks.ts` — every doc mutation through one locked read-merge-write; `setBanner`'s homepage branch shares the lock (lost-update fix).
- Knobs Nathan tunes live: `--tile-border` / `--handle-w` / `--grip-size` (surfacepm.css, self-centering) · `HANDLE_REVEAL_PX` (SurfaceView) · `EMBED_SCALE` (PageEmbed) · `--mdpm-scale` at :root.

**User Feedback**

- Nathan live-drives and drip-feeds mid-turn corrections — fold each immediately, commit in batches, bundle his tunes.
- Empty states get no meta-commentary; token names he says may not exist (state-active → state-selected) — map and flag, don't mint.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart** (electron-vite builds main ONCE at launch). Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`; relaunch with `-- --remote-debugging-port=9222` to keep CDP.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. (Plain `.css` DOES HMR reliably.)

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit — unless he authorizes a mutating gesture. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two passes, the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's, left uncommitted on purpose.

- **main is ahead of origin, unpushed** — Nathan pushes in batches on his own call; merge ≠ push.

- **Detail insets split by surface kind:** block surfaces (homepage, contexts) run the tight `--surface-inset` (8px tile body) + `--surface-banner-inset` (12px banner), driven by an `is-surface` class (`isSurfaceKind` in `Detail/Scope.ts`); page/table views keep `--content-inset` + `--fold-gutter`. Every banner title sits on the 12px inset (Nathan's call).

### Next Session

**The arc: finalize SurfacePM → merge to main → move to the Next Focuses.** Tonight's closeout pass cleared most of Nathan's "cleanup / DRY / CSS-duplication / doc-reconcile" preferred actions (see the late-07-12 summary). What remains to call the *system* done is below, then Nathan's post-merge feature queue. **His priority list and the prior roadmap are merged here — both preserved.**

#### SurfacePM closeout (must clear before merge)

Grounded state: view embeds, the PickerMenu block menu, the link graph, the geometry-only host lock, the view-embed config lock, and the identity `SettingsScaffold` all SHIPPED. The gaps that still hold the tile system short of parity:

- **Page-embed header + banners — DEFERRED to a [[SurfacePM]] Pending feature** (Nathan's call, 07-13). Design settled during a live pass: **banner off** = a hover-revealed breadcrumb (`Collection › Set › Page`, path `--label-secondary` / page `--label-control`, `control` size, opacity-only reveal on embed-hover or active edit, non-clickable); **banner on** = the real page banner image + in-line title; the on/off toggle is a right-click heading context menu (mirrors the view-embed chrome menus). Page embeds ship **header-less** for now — no longer a merge blocker. Full spec lives in [[SurfacePM]] Pending; the entry's `banner`/`title` stay wired (page embeds default banner-OFF).
- **6.2 Insert menu (G-9)** — background right-click → Page / View / Block through the shipped picker (its Page branch wants 6.3, or wire the interim drill so it's never a dead entry).
- **6.3 Link Page search pane + shared recents (G-16)** — the `state.json` recents record is shared plumbing Navigation reuses (locked append-on-open via `serializeOnFile`, `record:false`-guarded); the search PANE is a new UI surface to design.
- **Interaction foolproofing (Nathan's #1 — his hands)** — view embeds under drag-heavy gestures (column resize, group/row drags, view-switch slide, pill reorder); edge-release scroll on a dense surface (escalate to hover-intent capture only if the simple version bites); the borderless half-step; the picker flows (drill depth, Duplicate landing, Delete confirm, Source). Plus **verify the text-selection edge-zone tail**: at-rest selection is fixed (editable-true/readOnly), but the `.spm-edge` overlap eating a selection-drag near tile borders is unconfirmed — needs his mouse.

#### Robustness hardening (Claude's adds — decide in-or-out at merge)

- **Per-tile error boundary** — make the doc's "repair-not-reject, never crashes the host" true at the RENDER layer, not just the data layer. Cheap; worth doing before this is every context + the homepage.
- **Lazy-mount embeds** — every embed mounts a live CM6/table; a homepage-proper with 10–15 embeds mounts them all on open (the "expensive on every X" rule). Decide now vs. retrofit after it lags.
- **Layout undo (⌘Z)** — currently a Prospect; a rearrange-heavy surface misses it day one. Pull in, or defer with eyes open.
- **Empty-host state + `.nexus` gitignore** — a fresh host renders a blank pane with an undiscoverable create affordance; and the Fix-Log gitignore gap now bites hosts (they write `.nexus/` sidecars).
- **The shared debounced-save hook (flagged, NOT done)** — `MarkdownBlock` ↔ `PageEmbed` share ~35 LOC of save/flush scaffolding; extracting it is the real LOC win but a deliberate refactor across the save boundary (load-bearing `suppressFlush` + reset-on-path divergence), and the PageEmbed seam grows the `![[]]` consumer. Its own scoped task, not a tidy.

#### The Scale model → Nathan's "Scale >" slider

Nathan's "Next Task: drag-menu **Scale >** vertical slider (rides a default zoom, zooms the content)" needs the scale model finished first: the spec claims one `--mdpm-scale` drives everything, but the "stragglers" (glyphs, chevrons, gutter spacing) aren't fully unified. **Finish the single-scale-variable unification, THEN add the per-tile scale override + the slider-out-of-menu UI.** Building the slider on an unfinished model is backwards. Post-merge is fine.

#### Post-merge — the Next Focuses (Nathan's queue)

Distinct from SurfacePM-the-system; these CONSUME it (two reuse the embed framework, so the clean framework pays off here):

- **Page/View Previews** · **Filter-pane redesign** · **Navigation** (Window + Dropdown + Inspector → [[Navigation]] + [[Inspector]]) · **Page-Embedding — `![[]]`** (the embed framework's second consumer) · **Gallery / Card view** (a non-Table renderer). Plus the standing **relation/context pickers**.

#### Parked by design

The contexts-resolution brainstorm (sidebar, contexts-as-hosts, Homepage's final shape — the **graph-view host with widgets stays the current direction**).

### Pending Focuses

- **User Sections CRUD (the "Add Heading" feature).** Collections can render user-created sections but there's no way to make one (`mutate.ts` has zero section ops). Its own brainstorm→plan→build. → `Sidebar.md` Pending.

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deliberately deferred (→ [[Views]] `### Grouping`; the `flat` GroupConfig kind stays reserved).

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table. Container-surgical reconcile is the designed escalation at real scale.

- **Number editor eyeball items (Nathan may tune, not bugs):** Decimals "Hidden", fraction wording, bar clamp edges, the strokeless bar look, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build. Distinct from Block Surfaces (free-placement drawing inside Pages); shares the file-per-entity + single-live-editor patterns.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device is last-writer-wins. `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 is a `window.nexus` bridge shim + a native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore` (or scaffold it).

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed char. Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md`.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it. A fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending + Fix Log to a fresh session; compress the prior session's block into Recent Work.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another session's block.
