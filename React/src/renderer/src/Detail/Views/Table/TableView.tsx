import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, NexusTree, ResolvedColumn, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import { type SavedView, mintDefaultView } from '@shared/views'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { useSession } from '../../../store'
import { buildResolveContext, type ResolveContext } from './resolveContext'
import { buildSetNames } from './cellResolve'
import { Cell } from './Cell'
import { GroupHeader } from './GroupHeader'
import { columnLabel } from './columnLabel'
import { clampWidth, widthFor } from './columnWidths'
import { reorderColumns } from './columnReorder'
import { mergeOverrides } from './viewMerge'
import { ColumnMenu } from './ColumnMenu'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { Icon } from '@renderer/design-system/symbols'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'

/** The left gutter column that holds each row's hover-revealed drag grip (E-3 / H-5). */
const GUTTER_W = 22

/** A Collection uses its own schema; a Set inherits its ancestor Collection's (schema lives only on
 *  the Collection). [] when the owning Collection can't be found. */
function resolveContainerSchema(tree: NexusTree, source: CollectionNode | SetNode): PropertyDefinition[] {
  if (source.kind === 'collection') return source.properties ?? []
  const collections = [...tree.collections, ...tree.userSections.flatMap((s) => s.collections)]
  const owns = (sets: SetNode[] | undefined): boolean =>
    (sets ?? []).some((s) => s.id === source.id || owns(s.sets))
  return collections.find((c) => owns(c.sets))?.properties ?? []
}

/** The view to render: the per-machine active view if still present, else the first saved view, else
 *  a freshly-minted default (sentinel id until first saved). */
function pickView(source: CollectionNode | SetNode, activeId: string | undefined, schema: PropertyDefinition[]): SavedView {
  const views = source.views ?? []
  const active = activeId ? views.find((v) => v.id === activeId) : undefined
  return active ?? views[0] ?? mintDefaultView(schema)
}

