## Handoff — Pommora React

A long multi-day session (06-27 → 07-04) that built the Properties + Tables + ViewPane stack end-to-end, then the Link/URL property pane. Shipped green on `main` through **1140 tests**: PropertiesV2 (the nexus-wide property registry), the Tables cell-gesture + group-band system (Phases 1-3, including the grouped Status editor), and the 7-2 ViewPane Properties assign-flow. The Link/URL stint (07-04) is green at **1209** but UNCOMMITTED, bundled, awaiting Nathan's commit go — its one open bug is the rename-field "space" (Fix Log #1, parked for Monday).

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026 → 07-04-2026

> **Nathan (pinned):** The link/URL pane — what I assumed was the SIMPLEST interface — turned into 8+ hours of refactoring & bug fixes. We finish it Monday when my Fable usage resets (the rename "space" bug = Fix Log #1). The NEXT session is just finishing another property pane, not the caret.

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Model:** Opus 4.8 → Fable 5 → Opus 4.8
**Compactions:** ~18 (best-effort; multi-window session)
**Connectors:** Figma MCP (early — Switch component); Electron CDP for live screenshots + UI drive (not MCP)
**Agents:** general-purpose (adversarial reviews ×6+), code-simplifier (×7), build-breaking-agent (×6)
**Skills:** handoff; `superpowers:brainstorming` / `writing-plans` / `executing-plans`; `studio-brainstorm`

**The Tables cell + group system (Phases 1-3):** the full cell-gesture matrix — title navigates; status/select/multi/context open the PickerMenu-based `PropertyPicker`; a checkbox-look status cycles its group; numbers inline-edit, urls/files open through sanctioned IPC; right-click always menus (per-type Style + Clear). Per-view looks + formats persist in the SavedView's `column_styles`, never the definition. Group bands drag to reorder — structural → the view-level `group_order`, property → `group.order` + manual mode, a Set band nests via a real `moveSet`; value-less rows flatten header-less at the bottom (no "None" band). Band headers mirror the sidebar (glyph-click toggle, double-click open, right-click the native set menu + inline rename). The reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/` for Gallery/List reuse. → `Features/TableView.md`.

**The Status property:** an OPEN group model — each group is a stable `id` carrying a user-editable label, a color, and its own options; it ships three calendar-phase defaults (**Open / Active / Done**), and further groups drop into the enum with no data change (a future EventKit bridge maps a per-group done-semantic). Group ids are load-bearing — all status logic keys off the id; order is display-only. An option's `value` IS its label (value=title); a rename cascades the new value onto every assigning page's `$status`. The grouped Status editor edits it in place: a per-group `+` for an inline-named option, hover-recolor, drag within/across groups, and a right-click **Rename · Remove · Clear**. → `Features/Properties.md`.

**The 7-2 ViewPane Properties flow:** the Properties pane is the full assign surface — assigned rows over a bottom-pinned **All Properties** disclosure that rises open on the pane's beat; promote a definition by its `+` or by dragging it into the assigned group; drag within a group reorders (assigned = the Collection's order, All Properties = the nexus order); drag an assigned row out **Removes** it (strip-and-cache, restored by validating the cached encoding against the def's DECLARED type). The global **Delete** lives only inside a property's own editor pane, behind main's confirm. Creating mints into the registry (+ the nexus order) and assigns here. → `History.md` 07-02, `Features/Properties.md`, the 6-28 spec.

**PropertiesV2 — the nexus-wide registry:** definitions live nexus-wide in `.nexus/properties.json` (`{order, defs}` — the defs plus a nexus-wide cosmetic display order); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface receives a resolved schema (the `schema:*` IPC is unchanged). Registry mutations serialize; SQLite mirrors it as a pure, regeneratable accelerator. → `History.md` 07-01.

**The Link/URL property pane (07-04, UNCOMMITTED — green at 1209):** the URL/Link property pane, front to back. Value resolution scopes to the column's DECLARED type — `resolveFieldValue` (`pipeline/value.ts`) coerces the plain-string kinds (url/select/datetime) to the column type post-cache, so a `[alias](url)` link resolves as a url, not a select pill (schema is threaded through the pipeline + sort helpers; sort/filter key on `alias ?? url`, never the async title). `link-title` mode shows a fetched page `<title>` — main owns the `net` fetch + `<title>` parse + the `.nexus/linkTitles.json` cache (sync-excluded, StringDecoder-safe across chunk boundaries), with a bare-domain fallback; an alias always wins. The rename popover sets the alias, stored markdown-native as `[alias](url)`. Nathan's takeaway (pinned): the surface he expected to be simplest cost 8+ hours because the codec, the render pipeline, and the shared caret/picker/input machinery all converge on this one cell. One open bug — the rename-field "space" → **Fix Log #1** (Monday). → `Features/Properties.md`.

**Chips + the hover-×:** chips are shape primitives (`chipPill` · `chipLabel` 6px-radius owning select/multi · `chipContext` · `chipCapsule` · `chipBox`). Every PILL chip reveals a hover-× on its right third — an opacity-only melt (the text renders three times; the reveal flips opacities, a pre-masked `blur(2px)` fill-colored twin under a crisp copy), the shape forced by a Chromium dropped-repaint family (laws + a mandatory re-verify matrix → `Guidelines/Build-Gotchas.md §Chip Melt`); capsule/checkbox looks clear via their menu instead. **No-empties rule** in `applyPropertyValue`: null OR empty (`[]`/`''`) deletes the key — checkbox-false and number-0 stay, and tier `area: []` deliberately keeps writing (context-wiping fights the nexus index). → `Features/TableView.md`.

**Table overflow + the DRY OverflowScroll:** every column holds its resolved width; a table wider than the pane h-scrolls the whole view past it (capped-with-filler when it fits, the right inset flattened while overflowing — from ONE table-level ResizeObserver). `design-system/components/OverflowScroll.tsx` is THE truncate-hover-scroll box (the icon rides inside the scroll box, an rAF bounce-back, a two-edge eclipse fade so clipped content never hard-cuts), wrapped around every cell content type and shared with the sidebar rows. → `Features/TableView.md` §Overflow & Scroll.

**Perf posture:** the hot paths are cached/memoized — one WeakMap value-parse cache keyed on frontmatter identity, `React.memo` rows over identity-stable props, a var-driven column drag (no per-frame table re-render), store-level structural sharing (watcher echoes are no-ops), and all drag geometry snapshotted at activation (no per-pointermove rect storm). **Standing debt:** main still re-walks the whole nexus per fs event, no row virtualization (bites at thousands), and external VALUE edits don't live-refresh an open table — see Pending Focuses.

**Lessons Learned**

- **"Please confirm" means STOP and talk, then wait.** State the understanding, end the turn, implement on the go-ahead. → memory `feedback-confirm-means-stop-and-talk`.

- **Same nominal icon size ≠ same visual size across libraries.** Tabler and Lucide draw different glyph geometry in the same box; when surfaces must match, they share the SOURCE (the registry), not just the size literal. Nathan spots a mismatch instantly.

- **A restore path must validate against the DECLARED type, never re-infer by shape.** `parsePropertyValue`'s shape precedence is load-bearing for reads, but routing restore (or any value resolution) through it destroys select values shaped like dates/URLs — validate against the column's declared type at the write-back / post-cache.

- **Every read-modify-write surface needs its own serialization chain.** The registry had `mutateRegistry`, pages `serializeOnFile`; a new RMW surface with none corrupts under concurrency (a Remove racing an Assign, 24/25 runs). New RMW = new chain, day one.

- **A lock key must be canonicalized, or it silently splits.** `serializeOnFile` keys on the path STRING — a realpath'd path vs a raw session-root-joined one hit two buckets on any symlinked-root ancestry, and the same file never serialized. Canonicalize the root ONCE at `openSession`; canonical on the locks, RAW on what you persist/show. A test using raw paths on both sides hid it — a race regression test must derive its keys exactly as production does.

- **Nathan's knob requests are SCOPED.** "The padding in JUST the viewpane" means a viewpane-local class, not the shared primitive — over-scoping a knob is a miss even when the value's right. And when a knob doesn't move what he's pointing at, find the ACTUAL holder.

- **Don't chain the gate and the commit in one command; a pipe masks an exit code.** `vitest; git commit` commits on a red suite; `vitest | tail` exits with tail's 0. Capture to a file, read `$?`, then commit separately.

- **`scrollWidth` floors at `clientWidth`** — any "is content bigger than the box" that subtracts a hypothetical from `clientWidth` while comparing against `scrollWidth` is a one-way latch. Compare KNOWN content size (state) against the box.

- **React 19 does not delegate `scroll`.** `onScroll` on an ancestor never fires for a descendant's scroll; use a native capture-phase listener, or own the node.

- **Diagnose the real complaint in code before asking.** → memory `feedback-diagnose-before-asking`.

- **An overlay rendered inside its own trigger re-fires the trigger.** A cell picker living inside the cell whose click opens it needs a propagation boundary, or the option-click bubbles back and re-opens it. Apply to every in-cell editor.

- **A feature can be CDP-verified correct three times and still be wrong.** Screenshots prove mechanics, not feel — a visual-preference feature isn't done until Nathan uses it by hand.

- **A memoized context freezes every closure behind it.** A context memo froze a callback to first-render props (async-loaded data didn't exist yet), so it silently no-op'd. The house fix is the ref pattern (`onDropRef.current`). Any callback crossing a memoized context + long-lived listener needs it.

- **Test fixtures inherit your mental model's geometry.** Band tests measured headers as ADJACENT rows; the real render puts data rows between them, and the build-breaker caught the misplaced-reparent only by running the model over realistic gap geometry. Fixtures must model the render's real shape.

- **When a verifiably-correct fix keeps "not working," suspect it isn't being SERVED before writing more code.** CSS-in-TS + component-handler edits don't reliably hot-swap (Working Notes) — a correct fix reads as a failure, tempting band-aid on band-aid. Confirm a full kill+relaunch served the change before concluding it failed. Grounding "stale server" (checking the process + the documented gotcha) is right; reflexively blaming it is not.

**Key Files & Insights**

- `Detail/Views/PropertyEditing/` — the table-agnostic editing home: `PropertyPicker` (+ `StatusCapsule`), `PropertyEditor`, `statusCycle` (the status group cycle + glyph map), `formatValue` (en-US pinned, local-midnight date parse). Gallery/List mount these as-is later.
- `design-system/components/OverflowScroll.tsx` — THE overflow mechanism (hover-scroll + bounce-back; the eclipse fade is scroll-driven CSS, activated only on real overflow, so nothing measures or goes stale); the sidebar shares `slideScrollBack`.
- `Detail/Views/Table/TableView.tsx` — gesture routing (`onCellClick`/`openCellMenu`/`cellEditor`), the table-level `cellPicker` (self-managed portal, keyed per-cell), per-view style state. No row virtualization yet — the standing perf debt.
- `shared/columnStyles.ts` + `Table/columnStyles.ts` — type+zod+defaults live shared (main needs them for menus); the schema-aware `styleFor` resolver is renderer-side because `shared/` can't import the pipeline's `declaredType`.
- `main/mutate.ts` `serializeOnFile` — per-path write chain for the hot value ops; the pattern to reuse for any RMW on user files.
- `nativeCaret.ts` — a GLOBAL drawn caret over every input (hides the native one, positions a bar via a measuring mirror). Assumes LEFT-aligned text (its own comment). The prime suspect for the rename "space" — see Fix Log #1.

**Landmines**

- **The dev app runs against Nathan's REAL Nexus.** Value writes via the UI are his data; automated CDP must never pick/commit — open + Esc only.
- **Parallel sessions** — stage explicit paths, never `-A`.
- **The whole Link/URL stint is UNCOMMITTED + bundled** in the working tree — the title-fetch, the codec coercion refactor, `LinkCell`/`TextPicker`/`URLEditor`, the rename nonce, `Properties.md`, plus new files (`shared/links.test`, `Table/linkValue{,.test}`, `Table/linkColor`, `main/linkTitles{,.test}`, `main/io/linkTitles{,.test}`). Awaiting Nathan's commit go. The next (property-pane) session must NOT `git add -A` — that sweeps this AND concurrent parallel-session edits (MarkdownPM, History.md, Mobile docs are all dirty). Stage explicit paths; don't clobber the Link files.

**User Feedback**

- Talk-first (see Lessons). Screenshot-verify visual claims — mechanics prove nothing about feel.
- The value picker shows option VALUES regardless of name; groups are containers, never pickable chips.
- Capsule = the icon-only chip in the token set; picker options follow the column's glyph look.

### Session Summary - B (mobile future-proofing — separate session)

**Session B ID:** 164497e3-c3c6-4f45-978a-04a1375df1e6
**Dates:** 07-04-2026
**Model:** Opus 4.8
**Agents:** general-purpose (×16 — research + code exploration), build-breaking-agent (×2 — spec review rounds)
**Commands:** /clear, /handoff
**Skills:** studio-brainstorm; handoff

A separate session did **mobile future-proofing** — no changes to this build's product surfaces.

**iOS companion — ratified spec:** A full `studio-brainstorm` on a **Capacitor-based iOS companion** (reuse the renderer in a WebView, re-host the main process natively, iCloud app-owned-container sync, single-user most-recent-wins), pressure-tested across two adversarial-review rounds — a HIGH `.nexus/`-sync-exclusion landmine and the "renderer ships untouched" overstatement both caught and folded. Spec landed under `.claude/Mobile/`: `MobileSpec` + `MobileArchitecture` · `NexusSync` · `MobilePM` · `FormFactor` · `MobileResources` · `MobileDecisionLog`, mirrored to `II. Mobile`. Verdict: a scoped **port, not a rewrite** — Claude builds the code, Nathan owns the Apple/Xcode ceremony + the phone form-factor design.

**Four desktop pre-paves shipped (`02bb4e11`, main):** cheap, behavior-preserving changes that shrink the eventual port — a standalone app Vite target (`vite.config.app.ts` → `npm run dev:app` renders the real app in any browser), one shared `assetUrl.ts` (was 3 copies), a `DEVICE_LOCAL_NEXUS_FILES` set in `paths.ts` (future iCloud sync-exclusion), and iOS soft-keyboard input attributes on the MarkdownPM editor. Explicit-path staged.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R** and **`src/main`/preload need a dev-server restart**. Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev` (no CDP port). For a Claude-inspectable session: `… POMMORA_DEBUG_PORT=9222 npm run dev` (HMR + CDP), or a built app on 9222 after `npm run build`. Kill: `pkill -f "Project Pommora/React/node_modules/electron"`.
- **HMR is NOT trustworthy for two change classes:** (1) **vanilla-extract `*.css.ts`** — a style edit silently keeps serving the stale compiled CSS (the split-brain gotcha); a plain restart usually heals it, ⌘R never does. (2) **A component's focus effect / event handler / attribute change** — Fast-Refresh often doesn't re-apply it to an already-loaded module. Both cost real rounds of "it still happens" when the fix was correct but never served. Do a FULL kill + relaunch before concluding a CSS-in-TS or handler change failed. → Build-Gotchas §Toolchain.
- CDP tooling in the scratchpad: `cdp-shot.mjs` (screenshot/eval/clip) + `cdp-emulate.mjs` (viewport emulation). **Reading** a screenshot surfaces it to Nathan.
- **Mutating gestures against the running app (real Nexus) need Nathan's explicit authorization** — with the standing condition that state is restored exactly (drop → verify on disk → reverse). Without it: drag-and-abort / open-and-Esc only.

### Next Session — the ViewPane arc

**Property panes are the through-line.** The Select, Multi-Select, and Status option editors + the URL/Link pane have SHIPPED; the remaining ViewPane panes are stubs ("{Pane} — pending" captions in `ViewPane.tsx`). Build order:

1. **Finish the rest-of-properties per-type panes** — the remaining stubs are **Number, Date, and the other value-type editor panes**, riding the same nested-slide + pane-beat plumbing the option editors used. This is THE next-session target (Nathan-pinned: not the caret bug). The rich tail (formats, change-type confirm with the lossy strip, duplicate) rides the same arc — 6-28 spec §Pending.
2. **THEN the naming / duplicate-title work = §H of the 7-3 decision log** — keep value=title, add a reserved-char auto-disambiguate matcher (add-on-collision / drop-when-unique) across Select / Multi / Status together. This cycle absorbs a legacy-data migration (stale group labels + `value≠label` lowercase values on pre-value=title properties — Nathan's own Status property is the live example). The duplicate-title conflict is the headline.
3. **The in-pane chip-style picker for Status** (Standard / Compact / Checkbox → pill / capsule / check), persisted per-view in `column_styles` — but the pane KEEPS pills regardless.
4. **The sibling panes** (Layout · Group · Sort · Filter) + **View management** (rename/duplicate/delete, the active-view switcher — Part-1 IPC shipped, UI-less), per 6-28 spec §Pending, wiring the already-shipped `GroupConfig` / `SortCriterion[]` / `FilterGroup` / `views:*` seams.

Build discipline: the ViewPane CSS is a KNOB FILE (`viewPane.css.ts` — COLOR/SIZE/PAD/ICON groups; sizes are Nathan's, never re-tune); TopRows name their DESTINATION; every pane push rides the nested PaneSlider. Open threads to confirm while building: file chips deliberately have no hover-× (removal = deleting an attachment); the old capsule floating-× idea is likely dead post-menu-Clear but never formally killed.

### Pending Focuses

- **(Perf) Remaining debt:** (1) main re-walks the whole nexus per watcher event (fs + YAML for every page; the durable fix is the surgical-reconcile arc — Swift precedent: 11 TDD commits, coarse-rebuild fallback for structural events). (2) **Virtualization** — every row still MOUNTS; bites at thousands. (3) External VALUE edits don't live-refresh open tables (loadValues runs per container open only; the tree carries structure, not values).
- **Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts, the box-nesting guard table, cross-container re-prefix.
- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build.
- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.
- **Automatic Scrolling** — must-have for views + MarkdownPM.
- **iCloud-sync readiness (future cloud feature):** an in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device edits are last-writer-wins (atomic temp+rename prevents corruption; true conflict handling is the sync feature's job). Also: `.nexus/index.db` needs excluding from sync, and the page walk must skip evicted `.icloud` placeholders. Recorded so the sync feature inherits them.
- **Mobile iOS companion (parked — session B):** ratified spec at `.claude/Mobile/MobileSpec.md` (+ 6 siblings); 4 desktop pre-paves shipped (`02bb4e11`). **Step 1 is the gate: a `window.nexus` bridge shim + a native iCloud Swift plugin** (nothing functions until the phone can read the Nexus). No commitment to build.

### Fix Log

- **#1 (Monday, Fable) — the rename-popover "space" (open, top priority).** A space-like glyph appears at the field's start when you open a link Rename (even on an already-aliased link), delete-able once but back on the next open. PROVEN not a stored/typed/programmatic character (real Nexus values are clean + trimmed; `beforeinput` never fires it; the whole renderer was grepped for `.value=`). Prime suspect: `nativeCaret.ts` — the global drawn-caret whose comment (`:97-99`) admits it "assumes left-aligned text — a text-align:center field would mis-place it"; the field was centered, so it's likely the drawn BAR offset, not a character. **Next step:** re-add a `[CARET-DIAG]` log (input `.value`@200ms + the `onInput` inputType) to settle character-vs-drawn-bar in one capture, then fix `nativeCaret`'s mirror measurement or the field. The separate caret-FLOAT symptom is already fixed (per-rename nonce key). All space-fix scaffolding was removed on Nathan's order — start clean.
- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either half corrupts the document (`MarkdownPM/editor/blockModel.ts` — test-pinned, unguarded).
- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known Issues.
- The "File" property icon gets clipped by its vertical row padding on the ViewPane.
- **`.nexus/activeViews.json` isn't gitignored (open).** Neither it nor its per-machine siblings (`folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles`) are ignored in the Nexus repo — using the pane on a fresh container creates a would-sync file. Add these to the Nexus `.gitignore` (or have the app scaffold it) before the view-management switcher ships.
- You still cannot actually create a Context via sidebar crud.
- **Outliner rails on ordered / arrow / `+` lists deferred.** Scoped to dash-bullets + checkboxes (clean glyph-centre math); ordered numbers + arrow/`+` need per-glyph centring + vertical-evenness tuning (~30 min) parked rather than shipped misaligned. → `Features/MarkdownPM.md`.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if it was always so — "the picker shows values, not groups" was always the intent, so state it plainly and silently fix anything that contradicted it; don't narrate the reversal or version the mistake. A fresh agent should never be able to tell a mistake was made.
- **Resolve = delete + route, never tag.** When an entry here is genuinely done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.
- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending Focuses forward to a fresh sequential session.
- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.
- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; the Cornerstone + footer are shared; never edit another session's block.
