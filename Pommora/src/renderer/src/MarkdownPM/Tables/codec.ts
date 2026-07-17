import { parse } from '../parser'
import type { Align, Column, TableModel } from './model'
import { normalize } from './model'

export interface CellSpan {
  text: string
}
export interface RowSplit {
  cells: CellSpan[]
  segments: [number, number][] // untrimmed pipe-to-pipe span per cell (one flex item each)
}

// GFM table-cell escaping: a literal backslash or pipe inside a cell is backslash-escaped so it
// round-trips through the pipe-delimited row without reading as a column boundary. Inverse pair —
// escape on commit (sync.ts), unescape at the cell-display boundary (TableView). The model + segments
// stay in raw source form; only the editable display is unescaped.
export const escapeCell = (s: string): string => s.replace(/([\\|])/g, '\\$1')
export const unescapeCell = (s: string): string => s.replace(/\\([\\|])/g, '$1')

// A cell is single-line GFM on disk, so an in-cell line break serializes as `<br>` (literal newlines would
// split the row). These pair the escaping with the `<br>` ⇄ newline transform for the full round-trip:
// cellToSource on commit, cellToDisplay when seeding the cell editor.
export const cellToSource = (display: string): string =>
  escapeCell(display).replace(/\r?\n/g, '<br>')
export const cellToDisplay = (source: string): string =>
  unescapeCell(source).replace(/<br\s*\/?>/gi, '\n')

// Split a row line on UNescaped pipes. Returns trimmed cell text + absolute pipe offsets (line start = `base`).
export function splitRow(line: string, base: number): RowSplit {
  const cuts: number[] = [] // relative offsets of the structural pipes
  for (let i = 0; i < line.length; i++) {
    if (line[i] !== '|') continue
    // A pipe is structural unless preceded by an ODD run of backslashes (one-char look-behind missed
    // `\\|`, where the backslash is itself escaped and the pipe is a real boundary — micromark's rule).
    let bs = 0
    for (let j = i - 1; j >= 0 && line[j] === '\\'; j--) bs++
    if (bs % 2 === 0) cuts.push(i)
  }
  const segs: [number, number][] = []
  const hasLead = line.trimStart()[0] === '|'
  // A trailing pipe is structural only if unescaped (in `cuts`) — `a | b\|` ends the last CELL, not the row.
  const hasTrail = line.trimEnd().slice(-1) === '|' && cuts.includes(line.trimEnd().length - 1)
  const starts = hasLead ? cuts : [-1, ...cuts]
  const ends = hasTrail
    ? cuts.slice(hasLead ? 1 : 0)
    : [...(hasLead ? cuts.slice(1) : cuts), line.length]
  for (let k = 0; k < ends.length; k++) segs.push([starts[k] + 1, ends[k]])
  const cells: CellSpan[] = segs.map(([s, e]) => ({ text: line.slice(s, e).trim() }))
  const segments = segs.map(([s, e]) => [base + s, base + e] as [number, number])
  return { cells, segments }
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
  for (const t of src.split('\n')) {
    out.push({ text: t, from })
    from += t.length + 1
  }
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
  const rows = ls
    .slice(2)
    .filter((l) => l.text.trim() !== '')
    .map((l) => splitRow(l.text, l.from).cells.map((c) => c.text))
  return normalize({ columns, header, rows })
}

function delimCell(c: Column): string {
  const bar = '-'.repeat(Math.max(1, c.dashes))
  return c.align === 'center'
    ? `:${bar}:`
    : c.align === 'right'
      ? `${bar}:`
      : c.align === 'left'
        ? `:${bar}`
        : bar
}
export function serialize(m: TableModel): string {
  // Sink guard: a cell carrying a raw newline would split its row across lines and break the GFM, so
  // re-encode any in-cell newline as <br>. Defensive — a healthy model never holds one (cellToSource).
  const row = (cells: string[]): string =>
    `| ${cells.map((c) => c.replace(/\r?\n/g, '<br>')).join(' | ')} |`
  return [row(m.header), `| ${m.columns.map(delimCell).join(' | ')} |`, ...m.rows.map(row)].join(
    '\n',
  )
}