export function TableView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)
  const [values, setValues] = useState<Record<string, PageFrontmatter>>({})
  const [activeViewId, setActiveViewId] = useState<string | undefined>(undefined)
  const [viewOrders, setViewOrders] = useState<Record<string, string[]>>({})

  // Lazy value load + active-view pointer + manual-order cache on container open; `cancelled` guards a
  // fast container swap.
  useEffect(() => {
    let cancelled = false
    void window.nexus.loadValues(source.path).then((v) => {
      if (!cancelled) setValues(v)
    })
    void window.nexus.activeViews.get().then((m) => {
      if (!cancelled) setActiveViewId(m[source.id])
    })
    void window.nexus.viewOrders.get().then((m) => {
      if (!cancelled) setViewOrders(m)
    })
    return () => {
      cancelled = true
    }
  }, [source.path, source.id])

  const schema = useMemo(() => (tree ? resolveContainerSchema(tree, source) : []), [tree, source])
  const view = useMemo(() => pickView(source, activeViewId, schema), [source, activeViewId, schema])
  // Local override layer — reorder + resize + hide + collapse apply instantly, persist async (watcher
  // confirms). Order + hidden go in `liveView` (the pipeline reads them); width stays a separate
  // override so a resize doesn't re-run the pipeline. All re-seed on view change.
  const [orderOverride, setOrderOverride] = useState<string[] | null>(null)
  const [widthOverride, setWidthOverride] = useState<Record<string, number>>({})
  const [hiddenOverride, setHiddenOverride] = useState<string[] | null>(null)
  const [manualOverride, setManualOverride] = useState<string[] | null>(null)
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set(view.collapsed_groups ?? []))
  const [headerMenu, setHeaderMenu] = useState<{ id: string; left: number; top: number } | null>(null)
  const [collapsing, setCollapsing] = useState<string | null>(null)
  useEffect(() => {
    setOrderOverride(null)
    setWidthOverride({})
    setHiddenOverride(null)
    setManualOverride(null)
    setHeaderMenu(null)
    setCollapsing(null)
    setCollapsed(new Set(view.collapsed_groups ?? []))
  }, [view.id])
  const liveView = useMemo(() => {
    if (!orderOverride && !hiddenOverride) return view
    return {
      ...view,
      property_order: orderOverride ?? view.property_order,
      hidden_properties: hiddenOverride ?? view.hidden_properties
    }
  }, [view, orderOverride, hiddenOverride])
  // Manual row order (viewOrders cache) is the sort tiebreaker (D-5/D-6) — passed to the pipeline ONLY
  // when the view is sorted or grouped (an unsorted, ungrouped view uses canonical page_order instead).
  const sortedOrGrouped = (liveView.sort?.length ?? 0) > 0 || liveView.group != null
  const manualOrder = sortedOrGrouped ? (manualOverride ?? viewOrders[view.id]) : undefined
  const { columns, groups } = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, values)
    return resolveView({ rows, setTree, view: liveView, schema, manualOrder })
  }, [source, values, liveView, schema, manualOrder])
  const ctx = useMemo(() => (tree ? buildResolveContext(tree, schema) : null), [tree, schema])
  const setNames = useMemo(() => buildSetNames(source), [source])

  // Persist the saved view + every live override (order + collapse) + a patch, so no one mutation
  // clobbers another's unsaved state — the exact Swift reorder/resize data-loss H-2 guards against.
  const persistView = (patch: Partial<SavedView>): void => {
    void window.nexus.views.save(source.path, source.kind, mergeOverrides(liveView, widthOverride, collapsed, patch))
  }
  const toggleCollapse = (key: string): void => {
    const next = new Set(collapsed)
    if (next.has(key)) next.delete(key)
    else next.add(key)
    setCollapsed(next)
    persistView({ collapsed_groups: [...next] })
  }
  const reorderColumn = (activeId: string, overId: string): void => {
    const next = reorderColumns(
      columns.map((c) => c.id),
      liveView.property_order,
      activeId,
      overId
    )
    setOrderOverride(next)
    persistView({ property_order: next })
  }
  // Resize applies live (a separate override, so the pipeline doesn't re-run) and returns the clamped
  // width so the header tracks the real edge; commit persists the merged widths.
  const resizeColumn = (id: string, width: number): number => {
    const clamped = clampWidth(Math.round(width), id, schema)
    setWidthOverride((prev) => ({ ...prev, [id]: clamped }))
    return clamped
  }
  const commitResize = (id: string, width: number): void => {
    persistView({ column_widths: { ...liveView.column_widths, ...widthOverride, [id]: clampWidth(width, id, schema) } })
  }
  // Hide animates the column shut on the disclosure token (E-11): setCollapsing drives its <col> to
  // width 0; commitHide fires on that col's transitionend, dropping it from the pipeline + persisting.
  const hideColumn = (id: string): void => {
    setHeaderMenu(null)
    setCollapsing(id)
  }
  const commitHide = (id: string): void => {
    if (collapsing !== id) return
    const hidden = [...(liveView.hidden_properties ?? []), id]
    setCollapsing(null)
    setHiddenOverride(hidden)
    persistView({ hidden_properties: hidden })
  }
  // Right-click a header → menu below it (E-1). Positioned at the .table-view level, not in the th
  // (whose overflow would clip it). Title is the primary column — not hideable, so no menu.
  const openHeaderMenu = (id: string, hideable: boolean, e: React.MouseEvent): void => {
    e.preventDefault()
    const th = e.currentTarget as HTMLElement
    const tv = th.closest('.table-view')
    if (!hideable || !tv) return
    const thR = th.getBoundingClientRect()
    const tvR = tv.getBoundingClientRect()
    setHeaderMenu({ id, left: thR.left - tvR.left, top: thR.bottom - tvR.top })
  }

  if (!ctx) return <div className="table-empty">Loading…</div>
  if (groups.length === 0) return <div className="table-empty">No pages here</div>

  // Saved widths are clamped to the type's [min, max] (Q-4) — a stale/out-of-range saved value can't
  // squash a column below legibility or stretch it past its cap.
  const colWidth = (id: string): number =>
    collapsing === id
      ? 0
      : clampWidth(widthOverride[id] ?? liveView.column_widths?.[id] ?? widthFor(id, schema).default, id, schema)
  const totalWidth = GUTTER_W + columns.reduce((sum, c) => sum + colWidth(c.id), 0)
  // Per-layer indent on the title cell + group headers (J-3), DRY via the --table-indent / pad-x vars.
  const indent = (depth: number): string | undefined =>
    depth > 0 ? `calc(var(--table-pad-x) + var(--table-indent) * ${depth})` : undefined

  // Row drag (E-3): the flat data-row order + each row's group key, feeding the vertical SortableZone.
  // canReorderRow confines a drop to the SAME group for now — cross-group reassignment is D-4 (Task 13d).
  const dataRows: { id: string; groupKey: string }[] = []
  const collectRows = (g: ResolvedGroup): void => {
    for (const r of g.items) dataRows.push({ id: r.id, groupKey: g.key })
    for (const c of g.children ?? []) collectRows(c)
  }
  groups.forEach(collectRows)
  const rowGroup = new Map(dataRows.map((r) => [r.id, r.groupKey] as const))
  const canReorderRow = (a: string, o: string): boolean => rowGroup.get(a) === rowGroup.get(o)
  const reorderRow = (activeId: string, overId: string): void => {
    const next = reorder(
      dataRows.map((r) => ({ id: r.id })),
      activeId,
      overId
    ).map((o) => o.id)
    setManualOverride(next)
    void window.nexus.viewOrders.set(view.id, next)
  }

  const renderRows = (g: ResolvedGroup, depth: number): React.JSX.Element[] => {
    const out: React.JSX.Element[] = []
    const isCollapsed = collapsed.has(g.key)
    if (g.kind !== 'ungrouped') {
      out.push(
        <tr key={`gh-${g.key}`} className="group-header-row">
          <td colSpan={columns.length + 2} style={{ paddingLeft: depth > 0 ? `calc(var(--table-indent) * ${depth})` : 0 }}>
            <GroupHeader
              group={g}
              view={liveView}
              ctx={ctx}
              setNames={setNames}
              collapsed={isCollapsed}
              onToggle={() => toggleCollapse(g.key)}
            />
          </td>
        </tr>
      )
      if (isCollapsed) return out
    }
    for (const row of g.items) {
      out.push(
        <DataRow
          key={row.id}
          row={row}
          columns={columns}
          ctx={ctx}
          depth={depth}
          indent={indent}
          hideIcon={liveView.hide_page_icons ?? false}
          selected={selection.kind === 'page' && selection.id === row.id}
          onSelect={() => void select({ kind: 'page', id: row.id, path: row.path })}
        />
      )
    }
    for (const child of g.children ?? []) out.push(...renderRows(child, depth + 1))
    return out
  }

  return (
    <div className="table-view">
      <table className={cx('data-table', text.body.standard, liveView.hide_borders && 'no-borders')} style={{ minWidth: totalWidth }}>
        <colgroup>
          {/* Left gutter column for the per-row drag grip (E-3). */}
          <col style={{ width: GUTTER_W }} />
          {columns.map((c) => (
            <col
              key={c.id}
              className={cx(collapsing === c.id && 'col-collapsing')}
              style={{ width: colWidth(c.id) }}
              onTransitionEnd={() => commitHide(c.id)}
            />
          ))}
          {/* Filler column absorbs pane width past the summed columns so the grid spans full-width. */}
          <col className="col-filler" />
        </colgroup>
        <thead>
          <tr>
            <th className="cell-gutter" aria-hidden="true" />
            {/* Headers are a horizontal sortable zone (E-2); the filler th sits outside it, inert. */}
            <SortableZone items={columns.map((c) => c.id)} axis="x" bounds="parent" itemRole={null} onReorder={reorderColumn}>
              {columns.map((c) => (
                <ColumnHeader
                  key={c.id}
                  id={c.id}
                  label={columnLabel(c.id, schema, ctx.labels)}
                  width={colWidth(c.id)}
                  onResize={resizeColumn}
                  onResizeCommit={commitResize}
                  onContextMenu={(e) => openHeaderMenu(c.id, c.kind !== 'title', e)}
                />
              ))}
            </SortableZone>
            <th className="cell-filler" aria-hidden="true" />
          </tr>
        </thead>
        <tbody>
          {/* Rows are a vertical sortable zone (E-3); the group-header rows aren't drag items. */}
          <SortableZone items={dataRows.map((r) => r.id)} axis="y" itemRole={null} canReorder={canReorderRow} onReorder={reorderRow}>
            {groups.flatMap((g) => renderRows(g, 0))}
          </SortableZone>
        </tbody>
      </table>
      {headerMenu && (
        <ColumnMenu
          left={headerMenu.left}
          top={headerMenu.top}
          onHide={() => hideColumn(headerMenu.id)}
          onClose={() => setHeaderMenu(null)}
        />
      )}
    </div>
  )
}

