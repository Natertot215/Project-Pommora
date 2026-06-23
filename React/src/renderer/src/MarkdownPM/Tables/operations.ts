import type { Align, Column, TableModel } from './model'

type RowWhere = 'above' | 'below'
type ColWhere = 'left' | 'right'

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

function spliceAt<T>(arr: T[], pos: number, del: number, ...ins: T[]): T[] {
  const a = [...arr]
  a.splice(pos, del, ...ins)
  return a
}

export function insertRow(m: TableModel, atBodyIndex: number, where: RowWhere): TableModel {
  const pos = where === 'below' ? atBodyIndex + 1 : atBodyIndex
  const blank = m.columns.map(() => '')
  return { ...m, rows: spliceAt(m.rows, pos, 0, blank) }
}

export function deleteRow(m: TableModel, atBodyIndex: number): TableModel {
  return { ...m, rows: m.rows.filter((_, i) => i !== atBodyIndex) }
}

export function insertColumn(m: TableModel, atIndex: number, where: ColWhere): TableModel {
  const pos = where === 'right' ? atIndex + 1 : atIndex
  const avg = Math.round(m.columns.reduce((s, c) => s + c.dashes, 0) / m.columns.length)
  const col: Column = { align: null, dashes: Math.max(1, avg) }
  return {
    columns: spliceAt(m.columns, pos, 0, col),
    header: spliceAt(m.header, pos, 0, ''),
    rows: m.rows.map((r) => spliceAt(r, pos, 0, ''))
  }
}

export function deleteColumn(m: TableModel, atIndex: number): TableModel {
  const drop = <T>(arr: T[]): T[] => arr.filter((_, i) => i !== atIndex)
  return { columns: drop(m.columns), header: drop(m.header), rows: m.rows.map(drop) }
}

export function setAlign(m: TableModel, col: number, align: Align): TableModel {
  return { ...m, columns: m.columns.map((c, i) => (i === col ? { ...c, align } : c)) }
}

// Positive dashDelta widens columns[boundaryIndex] and narrows columns[boundaryIndex+1]
// (the boundary moves right); the total is conserved and the shrinking side floors at 1 dash.
export function resizeColumn(m: TableModel, boundaryIndex: number, dashDelta: number): TableModel {
  const left = m.columns[boundaryIndex].dashes
  const right = m.columns[boundaryIndex + 1].dashes
  const d = clamp(dashDelta, -(left - 1), right - 1)
  return {
    ...m,
    columns: m.columns.map((c, i) =>
      i === boundaryIndex
        ? { ...c, dashes: left + d }
        : i === boundaryIndex + 1
          ? { ...c, dashes: right - d }
          : c
    )
  }
}

export function moveRow(m: TableModel, from: number, to: number): TableModel {
  return { ...m, rows: spliceAt(spliceAt(m.rows, from, 1), to, 0, m.rows[from]) }
}

export function moveColumn(m: TableModel, from: number, to: number): TableModel {
  const move = <T>(arr: T[]): T[] => spliceAt(spliceAt(arr, from, 1), to, 0, arr[from])
  return { columns: move(m.columns), header: move(m.header), rows: m.rows.map(move) }
}
