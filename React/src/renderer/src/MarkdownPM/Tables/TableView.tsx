import './widget.css'
import { useRef } from 'react'
import type { EditorView } from '@codemirror/view'
import type { Align, TableModel } from './model'
import { CellEditor } from './CellEditor'
import { unescapeCell } from './codec'
import { nextCell, type NavDir } from './navigate'
import type { ConnectionsApi } from '../connections'

function alignClass(align: Align): string {
  return `mdpm-tbl-align-${align ?? 'left'}`
}

// The interactive table: dash-ratio columns (<colgroup> + table-layout:fixed); every cell is a live
// CellEditor. onCellCommit + navigation speak the visual-row convention — row 0 = header, row >= 1 = body.
export function TableView({
  model,
  onCellCommit,
  onExit,
  connections
}: {
  model: TableModel
  onCellCommit: (row: number, col: number, text: string) => void
  onExit: (dir: 'before' | 'after') => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const total = model.columns.reduce((sum, c) => sum + Math.max(1, c.dashes), 0) || model.columns.length
  const cells = useRef(new Map<string, EditorView>())
  const totalRows = model.rows.length + 1
  const cols = model.columns.length

  const navigate = (row: number, col: number, dir: NavDir): void => {
    const target = nextCell(totalRows, cols, row, col, dir)
    if (target === 'before' || target === 'after') {
      onExit(target)
      return
    }
    const view = cells.current.get(`${target.row},${target.col}`)
    if (view) {
      view.focus()
      view.dispatch({ selection: { anchor: view.state.doc.length } }) // caret at end of the target cell
    }
  }

  const register =
    (row: number, col: number) =>
    (view: EditorView): (() => void) => {
      const key = `${row},${col}`
      cells.current.set(key, view)
      return () => cells.current.delete(key)
    }

  const cell = (row: number, col: number, text: string): React.JSX.Element => (
    <CellEditor
      initial={unescapeCell(text)}
      connections={connections}
      onCommit={(t) => onCellCommit(row, col, t)}
      onNavigate={(dir) => navigate(row, col, dir)}
      register={register(row, col)}
    />
  )

  return (
    <table className="mdpm-tbl">
      <colgroup>
        {model.columns.map((c, i) => (
          <col key={i} style={{ width: `${(Math.max(1, c.dashes) / total) * 100}%` }} />
        ))}
      </colgroup>
      <thead>
        <tr>
          {model.header.map((text, ci) => (
            <th key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
              {cell(0, ci, text)}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {model.rows.map((row, ri) => (
          <tr key={ri}>
            {row.map((text, ci) => (
              <td key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
                {cell(ri + 1, ci, text)}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}