/** One column header: draggable to reorder (E-2 — `handle` makes the th the grab surface, ghosted via
 *  `isDragging`) plus a right-edge resize strip (H-2). The strip stops propagation so a resize never
 *  starts a reorder; the pointer delta is divided by the live zoom so a screen drag maps onto the
 *  table's pre-zoom <col> width. */
function ColumnHeader({
  id,
  label,
  width,
  onResize,
  onResizeCommit,
  onContextMenu
}: {
  id: string
  label: string
  width: number
  onResize: (id: string, width: number) => number
  onResizeCommit: (id: string, width: number) => void
  onContextMenu?: (e: React.MouseEvent) => void
}): React.JSX.Element {
  const { setNodeRef, style, handle, isDragging } = useDragItem(id)
  const startResize = (e: React.PointerEvent<HTMLSpanElement>): void => {
    e.preventDefault()
    e.stopPropagation()
    const grip = e.currentTarget
    const th = grip.closest('th')
    const zoom = (th && th.getBoundingClientRect().width / width) || 1
    const startX = e.clientX
    let last = width
    grip.setPointerCapture(e.pointerId)
    const move = (ev: PointerEvent): void => {
      last = onResize(id, width + (ev.clientX - startX) / zoom)
    }
    const end = (): void => {
      grip.removeEventListener('pointermove', move)
      grip.removeEventListener('pointerup', end)
      grip.removeEventListener('pointercancel', end)
      onResizeCommit(id, last)
    }
    grip.addEventListener('pointermove', move)
    grip.addEventListener('pointerup', end)
    grip.addEventListener('pointercancel', end)
  }
  return (
    <th ref={setNodeRef} style={style} className={cx(isDragging && 'col-dragging')} {...handle} onContextMenu={onContextMenu}>
      {label}
      <span className="col-resizer" onPointerDown={startResize} />
    </th>
  )
}

