# MarkdownPM Review Fixes — Implementation Plan

**Goal:** Land every confirmed finding from the critical review of the MarkdownPM editor — the headline marker rework, the DRY consolidation that unblocks it, the independent correctness bugs, and the dead-code removals.

**Source:** 24 adversarially-confirmed findings (6-lens review). The leverage is concentrated: one structural decision (atomic marker widgets) causes the entire known list-editing issue, and one DRY violation (marker parsing open-coded nine ways) sits directly beside it and blocks the fix.

**Net direction:** removal over addition. The fixes delete more code than they add (estimate below).

**Discipline:** TDD per task; a green commit per task (`npm run test` + `npm run typecheck`); the marker rework closes with a live UIX pass + screenshots with Nathan before closeout (prior attempts at it were reverted on alignment).

---

## Global Constraints

- Behavior layer (`parser/`, `detect/`, `tokens/`, `input/`, `decorations/intent.ts`) stays framework-free + unit-tested. No CM6 imports leak below `editor/`.
- One source of truth for marker parsing (DRY hard-rule). After Phase 3 there is exactly one list-marker parser.
- Markers are **editable source text**, never replaced by atomic widgets — except the checkbox, which stays an interactive control over the bracket only.
- CSS colour/size come from the `--var` bridge tokens, never literals the token layer owns.
- No dates, no version stamps. Phases and steps only.

---

## Estimated Lines of Code Changed

Counted from the prescribed diffs (approximate — a plan, not a landed diff):

| Item | Files | + | − | Net |
|------|-------|---|---|-----|
| Delete `callouts/codec.ts` + test | 2 | 0 | ~54 | −54 |
| Delete `isInsideLatex` + test block | 2 | 0 | ~31 | −31 |
| Fix `bracketSkipOnEnter` comment | 1 | ~1 | ~2 | −1 |
| `[[`/`((` auto-pair stray-closer fix | 2 | ~12 | ~4 | +8 |
| Consolidate pair tables (3→1) | 1 | ~8 | ~14 | −6 |
| Rename revert-on-failure | 4 | ~10 | ~5 | +5 |
| `parseListMarker` consolidation | 3 | ~35 | ~55 | −20 |
| Marker rework — intent layer | 1 | ~25 | ~30 | −5 |
| Marker rework — CM6 adapter | 1 | ~8 | ~32 | −24 |
| Marker rework — CSS | 1 | ~30 | ~20 | +10 |
| Marker rework — tests | 2 | ~12 | ~12 | 0 |
| **Total** | **~12 files** | **~171** | **~311** | **≈ −140** |

**~480 lines touched; net ≈ −140 (a reduction).** That's the headline: implementing the entire review *shrinks* the codebase.

---

## Phase 1 — Dead-Code Removal (safe, independent, do first)

Shrinks the surface before the structural work. Each task is a standalone green commit.

### Task 1.1 — Delete the callout codec

**Files:** Delete `src/renderer/src/MarkdownPM/callouts/codec.ts` + `callouts/codec.test.ts` (and the `callouts/` dir if empty).

