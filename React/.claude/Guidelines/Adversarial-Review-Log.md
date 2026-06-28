## Adversarial Review Log

A running catalog of every way a MarkdownPM editor feature broke under Nathan's hands **after** Claude called it shipped, robust, or "bulletproof." Two features so far — **Callouts** and **Tables** — each fuzzed until it stopped breaking. Kept for two reasons: to make the lesson un-ignorable, and to seed a reusable skill whose only job is finding ways to break things.

This is the running-UI companion to `// The Studio //.claude/rules/Review-Discipline.md` — that rule governs *docs* ("never call a spec bulletproof before an adversarial review proves it"); this Log is the same failure mode at the *functional* layer.

### The pattern that has to die

The loop repeated almost verbatim, across both features:

1. Claude implements a slice, runs the happy path, sees it work, and reports it as solid / robust / done.
2. Nathan opens the editor and does one slightly-weird thing.
3. It breaks — instantly, and usually in a way that was invisible from the code or the spec.
4. Repeat.

Confidence was **asserted up front** instead of **earned by failed attempts to break it.** Almost every break below was reachable by a human doing an ordinary-but-not-happy-path thing in seconds. None were exotic. Both features passed typecheck and their unit tests the entire time they were breaking.

---

### Callouts — the catalog

Grouped by class, because the classes are the point (they generalize).

**A — Input shorthand & text transforms**

- `||ab` ate the trailing text: the `||` → `> [!callout]` shorthand consumed the whole line instead of just the `||`.
- `||` typed next to an existing quote/callout merged the blocks and leaked a raw `[callout]` tag into the render — detection wasn't per-head.
- `- ` typed inside a callout became an en-dash `–`: the dash→en-dash auto-format measured prose from the raw line start and never accounted for the hidden `> ` prefix.

**B — Deletion & caret (the richest vein)**

- Plain Backspace at a callout line *exited the box* instead of joining within it.
- Forward-delete or typing at the head corrupted the `[!callout]` tag itself.
- Deleting a body line silently demoted the whole callout to a plain blockquote.
- Shift+Delete — and, once checked, *every* non-plain delete combo (Cmd/Alt/forward) — eroded a body line's `> ` into `>body`, or dropped the line clean out of the box. The `atomicRanges` fix made it *cleanly* de-callout, which was still a break; only a `transactionFilter` guard actually closed it.
- The caret couldn't enter a heading at all (not callout-specific — surfaced incidentally).
- Parking the caret just above a table rendered it massive and offset, because the table's gutter padding was a real, enterable caret target.

**C — Nested constructs**

- List items lost their list behavior entirely inside a callout.
- Bullets didn't render inside a callout — the bullet widget *absorbed* the prefix-hide replace (CM6 drops a widget-replace that merely touches a preceding replace).
- Bullets in plain blockquotes weren't indented.
- Nested blockquotes inside a callout rendered flat instead of nested.
- Code blocks broke out of the callout's gutter, lost their background, and their text wasn't inset.
- A three-deep nested quote mislabeled its middle line as both first *and* last, producing a notch artifact.

**D — Layout & chrome**

- Shift+Enter with a selection straddling the box edge pulled outside text *into* the box.
- Two adjacent callouts had no vertical gap between them.
- A callout on the document's first line didn't drop its top padding the way headings do.
- Folded headings had no room to live inside the box (inner padding too tight).

**E — Fix-induced regression**

