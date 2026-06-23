import './widget.css'
import type { Align, TableModel } from './model'

function alignClass(align: Align): string {
  return `mdpm-tbl-align-${align ?? 'left'}`
}

// Read-only render of a parsed table. Columns size by dash-ratio (our width convention) via <colgroup>
// + table-layout:fixed; cell text is raw for now — inline rendering + editing arrive in later slices.
export function TableView({ model }: { model: TableModel }): React.JSX.Element {
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
              {cell}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {model.rows.map((row, ri) => (
          <tr key={ri}>
            {row.map((cell, ci) => (
              <td key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
                {cell}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}
