import { parse, isInsideCode } from '../parser'
import type { Column } from './model'
import { splitRow, parseDelimiter, docLines, type CellSpan } from './codec'

export interface RowGeom {
  from: number
  to: number
  cells: CellSpan[]
  pipes: number[]
  segments: [number, number][]
}

export interface TableRegion {
  from: number
  to: number
  rows: RowGeom[]
  delimiter: { from: number; to: number; columns: Column[] }
}

const lineTo = (l: { text: string; from: number }): number => l.from + l.text.length

function isTable(block: string): boolean {
  const tree = parse(block)
  return tree.children.length === 1 && tree.children[0].type === 'table'
}

function rowGeom(l: { text: string; from: number }): RowGeom {
  const { cells, pipes, segments } = splitRow(l.text, l.from)
  return { from: l.from, to: lineTo(l), cells, pipes, segments }
}

// Self-healing detector: a region is the maximal header+delimiter+body block that
// `parse()`s to a single GFM table. micromark is the sole authority on validity;
// blockquote and fenced-code headers are excluded up front.
// Single-entry memo: a keystroke calls this several times (guard ×2, decorations ×2, atomicRanges,
// findCell) on the same doc string, and each call re-parses with micromark — so cache the last result.
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
    let last = i
    while (last + 1 < lines.length && lines[last + 1].text.trim() !== '') {
      if (!isTable(doc.slice(header.from, lineTo(lines[last + 1])))) break
      last++
    }
    const body = lines.slice(i + 1, last + 1)
    regions.push({
      from: header.from,
      to: lineTo(lines[last]),
      rows: [rowGeom(header), ...body.map(rowGeom)],
      delimiter: { from: lines[i].from, to: lineTo(lines[i]), columns }
    })
    i = last + 1
  }
  cacheDoc = doc
  cacheRegions = regions
  return regions
}
