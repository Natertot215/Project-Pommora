## MarkdownPM — Build-Breaking Findings

Consolidated from four adversarial runs (two skill-less baselines, two skill-bearing rounds) against a build that was typecheck-clean with all tests green. `[verified]` = reproduced by executing the real modules; `[traced]` = full code-path trace. Severity: High = data loss/corruption/silent failure · Medium = visible everyday breakage · Low = edge polish. This document is the cleanup phase's input.

### Tier 1 — Verified Data Loss & Corruption

- **Stale table-widget model overwrites disk** `[verified]` — self-edits only remap decorations, so the widget's captured `text`/`model` go stale after any cell edit; the heading-column toggle rebuilds from that stale snapshot and the focused cell force-syncs to it — the next keystroke commits stale text over the real doc. (`Tables/widget.tsx:302`, `CellEditor.tsx:150-157`)
- **Shared debounced-save timer loses edits across pages** `[traced]` — one `saveTimer` for all pages; edit A, switch, type in B within 400ms → A's pending write is cleared and never fired. Also no flush on unmount or `before-quit`. (`Detail/PageView.tsx:30-37`)
- **Escaped trailing pipe drops a cell** `[verified]` — `splitRow`'s `hasTrail` reads `\|` as structural, so a foreign row's last cell vanishes from the model; any structural edit serializes the loss to disk. (`Tables/codec.ts:40`)
- **Literal `<br>` typed in a cell becomes a real line break** `[verified]` — codec escapes `\` and `|` but not `<`; the encode/decode pair isn't injective, so typed text changes meaning on the next widget rebuild. (`Tables/codec.ts:23-25`)
- **Fence-blind heading detection corrupts docs via drag and fold** `[verified]` — `headingSections` never consults fences, so a `# comment` inside a code block is a "heading": dragging the real heading above it relocates a partial fence (doc corrupted, everything below swallowed as code); folding it hides the closing fence and the next real section; the bogus key persists to `folds.json`. (`editor/folding.ts:37`, `editor/blockModel.ts:127`)
- **List drag abandons an item's continuation lines** `[verified]` — `subBlockAt` requires every line to parse as a marker, disagreeing with `blockModel`'s continuation rule; dragging a wrapped item moves only its marker line. (`editor/listDragModel.ts:51`)
- **Em-dash/arrow transforms corrupt content in unguarded contexts** `[verified]` — the transform gate is fence-only: `--` converts inside inline code (`npm install —save`), inside URLs (`https://ex—a`), and inside `[[titles]]` (silently retargeting connections — titles are exact-match identifiers). (`parser/index.ts:11`, `input/index.ts:294,309`)

### Tier 2 — Guard Over-Blocking & Unguarded Twins (silent no-ops, dead features)

- **Format menu × callouts** `[verified]` — Heading/List on a callout head leaks the literal `[!callout]` tag into a heading and demotes the box; on a body line the change starts inside the hidden `> ` prefix so `calloutGuard` cancels it — every menu item is a silent no-op. Transforms are prefix-aware; the menu layer never learned it. (`input/format.ts:106-163`)
- **calloutGuard rejects instead of repairing** `[verified]` — the same guard kills triple-click-select + Delete, Cmd+Backspace on body lines, dragging the last item out of a callout, and legitimate whole-line deletions starting at line start. Fix shape: clamp/repair the transaction, don't cancel it. (`editor/calloutGuard.ts:18-32`)
- **Forward-delete is the unguarded twin of backspace** `[verified]` — Fn+Delete at a line-end above a table dissolves the whole table to raw pipes; at a callout line-end it splices the next line in with its `>` intact. Every seam guard is backward-only. Same class: **paste-fusing** — the table merge guard covers deletions but not insertions, so pasting a table against another fuses them. (`Tables/guard.ts`, `input/index.ts`)
- **Prose typed below a table is absorbed as a row** `[verified]` — GFM lazy continuation: any non-blank line touching the table's bottom joins the region live, character by character. Needs blank-fencing on exit, mirroring Insert Table. (`Tables/regions`)

### Tier 3 — Everyday Breakage