Verified test-only: no production import of `expandShorthand`/`parseCalloutType`/`isCalloutLine`. It's a speculative seam for a feature (`::` callouts) that hasn't shipped — write it when callouts are built (it's already specced in `MarkdownPM-Build-Plan.md`).

- [ ] Confirm no prod import: `grep -rn "callouts/codec" src/renderer/src | grep -v callouts/codec.test` returns nothing
- [ ] Delete both files
- [ ] `npm run test && npm run typecheck` green
- [ ] Commit: `chore(MarkdownPM): remove unused callout codec (deferred feature)`

### Task 1.2 — Delete `isInsideLatex`

**Files:** `src/renderer/src/MarkdownPM/parser/index.ts` (remove the function, lines ~53-76); `parser/parser.test.ts` (remove the `isInsideLatex` import + its `describe` block, lines ~44-55).

Verified dead in production — only its own test references it. LaTeX gating is deferred; `dashArrow` gates on `isInsideWikilink` only. (`isInsideCode` + `isInsideWikilink` stay — they have live callers.)

- [ ] Remove the function + its test block + the import
- [ ] `npm run test && npm run typecheck` green
- [ ] Commit: `chore(MarkdownPM): remove dead isInsideLatex (latex gating deferred)`

### Task 1.3 — Correct the misleading `bracketSkipOnEnter` comment

**Files:** `src/renderer/src/MarkdownPM/input/index.ts:140-141`.

The comment claims a "list-marker checkbox carve-out … caller order handles that" that the code does **not** implement — `bracketSkipOnEnter` runs *first* in `onEnter` and wins. Per the no-misleading-comments rule, fix the comment to state reality (it runs before list continuation; a caret between an empty `[ ]` jumps the closer).

- [ ] Replace the comment with one matching actual behaviour
- [ ] `npm run test` green (no logic change)
- [ ] Commit: `docs(MarkdownPM): correct bracketSkipOnEnter comment to match behaviour`

---

## Phase 2 — Independent Correctness Fixes

No dependency on the marker rework. Each ships green.

### Task 2.1 — Fix the `[[` / `((` auto-pair stray closer

**Files:** `src/renderer/src/MarkdownPM/input/index.ts` (`autoPair`, lines ~106-127); `input/input.test.ts`.

**Bug:** typing `[` then `[` yields `[[]]]` — the first `[` auto-paired to `[]`, then the multi-pair branch inserts `[]` again without consuming the existing closer. Wikilinks are the core gesture in this Obsidian-like product, so every `[[` a user starts is corrupted.

- [ ] **Step 1 — failing test.** In the auto-pair describe block:
```ts
it('[[ collapses the existing closer instead of stacking a stray ]', () => {
  // doc is "[]" with caret after the first "[" (autoPair already paired the first [)
  const e = autoPair('[]', 1, 1, '[')!
  expect(apply('[]', e)).toBe('[[]]') // not "[[]]]"
  expect(e.selection).toBe(2)
})
it('(( collapses the existing closer', () => {
  const e = autoPair('()', 1, 1, '(')!
  expect(apply('()', e)).toBe('(())')
})
```
- [ ] **Step 2 — run, confirm it fails** (`[[]]]` / `(())`-with-stray)
- [ ] **Step 3 — fix.** In the `inserted in MULTI_PAIR && prev === inserted` branch, when the existing closer sits to the right (`doc[selStart] === SINGLE_PAIR[inserted]` for `(`, or `]` for `[`), consume it — replace `[c-1, c+1)` so the net result is `openopen + close` (one closer, not two). Mirrors Swift's `hasAutoCloseBracket` collapse (`MarkdownListHandler.swift`).
- [ ] **Step 4 — run, green**
- [ ] Commit: `fix(MarkdownPM): [[ and (( no longer leave a stray closer`

### Task 2.2 — Rename revert-on-failure

**Files:** `store.ts` (`submitRename`, ~238); `Detail/PageView.tsx:45`; `MarkdownPM/index.tsx` (`onRename` prop type, ~24); `MarkdownPM/TitleBar.tsx` (`commit`, ~18-22).

**Bug:** `TitleBar.commit()` fires `onRename` fire-and-forget and never reverts. On a failed rename the on-screen title keeps the typed draft while disk/store hold the original — a spec violation (`MarkdownPM.md` rename contract). The editor doesn't remount on failure (path unchanged), so the stale draft persists.

- [ ] **Step 1 — make the rename path report success.** `submitRename` → `Promise<boolean>`: `return (await get().mutate(...))` after `mutate` is changed to return `res.ok` (it currently returns void; have it `return res.ok` on both branches). Thread the boolean through `PageView` (`onRename={(n) => submitRename(pageDetail.path, 'page', n)}`) and the `index.tsx` prop type (`onRename?: (newName: string) => Promise<boolean> | void`).
- [ ] **Step 2 — TitleBar awaits + reverts.** Make `commit` async: `const ok = await onRename?.(next); if (ok === false) setValue(title)`.
- [ ] **Step 3 — verify** `npm run typecheck` (the Promise thread compiles) + existing tests green
- [ ] Commit: `fix(MarkdownPM): revert the title draft when a rename fails`

### Task 2.3 — Collapse the three auto-pair tables into one

**Files:** `src/renderer/src/MarkdownPM/input/index.ts` (`MULTI_PAIR` ~101, `SINGLE_PAIR` ~102, `DELETE_PAIR` ~129).

Three independent pair tables silently disagree — `{` auto-pairs and Enter-skips but won't auto-delete; the `{` SINGLE_PAIR entry never round-trips. Derive open/close/delete from **one** table so a brace can't be half-supported.

- [ ] **Step 1 — failing test:** `autoDelete('{}', 1, 1)` should delete both halves (currently null)
- [ ] **Step 2 — one source.** Define a single `PAIRS` map of `open → { close, multi? }`; derive the multi-char, single-char, and delete lookups from it. Remove the dead/duplicate entries.
- [ ] **Step 3 — run, green** (all auto-pair/delete/skip tests still pass)
- [ ] Commit: `refactor(MarkdownPM): single source for bracket pairs`

---

## Phase 3 — DRY: One List-Marker Parser

The prerequisite for Phase 4. List-marker parsing is open-coded ≥9 times across three layers with divergent regexes (`detect` uses `\s` which crosses lines; `input` uses `[ \t]`; `intent` splits one concept into three per-type regexes). Hoist one structured parser; every layer consumes it. Design its return shape to **already serve the new marker model**, so Phase 4 changes only rendering, not parsing.

### Task 3.1 — Add `parseListMarker` + shared indent helpers in `detect`

**Files:** `src/renderer/src/MarkdownPM/detect/index.ts`; new tests in `detect/detect.test.ts`.

- [ ] **Step 1 — failing tests** covering bullet / ordered / checkbox / non-list, each asserting the structured ranges:
```ts
// parseListMarker('  - x')   → { indent:'  ', kind:'bullet',   markerStart:2, markerEnd:4, contentStart:4, level:1 }
// parseListMarker('3. x')    → { indent:'',   kind:'ordered',  digits:'3', markerStart:0, markerEnd:3, contentStart:3, level:0 }
// parseListMarker('- [x] y') → { indent:'',   kind:'checkbox', bracketStart:2, bracketEnd:5, checked:true, markerEnd:6, contentStart:6, level:0 }
// parseListMarker('plain')   → null
```
- [ ] **Step 2 — implement** one `parseListMarker(line: string)` returning that union (offsets are line-relative; the caller adds the line start). Use `[ \t]` consistently — never `\s`. Export the shared `indentLevel(ws)` and `MAX_NESTING_LEVEL` from here too (currently the `tabs + ⌊spaces/2⌋` cap-3 formula is written three times).
- [ ] **Step 3 — run, green**
- [ ] Commit: `feat(MarkdownPM): single parseListMarker source (structured ranges)`

### Task 3.2 — Route `input/index.ts` through `parseListMarker`

**Files:** `src/renderer/src/MarkdownPM/input/index.ts`.

- [ ] Replace `listMarkerRe`, `lineMarkerRe`, and the inline indent-level math in `indentListOnTab` with `parseListMarker` + the shared `indentLevel`/`MAX_NESTING_LEVEL`. `continueListOnEnter`, `smartBackspace`, `indentListOnTab` consume the structured result. (`shorthandCheckboxRe` for `-[]`→`- [ ]` canonicalization stays — it matches a *pre-canonical* shorthand the parser intentionally doesn't.)
- [ ] **Verify** the full `input/input.test.ts` suite stays green (behaviour unchanged — same continuation/backspace/tab outcomes)
- [ ] Commit: `refactor(MarkdownPM): input transforms consume parseListMarker`

### Task 3.3 — Route `decorations/intent.ts` through `parseListMarker`; delete the leftovers

**Files:** `src/renderer/src/MarkdownPM/decorations/intent.ts`; remove `listRegex` from `detect/index.ts` + its `detect.test.ts` line; share the blockquote-prefix regex.

- [ ] Replace `BULLET_RE`, `ORDERED_RE`, `CHECKBOX_RE`, and the local `indentLevel` in `intent.ts` with `parseListMarker` + shared helpers. The list branch becomes one call that switches on `kind`.
- [ ] Delete `listRegex` (test-only) from `detect`. Export the blockquote-prefix regex once from `detect` and consume it in both `input/index.ts` and `intent.ts` (currently character-identical in two places).
- [ ] **Verify** `decorations/intent.test.ts` stays green (intents unchanged — still widget/line for now; Phase 4 changes the emission)
- [ ] Commit: `refactor(MarkdownPM): intent layer consumes parseListMarker; drop dead regexes`

---

## Phase 4 — The Marker Rework (headline)

**The root cause:** every list marker is emitted as `{kind:'widget', from:lineStart, to:lineStart+match[0].length}` and rendered via `Decoration.replace({widget})` — an **atomic** CM6 range that *removes* the marker source from the editing buffer. The caret can't enter it; typing a space after a number marker re-lays the widget over the just-typed space and shoves the caret out (the "swallowed space"); bordering inline tokens lose their offsets (bold reveals raw `**`). The Swift target is the opposite: markers stay as **editable text painted transparent**, with the glyph drawn as an always-on overlay.

**Target model:**

| Marker | Source treatment | Glyph |
|--------|------------------|-------|
| Bullet `-` | transparent `mark` over the `-` char (stays editable, width kept) | `•` via `::before` on the `.md-li-bullet` line, positioned in the indent gutter |
| Ordered `N.` | **none** — render literally as visible source text (recolour class only) | the literal `N.` *is* the glyph; remove `OrderedWidget` entirely |
| Checkbox `[ ]` | interactive widget over the **bracket only** (`[ls+bracketStart, ls+bracketEnd)`), trailing space excluded | the chip control (kept — it's a real control) |

This makes ordered markers correct for free (no widget → no atomic boundary → no swallowed space), turns the bullet into editable transparent text + a CSS overlay, and trims the trailing space out of the checkbox range so the caret can land after it.

> **Landmine (from the dissent, respect it):** the marker-zone CSS is currently coupled to the in-flow widget (`.md-li-marker` as an `inline-block`). The transparent-text approach was attempted before and reverted because the hanging-indent alignment broke. Do the CSS gutter-overlay move **as part of this phase**, and tune alignment live with screenshots — do not treat it as a naive decoration swap.

### Task 4.1 — Change the intent emission

**Files:** `src/renderer/src/MarkdownPM/decorations/intent.ts`; `WidgetSpec` type.

- [ ] **Step 1 — update tests first** (`decorations/intent.test.ts`): bullet asserts a `class` intent (transparent marker) over the `-` + a `line` class `md-li md-li-bullet`, **not** a bullet widget; ordered asserts a `class` (recolour) over `N.` + a list line, **no** widget; checkbox asserts a widget whose range ends at the bracket end (no trailing space).
- [ ] **Step 2 — implement.** In the list branch (now driven by `parseListMarker`):
  - bullet → `{kind:'class', from:markerStart, to:markerEnd, className:'md-marker-hidden'}` + line `md-li md-li-bullet`
  - ordered → `{kind:'class', from:markerStart, to:markerEnd, className:'md-ol-marker'}` + line `md-li`
  - checkbox → line `md-li` + `{kind:'widget', from:ls+bracketStart, to:ls+bracketEnd, spec:{type:'checkbox', …}}`
  - Remove `{type:'bullet'}` and `{type:'ordered'}` from `WidgetSpec`.
- [ ] **Step 3 — run, green**
- [ ] Commit: `feat(MarkdownPM): markers stay editable source (intent layer)`

### Task 4.2 — Simplify the CM6 adapter

**Files:** `src/renderer/src/MarkdownPM/editor/decorations.ts`.

- [ ] Delete `BulletWidget` (~21-31) and `OrderedWidget` (~33-48); remove their `widgetFor` cases. `widgetFor` now handles only `hr` + `checkbox`.
- [ ] **Verify** `npm run typecheck` (the `WidgetSpec` switch is now exhaustive over two cases) + tests green
- [ ] Commit: `refactor(MarkdownPM): drop bullet/ordered widgets (markers are source now)`

### Task 4.3 — CSS: gutter overlay + transparent marker

**Files:** `src/renderer/src/MarkdownPM/Styles.css`.

- [ ] Add `.md-marker-hidden { color: transparent }` (the `-` stays in the buffer, occupies width, paints invisible).
- [ ] Move the marker model from the in-flow `.md-li-marker` inline-block to a line `::before` overlay. Starting point (tune live):
```css
.mdpm-editor .cm-line.md-li {
  --bullet-indent: 20px;
  --gap: 4px;
  --li-col: calc((var(--li-level, 0) + 1) * var(--bullet-indent));
  position: relative;            /* anchor the ::before, like .md-bq */
  padding-left: calc(var(--li-col) + var(--gap));
}
.mdpm-editor .cm-line.md-li-bullet::before {
  content: '•';
  position: absolute;
  left: var(--li-col);
  font-size: 1.25em;             /* confirmed-correct bullet size */
  color: color-mix(in srgb, var(--label-primary) 80%, transparent); /* confirmed 80% */
}
```
  Remove the now-unused `.md-li-marker` zone rules (bullet/ordered no longer render a marker span; the checkbox widget keeps its own `.md-li-marker` wrapper or gets a minimal replacement).
- [ ] **Step — live tune** the gutter alignment so bullet, ordered, and checkbox text columns line up and wrapped lines hang flush. **Screenshots with Nathan** — this is where prior attempts failed.
- [ ] Commit: `style(MarkdownPM): list markers as gutter overlay over editable source`

### Task 4.4 — Verify + close out

- [ ] Full `npm run test && npm run typecheck` green
- [ ] Run the **manual-test checklist** (`MarkdownPM-Manual-Test.md`) end-to-end in the live app — every list case, with attention to: typing a space after `1.`, editing inside a marker, caret entering the marker zone, bold immediately after a marker, nested-list alignment.
- [ ] Live UIX pass with Nathan (screenshots) before declaring done.
- [ ] Update `Handoff.md`: clear the "Known issue — list markers" section; note the marker model is now Swift-aligned (editable source + overlay).

---

## Self-Review

- **Coverage:** all 24 confirmed findings map to a task — marker model (4.1-4.3), DRY parser + indent + blockquote-regex (Phase 3), `[[` bug (2.1), rename revert (2.2), pair tables (2.3), dead code (1.1-1.2), comment (1.3). The three CSS-token drifts (bullet 80%/1.25em, blockquote bar colour) are **dropped per Nathan** — current values confirmed correct.
- **Ordering:** Phase 3 precedes Phase 4 so `intent.ts` is refactored to `parseListMarker` once, then Phase 4 changes only emission — `intent.ts` isn't rewritten twice.
- **Type consistency:** `parseListMarker` is defined in 3.1 and consumed identically in 3.2/3.3/4.1; `WidgetSpec` loses `bullet`/`ordered` in 4.1 before the adapter switch narrows in 4.2.
