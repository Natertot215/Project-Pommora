import './widget.css'
import { useLayoutEffect, useRef, useState } from 'react'
import { GripHorizontal, GripVertical } from 'lucide-react'
import type { EditorView } from '@codemirror/view'
import type { Align, TableModel } from './model'
import type { TableMenuContext } from '@shared/tableMenu'
import { CellEditor } from './CellEditor'
import { cellToDisplay } from './codec'
import { clamp } from './operations'
import { nextCell, type NavDir } from './navigate'
import type { ConnectionsApi } from '../connections'

function alignClass(align: Align): string {
  return `mdpm-tbl-align-${align ?? 'left'}`
}

const RESIZE_HIT = 10

interface Geom {
  cols: { left: number; width: number }[]
  rows: { top: number; height: number }[]
}

type Axis = 'col' | 'row'
interface Drag {
  axis: Axis
  from: number
  to: number
  delta: number
}

// A live column-boundary resize: pixel-exact preview of the two adjacent columns while dragging; the dash
// counts are only recomputed + committed on release.
interface Resize {
  boundaryIndex: number
  leftPx: number
  rightPx: number
}

function shift(drag: Drag | null, axis: Axis, index: number, size: number): string | undefined {
  if (!drag || drag.axis !== axis) return undefined
  const { from, to, delta } = drag
  const t = axis === 'col' ? 'translateX' : 'translateY'
  if (index === from) return `${t}(${delta}px)`
  if (to < from && index >= to && index < from) return `${t}(${size}px)`
  if (to > from && index > from && index <= to) return `${t}(${-size}px)`
  return undefined
}

function slotAt(axis: Axis, geom: Geom, rel: number): number {
  const spans = axis === 'col' ? geom.cols : geom.rows
  for (let i = 0; i < spans.length; i++) {
    const s = axis === 'col' ? geom.cols[i].left + geom.cols[i].width : geom.rows[i].top + geom.rows[i].height
    if (rel < s) return i
  }
  return spans.length - 1
}

