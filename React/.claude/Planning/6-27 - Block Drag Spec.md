# Block Drag — Notion-Style Block Handles

**Status:** V2 — round-1 adversarial review folded in (compile-grounding + logic/coverage + over-engineering). Pending a round-2 verification before ratified.

Give every top-level block a hover grab-handle in the left gutter that drags the **whole block** to reorder it. Built on the editor's drag primitives — but honestly: the *visual* (in-place shade + insertion line) and the *commit shape* are true reuse; the candidate geometry, the block resolver, the per-block handles, and the table path are net-new. The reuse is the skeleton, not the muscle.

## Scope — two deliverables

The review (over-engineering) made the cut clear: **ship top-level reorder first; nesting is a second deliverable.** With top-level-only, no interior drop slot is ever offered, so the entire nesting-guard apparatus is unnecessary in V1.

- **V1 (this spec):** top-level reorder for **heading, list, paragraph, code, callout, blockquote, table**. No nesting, no guards. The table is a distinct path (a new React-side gesture — §3) because its widget swallows pointer events, but Nathan wants it in V1.
- **V2 (deferred — separate spec when V1 is lived-in):** nesting into containers (callout-interior handles, the guard table, cross-container re-prefix, the `depth` field).

## What gets a handle (V1)

| Block | Scope it grabs | Handle |
|---|---|---|
| Heading | the heading + its whole section (to the next equal/higher heading) | the **chevron** — fold *and* drag, one unified gesture |
| List (top level) | the entire list, grabbed at **item 1** only | a rail grip at item 1 |
| Callout / blockquote | the box's full line span (derived — see below) | a rail grip against the box's own border |
| Code block | the fence + its content | a rail grip |
| Paragraph | the run of non-blank lines it owns | a rail grip |
| Table | the whole table | a **new** drag affordance on the widget (its grips are inert for dragging) |

Sub-list items keep their existing glyph drag and do **not** get the whole-list handle. Nested-in-box content is V2.

## The load-bearing constraint

Handles are **content-anchored, never a CodeMirror gutter.** CM positions a gutter from its line-height *model*, which estimates off-screen variable-height blocks at the default height — so a gutter handle below a callout/fold drifts from its line (the bug just fixed for the fold chevron, `folding.ts:239`, `Styles.css:196`). Every handle is a `::before` glued to its block's first line in the `--fold-gutter` strip. Two honest caveats the review surfaced:

- **Multi-line hover-reveal needs JS.** CSS `:hover` on a first-line `::before` only fires when the *first line* is hovered. "Hover anywhere in a block → reveal its handle" requires a JS hover→`blockAt`→toggle-a-class-on-the-first-line bridge. Net-new, small.
- **It's two gutters, not one.** Top-level handles sit in the outer `--fold-gutter` strip; callout/quote handles sit against the box's inner border. Same *mechanism* (`::before` on the first line), two *positions*.

## Architecture

### 1. The keystone — `blockAt(doc, pos) → { from, to, kind } | null`

One pure, unit-testable source of truth for "what block owns this line, where it starts/ends, what kind it is." Returns **`{ from, to, kind }`** — no `depth` (the review confirmed the mover reads only `from`/`to`; `depth` has no V1 consumer and arrives with nesting). `kind` is needed even in V1: it drives the renumber trigger *and* keeps the paragraph catch-all from swallowing other blocks.

`to` is **exclusive of the trailing newline** — the same convention `SubBlock.to`, `headingSections.to`, and table `region.to` already use (`listDragModel.ts`, `folding.ts`, table regions). Pinned, because `slotFrom`'s self-drop guard relies on it.

Built by dispatching to the existing detectors — **but the taxonomy must be closed so the paragraph rule (the catch-all) never absorbs a real block:**

- **Heading** → `headingSections` (`folding.ts`), shape `{from, lineEnd, level, key, to}`. Note: a body-less heading is *dropped* from `headingSections`, so `blockAt` derives a heading-only block's range itself (one line).
- **List** → `subBlockAt` for an item; extend to all top-level sibling items for the whole-list grab.
- **Code** → `fencedCodeRanges` (`decorations/intent.ts`) — true range-reuse.
- **Callout / blockquote** → **new range derivation**: `calloutLines`/`blockquotePrefixRe` give per-*line* membership, not a `{from,to}` — walk the membership (the `last:true` marker ends a callout) to get the box span. New code, small.
- **Thematic break `---`** → `isThematicBreakLine` (`detect/index.ts:168`) — one-line block.
- **Block math `$$…$$`** → `blockLatexRegex` (`detect/index.ts:7`) — delimited range, mirror the fence walk.
- **Table** → the table source region (`Tables/regions.ts`) — recognized so the paragraph rule never absorbs its `| … |` lines, and so it's draggable.
- **Paragraph** → the run of non-blank lines **not claimed by ANY detector above**. The catch-all is bounded by every other kind.
- **Unrecognized line** → `null` (no handle). Safe fallthrough; never absorbed into a paragraph.

### 2. The drag — adapt the gesture, replace the geometry

`listDrag.ts` already owns the gesture lifecycle (pointerdown → ACTIVATION threshold → in-place shade → fixed insertion line → drop). **Truly reusable, verbatim:** the `Overlay` class + `shadeField` (type-blind visual) and `diffAsSingleReplace` (the minimal-replace commit). **What must change:**

