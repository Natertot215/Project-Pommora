import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, NexusTree, ResolvedColumn, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import { type SavedView, mintDefaultView } from '@shared/views'
import { applyPropertyValue } from '@shared/propertyValue'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { declaredType } from '../pipeline/value'
import { useSession } from '../../../store'
import { buildResolveContext, type ResolveContext } from './resolveContext'
import { buildSetNames } from './cellResolve'
import { Cell } from './Cell'
import { GroupHeader } from './GroupHeader'
import { columnLabel } from './columnLabel'
import { clampWidth, widthFor } from './columnWidths'
import { reorderColumns } from './columnReorder'
import { mergeOverrides } from './viewMerge'
import { groupKeyToValue, REASSIGNABLE_GROUP_TYPES } from './reassign'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { Icon } from '@renderer/design-system/symbols'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'

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
  // Optimistic property patches keyed by page id (cross-group reassignment, D-4): the loaded values
  // never re-read on a write, so a reassigned row re-groups only because this patch feeds the pipeline.
  const [valueOverride, setValueOverride] = useState<Record<string, PageFrontmatter> | null>(null)
  const [activeViewId, setActiveViewId] = useState<string | undefined>(undefined)
  const [viewOrders, setViewOrders] = useState<Record<string, string[]>>({})

  // Lazy value load + active-view pointer + manual-order cache on container open; `cancelled` guards a
  // fast container swap.
  useEffect(() => {
    let cancelled = false
    setValueOverride(null) // canonical values for the new container supersede any optimistic patches
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
  const [collapsing, setCollapsing] = useState<string | null>(null)
  useEffect(() => {
    setOrderOverride(null)
    setWidthOverride({})
    setHiddenOverride(null)
    setManualOverride(null)
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
  const sortKeys = liveView.sort?.length ?? 0
  // The grouped property + whether a cross-group drop can reassign it (D-4): status/select/checkbox map
  // a group key straight to a value; a date bucket doesn't, so date grouping isn't reassignable.
  const groupPropId = liveView.group?.kind === 'property' ? liveView.group.property_id : undefined
  const groupPropType = groupPropId ? declaredType(groupPropId, schema) : undefined
  const canReassign = groupPropType !== undefined && REASSIGNABLE_GROUP_TYPES.has(groupPropType)
  // Within-group reorder needs a single sort key (clamped) or a property group, never a multi-key sort
  // (D-3); cross-group reassignment is independent of the sort count (D-3). The grip shows if either is
  // possible — the structural/flat default stays off pending its page_order-per-set persistence.
  const canReorderWithin = sortKeys < 2 && (sortKeys === 1 || groupPropId !== undefined)
  const dragDisabled = !(canReorderWithin || canReassign)
  // Optimistic property patches feed the pipeline so a reassigned row re-groups before the watcher round-trips.
  const effectiveValues = useMemo(() => (valueOverride ? { ...values, ...valueOverride } : values), [values, valueOverride])
  const { columns, groups } = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, effectiveValues)
    return resolveView({ rows, setTree, view: liveView, schema, manualOrder })
  }, [source, effectiveValues, liveView, schema, manualOrder])
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
    setCollapsing(id)
  }
  const commitHide = (id: string): void => {
    if (collapsing !== id) return
    const hidden = [...(liveView.hidden_properties ?? []), id]
    setCollapsing(null)
    setHiddenOverride(hidden)
    persistView({ hidden_properties: hidden })
  }
  // Right-click a header → native column menu (E-1). Title is the primary column — not hideable, no menu.
  const openHeaderMenu = async (id: string, hideable: boolean, e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    if (!hideable) return
    if ((await window.nexus.columnMenu()) === 'column:hide') hideColumn(id)
  }

  if (!ctx) return <div className="table-empty">Loading…</div>
  if (groups.length === 0) return <div className="table-empty">No pages here</div>

  // Saved widths are clamped to the type's [min, max] (Q-4) — a stale/out-of-range saved value can't
  // squash a column below legibility or stretch it past its cap.
  const colWidth = (id: string): number =>
    collapsing === id
      ? 0
      : clampWidth(widthOverride[id] ?? liveView.column_widths?.[id] ?? widthFor(id, schema).default, id, schema)
  const totalWidth = columns.reduce((sum, c) => sum + colWidth(c.id), 0)
  // Lead-cell + group-header left padding: the pad-x base lands the cell content on the grid (under its
  // column header); each nesting layer adds one --table-indent step (J-3). The grip + chevron live in
  // the views gutter via absolute CSS, independent of this.
  const indent = (depth: number): string =>
    depth > 0 ? `calc(var(--table-pad-x) + var(--table-indent) * ${depth})` : 'var(--table-pad-x)'

  // Row drag (E-3): the flat data-row order + each row's group key + path, feeding the vertical
  // SortableZone. Where you drop disambiguates (D-8) — same group reorders, a different group reassigns.
  const dataRows: { id: string; path: string; groupKey: string }[] = []
  const collectRows = (g: ResolvedGroup): void => {
    for (const r of g.items) dataRows.push({ id: r.id, path: r.path, groupKey: g.key })
    for (const c of g.children ?? []) collectRows(c)
  }
  groups.forEach(collectRows)
  const rowGroup = new Map(dataRows.map((r) => [r.id, r.groupKey] as const))
  const rowPath = new Map(dataRows.map((r) => [r.id, r.path] as const))
  // Cross-group drop (D-4): write the dragged page's grouped property to the destination group's value
  // (the no-value band clears it), patching the loaded values now so the row re-groups before the write
  // round-trips (loadValues never re-runs mid-session).
  const reassignRow = (pageId: string, destGroupKey: string): void => {
    const path = rowPath.get(pageId)
    if (!groupPropId || !path) return
    const value = groupKeyToValue(destGroupKey, groupPropType)
    const prior = values[pageId]
    const patched: PageFrontmatter = {
      ...(prior ?? { id: pageId }),
      properties: applyPropertyValue(prior?.properties, groupPropId, value)
    }
    setValueOverride((prev) => ({ ...prev, [pageId]: patched }))
    void window.nexus.mutate({ op: 'setProperty', path, propertyId: groupPropId, value })
  }
  // Same group → reorder (clamped per D-3/D-6); different group → reassign when the property allows (D-4).
  const canReorderRow = (a: string, o: string): boolean =>
    rowGroup.get(a) === rowGroup.get(o) ? canReorderWithin : canReassign
  const reorderRow = (activeId: string, overId: string): void => {
    const destKey = rowGroup.get(overId)
    if (destKey !== undefined && destKey !== rowGroup.get(activeId)) {
      reassignRow(activeId, destKey)
      return
    }
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
          <td colSpan={columns.length + 1} style={{ paddingLeft: indent(depth) }}>
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
          dragDisabled={dragDisabled}
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
                  onContextMenu={(e) => void openHeaderMenu(c.id, c.kind !== 'title', e)}
                />
              ))}
            </SortableZone>
            <th className="cell-filler" aria-hidden="true" />
          </tr>
        </thead>
        <tbody>
          {/* Rows are a vertical sortable zone (E-3); the group-header rows aren't drag items. */}
          <SortableZone items={dataRows.map((r) => r.id)} axis="y" itemRole={null} disabled={dragDisabled} canReorder={canReorderRow} onReorder={reorderRow}>
            {groups.flatMap((g) => renderRows(g, 0))}
          </SortableZone>
        </tbody>
      </table>
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