- **Inline code suppresses nothing** `[verified]` — `isInsideCode` is fence-only: connections/links inside `` `code` `` render colored and clickable, autopair and dash transforms fire inside spans, autocomplete opens inside code. Clicks inside *fenced* code also still navigate (`editor/links.ts`, `editor/connections.ts`).
- **Ordered renumbering breaks at nested children** `[verified]` — both `continueListOnEnter` and `renumberOrderedRun` terminate at the first deeper-indented line → duplicate numbers in any nested ordered list.
- **Enter-before-apostrophe teleports the caret** `[verified]` — `closerEndAt` counts every `'` as a delimiter; a contraction earlier in the line makes Enter jump past a later apostrophe instead of splitting.
- **Autopair doubled-marker branch stacks markers** `[verified]` — typing the closing `**` of `**word**` yields `**word****`; `snake_` + `_` → `snake____`; and the spec's own `2 * 3` example pairs (spec and unit test assert opposite behaviors).
- **No exit-on-empty for lists/quotes** `[verified]` — Enter on an empty `- ` or `> ` continues forever; a callout ending the doc is a full keyboard trap (every escape route is one of the silent no-ops above).
- **Viewport fence parity strips styling** `[verified]` — when the viewport top sits inside a tall code block, the closing fence reads as an opener and everything below renders raw until the next scroll. (`editor/decorations.ts:103-129`)
- **A second markdown engine is live** `[traced]` — `markdown()` defaults install Lezer's Enter/Backspace keymap and `pasteURLAsLink`: `1)` lists auto-continue on decline paths, and pasting a URL over a selection rewrites it to `[selection](url)` against the spec's paste-literal rule. (`index.tsx:109`)
- **No IME/composition guard on either inputHandler** `[traced]` — transforms dispatch mid-composition (CM's own closeBrackets bails on `compositionStarted`; MarkdownPM doesn't); CJK/dead-key input can be garbled.
- **Single-tilde strikethrough eats characters** `[verified]` — `pushEmphasis` hardcodes marker width 2, but micromark parses `~one~`: first and last letters vanish at rest. Also `~~~` fences are invisible to the entire fence layer.
- **`1. [ ]` task box is permanently invisible** `[verified]` — the hide decoration on ordered lines has no caret gate, so the on-disk ` [ ] ` can never be seen or edited.

### Tier 4 — Relocating-State Cluster

- **Heading-column state keyed by table index** `[traced]` — migrates to the wrong table on insert/delete/drag above it; the wrong binding persists to `.nexus/`. (Noted in code as accepted v1 limitation — confirm disposition.)
- **Fold persistence keyed by heading text + ordinal** `[verified]` — a duplicate heading inserted above a folded one re-points the saved fold at the wrong section on reload.
- **Deleting a folded heading strands its body** `[traced]` — the body stays hidden with no chevron anywhere; looks like data loss (disk is intact) until reload.
- **Active cell identity is positional** `[traced]` — structural edits from the grip menu re-point the focused editor at a different cell mid-edit.
- **Fold clone map: module-global, offset-keyed** `[traced]` — leaks DOM clones across page opens, remap-desyncs (expand animates an empty box), collides across instances.
- **Autocomplete panel survives blur** (page editor only; the cell editor already has the fix) `[traced]`; **list drag** lacks blockDrag's scroll re-measure and Escape/blur abort `[traced]`.

### Tier 5 — Performance (Nathan-confirmed cleanup priority)

- **Per-keystroke O(doc) work, flagged by all four runs** — several full `doc.toString()` calls plus per-line micromark parses per keystroke *and caret move*: `decorationsFor`'s whole-doc line walk, duplicate `calloutLines` passes (guard + atomic + decorations), `blockStarts`, `headingSections`, double `tableRegions` in the merge guard. Converged fix: one shared per-`Text` WeakMap memo (the `folding.ts` `sectionCache` pattern). Also noted: the unused Lezer `markdown()` parse is paying cost per keystroke for nothing (see the second-engine finding — removing/configuring it serves both).

### Spec & Doc Reconciliation

