# MarkdownPM Tables Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task (Nathan executes inline, single-agent). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive GFM table editor to the React MarkdownPM (CodeMirror 6) — resizable columns, structural ops, inline live-preview cell editing — that serializes to portable GFM on disk.

**Architecture:** The table stays live document text decorated into a grid (not a replaced block widget). A framework-free headless core (`model`/`codec`/`regions`/`operations`) does all GFM↔structure logic with zero CM6; a thin CM6 adapter (`decorations`/`input`/`resize`) renders + edits it. Column width is encoded as dash-count in the delimiter row (Pandoc convention), rendered as `flex-grow` ratios. The feature is one CM6 extension appended in `index.tsx` — removing it degrades tables to plain text.

**Tech Stack:** TypeScript, CodeMirror 6 (`@codemirror/view`, `@codemirror/state`), micromark + `mdast-util-gfm` (already wired in `parser/index.ts`), vitest, vanilla-extract design tokens via the `--var` bridge.

## Global Constraints

- **Portable GFM on disk.** Tables serialize to standard GFM pipe tables; nothing non-portable is written.
- **Never auto-tidy.** Source is mutated only on a user gesture (typing, structural op, resize). An untouched foreign table saves back byte-identical.
- **Width = dash count per delimiter cell** (Pandoc); **alignment = colons** (`:--`/`:-:`/`--:`); width counts dashes only; default equal; floor 1 dash.
- **Pipe model is a dichotomy** (grounded by probe — a raw `|` inside inline code breaks the GFM parse, so there is no "pipe-in-code" case): every `|` in cell source is either a structural boundary (hidden) or an escaped `\|` (renders as literal `|`, backslash hidden). Typing `|` in a cell inserts `\|`.
- **No new editor engine.** CodeMirror 6 only; reuse the existing `parser`/`tokens`/`decorations` strata.
- **Design values are tokens**, never literals — `--fill-tertiary`, `--label-secondary`, `body.emphasized`, `--separator-border`, via the `theme-vars.css.ts` `--var` bridge.
- **Inline content renders for free** — the existing `markdownDecorations` ViewPlugin already tokenizes the whole doc, so bold/links/connections inside cell text are styled without table-specific work.
- **All offsets are character (codepoint) offsets**, surrogate-safe at cell boundaries.

---

### Task 1: Table model (`Tables/model.ts`)

**Files:**
- Create: `React/src/renderer/src/MarkdownPM/Tables/model.ts`
- Test: `React/src/renderer/src/MarkdownPM/Tables/model.test.ts`

**Interfaces:**
- Produces: `Align = 'left'|'center'|'right'|null`; `Column = { align: Align; dashes: number }`; `TableModel = { columns: Column[]; header: string[]; rows: string[][] }`. Cell strings hold raw source text (escapes like `\|` intact, surrounding spaces trimmed). `header.length === columns.length`; every `rows[i].length === columns.length`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect } from 'vitest'
import { emptyTable, normalize } from './model'