/** One data row + its hover-revealed drag grip (E-3 / H-5). The grip sits in the lead cell's gutter
 *  lane — the same slot the group disclosure chevron occupies — so handles align with the chevrons and
 *  the row content lines up with the group headers. useDragItem ghosts the row while it's lifted. */
function DataRow({
  row,
  columns,
  ctx,
  depth,
  indent,
  hideIcon,
  selected,
  dragDisabled,
  onSelect
}: {
  row: ViewRow
  columns: ResolvedColumn[]
  ctx: ResolveContext
  depth: number
  indent: (depth: number) => string | undefined
  hideIcon: boolean
  selected: boolean
  dragDisabled: boolean
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
      {columns.map((c, i) =>
        i === 0 ? (
          <td key={c.id} className="cell-lead" style={{ paddingLeft: indent(depth) }}>
            {!dragDisabled && (
              <span className="row-grip" {...handle} onClick={(e) => e.stopPropagation()} aria-label="Drag to reorder">
                <Icon name="grip-vertical" size={14} />
              </span>
            )}
            <Cell row={row} column={c} ctx={ctx} hideIcon={hideIcon} />
          </td>
        ) : (
          <td key={c.id}>
            <Cell row={row} column={c} ctx={ctx} hideIcon={hideIcon} />
          </td>
        )
      )}
      <td className="cell-filler" />
    </tr>
  )
}