- **Candidates → a NEW `collectBlockBoundaries`.** `collectCands` is a list-*geometry* function: it derives each candidate's `left` and adopted `indent` from `lm.markerStart` (`listDrag.ts:131,137`). It cannot be widened — a paragraph/heading has no marker. Write a sibling that returns boundaries with explicit `(left, indent)` per kind (list → marker-derived, as today; others → line-start + leading whitespace). **Keep the existing list path byte-for-byte and re-prove the list-drag tests before adding kinds** (this is the named regression risk — confirmed real).
- **Move → feed `{from,to}` not a `SubBlock`.** `moveBlockChanges`/`dropChanges` slice on `from`/`to` (reusable), but are typed for `SubBlock` and their EOF/cut heuristic (`listDragModel.ts:85-95`) was only tested on single list items. Accept a plain range and **add unit tests for multi-line non-list blocks at top-of-doc and EOF** (a code fence with an internal blank line is the adversarial case). For V1 the move is *verbatim* (no re-indent — blocks keep their column; `reindentBlock(text, undefined)` is a no-op), so the `> `-re-prefix path stays dormant until V2 nesting.
- **Top-of-doc + EOF slots both explicit.** `moveBlockChanges` has an EOF branch; there is **no** guaranteed `at:0` slot. Mirror the EOF special-case so "drop before the first block" is always reachable.
- **No-op rule.** A top-level block shows a handle iff ≥1 *other* top-level block exists. This needs the **whole-doc top-level block list**, not a per-line check — compute it from `blockAt` once, cache it, invalidate on docChange (O(1) per hover).

### 3. Handles & the rail

A `::before` on each block's first line, in the `--fold-gutter` strip, reusing the chevron's positioning. New rail grips for **paragraph / code / list-item-1**; callout/blockquote grips sit against their border. Hover-reveal via the JS first-line-class bridge (above).

- **Heading = the chevron, fold AND drag, as ONE gesture.** The chevron is a `::before` hit-tested by `clientX < line.left` on a `.md-foldable` line (`folding.ts:256`). Today fold fires on raw `mousedown`; that handler and a drag `pointerdown` would race (the existing list-drag already had to suppress the compat `mousedown`). **Merge them into one pointerdown owner in the chevron zone: press → if it crosses ACTIVATION, drag the section; if released in place, toggle the fold.** This changes folding from mousedown-immediate to pointerup-without-threshold (a slight feel change — acceptable, matches the glyph). The chevron stays a `::before` (no drift); the x-zone test already isolates it from heading-text clicks.
- **Folded-heading drag tears the fold down first.** A live fold is a block-replace whose positions map through changes; `dropChanges`'s coarse single-replace collapses them and orphans the clone (`cloneMap` keyed by offset). On commit of a folded-section drag: **drop the fold (`dropEffect`/clear) → move → re-fold by `key`** (disk persistence already keys by text, so this only re-establishes in-session state). Never map a fold through the move.

### 4. Build sequence — every phase ships green, THEN gets its own adversarial review

Nathan's rule: **each task gets an adversarial review** (compile-grounding + logic; plus a post-functional UIX review once there's working UI) before the next starts. Only green, reviewed commits are facts.

1. **`blockAt` + tests** — the resolver, taxonomy closed (incl. HR/math/box-range), exclusive-`to` pinned. Pure, no UI. → review.
2. **`collectBlockBoundaries` + move adapter** — new boundary collector (list path unchanged + re-proven), `{from,to}` move with multi-line top/EOF tests. → review (regression focus).
3. **Rail handles + no-op rule** — `::before` grips for paragraph/code/list-item-1/callout/quote; the cached block-list; hover-reveal JS bridge. Top-level reorder working for non-heading blocks. → review (+ UIX).
4. **Heading chevron dual-role** — unified fold/drag gesture + fold-teardown-on-move. → review (+ UIX).
5. **Table drag** — a new draggable affordance on the table widget + a React-side gesture calling an exported `startBlockDrag(view, range)` (the editor's pointer handlers never fire inside the event-swallowing widget); the widget re-derives its range from `tableIndex` on drag-start. → review (+ UIX).
6. **V1 polish & close** — feedback edge cases, the full verification list. → review (+ UIX).

(V2 deliverable, separate spec: nesting — interior candidates, guard table, cross-container re-prefix, `depth`.)

## Defaults assumed (veto on the round-2 review)

- Reveal = hover-anywhere-in-block (via the JS bridge).
- Paragraph = consecutive non-blank lines, bounded by a blank line *or any other detected block*.
- Heading drag overloads the chevron (per Nathan) rather than adding a separate grip — contingent on the unified-gesture approach above being clean.

## Verification

- `npm run typecheck` + `npx vitest run` green; **existing list-drag tests pass unchanged** after the boundary refactor (the regression gate); new tests for `blockAt` (every kind incl. HR/math/body-less heading), multi-line move at top-of-doc + EOF.
- Each block type: hover shows a handle at the first line; drag reorders the whole block; shade + insertion line track; no-sibling block shows no handle.
- Drag a **folded** heading → it stays folded (or re-folds), body not lost, reveal animates on expand.
- Chevron still folds on click, drags on press; list glyph drag unchanged; caret still places when clicking heading text.
- `---`, `$$…$$`, and an image-on-its-own-line are scoped as their own blocks, never absorbed into an adjacent paragraph.
- No gutter drift: handles stay glued to their lines below callouts/folds at any scroll position.
- Live-verified on the **9223 / Test Nexus** server, never the working Nexus.