describe('model', () => {
  it('emptyTable builds an N×M rectangular model with equal default dashes', () => {
    const m = emptyTable(3, 3)
    expect(m.columns.map((c) => c.dashes)).toEqual([6, 6, 6]) // seeded magnitude, total ≥ ~18
    expect(m.columns.every((c) => c.align === null)).toBe(true)
    expect(m.header).toEqual(['', '', ''])
    expect(m.rows).toEqual([['', '', ''], ['', '', '']]) // 3 rows total incl. header → 2 body
  })
  it('normalize pads short rows and truncates long rows to column count', () => {
    const m = normalize({ columns: [{ align: null, dashes: 3 }, { align: null, dashes: 3 }], header: ['a'], rows: [['x', 'y', 'z']] })
    expect(m.header).toEqual(['a', ''])
    expect(m.rows).toEqual([['x', 'y']])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/model.test.ts`
Expected: FAIL — `emptyTable`/`normalize` not exported.

- [ ] **Step 3: Write minimal implementation**

```ts
export type Align = 'left' | 'center' | 'right' | null
export interface Column { align: Align; dashes: number }
export interface TableModel { columns: Column[]; header: string[]; rows: string[][] }

export const DEFAULT_DASHES = 6 // seeded so total ≥ ~18 → fluid resize quantum

export function emptyTable(cols: number, rows: number): TableModel {
  return {
    columns: Array.from({ length: cols }, () => ({ align: null, dashes: DEFAULT_DASHES })),
    header: Array.from({ length: cols }, () => ''),
    rows: Array.from({ length: Math.max(0, rows - 1) }, () => Array.from({ length: cols }, () => ''))
  }
}

export function normalize(m: TableModel): TableModel {
  const n = m.columns.length
  const fit = (r: string[]): string[] => Array.from({ length: n }, (_, i) => r[i] ?? '')
  return { columns: m.columns, header: fit(m.header), rows: m.rows.map(fit) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/model.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add React/src/renderer/src/MarkdownPM/Tables/model.ts React/src/renderer/src/MarkdownPM/Tables/model.test.ts
git commit -m "feat(react/tables): headless TableModel + normalize"
```

---

### Task 2: Codec — parse + serialize (`Tables/codec.ts`)

**Files:**
- Create: `React/src/renderer/src/MarkdownPM/Tables/codec.ts`
- Test: `React/src/renderer/src/MarkdownPM/Tables/codec.test.ts`

**Interfaces:**
- Consumes: `TableModel`, `Align` (Task 1); `parse` from `../parser`.
- Produces: `parseTable(src: string): TableModel | null` (null when `src` isn't a single valid GFM table); `serialize(m: TableModel): string` (canonical fully-piped GFM, dash counts from `columns[i].dashes`, alignment colons from `align`). Round-trip stable: `serialize(parseTable(canonical)) === canonical`. Helpers `splitRow(line, base) → {cells, pipes}` and `parseDelimiter(line) → Column[]|null` exported for Task 3.

**Grounding (from the mdast probe):** mdast cell positions span pipe-to-pipe incl. whitespace, and the delimiter line is NOT an mdast row (it's the gap between header and first body row). So the codec works off raw lines: split each row on unescaped `|`, trim cells; parse the delimiter line for dashes + colons. A `\|` stays within its cell (micromark keeps it); a raw `|` in code breaks the parse (→ `parseTable` returns null, self-healing).

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect } from 'vitest'
import { parseTable, serialize, splitRow, parseDelimiter } from './codec'

describe('codec', () => {
  it('splitRow splits on unescaped pipes, keeps \\| in-cell, records pipe offsets', () => {
    const r = splitRow('| a\\|b | c |', 0)
    expect(r.cells.map((c) => c.text)).toEqual(['a\\|b', 'c'])
    expect(r.pipes).toEqual([0, 7, 11]) // leading, middle, trailing structural pipes
  })
  it('parseDelimiter reads dashes + alignment', () => {
    expect(parseDelimiter('|:--|--:|:-:|')).toEqual([
      { align: 'left', dashes: 2 },
      { align: 'right', dashes: 2 },
      { align: 'center', dashes: 1 }
    ])
  })
  it('parseTable returns null on a non-table and on a code-broken pipe', () => {
    expect(parseTable('not a table')).toBeNull()
    expect(parseTable('| `a|b` | c |\n|---|---|')).toBeNull()
  })
  it('round-trips canonical GFM with widths + alignment', () => {
    const src = '| a | b |\n| :--- | ---: |\n| 1 | 2 |'
    const m = parseTable(src)!
    expect(m.columns).toEqual([{ align: 'left', dashes: 3 }, { align: 'right', dashes: 3 }])
    expect(m.header).toEqual(['a', 'b'])
    expect(m.rows).toEqual([['1', '2']])
    expect(serialize(m)).toBe(src)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/codec.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

```ts
import { parse } from '../parser'
import type { Align, Column, TableModel } from './model'
import { normalize } from './model'

export interface CellSpan { from: number; to: number; text: string } // absolute doc offsets of trimmed cell text
export interface RowSplit { cells: CellSpan[]; pipes: number[] }

// Split a row line on UNescaped pipes. Returns trimmed cell text + absolute pipe offsets (line start = `base`).
export function splitRow(line: string, base: number): RowSplit {
  const pipes: number[] = []
  for (let i = 0; i < line.length; i++) if (line[i] === '|' && line[i - 1] !== '\\') pipes.push(base + i)
  const segs: [number, number][] = []
  const hasLead = line.trimStart()[0] === '|'
  const hasTrail = line.trimEnd().slice(-1) === '|'
  const cuts = pipes.map((p) => p - base)
  const starts = hasLead ? cuts : [-1, ...cuts]
  const ends = hasTrail ? cuts.slice(hasLead ? 1 : 0) : [...(hasLead ? cuts.slice(1) : cuts), line.length]
  for (let k = 0; k < ends.length; k++) segs.push([starts[k] + 1, ends[k]])
  const cells: CellSpan[] = segs.map(([s, e]) => {
    const raw = line.slice(s, e)
    const lead = raw.length - raw.trimStart().length
    const text = raw.trim()
    return { from: base + s + lead, to: base + s + lead + text.length, text }
  })
  return { cells, pipes }
}

const DELIM_CELL = /^\s*(:?)(-+)(:?)\s*$/
export function parseDelimiter(line: string): Column[] | null {
  const inner = line.replace(/^\s*\|/, '').replace(/\|\s*$/, '')
  const cols: Column[] = []
  for (const part of inner.split('|')) {
    const m = DELIM_CELL.exec(part)
    if (!m) return null
    const align: Align = m[1] && m[3] ? 'center' : m[3] ? 'right' : m[1] ? 'left' : null
    cols.push({ align, dashes: m[2].length })
  }
  return cols
}

export function docLines(src: string): { text: string; from: number }[] {
  const out: { text: string; from: number }[] = []
  let from = 0
  for (const t of src.split('\n')) { out.push({ text: t, from }); from += t.length + 1 }
  return out
}

export function parseTable(src: string): TableModel | null {
  const tree = parse(src)
  if (tree.children.length !== 1 || tree.children[0].type !== 'table') return null
  const ls = docLines(src.replace(/\n+$/, ''))
  if (ls.length < 2) return null
  const columns = parseDelimiter(ls[1].text)
  if (!columns) return null
  const header = splitRow(ls[0].text, ls[0].from).cells.map((c) => c.text)
  const rows = ls.slice(2).filter((l) => l.text.trim() !== '').map((l) => splitRow(l.text, l.from).cells.map((c) => c.text))
  return normalize({ columns, header, rows })
}

function delimCell(c: Column): string {
  const bar = '-'.repeat(Math.max(1, c.dashes))
  return c.align === 'center' ? `:${bar}:` : c.align === 'right' ? `${bar}:` : c.align === 'left' ? `:${bar}` : bar
}
export function serialize(m: TableModel): string {
  const row = (cells: string[]): string => `| ${cells.join(' | ')} |`
  return [row(m.header), `| ${m.columns.map(delimCell).join(' | ')} |`, ...m.rows.map(row)].join('\n')
}
```

- [ ] **Step 4: Run tests; iterate `splitRow` boundary handling until green**

Run: `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/codec.test.ts`
Expected: PASS. (`splitRow`'s outer-pipe edge logic is the fiddly part — add a no-outer-pipe case `splitRow('a | b', 0)` → cells `['a','b']` and fix until green.)

- [ ] **Step 5: Commit**

```bash
git add React/src/renderer/src/MarkdownPM/Tables/codec.ts React/src/renderer/src/MarkdownPM/Tables/codec.test.ts
git commit -m "feat(react/tables): GFM codec — dash-width + alignment, escaped-pipe dichotomy"
```

---

### Task 3: Region detection (`Tables/regions.ts`)

**Files:**
- Create: `React/src/renderer/src/MarkdownPM/Tables/regions.ts`
- Test: `React/src/renderer/src/MarkdownPM/Tables/regions.test.ts`

**Interfaces:**
- Consumes: `parse`, `isInsideCode` from `../parser`; `splitRow`, `parseDelimiter`, `docLines` (Task 2).
- Produces: `tableRegions(doc: string): TableRegion[]` where `TableRegion = { from: number; to: number; rows: RowGeom[]; delimiter: { from: number; to: number; columns: Column[] } }` and `RowGeom = { from: number; to: number; cells: CellSpan[]; pipes: number[] }`. Rows are header + body (NOT the delimiter). A region is valid iff its contiguous header+delimiter+body block `parse()`s to a single `table` node; regions whose header line is inside a fenced code block (`isInsideCode`) or starts with `>` are skipped. This is the self-healing predicate + the geometry the decoration/atomic layers consume.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, it, expect } from 'vitest'
import { tableRegions } from './regions'

describe('regions', () => {
  it('finds a top-level table and its row/pipe geometry; excludes the delimiter from rows', () => {
    const doc = 'intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nafter'
    const [r] = tableRegions(doc)
    expect(r.rows.length).toBe(2) // header + 1 body
    expect(r.delimiter.columns.length).toBe(2)
    expect(doc.slice(r.from, r.to)).toBe('| a | b |\n|---|---|\n| 1 | 2 |')
  })
  it('skips a pipe table inside a fenced code block', () => {
    const doc = '```\n| a | b |\n|---|---|\n```'
    expect(tableRegions(doc)).toEqual([])
  })
  it('skips a half-typed table (no delimiter yet)', () => {
    expect(tableRegions('| a | b |\nnot a delimiter')).toEqual([])
  })
})
```

- [ ] **Step 2: Run to fail.** `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/regions.test.ts` — FAIL.

- [ ] **Step 3: Implement** — walk `docLines`; for each line `i` where `parseDelimiter(line[i])` succeeds and `line[i-1]` looks like a header row and isn't `isInsideCode`/blockquote, extend down over contiguous non-blank pipe rows; confirm the block `parse()`s to a single `table`; build `RowGeom` (header + body) via `splitRow` and the delimiter geometry. The three tests pin the contract.

- [ ] **Step 4: Run to pass.** PASS.

- [ ] **Step 5: Commit**

```bash
git add React/src/renderer/src/MarkdownPM/Tables/regions.ts React/src/renderer/src/MarkdownPM/Tables/regions.test.ts
git commit -m "feat(react/tables): self-healing region detector + row/pipe geometry"
```

---

### Task 4: Structural operations (`Tables/operations.ts`)

**Files:**
- Create: `React/src/renderer/src/MarkdownPM/Tables/operations.ts`
- Test: `React/src/renderer/src/MarkdownPM/Tables/operations.test.ts`

**Interfaces:**
- Consumes: `TableModel`, `Column` (Task 1).
- Produces, all pure `TableModel → TableModel`: `insertRow(m, atBodyIndex, where)`, `deleteRow(m, atBodyIndex)`, `insertColumn(m, atIndex, where)` (new dashes = rounded average of existing), `deleteColumn(m, atIndex)`, `setAlign(m, col, align)`, `resizeColumn(m, boundaryIndex, dashDelta)` (transfer between `boundaryIndex` and `boundaryIndex+1`, total constant, floor 1), `moveRow(m, from, to)`, `moveColumn(m, from, to)`.

- [ ] **Step 1: Write the failing test** (the invariants that matter)

```ts
import { describe, it, expect } from 'vitest'
import { insertColumn, resizeColumn, deleteColumn } from './operations'
import type { TableModel } from './model'

const base: TableModel = {
  columns: [{ align: null, dashes: 10 }, { align: null, dashes: 10 }, { align: null, dashes: 10 }],
  header: ['a', 'b', 'c'], rows: [['1', '2', '3']]
}

describe('operations', () => {
  it('insertColumn adds avg-dash column, keeps existing dashes, widens every row', () => {
    const m = insertColumn(base, 1, 'right')
    expect(m.columns.map((c) => c.dashes)).toEqual([10, 10, 10, 10])
    expect(m.header).toEqual(['a', 'b', '', 'c'])
    expect(m.rows[0]).toEqual(['1', '2', '', '3'])
  })
  it('resizeColumn transfers dashes between the two adjacent columns only', () => {
    const m = resizeColumn(base, 0, +3)
    expect(m.columns.map((c) => c.dashes)).toEqual([13, 7, 10]) // col2 untouched, total constant
  })
  it('resizeColumn clamps at the 1-dash floor', () => {
    const m = resizeColumn(base, 0, -20)
    expect(m.columns[1].dashes).toBe(1)
    expect(m.columns[0].dashes + m.columns[1].dashes).toBe(20)
  })
  it('deleteColumn removes the cell from every row', () => {
    const m = deleteColumn(base, 1)
    expect(m.columns.length).toBe(2)
    expect(m.rows[0]).toEqual(['1', '3'])
  })
})
```

- [ ] **Step 2: Run to fail.** `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/operations.test.ts` — FAIL.

- [ ] **Step 3: Implement** each as a pure array transform (splice columns/rows; `resizeColumn` moves `clamp(dashDelta, -(left-1), right-1)` between the pair). The invariant tests are the contract.

- [ ] **Step 4: Run to pass.** PASS.

- [ ] **Step 5: Commit**

```bash
git add React/src/renderer/src/MarkdownPM/Tables/operations.ts React/src/renderer/src/MarkdownPM/Tables/operations.test.ts
git commit -m "feat(react/tables): structural ops — insert/delete/move/resize/align"
```

**Slice 1 gate:** `cd "React" && npx vitest run src/renderer/src/MarkdownPM/Tables/` is fully green — headless core done, zero CM6.

---

### Task 5: Off-caret grid render (`Tables/decorations.ts`, `Tables/index.ts`, `Tables/Tables.css`)

**Files:** Create `Tables/decorations.ts`, `Tables/index.ts`, `Tables/Tables.css`; Modify `MarkdownPM/index.tsx` (append the extension to the editor's extension array, beside `markdownDecorations`).

**Interfaces:** Consumes `tableRegions` (Task 3); CM6 `Decoration`, `ViewPlugin`, `EditorView`. Produces `tableExtension(): Extension` (a `ViewPlugin` providing the table `DecorationSet`; Task 6 extends it with `atomicRanges` + input).

**Pattern (grounded in `editor/decorations.ts`):** `ViewPlugin.fromClass` rebuilding on `docChanged || selectionSet || focusChanged`. Per region: each row line → `Decoration.line({ class: 'md-table-row' })`; each cell content span → `Decoration.mark({ class: 'md-table-cell', attributes: { style: \`flex:${dashes} 0 0\`, 'data-align': align ?? 'left' } })`; each structural pipe (single char) → `Decoration.replace({})`; the delimiter line → `Decoration.line({ class: 'md-table-delim' })` (CSS `display:none` — a ViewPlugin can't emit block replaces); header row → add `md-table-header`.

- [ ] Step 1: `Tables.css` — `.md-table-row{display:flex}`, `.md-table-cell{min-width:0;overflow-wrap:anywhere}`, `[data-align=center/right]` text-align, `.md-table-header{background:var(--fill-tertiary)}` + emphasized text, separators via `var(--separator-border)`, `.md-table-delim{display:none}`.
- [ ] Step 2: `decorations.ts` — the ViewPlugin per the pattern; `index.ts` exports `tableExtension()`.
- [ ] Step 3: `index.tsx` — import + append `tableExtension()`.
- [ ] Step 4: **Visual gate (Nathan):** a static 3×3 renders as an aligned grid; pipes + delimiter hidden; header styled; columns proportional to dashes; caret lands inside cells. Tune CSS live.
- [ ] Step 5: Commit `feat(react/tables): off-caret grid render`.

---

### Task 6: Cell editing + navigation (`Tables/input.ts`)

**Files:** Create `Tables/input.ts`; wire its keymap (`Prec.highest`), `atomicRanges`, and `inputHandler` into `tableExtension()`.

**Interfaces:** Consumes `tableRegions`; produces `tableInput(): Extension`.

**Grounded specifics:** the existing keymap is `Prec.high` (`editor/input.ts:60`) so table handlers register at **`Prec.highest`** and `return false` when the caret isn't in a table (list/blockquote handlers still run). Register all structural pipes + delimiter lines in `EditorView.atomicRanges.of(view => rangeSet)` — arrow-key skip only, so Tab/Enter compute their own landing offset (next cell content start, from `tableRegions`). Content-pipe escape via `EditorView.inputHandler.of` (mirror `editor/input.ts:68`): `|` typed in a cell inserts `\|`.

- [ ] Step 1: `atomicRanges` facet from region pipe/delimiter geometry.
- [ ] Step 2: Tab/Shift-Tab/Enter cell navigation; exit at edges.
- [ ] Step 3: Backspace/Delete suppressed when it would cross a structural pipe (else `return false`).
- [ ] Step 4: `|`→`\|` inputHandler inside cells.
- [ ] Step 5: **Visual gate (Nathan):** typing renders live-preview-formatted; structure never appears; Tab/Enter move cell-to-cell; backspace can't eat structure; typed `|` shows literal.
- [ ] Step 6: Commit `feat(react/tables): live cell editing + atomic navigation`.

---

### Task 7: Grip + structural menu + Insert Table

**Files:** Grip + structural menu in the `Tables/` adapter (renderer DOM overlay); Modify `src/main/editorMenu.ts:100` (add `{ label: 'Insert Table', click: act('block:table') }` to the Block submenu) + the renderer's `menu:action` handler (route `block:table` → insert `serialize(emptyTable(3, 3))` below the caret line).

**Interfaces:** Consumes `operations` (Task 4), `serialize`/`emptyTable`, `tableRegions`.

- [ ] Step 1: `Insert Table` in the Electron Block submenu + the `block:table` renderer action (3×3 below the caret line; never split it).
- [ ] Step 2: Grip overlay — floating Lucide grip (`label-secondary`), per column/row, hover-revealed, positioned from region geometry.
- [ ] Step 3: Right-click grip → structural menu → apply the matching `operations` fn → re-`serialize` → dispatch the change over the region range.
- [ ] Step 4: **Visual gate (Nathan):** insert from the Block menu; every menu op works; the cell-formatting right-click is unaffected.
- [ ] Step 5: Commit `feat(react/tables): grip menu + Insert Table`.

---

### Task 8: Resize (`Tables/resize.ts`)

**Files:** Create `Tables/resize.ts`; wire into `tableExtension()`.

**Interfaces:** Consumes `operations.resizeColumn`, region geometry.

- [ ] Step 1: `col-resize` cursor + pointer drag on column boundaries (thin hit-zone from geometry).
- [ ] Step 2: during drag the boundary tracks the cursor (transient CSS); crossing a dash-width threshold → `resizeColumn(model, boundary, ±1)` → re-serialize → dispatch; snap to nearest whole-dash on release.
- [ ] Step 3: floor 1; single-column tables expose no boundary.
- [ ] Step 4: **Visual gate (Nathan):** dragging a boundary — fluid, one-dash steps, neighbors hold.
- [ ] Step 5: Commit `feat(react/tables): column resize via dash transfer`.

---

### Task 9: Round-trip hardening

**Files:** Modify `Tables/codec.ts`/`input.ts` as needed; Create `Tables/roundtrip.test.ts`.

- [ ] Step 1: tests — foreign no-outer-pipe table survives untouched (byte-identical on save); ragged rows pad on render only; emoji cell offsets stay aligned; paste-into-cell sanitizes (newlines→spaces, `|`→`\|`); paste-over-selection re-grids.
- [ ] Step 2: implement the paste handler + verify no-auto-tidy (a parsed-but-untouched table is never rewritten).
- [ ] Step 3: Visual + corpus gate.
- [ ] Step 4: Commit `feat(react/tables): round-trip hardening + paste`.

**Post-v1:** drag-to-reorder on the grip, wired to `moveRow`/`moveColumn` via PommoraDND (rows) + a column companion handler.

---

## Self-Review

- **Spec coverage:** detection (T3), dash-width + alignment codec (T2), structural ops + insert-avg + resize-transfer (T4), grid render (T5), no-syntax live cells + atomic nav + content-pipe (T6), grip menu + creation (T7), resize (T8), round-trip/paste/emoji (T9). The pipe model is corrected to a **dichotomy** (probe-grounded) — the same correction folds into the spec's §Cell-Model.
- **Type consistency:** `TableModel`/`Column`/`Align` defined in T1, consumed unchanged through T2–T8; `CellSpan`/`RowSplit`/`RowGeom`/`TableRegion` defined in T2–T3, consumed by T5–T8.
- **Placeholders:** headless tasks (T1–T4) carry full test + implementation code; CM6 tasks (T5–T9) carry the grounded pattern + exact files + visual-verify gates, with UI specifics tuned live against the running app per the spec.