export function TableView({
  model,
  onCellCommit,
  onExit,
  onReorder,
  onResize,
  onMenu,
  onUndo,
  onRedo,
  connections
}: {
  model: TableModel
  onCellCommit: (row: number, col: number, text: string) => void
  onExit: (dir: 'before' | 'after') => void
  onReorder: (axis: Axis, from: number, to: number) => boolean
  onResize: (boundaryIndex: number, dashDelta: number) => boolean
  onMenu: (ctx: TableMenuContext) => void
  onUndo: () => void
  onRedo: () => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const total = model.columns.reduce((sum, c) => sum + Math.max(1, c.dashes), 0) || model.columns.length
  const cells = useRef(new Map<string, EditorView>())
  const totalRows = model.rows.length + 1
  const cols = model.columns.length

  const wrapRef = useRef<HTMLDivElement>(null)
  const tableRef = useRef<HTMLTableElement>(null)
  const [geom, setGeom] = useState<Geom>({ cols: [], rows: [] })
  const [drag, setDrag] = useState<Drag | null>(null)
  const [resize, setResize] = useState<Resize | null>(null)

  useLayoutEffect(() => {
    const measure = (): void => {
      const table = tableRef.current
      const wrap = wrapRef.current
      if (!table || !wrap) return
      const w = wrap.getBoundingClientRect()
      const headerCells = table.tHead?.rows[0]?.cells
      const colGeom = headerCells
        ? Array.from(headerCells).map((c) => {
            const b = c.getBoundingClientRect()
            return { left: b.left - w.left, width: b.width }
          })
        : []
      const allRows = [...(table.tHead?.rows ?? []), ...(table.tBodies[0]?.rows ?? [])]
      const rowGeom = allRows.map((r) => {
        const b = r.getBoundingClientRect()
        return { top: b.top - w.top, height: b.height }
      })
      setGeom({ cols: colGeom, rows: rowGeom })
    }
    measure()
    const ro = new ResizeObserver(measure)
    if (tableRef.current) ro.observe(tableRef.current)
    return () => ro.disconnect()
  }, [model])

  // updateDOM re-renders in place (no re-mount), so a live drag survives the model update.
  // Clear when the model changes so the dropped item settles without holding its drag transform.
  useLayoutEffect(() => {
    setDrag(null)
    setResize(null)
  }, [model])

  const startDrag = (e: React.PointerEvent<HTMLDivElement>, axis: Axis, index: number): void => {
    if (axis === 'row' && index === 0) return // the header row never drags
    if (e.button !== 0) return // only the left button drags; a right-press falls through to the context menu
    e.preventDefault()
    const wrap = wrapRef.current
    if (!wrap) return
    // Capture the pointer to the grip (so moves over the nested cell editors report to it, not get
    // swallowed), but bind move/up on WINDOW: the grip element is re-rendered mid-drag (setDrag + the
    // ResizeObserver on the transform reflow), and listeners hung on it get dropped when the node detaches
    // — capture then implicitly releases WITHOUT firing pointerup, so the drag would never clear (freeze).
    const grip = e.currentTarget
    grip.setPointerCapture(e.pointerId)
    const box = wrap.getBoundingClientRect()
    const origin = axis === 'col' ? box.left : box.top
    const start = axis === 'col' ? e.clientX : e.clientY
    let current: Drag = { axis, from: index, to: index, delta: 0 }
    setDrag(current)
    const onMove = (ev: PointerEvent): void => {
      const pos = axis === 'col' ? ev.clientX : ev.clientY
      let to = slotAt(axis, geom, pos - origin)
      if (axis === 'row') to = Math.max(1, to) // can't drop a row above the header
      current = { axis, from: index, to, delta: pos - start }
      setDrag(current)
    }
    const onUp = (ev: PointerEvent): void => {
      grip.releasePointerCapture(ev.pointerId)
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      // A real reorder clears drag via the model-change effect; a no-op (same serialization) won't re-render, so clear here.
      if (current.to === current.from || !onReorder(axis, current.from, current.to)) setDrag(null)
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
  }

  // Drag a column boundary: dashes move between the two adjacent columns (total conserved, 1-dash floor).
  // Preview is pixel-exact (override both <col> widths in px); on release we quantize the new left width
  // to whole dashes and commit one resizeColumn. Same window-bound pointer-capture pattern as startDrag.
  const startResize = (e: React.PointerEvent<HTMLDivElement>, boundaryIndex: number): void => {
    if (e.button !== 0) return
    e.preventDefault()
    const i = boundaryIndex
    const leftDashes = Math.max(1, model.columns[i].dashes)
    const rightDashes = Math.max(1, model.columns[i + 1].dashes)
    const combinedDashes = leftDashes + rightDashes
    const startLeftPx = geom.cols[i]?.width ?? 0
    const startRightPx = geom.cols[i + 1]?.width ?? 0
    const combinedPx = startLeftPx + startRightPx
    if (combinedPx === 0) return
    const oneDashPx = combinedPx / combinedDashes
    const handle = e.currentTarget
    handle.setPointerCapture(e.pointerId)
    const startX = e.clientX
    let leftPx = startLeftPx
    setResize({ boundaryIndex: i, leftPx: startLeftPx, rightPx: startRightPx })
    const onMove = (ev: PointerEvent): void => {
      const delta = clamp(ev.clientX - startX, -(startLeftPx - oneDashPx), startRightPx - oneDashPx)
      leftPx = startLeftPx + delta
      setResize({ boundaryIndex: i, leftPx, rightPx: startRightPx - delta })
    }
    const onUp = (ev: PointerEvent): void => {
      handle.releasePointerCapture(ev.pointerId)
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      const newLeftDashes = clamp(Math.round(leftPx / oneDashPx), 1, combinedDashes - 1)
      const dashDelta = newLeftDashes - leftDashes
      // No change (or a no-op commit) won't re-render → clear the preview here, like reorder's onUp.
      if (dashDelta === 0 || !onResize(i, dashDelta)) setResize(null)
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
  }

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
      initial={cellToDisplay(text)}
      connections={connections}
      onCommit={(t) => onCellCommit(row, col, t)}
      onNavigate={(dir) => navigate(row, col, dir)}
      onUndo={onUndo}
      onRedo={onRedo}
      register={register(row, col)}
    />
  )

  // Grips swallow mousedown so a click on one (to drag or open the right-click menu) never pulls focus or
  // moves the editor caret to the click point — the grip is a control, not a text position.
  const swallowCaret = (e: React.MouseEvent): void => e.preventDefault()

  const colDragged = (ci: number): boolean => drag?.axis === 'col' && drag.from === ci
  const colW = (ci: number): number => geom.cols[ci]?.width ?? 0
  const rowH = (ri: number): number => geom.rows[ri]?.height ?? 0

  // While resizing, every column is sized in px (the two at the boundary from the live preview, the rest
  // from their measured widths) so the table total stays fixed; otherwise columns are dash-proportional %.
  const colWidth = (ci: number): string => {
    if (resize) {
      if (ci === resize.boundaryIndex) return `${resize.leftPx}px`
      if (ci === resize.boundaryIndex + 1) return `${resize.rightPx}px`
      return `${colW(ci)}px`
    }
    return `${(Math.max(1, model.columns[ci].dashes) / total) * 100}%`
  }

  const tableTop = geom.rows[0]?.top ?? 0
  const lastRow = geom.rows[geom.rows.length - 1]
  const tableHeight = lastRow ? lastRow.top + lastRow.height - tableTop : 0

  return (
    <div
      className={`mdpm-tbl-wrap${drag ? ' mdpm-tbl-dragging' : ''}${resize ? ' mdpm-tbl-resizing' : ''}`}
      ref={wrapRef}
    >
      <table className="mdpm-tbl" ref={tableRef}>
        <colgroup>
          {model.columns.map((_, i) => (
            <col key={i} style={{ width: colWidth(i) }} />
          ))}
        </colgroup>
        <thead>
          <tr>
            {model.header.map((text, ci) => (
              <th
                key={ci}
                className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}${colDragged(ci) ? ' mdpm-tbl-subject' : ''}`}
                style={{ transform: shift(drag, 'col', ci, colW(ci)) }}
              >
                {cell(0, ci, text)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {model.rows.map((row, ri) => (
            <tr
              key={ri}
              className={drag?.axis === 'row' && drag.from === ri + 1 ? 'mdpm-tbl-subject' : ''}
              style={{ transform: shift(drag, 'row', ri + 1, rowH(ri + 1)) }}
            >
              {row.map((text, ci) => (
                <td
                  key={ci}
                  className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}${colDragged(ci) ? ' mdpm-tbl-subject' : ''}`}
                  style={{ transform: shift(drag, 'col', ci, colW(ci)) }}
                >
                  {cell(ri + 1, ci, text)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {geom.cols.map((c, i) => (
        <div
          key={`col-${i}`}
          className="mdpm-tbl-grip-zone mdpm-tbl-grip-col"
          style={{ left: c.left, width: c.width }}
          onMouseDown={swallowCaret}
          onPointerDown={(e) => startDrag(e, 'col', i)}
          onContextMenu={(e) => {
            e.preventDefault()
            onMenu({ kind: 'column', index: i, align: model.columns[i]?.align ?? null })
          }}
        >
          <GripHorizontal className="mdpm-tbl-grip" size={14} strokeWidth={2} />
        </div>
      ))}
      {geom.rows.map((r, j) => (
        <div
          key={`row-${j}`}
          className="mdpm-tbl-grip-zone mdpm-tbl-grip-row"
          style={{ top: r.top, height: r.height }}
          onMouseDown={swallowCaret}
          onPointerDown={(e) => startDrag(e, 'row', j)}
          onContextMenu={(e) => {
            e.preventDefault()
            onMenu(j === 0 ? { kind: 'header', index: 0 } : { kind: 'row', index: j })
          }}
        >
          <GripVertical className="mdpm-tbl-grip" size={14} strokeWidth={2} />
        </div>
      ))}
      {geom.cols.slice(0, -1).map((c, i) => (
        <div
          key={`resize-${i}`}
          className="mdpm-tbl-resize-zone"
          style={{ left: c.left + c.width - RESIZE_HIT / 2, top: tableTop, height: tableHeight, width: RESIZE_HIT }}
          onMouseDown={swallowCaret}
          onPointerDown={(e) => startResize(e, i)}
        />
      ))}
    </div>
  )
}