- A "prefix-aware" fence regex written to *fix* code-in-callout broke unrelated top-level code blocks that quote a ``` fence. A fix in one spot silently broke a neighbor. Resolved by pairing fences by quote-depth.

---

### Tables — the catalog

Same exercise, earlier feature. Note how many classes recur.

**A — Cell editing & corruption**

- Newlines split a row: Shift+Enter / Mod+Enter / a multi-line paste could push a newline into a cell, splitting the GFM row in two. Fixed — those inserts are consumed/flattened and the commit flattens `\n`→space, so no input can split a row.
- Phantom column from an escaped pipe: a literal `\|` in a cell wasn't round-tripped, so it spawned a phantom column on render. Fixed — the codec escapes/unescapes backslash *and* pipe; `\|` stays one cell.
- Boundary delete ate the structural pipes: a backspace/delete at the table's edge chewed into its `|` skeleton and broke it to raw text. Fixed — `atomicRanges` over the block make a boundary delete remove the whole table as one undoable unit instead.
- Empty cells rendered a line shorter than filled ones (asymmetric line-height). Fixed — a `:empty::before` zero-width placeholder line box.

**B — Caret & selection in cells**

- Caret-in-cell scroll trap: the nested cell's own `.cm-scroller` captured the mousewheel, so scrolling stalled inside the cell instead of moving the page. Fixed — the cell scroller opts out of being a scroll container, so the wheel chains to the page editor.
- Two-click-to-edit: the browser's native focus-shift raced the cell-activation, so the first click only focused and a second was needed to place the caret. Fixed — the activating mousedown is `preventDefault`-ed so focus can't be stolen; the caret lands at the click point via `posAtCoords`. (It has its own regression test, named "the two-click bug.")

**C — Multi-table structure**

- Two tables fused: deleting the single blank line between two adjacent tables merged them into one. Fixed — a `transactionFilter` refuses that deletion and an inserted table is blank-line-fenced. *(Same mechanism the callout guard later reused.)*
- Last-column delete left a husk: deleting the last column should remove the table, not leave a broken header. Fixed — last-column-delete removes the table; the header row isn't a deletable row.
- Orphan blank line: deleting a table that's the last thing in the doc with no trailing newline leaves one stray blank line. **Open** — known minor, deferred.

**D — Drag / grip interaction**

- Grip drop lost: pointermove/up bubbled through the nested cell editors before reaching the window listener, so the drag never recorded a target and the drop didn't persist. Fixed — the grip `setPointerCapture`-s the pointer so events route straight to it.
- Row grips invisible: the editor's scroll chrome intercepted the negative-margin gutter's hover area, so the row grips never revealed. Fixed — row grips moved back inside a real hoverable left gutter.
- No-op reorder/resize froze: a drag that ended where it started froze the preview instead of snapping back. Fixed — a no-op clears the preview locally (stays one undoable step).

**E — Connections inside cells**

- Tab discarded an open autocomplete candidate: with the `[[…]]` panel open and a candidate highlighted, Tab navigated to the next cell instead of accepting it. Fixed — Tab is gated on the panel being open (picks when open, navigates only when closed).
- Aliased `[[A|B]]` vs the cell pipe: the `|` in an aliased connection collides with the cell delimiter, with no way to disambiguate on disk. **Open** — autocomplete only inserts alias-free `[[Title]]`; the syntax call is unresolved.

**F — Layout & chrome (incl. fix-induced)**

- Page banner glued to the top over a table: the page header's scroll-park keys on a `scroll-timeline` name, but the same descendant selector also matched every nested cell `.cm-scroller`, making the name ambiguous and freezing the banner. Fixed — the cell scroller opts out of the timeline, leaving the main scroller its sole owner. *(Fix-induced: the cell-scroll fix is what created the ambiguous selector.)*
- Shift+Enter wrongly no-op'd: the cell-corruption hardening over-corrected and killed Shift+Enter entirely; the right behavior is an in-cell soft break serialized as `<br>`. Fixed — restored. *(Fix-induced regression, caught and corrected.)*

**G — Cross-feature**

- A **table inside a callout** renders as raw text: the table's region detection uses absolute line offsets, not prefix-aware ones, so it can't find a table behind `> ` markers. **Open** — finicky, deferred; the callout box stays intact around the raw text. This is the literal intersection of the two features' edge cases.

**Accepted tradeoffs (not bugs, for completeness)**

- No lagging resize bar — the moving columns + `ew-resize` cursor are the only drag feedback; a separate indicator lags the smooth motion (async measurement). Deliberate.
- No horizontal scroll — many columns narrow and wrap by design (the dash-width model conserves total width; the source stays portable GFM).
- Heading-column is a Pommora-only `.nexus/` visual (GFM has no header *column*) — the `.md` stays plain GFM. A paradigm decision, not a bug.
- Performance was a separate axis, fixed alongside: scroll-on-mount editor thrash (only the focused cell is a live editor), full-doc tokenization per keystroke (viewport-only), O(rows²) region detection (one parse), and a heading-toggle that rebuilt every table (partial swap).

---

### What recurs across both — the real payload

The bugs differ; the **classes** don't. The same handful of failure shapes produced almost every break in both features:

- **Deletion eats structure** — a delete reaching a construct's hidden skeleton (`> ` prefix, `|` pipes) corrupts it instead of being absorbed.
- **Caret traps in nested editors** — a nested CM scroller or an enterable gutter steals focus/scroll/caret.
- **Nesting & cross-feature seams** — a construct inside another (lists/code/quotes/tables inside a callout) hits detection that wasn't written to look behind a prefix.
- **Fix-induced regressions** — the most insidious class: a fix in one spot silently breaks a neighbor (the fence regex, the cell-scroll selector, the no-op'd Shift+Enter).
- **Paradigm / portability conflicts** — aliased-pipe vs cell-pipe, header-column vs GFM — where the on-disk format and the UI affordance disagree.

And the **fix pattern recurs too**: both features made their structure uncorruptible with the *same two CM6 primitives* — a `transactionFilter` that refuses the structure-breaking change, plus `atomicRanges` so the caret can't reach the structural characters in the first place. Tables found this pattern first (merge-guard + block atomic); the callout guard reused it almost verbatim. **That a fix generalizes across features is the whole argument for a skill: so do the breaks.**

### Why they were missed

Each class maps to a shortcut taken during testing:

- **Happy-path only** — typed the feature the way it's "meant" to be used, never the way a confused user would.
- **One caret position** — tested at the start of a line, not the end, the middle, or the boundary.
- **One key** — tested Backspace, not the Shift/Cmd/Alt/forward matrix. The break lived in the combos never pressed.
- **Constructs in isolation** — tested a bullet, a quote, a table on their own; never nested inside the new thing.
- **Read the code, not the screen** — trusted that correct-looking decoration logic produced correct pixels. UIX failure is indistinguishable from data failure until you *look*.

The real surface area of a syntactic, stateful editor feature is `{every key combo} × {every caret offset} × {every nesting depth} × {every adjacency}`. It's enormous. The happy path samples well under 1% of it, and every bug here lived in the other 99%.

### The lesson

- **Never say "bulletproof," "robust," or "done" before something has actively survived an attempt to break it.** Confidence is the *output* of failed break-attempts, not a preface to them.
- **The bug is almost never in the code you can read** — it's in the interaction you didn't try. Drive the real UI; reading the source proves nothing about the render or the keymap.
- **Green ≠ done.** Compiles + happy path + passing unit tests is the *start* of verification, not the end.
- **Verify by trying to break it, not by confirming it works.** One weird input is worth more than ten happy-path confirmations.

### Skill seed — the "break-things" reviewer

This Log is the raw material for a reusable skill whose sole purpose is adversarial breakage. What it should systematize:

- **A break-attempt taxonomy** — the recurring classes above (deletion-eats-structure · caret/scroll traps · nesting & cross-feature seams · fix-induced regressions · paradigm/portability conflicts · the input-transform & combo matrix) as a reusable checklist that generalizes past any one feature.
- **The "toddler" method, made standard** — every input, every key combo, every caret position; *screenshot every attempt*; **no deferred findings** — if it broke, find the fix and apply it before moving on.
- **A combinatorial generator** — mechanically enumerate `{keys} × {positions} × {nesting} × {adjacency}` rather than relying on the tester to imagine cases.
- **Known fix-patterns to reach for** — e.g. structure that must survive the keyboard wants a `transactionFilter` (refuse) + `atomicRanges` (unreachable), proven across both features here.
- **A required deliverable** — a catalog exactly like this one (break → repro → fix), produced *before* the feature may be called done.

The discipline is the deliverable: the skill exists so this Log never has to be written again.

---

### Block Drag — the discipline, applied

The first MarkdownPM feature reviewed adversarially **before** Nathan could break it by hand, instead of after. The same failure classes surfaced — but dispatched agents found them at the spec and pure-function layer, where the cost was a doc edit and a rewritten walk-loop, not a thrash session in the live editor. The loop, run forward.

**Spec review (three agents, before any code)** found the spec's "reuse wholesale" thesis overstated in five load-bearing spots, every one code-grounded:

- `collectCands` was framed as a candidate *filter* to widen — it's actually list *geometry* (it derives each drop target's adopted indent from the list marker), so widening it in place would silently change the shipped list-drag's re-indent behavior. The reuse claim was false.

- The table's "existing top-row grip" was cited as the drag handle — that grip early-returns from dragging and the widget swallows all pointer events, so whole-table drag is the *largest* net-new piece, not a thin bridge. The biggest work was mislabeled the smallest.

- Folded-heading drag was claimed to "just move the range" — the fold's mapped positions collapse under the move's coarse single-replace and its clone orphans, silently losing the fold. It needs an explicit teardown-then-re-fold.

- The chevron was reused for drag "like the list glyph" — but the glyph is a real DOM node and the chevron is a `::before` hit-tested by x-coordinate with its own open/closed visibility. Not the same; the fold and drag handlers must merge or they race.

- Taxonomy holes — `---`, block math, and image embeds fall through the paragraph catch-all and get mis-scoped. The catch-all had to be bounded by every other kind.

**Phase-1 `blockAt` review (two agents, after green)** — the resolver passed **12/12 unit tests and typecheck**, and the review still found a real, high-frequency bug by running the actual code:

- **List lazy-continuation split the list.** `- item one\n  wrapped text\n- item two` resolved the wrapped body as an orphan paragraph, so dragging item 1 would have left its own text behind. Multi-line list items are ordinary — it would have fired constantly. Fixed: the list walk is continuation-aware (marker lines plus their indented bodies), the case pinned as a test.

- Two judgment calls were pinned rather than papered over: blank-separated "loose" lists split into separate blocks (a conscious V1 decision, tested), and the multi-line `$$…$$`-with-a-blank gap *corrupts* (orphaned `$$`), so it's documented as corrupting, not merely sub-optimal.

**The new payload:** every entry above this one was a break a human found *after* "done." These were found by adversarial agents at the spec and pure-function layer, *before* the UI existed — and `12/12 green` was, once again, exactly when the bug was hiding. Same lesson, proven from the other direction: green is the start of verification, and the review is what earns the confidence. This is the Log's thesis working as designed instead of in hindsight.

**Post-green interaction sweep (four agents, after the gesture shipped green)** — a sweep aimed *only* at what unit tests structurally can't reach: pointer/scroll/abort timing and live geometry. It surfaced a four-item HIGH set, none of which a pure-function test could see:

- **The corruption keeper — silent block-fusion.** A relocation that dropped a block glue-adjacent to another *fused* the two on disk: a moved paragraph landing against a list became its lazy continuation; the doc was quietly corrupted. It passed every `blockMoveChanges` test. Fixed by blank-separating at **both** new seams (the insert seam *and* the cut hole), not just the drop point. This is the data-layer twin of the table merge-guard and the callout `>` guard — the **third** instance of the same shape: *a structural operation must defend its own seams, or the structure it touches fuses/erodes.* That the fix generalizes is, again, the argument for the skill.

- **Scroll staleness, missing abort, accent geometry** — candidate coordinates measured at grab-time go stale the instant the viewport scrolls (CM renders ~viewport only); a drag had no Escape/blur escape hatch; the insertion line measured text coords, so it drew *inside* a callout/code border. All three are lifecycle/geometry facts invisible to a doc-string test — they only exist once a real pointer is moving over a real scroller.

**The no-op slot reads as broken (layer-confusion, caught live this session).** The drop model has a by-design "stay put" slot — releasing where the block already sits draws **no line** and moves nothing. That is visually *identical* to "the insertion line is broken." This session's own screenshot harness dropped a list onto exactly that slot, saw no line, and it read as a regression until the target was moved to a real relocation and the line appeared. A textbook hit of the layer-confusion rule: *"no line" can be correct behavior or a real failure — confirm which before you "fix" it.*

**UIX feel still needed Nathan's eyes after functional-green.** Three things were functionally correct and wrong to the eye, fixable only by driving the real UI: the snap was too eager (jumped to a far target before the pointer was near it), the line showed *above* the next block instead of *below* the prior one ("show where it lands, not what it passes"), and it sat *inside* the callout box instead of on its outer border. Spec-layer and pure-function adversarial agents found real bugs *and left every one of these untouched* — they're orthogonal. **Adversarial review before the UI does not make the post-functional UIX review optional.** (This is the functional-layer proof of Review-Discipline's "post-functional UIX review is mandatory.")

**The harness has a ceiling — name it, don't fake it.** CDP synthetic-mouse driving reaches CM-line gutter grips reliably (it captured paragraph / list / heading / callout drags as real screenshots), but it **can't arm the React table widget** through CM6's viewport virtualization + the widget's own pointer-capture/region resolution. The honest move is to report that gap and verify the table by its shared `startBlockDrag` core + a prior live pass — never to stage a frame that implies a capture that didn't happen. Next time the table needs hard visual proof, the right tool is a real Playwright harness, not more synthetic-event coaxing.