- Ambiguous-connection rendering: `Features/Connections.md` vs `MarkdownPM.md` vs code — three different stories; reconcile by replacement.
- Menu offers H1–H5; spec says H1–H4. The ` - ` → en-dash transform is undocumented. `2 * 3` pairing contradicts the spec's literal-stay claim (and its own test).
- `Styles.css:128` hardcodes `--banner-shadow: #0000008c` instead of a design-system token (hard-rule violation). `•` accepted as a list marker — non-portable, unsanctioned.
- CRLF files silently normalize to LF on first save — "never auto-tidies source" holds only for LF files.

### Root-Cause Map (first-hand code read; the cleanup's real shape)

The findings above collapse into these shared roots — fixing a root closes every finding downstream of it:

1. **`parser/isInsideCode` is the broken primitive with the widest blast radius** — fence-only (no `~~~`, no inline spans, prefix-blind), and it gates `autoPair`, `autoDelete`, `dashArrow`, `closerEndAt`, wikilink/link tokenization, and autocomplete. Corroborating evidence it's an oversight: latex tokens *do* get filtered through `notOverlapping(code)` (`tokens/index.ts:143-152`); wikis/links don't.
2. **The format layer never got the prefix-awareness the typing layer has** — `blockPrefix` already exists in `input/index.ts:24`; `stripBlockMarkers` (`input/format.ts:166`) just doesn't use it. One reuse fixes menu × callout head, menu × callout body, menu × quote, and the doubled markers.
3. **`calloutGuard` should repair, not cancel** — `stripsCalloutPrefix`'s `from >= off` catches line-start deletions (triple-click, Cmd+Backspace, whole-line drag cuts); clamping the deletion to `prefixEnd` (or treating from-at-line-start as whole-line intent) fixes four findings at once.
4. **Stale snapshots and positional identity** — the heading-col toggle reuses `w.text`/`w.model` (`Tables/widget.tsx:302`; the only reuse site — normal rebuilds self-heal via `eq()`); `cloneMap` keys by fold-time offset while the fold entries remap; heading-col + fold persistence key positionally. Each needs its remap/re-derive.
5. **Seam guards are single-direction** — backward-only delete guards (forward-delete dissolves tables, pulls `>` into content), deletion-only merge guard (paste-fusion; the insertion gap is a *documented* decision whose comment only considered typed dashes, not pasted tables), no blank-fence after a table on Enter.
6. **`headingSections` is fence-blind** (`editor/folding.ts:44`) — one filter through the already-computed `fencedCodeRanges` fixes heading-drag corruption, bogus fold chevrons, and poisoned persist keys together.
7. **Two walkers break instead of skipping descendants** — `subBlockAt` (`listDragModel.ts:51`, drops continuation lines from drags) and both ordered-renumber walkers. Same one-rule fix.
8. **`PageView` save timer: flush, don't clear** — one shared ref across pages (PageView never remounts; only `MarkdownEditor` keys on path), plus no unmount/quit flush. Renderer-side loss is certain from the code.
9. **`markdown()` called with defaults** (`index.tsx:109`) — the second engine's keymap and paste-URL rewrite ride in; configure or strip it (also recovers its per-keystroke parse cost).
10. **Small pure-function gates** — `closerEndAt` needs the word-char gate `autoPair` already has; `autoPair`'s multi branch runs before that gate and can't tell fresh-pair from typed-over closer.
11. **Viewport slice-tokenize fence parity** (`decorations.ts:99-119`) — the code's own comment handles the fence-opened-above case but missed its inverse: a closing fence inside the slice reads as an opener, and the whole-doc filter can only drop tokens, never restore them. Seed the slice's fence state from `fencedCodeRanges` (already computed at line 113).

Catalog corrections from the first-hand read: baseline 1's "cells revert on click-away" is overstated — the stale-snapshot corruption requires the heading-column-toggle path specifically; the `<br>` cell finding is a genuine design call (GFM-faithful vs typeable-literal), not a plain bug; the paste-fusion guard gap was deliberate-but-incomplete rather than missed.

### Accepted / Deliberate (do not re-flag)

Orphan blank line after last-table delete · table-in-callout raw text · aliased `[[Title|alias]]` cell exclusion · no lagging resize bar · no horizontal scroll · heading-column as `.nexus/`-only visual · loose-list splitting in block drag · alias-free autocomplete inserts.
