import './widget.css'
import type { Align, TableModel } from './model'
import { CellEditor } from './CellEditor'
import type { ConnectionsApi } from '../connections'

function alignClass(align: Align): string {
  return `mdpm-tbl-align-${align ?? 'left'}`
}

// The interactive table: columns size by dash-ratio (<colgroup> + table-layout:fixed); every cell is a
// live CellEditor. onCellCommit speaks the visual-row convention — row 0 = header, row >= 1 = body[row-1].
export function TableView({
  model,
  onCellCommit,
  connections
}: {
  model: TableModel
  onCellCommit: (row: number, col: number, text: string) => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const total = model.columns.reduce((sum, c) => sum + Math.max(1, c.dashes), 0) || model.columns.length

  return (
    <table className="mdpm-tbl">
      <colgroup>
        {model.columns.map((c, i) => (
          <col key={i} style={{ width: `${(Math.max(1, c.dashes) / total) * 100}%` }} />
        ))}
      </colgroup>
      <thead>
        <tr>
          {model.header.map((cell, ci) => (
            <th key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
              <CellEditor initial={cell} connections={connections} onCommit={(t) => onCellCommit(0, ci, t)} />
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {model.rows.map((row, ri) => (
          <tr key={ri}>
            {row.map((cell, ci) => (
              <td key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
                <CellEditor initial={cell} connections={connections} onCommit={(t) => onCellCommit(ri + 1, ci, t)} />
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}