/** One data row + its hover-revealed drag grip (E-3 / H-5). The grip in the left gutter is the only
 *  drag surface; useDragItem ghosts the row while it's lifted. */
function DataRow({
  row,
  columns,
  ctx,
  depth,
  indent,
  hideIcon,
  selected,
  onSelect
}: {
  row: ViewRow
  columns: ResolvedColumn[]
  ctx: ResolveContext
  depth: number
  indent: (depth: number) => string | undefined
  hideIcon: boolean
  selected: boolean
  onSelect: () => void
}): React.JSX.Element {
  const { setNodeRef, style, handle, isDragging } = useDragItem(row.id)
  return (
    <tr
      ref={setNodeRef}
      style={style}
      className={cx('data-row', selected && 'selected', isDragging && 'row-dragging')}
      onClick={() => {
        if (!isDragging) onSelect() // a drag-release isn't a select — the engine keeps isDragging set through the drop
      }}
    >
      <td className="cell-gutter">
        <span className="row-grip" {...handle} onClick={(e) => e.stopPropagation()} aria-label="Drag to reorder">
          <Icon name="grip-vertical" size={14} />
        </span>
      </td>
      {columns.map((c, i) => (
        <td key={c.id} style={i === 0 ? { paddingLeft: indent(depth) } : undefined}>
          <Cell row={row} column={c} ctx={ctx} hideIcon={hideIcon} />
        </td>
      ))}
      <td className="cell-filler" />
    </tr>
  )
}
