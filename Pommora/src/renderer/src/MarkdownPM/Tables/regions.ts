import { parse, isInsideCode } from '../parser'
import { normalize, type Column, type TableModel } from './model'
import { splitRow, parseDelimiter, docLines, type CellSpan } from './codec'

export interface RowGeom {
  cells: CellSpan[]
  segments: [number, number][]
}

export interface TableRegion {
  from: number
  to: number
  rows: RowGeom[]
  delimiter: { columns: Column[] }
}

const lineTo = (l: { text: string; from: number }): number => l.from + l.text.length

function isTable(block: string): boolean {
  const tree = parse(block)
  return tree.children.length === 1 && tree.children[0].type === 'table'
}

function rowGeom(l: { text: string; from: number }): RowGeom {
  return splitRow(l.text, l.from)
}

// Single-entry memo: a keystroke calls this several times on the same doc string (guard, decorations,
// atomicRanges) and each call re-parses with micromark — cache the last result.
let cacheDoc: string | null = null
let cacheRegions: TableRegion[] = []
export function tableRegions(doc: string): TableRegion[] {
  if (doc === cacheDoc) return cacheRegions
  const lines = docLines(doc)
  const regions: TableRegion[] = []
  let i = 1
  while (i < lines.length) {
    const columns = parseDelimiter(lines[i].text)
    const header = lines[i - 1]
    if (
      !columns ||
      header.text.trim() === '' ||
      header.text.trimStart()[0] === '>' ||
      isInsideCode(header.from, doc) ||
      !isTable(doc.slice(header.from, lineTo(lines[i])))
    ) {
      i++
      continue
    }
    // Grab the contiguous non-blank block lexically, then confirm with a SINGLE parse — shrinking only
    // if a non-table line is glued on without a blank separator (rare). The old per-line `isTable` made
    // this O(rows²) parses per table on every keystroke; the common case is now one parse.
    let last = i
    while (last + 1 < lines.length && lines[last + 1].text.trim() !== '') last++
    while (last > i && !isTable(doc.slice(header.from, lineTo(lines[last])))) last--
    const body = lines.slice(i + 1, last + 1)
    regions.push({
      from: header.from,
      to: lineTo(lines[last]),
      rows: [rowGeom(header), ...body.map(rowGeom)],
      delimiter: { columns },
    })
    i = last + 1
  }
  cacheDoc = doc
  cacheRegions = regions
  return regions
}

// Equivalent to `parseTable` on the region's source (regression-tested), without a second micromark pass.
export function modelFromRegion(region: TableRegion): TableModel {
  return normalize({
    columns: region.delimiter.columns,
    header: region.rows[0].cells.map((c) => c.text),
    rows: region.rows.slice(1).map((r) => r.cells.map((c) => c.text)),
  })
}
