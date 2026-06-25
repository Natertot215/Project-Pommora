import { useMemo } from 'react'
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef
} from '@tanstack/react-table'
import type {
  CollectionNode,
  PageNode,
  SelectionState,
  SetNode,
  ViewRow
} from '@shared/types'
import { resolveView } from './pipeline'
import { useSession } from '../../store'

// --- row flattening -------------------------------------------------------

/**
 * Flatten a container's pages (its own + every nested Set, any depth) into the
 * pipeline's ViewRow shape. The loaded NexusTree carries only intrinsic
 * PageNode fields, so `frontmatter` is absent today — property columns light
 * up automatically once a stage populates it (see ViewRow doc in @shared/types).
 */
function flattenRows(node: CollectionNode | SetNode): ViewRow[] {
  const rows: ViewRow[] = []
  const walk = (n: { pages: PageNode[]; sets?: SetNode[] }): void => {
    for (const p of n.pages) rows.push({ id: p.id, title: p.title, icon: p.icon, path: p.path })
    for (const s of n.sets ?? []) walk(s)
  }
  walk(node)
  return rows
}

// --- property-column derivation -------------------------------------------

/**
 * Union of frontmatter keys across all rows, minus internal `_`-prefixed keys,
 * in first-seen order. Empty today (no frontmatter loaded) — the Title column
 * stands alone until per-page frontmatter is fetched into ViewRow.
 */
function propertyKeys(rows: ViewRow[]): string[] {
  const seen = new Set<string>()
  const keys: string[] = []
  for (const row of rows) {
    if (!row.frontmatter) continue
    for (const key of Object.keys(row.frontmatter)) {
      if (key.startsWith('_') || seen.has(key)) continue
      seen.add(key)
      keys.push(key)
    }
  }
  return keys
}

/** Flatten a single frontmatter value to display text — mirrors the pipeline's rule. */
function cellText(v: unknown): string {
  if (v === null || v === undefined) return ''
  if (Array.isArray(v)) return v.map(cellText).join(', ')
  if (typeof v === 'string') return v
  return String(v)
}

// --- view -----------------------------------------------------------------

const column = createColumnHelper<ViewRow>()

export function TableView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)

  // Sort by title (asc) in one implicit group — read-only ordering via the pure pipeline.
  // resolveView never mutates its input. The container flattens its own pages + every nested Set.
  const rows = useMemo<ViewRow[]>(() => {
    const flat = flattenRows(source)
    const groups = resolveView(flat, { sort: { field: 'title', direction: 'asc' } })
    return groups.flatMap((g) => g.rows)
  }, [source])

  const columns = useMemo<ColumnDef<ViewRow, string>[]>(() => {
    const titleCol = column.accessor('title', {
      header: 'Title',
      cell: (ctx) => ctx.getValue()
    }) as ColumnDef<ViewRow, string>
    const propCols = propertyKeys(rows).map(
      (key) =>
        column.accessor((r) => cellText(r.frontmatter?.[key]), {
          id: key,
          header: key,
          cell: (ctx) => ctx.getValue()
        }) as ColumnDef<ViewRow, string>
    )
    return [titleCol, ...propCols]
  }, [rows])

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel()
  })

  if (rows.length === 0) {
    return <div className="table-empty">No pages here</div>
  }

  return (
    <div className="table-view">
      <table className="data-table">
        <thead>
          {table.getHeaderGroups().map((hg) => (
            <tr key={hg.id}>
              {hg.headers.map((h) => (
                <th key={h.id}>
                  {h.isPlaceholder ? null : flexRender(h.column.columnDef.header, h.getContext())}
                </th>
              ))}
            </tr>
          ))}
        </thead>
        <tbody>
          {table.getRowModel().rows.map((r) => {
            const row = r.original
            const isSelected = isRowSelected(selection, row.id)
            return (
              <tr
                key={r.id}
                className={`data-row${isSelected ? ' selected' : ''}`}
                onClick={() => void select({ kind: 'page', id: row.id, path: row.path })}
              >
                {r.getVisibleCells().map((c) => (
                  <td key={c.id}>{flexRender(c.column.columnDef.cell, c.getContext())}</td>
                ))}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function isRowSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'page' && sel.id === id
}
