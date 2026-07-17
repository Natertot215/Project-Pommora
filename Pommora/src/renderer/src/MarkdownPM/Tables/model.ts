export type Align = 'left' | 'center' | 'right' | null

export interface Column {
  align: Align
  dashes: number
}

export interface TableModel {
  columns: Column[]
  header: string[]
  rows: string[][]
}

export const DEFAULT_DASHES = 6

export function emptyTable(cols: number, rows: number): TableModel {
  return {
    columns: Array.from({ length: cols }, () => ({ align: null, dashes: DEFAULT_DASHES })),
    header: Array.from({ length: cols }, () => ''),
    rows: Array.from({ length: Math.max(0, rows - 1) }, () =>
      Array.from({ length: cols }, () => ''),
    ),
  }
}

export function normalize(m: TableModel): TableModel {
  const n = m.columns.length
  const fit = (r: string[]): string[] => Array.from({ length: n }, (_, i) => r[i] ?? '')
  return { columns: m.columns, header: fit(m.header), rows: m.rows.map(fit) }
}
