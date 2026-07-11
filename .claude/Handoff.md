## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system.** The full cell-gesture matrix, per-view looks/formats in `column_styles`, band drag, and the reusable table-agnostic editing surfaces in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Multi-View Scaffolding + per-type property editors.** The view switcher stack (ViewDropdown · ViewPane · two-door ViewSettings), the G-1 invariant (views never empty where visible), and the Date/Checkbox/Number/Status/Link editor panes. Only the relation/context pickers remain. → [[Views]] + [[Properties]].

- **Icon Picker + Sidebar Ribbon.** The full-Lucide picker in the shared PickerMenu; the ribbon + mode-switched sidebar (surface-launcher model, lazy `agenda:list`, creation via right-click). → [[Studio/Pommora/II. Features/Icons]] + [[Sidebar]].

- **The Table Grouping Pane (shipped + merged).** Grouping shipped for tables end-to-end — the pane (both doors), the pipeline (structural + sub-group resolver, Location order writing the real filesystem), and the drag surfaces — with the structural-only settings locked view-level beside `group_order`. The tableDnd frozen-closure fix (per-render `cfg` ref) rode along. → [[Views]] `### Grouping` + [[TableView]] + `History.md`.

### Session Summary — Block Surfaces: Certified Spec → Live System

**Session ID:** abc3bafe-70bc-41e4-adfd-aa052cfee424
**Date:** 07-10-2026
**Model:** Fable 5
**Compactions:** 1
**Connectors:** none
**Commands:** /clear · /handoff · /compact
**Agents:** Explore (1x - census) · general-purpose (2x - research) · build-breaking-agent (7x - spec rounds + per-task reviews) · code-simplifier (1x - closeout)
**Skills:** studio-brainstorm · superpowers:writing-plans · superpowers:executing-plans · handoff

One session, the whole arc: the Contexts rethink became a certified spec, the spec became SurfacePM, and SurfacePM became a live block system Nathan drove all evening.

**The spec:** `Planning/7-10 - Block Surfaces — Decision Log.md` — review-certified through three adversarial rounds, then reopened live for Section H (embed mechanics, all confirmed) and extended through G-15/H-11 as Nathan drip-fed decisions. The capability-fusion diagnosis (block dashboards reserved to tag tiers) drove the host-agnostic BlockHost design; the contexts resolution stays parked. Durable spec now lives at [[SurfacePM]].

**SurfacePM shipped from scratch** (the RGL teardown informed patterns; zero code copied — `SurfacePM/README.md` records provenance): the split-tree model (row ratios / independent column stacks / per-tile px heights), window-style edge resize (south stretch · north stack + cross-band pair · e/w splitters · alignment snap), PommoraDND feel (lift-follow-settle on Glide), the notched grip handle with its menu (Type ▸ / Style ▸ / Remove-confirmed), right-click background create with wedge fill, and pane-toggle 1:1 tracking. Consolidated engine review folded (settle interlock, snap dead band, codec salvage).

**The plumbing arc ran Tasks 0–3** of `Planning/Block Surfaces — Plumbing Plan.md` (plan itself plan-attacked; H1/H2 findings pre-empted real corruption): the block document behind the BlockHost seam (locked read-merge-writes on homepage.json, main-side patch validation, watcher ignores host dirs), markdown block tiles (ULID `.md` lifecycle, pure-body writes, trash-recoverable), and the shared page-embed framework — where Nathan redirected the static-render plan into **the CM6 portal**: every prose tile IS a read-only MarkdownPM view, editability flipped by compartment (E-4 rewritten), one `--mdpm-scale` variable sizing the whole editor, popups portaled to body (a transformed tile re-anchors `position:fixed` — H-11), gutter glyphs self-centering, caret-priority scroll.

**Lessons Learned**

- **A transformed ancestor breaks `position:fixed`** — SurfacePM tiles ride `translate()`, so ANY fixed-position UI inside a tile subtree misplaces + clips. Popups must portal to body; this will bite every future in-tile surface that forgets.

- **Reordering keyed DOM nodes mid-drag silently releases pointer capture** — tiles render in stable id order, never tree order (the zombie-gesture class). Same family: React batching guarantees a remove-IPC beats an unmount flush, so removal flows must suppress the flush explicitly.

- **CDP can't drive native reality:** right-click doesn't synthesize `contextmenu` in Electron, native menus block headless, and the earlier chip-melt lesson held — verify those paths with synthetic DOM dispatch + Nathan's hands, never claim them from CDP silence.

- **Dead reviewer agents are recoverable:** two build-breaking agents died silently at delivery; their findings were extracted from the subagent JSONL transcripts (`jq` over assistant text) and folded anyway. Quiet transcript + stale mtime = dead; the work isn't lost.

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

### Next Session

**1. Interaction testing + foolproofing (Nathan's #1).** Continue live-hands testing of the block surface: the closeout reviews' findings + live-probe lists (native menus, feel judgments, the flows CDP can't drive). Fold, fix, re-verify — the system is feature-rich but young.

**2. The Navigation system (Nathan's #2).** The prior arc's next: Navigation Window + Dropdown + Inspector, → [[Navigation]] + [[Inspector]].

**3. Plumbing plan Tasks 4–6** — view embeds (Linked first: per-instance view resolution across the four slot readers, then Custom + the nexus-wide row source), the link-graph host passes (indexer + the id-less block-body rename pass — cascade.ts:38's guard means a dedicated pass, NOT an extension), chrome completion (Insert menu, locks, page-embed header via ⋮ toggles).

**4. The contexts-resolution brainstorm** — parked companion pass (sidebar, contexts-as-hosts, Homepage's final shape).

**5. Filter authoring pane redesign** · **relation pickers** · **non-Table renderers** — the standing queue.

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
