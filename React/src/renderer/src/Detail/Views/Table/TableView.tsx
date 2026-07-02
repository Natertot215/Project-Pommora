import { useEffect, useMemo, useRef, useState } from 'react'
import type { CollectionNode, NexusTree, ResolvedColumn, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { PropertyDefinition, PropertyType } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import type { ColumnStyle } from '@shared/columnStyles'
import type { CellMenuContext } from '@shared/cellMenu'
import { parseStyleAction } from '@shared/columnMenu'
import { type ColumnAlign, type SavedView, mintDefaultView } from '@shared/views'
import { applyPropertyValue, type PropertyValue } from '@shared/propertyValue'
import { isValidLink, normalizeLinkUrl } from '@shared/links'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { PropertyPicker } from '../PropertyEditing/PropertyPicker'
import { nextCycleValue } from '../PropertyEditing/statusCycle'
import { useSession } from '../../../store'
import { buildResolveContext, type ResolveContext } from './resolveContext'
import { buildSetIcons, buildSetNames } from './cellResolve'
import { Cell } from './Cell'
import { GroupHeader } from './GroupHeader'
import { columnLabel, TIER_LEVEL_BY_ID } from './columnLabel'
import { clampWidth, widthFor } from './columnWidths'
import { alignFor } from './columnAlign'
import { styleFor } from './columnStyles'
import { reorderColumns } from './columnReorder'
import { mergeOverrides, mergeStyleRecords } from './viewMerge'
import { groupKeyToValue, REASSIGNABLE_GROUP_TYPES } from './reassign'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { IconPicker } from '@renderer/Components/IconPicker'
import { Icon } from '@renderer/design-system/symbols'
import { Reveal } from '@renderer/design-system/components/Reveal'
import { ACTIVATION } from '@renderer/design-system/interactions/shared'
import { TableRowDnd, useTableRowDrag } from './tableDnd'

// ── TUNABLE ── how far past a column's edge the dragged column's centre must travel before the slot
// flips (the sticky zone around the current slot). Larger = more deliberate / harder to leave a slot;
// smaller = snappier. Bump this one number to taste.
const COL_SHIFT_HYSTERESIS = 25

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

/** The right-click menu context for a cell (A-13): title = page meta; url/file = the column's Style
 *  radios + Edit; status = Style + Clear; the other style-bearing types = Style alone; tier and
 *  select/multi/context = Clear alone. Anything else has no menu (null). */
function cellMenuContextFor(
  col: ResolvedColumn,
  type: PropertyType | 'title' | 'tier' | undefined,
  style: ColumnStyle
): CellMenuContext | null {
  if (col.kind === 'title') return { kind: 'title' }
  if (col.kind === 'tier') return { kind: 'clear-only' }
  if (type === 'url' || type === 'file') return { kind: 'style-edit', type, current: style }
  if (type === 'status') return { kind: 'style-only', type, current: style, clearable: true }
  if (type === 'checkbox' || type === 'number' || type === 'datetime' || type === 'last_edited_time') {
    return { kind: 'style-only', type, current: style }
  }
  if (type === 'select' || type === 'multi_select' || type === 'context') return { kind: 'clear-only' }
  return null
}

export function TableView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)
  // The store's one write path — runs the op AND refetches immediately (load()), so a table reorder /
  // reassign propagates to the sidebar right away instead of waiting on the fs watcher's settle (~1s).
  const mutate = useSession((s) => s.mutate)
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
  const [alignOverride, setAlignOverride] = useState<Record<string, ColumnAlign>>({})
  const [styleOverride, setStyleOverride] = useState<Record<string, ColumnStyle>>({})
  const [hiddenOverride, setHiddenOverride] = useState<string[] | null>(null)
  const [manualOverride, setManualOverride] = useState<string[] | null>(null)
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set(view.collapsed_groups ?? []))
  const [collapsing, setCollapsing] = useState<string | null>(null)
  // Live column smooth-shift (A-4): the dragged column index, the slot it's over, and the cursor delta.
  // Transient — set on grab, cleared on drop; column indices into the resolved `columns`.
  const [colDrag, setColDrag] = useState<{ from: number; to: number; delta: number } | null>(null)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)
  // Columns fit → the rounded content-inset look; columns overflow → the right inset flattens and
  // the table h-scrolls to the glass edge (the left gutter holds). One read per pane resize /
  // track-set change — never per scroll or per pointermove.
  const viewRef = useRef<HTMLDivElement>(null)
  const [overflowing, setOverflowing] = useState(false)
  const overflowingRef = useRef(false)
  overflowingRef.current = overflowing
  // The one in-cell editing surface (A-2/A-6 picker · A-8/A-12 editor). Cleared on dismiss; the
  // exit presence keeps a PICKER mounted through its Bloom-out (reading the last target from the
  // ref while `editing` is already null) — the editor unmounts instantly.
  const [editing, setEditing] = useState<{ rowId: string; colId: string; mode: 'picker' | 'editor' } | null>(null)
  const editingExit = useExitPresence(editing !== null)
  const lastEditing = useRef(editing)
  if (editing) lastEditing.current = editing
  useEffect(() => {
    setOrderOverride(null)
    setWidthOverride({})
    setAlignOverride({})
    setStyleOverride({})
    setHiddenOverride(null)
    setManualOverride(null)
    setCollapsing(null)
    setColDrag(null)
    setCollapsed(new Set(view.collapsed_groups ?? []))
  }, [view.id])
  // A fresh tree (an external mutation — e.g. a sidebar reorder — or this table's own write round-tripping
  // back) carries the canonical page_order/values, so drop the optimistic order + value patches that were
  // masking it. Without this a reorder/reassign here pins its optimistic state and a later external change
  // wouldn't show until the view remounts.
  useEffect(() => {
    setManualOverride(null)
    setValueOverride(null)
  }, [source])
  const liveView = useMemo(() => {
    if (!orderOverride && !hiddenOverride) return view
    return {
      ...view,
      property_order: orderOverride ?? view.property_order,
      hidden_properties: hiddenOverride ?? view.hidden_properties
    }
  }, [view, orderOverride, hiddenOverride])
  // Manual row order (viewOrders cache) is the sort tiebreaker (D-5/D-6) — passed to the pipeline when
  // the view is sorted or grouped (an unsorted, ungrouped view otherwise reads canonical page_order). A
  // live `manualOverride` also feeds it so an unsorted-flat reorder shows instantly (before its page_order
  // write round-trips the fs) rather than snapping back.
  const sortedOrGrouped = (liveView.sort?.length ?? 0) > 0 || liveView.group != null
  const manualOrder =
    sortedOrGrouped || manualOverride ? (manualOverride ?? viewOrders[view.id]) : undefined
  const sortKeys = liveView.sort?.length ?? 0
  // The grouped property + whether a cross-group drop can reassign it (D-4): status/select/checkbox map
  // a group key straight to a value; a date bucket doesn't, so date grouping isn't reassignable.
  const groupPropId = liveView.group?.kind === 'property' ? liveView.group.property_id : undefined
  const groupPropType = groupPropId ? declaredType(groupPropId, schema) : undefined
  const canReassign = groupPropType !== undefined && REASSIGNABLE_GROUP_TYPES.has(groupPropType)
  // Within-group reorder is possible whenever the order is manually meaningful — anything but a multi-key
  // sort (D-3). Unsorted structural/flat views write the canonical on-disk page_order (reorderTo → movePage);
  // single-sorted / property-grouped views write the per-view manual tiebreaker (viewOrders). Cross-group
  // reassignment is independent of the sort count.
  const canReorderWithin = sortKeys < 2
  const structuralOrder = groupPropId === undefined && sortKeys === 0
  const dragDisabled = !(canReorderWithin || canReassign)
  // Optimistic property patches feed the pipeline so a reassigned row re-groups before the watcher round-trips.
  const effectiveValues = useMemo(() => (valueOverride ? { ...values, ...valueOverride } : values), [values, valueOverride])
  const { columns, groups } = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, effectiveValues)
    return resolveView({ rows, setTree, view: liveView, schema, manualOrder })
  }, [source, effectiveValues, liveView, schema, manualOrder])
  const ctx = useMemo(() => (tree ? buildResolveContext(tree, schema) : null), [tree, schema])
  // One mounted observer, two targets: the view (pane resizes) and the grid (its box moves when
  // the track set changes — a column resize/hide/add). Each fires one cheap read, never per-scroll.
  // Fit is measured against the pane AS COMPRESSED by the inspector, whether or not the hover
  // override has already lifted that compression — a fitting table gives way to the inspector, an
  // overflowing one keeps its width and scrolls under the glass (Nathan's conditional), and
  // measuring the hypothetical width is what keeps the boundary band from oscillating.
  useEffect(() => {
    const el = viewRef.current
    if (!el) return
    const check = (): void => {
      const shell = el.closest('.shell')
      const open = shell?.classList.contains('inspector-open') ?? false
      const lifted = open && overflowingRef.current
      const cs = lifted && shell ? getComputedStyle(shell) : null
      const liftedBy = cs
        ? Number.parseFloat(cs.getPropertyValue('--inspector-width')) + Number.parseFloat(cs.getPropertyValue('--glass-inset'))
        : 0
      setOverflowing(el.scrollWidth > el.clientWidth - (Number.isNaN(liftedBy) ? 0 : liftedBy) + 1)
    }
    check()
    const ro = new ResizeObserver(check)
    ro.observe(el)
    const grid = el.querySelector('.table-grid')
    if (grid) ro.observe(grid)
    return () => ro.disconnect()
    // biome-ignore lint/correctness/useExhaustiveDependencies: re-bind once the loading return gives way to the real grid.
  }, [ctx === null])
  const setNames = useMemo(() => buildSetNames(source), [source])
  const setIcons = useMemo(() => buildSetIcons(source), [source])

  // Persist the saved view + every live override (order + collapse) + a patch, so no one mutation
  // clobbers another's unsaved state — the exact Swift reorder/resize data-loss H-2 guards against.
  const persistView = (patch: Partial<SavedView>): void => {
    void window.nexus.views.save(
      source.path,
      source.kind,
      mergeOverrides(liveView, widthOverride, alignOverride, collapsed, patch, styleOverride)
    )
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
  // Hide animates the column shut on the disclosure token (E-11): setCollapsing drives its grid track to
  // 0 (colWidth → 0, animated via .col-hiding); commitHide fires on the header's grid-template-columns
  // transitionend, dropping the column from the pipeline + persisting.
  const hideColumn = (id: string): void => {
    setCollapsing(id)
  }
  const commitHide = (): void => {
    if (!collapsing) return
    const hidden = [...(liveView.hidden_properties ?? []), collapsing]
    setCollapsing(null)
    setHiddenOverride(hidden)
    persistView({ hidden_properties: hidden })
  }
  // A column's resolved alignment (E-5..E-7): the live override, else the saved value / E-6 type default.
  const colAlign = (id: string): ColumnAlign => alignOverride[id] ?? alignFor(id, schema, liveView)
  // A column's resolved display style (B-1..B-5): the live override keys, over the saved per-view
  // entry, over the type default.
  const colStyle = (id: string): ColumnStyle => ({ ...styleFor(id, schema, liveView), ...styleOverride[id] })
  // Set one style key: applies live via the override, persists per-key into column_styles — the align
  // pattern; the patch carries the not-yet-committed value so a state-batch can't drop it.
  const setColumnStyle = (id: string, key: keyof ColumnStyle & string, value: string): void => {
    const merged = { ...styleOverride[id], [key]: value } as ColumnStyle
    setStyleOverride((prev) => ({ ...prev, [id]: merged }))
    persistView({ column_styles: mergeStyleRecords(liveView.column_styles, { ...styleOverride, [id]: merged }) })
  }
  // Set a column's alignment: applies live via the override, persists to the SavedView column_alignments.
  const setColumnAlign = (id: string, align: ColumnAlign): void => {
    setAlignOverride((prev) => ({ ...prev, [id]: align }))
    persistView({ column_alignments: { ...liveView.column_alignments, ...alignOverride, [id]: align } })
  }
  // Right-click a header → native column menu (E-1/E-5): Align + Style + Hide. Title is the primary
  // column — fixed left, not hideable, no style — so it pops nothing. The style ctx rides only for a
  // schema-declared property type; the shared builder decides which types actually get items.
  const openHeaderMenu = async (id: string, isTitle: boolean, e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const t = declaredType(id, schema)
    const style = t !== undefined && t !== 'title' && t !== 'tier' ? { type: t, current: colStyle(id) } : undefined
    const action = await window.nexus.columnMenu({ align: colAlign(id), alignable: !isTitle, hideable: !isTitle, style })
    if (action === 'column:hide') hideColumn(id)
    else if (action?.startsWith('align:')) setColumnAlign(id, action.slice('align:'.length) as ColumnAlign)
    else if (action?.startsWith('style:')) {
      const parsed = parseStyleAction(action)
      if (parsed) setColumnStyle(id, parsed.key, parsed.value)
    }
  }
  // One typed property write (A-12's commit path): patch the row's loaded frontmatter optimistically
  // (loadValues never re-runs mid-session), then setProperty — the reassignRow pattern.
  const commitCellValue = (row: ViewRow, propertyId: string, value: PropertyValue | null): void => {
    const patched: PageFrontmatter = {
      ...row.frontmatter,
      properties: applyPropertyValue(row.frontmatter.properties, propertyId, value)
    }
    setValueOverride((prev) => ({ ...prev, [row.id]: patched }))
    void mutate({ op: 'setProperty', path: row.path, propertyId, value })
  }
  // A context column's pickable list — the NEXUS's contexts for its tier (reserved tier columns
  // read their fixed level; a user context prop reads its def's target tier). Null for anything else.
  const contextOptionsFor = (col: ResolvedColumn): Array<{ value: string; label: string; color?: string }> | null => {
    const level = col.kind === 'tier' ? TIER_LEVEL_BY_ID[col.id] : schema.find((d) => d.id === col.id)?.context_target?.tier
    if (!level || !tree) return null
    const list = level === 1 ? tree.contexts.areas : level === 2 ? tree.contexts.topics : tree.contexts.projects
    return list.map((c) => ({ value: c.id, label: c.title, ...('color' in c && c.color ? { color: c.color } : {}) }))
  }
  // A reserved tier column writes the BARE frontmatter array (`tier1/2/3`) through its own op;
  // a user context prop writes through setProperty like every other property value.
  const commitTierValue = (row: ViewRow, colId: string, ids: string[]): void => {
    const tier = TIER_LEVEL_BY_ID[colId]
    const patched = { ...row.frontmatter, [`tier${tier}`]: ids } as PageFrontmatter
    setValueOverride((prev) => ({ ...prev, [row.id]: patched }))
    void mutate({ op: 'setTier', path: row.path, tier, contextIds: ids })
  }
  // Single-click acts per the cell's type (A-2/A-4/A-6): checkbox-look status cycles its group,
  // checkbox toggles, status/select/multi/context open the picker. Acting stops propagation so the
  // row's select doesn't also fire; anything else bubbles.
  const onCellClick = (row: ViewRow, col: ResolvedColumn, e: React.MouseEvent): void => {
    if (col.kind === 'title') {
      // The ONLY navigate (A-7): row-click narrowed to the title cell; row background is a no-op.
      e.stopPropagation()
      void select({ kind: 'page', id: row.id, path: row.path })
      return
    }
    if (col.kind === 'tier') {
      e.stopPropagation()
      setEditing({ rowId: row.id, colId: col.id, mode: 'picker' })
      return
    }
    if (col.kind !== 'property') return
    const t = declaredType(col.id, schema)
    if (t === 'status' && colStyle(col.id).look === 'checkbox') {
      e.stopPropagation()
      const v = resolveFieldValue(row, col.id)
      const current = v.kind === 'status' || v.kind === 'select' ? v.value : undefined
      if (current === undefined) {
        // An EMPTY checkbox-look cell never cycles (a blind write) — it opens the picker to assign.
        setEditing({ rowId: row.id, colId: col.id, mode: 'picker' })
        return
      }
      const next = nextCycleValue(current, schema.find((d) => d.id === col.id))
      if (next !== null) commitCellValue(row, col.id, { kind: 'status', value: next })
    } else if (t === 'checkbox') {
      e.stopPropagation()
      const v = resolveFieldValue(row, col.id)
      commitCellValue(row, col.id, { kind: 'checkbox', value: !(v.kind === 'checkbox' && v.value) })
    } else if (t === 'status' || t === 'select' || t === 'multi_select' || t === 'context') {
      e.stopPropagation()
      setEditing({ rowId: row.id, colId: col.id, mode: 'picker' })
    } else if (t === 'number') {
      e.stopPropagation()
      setEditing({ rowId: row.id, colId: col.id, mode: 'editor' })
    }
  }
  // What the inline editor starts from, per the column's value shape.
  const editorInitial = (row: ViewRow, col: ResolvedColumn): string => {
    if (col.kind === 'title') return row.title
    const v = resolveFieldValue(row, col.id)
    if (v.kind === 'number') return String(v.value)
    if (v.kind === 'url') return v.value
    if (v.kind === 'file') return v.value[0]?.path ?? ''
    return ''
  }
  // Map the editor's raw text to its typed write (A-12): number parses (a lone '-'/'.' reverts),
  // url validates + normalizes, file edits the FIRST ref's path (multi-file editing is the picker
  // Prospect), title renames. Empty input clears the value.
  const commitEditorText = (row: ViewRow, col: ResolvedColumn, raw: string): void => {
    setEditing(null)
    const trimmed = raw.trim()
    if (col.kind === 'title') {
      if (trimmed && trimmed !== row.title) void mutate({ op: 'rename', path: row.path, kind: 'page', newName: trimmed })
      return
    }
    const t = declaredType(col.id, schema)
    if (t === 'number') {
      if (trimmed === '') return commitCellValue(row, col.id, null)
      const n = Number.parseFloat(trimmed)
      if (!Number.isNaN(n)) commitCellValue(row, col.id, { kind: 'number', value: n })
    } else if (t === 'url') {
      if (trimmed === '') return commitCellValue(row, col.id, null)
      if (isValidLink(trimmed)) commitCellValue(row, col.id, { kind: 'url', value: normalizeLinkUrl(trimmed) })
    } else if (t === 'file') {
      const v = resolveFieldValue(row, col.id)
      const refs = v.kind === 'file' ? v.value : []
      if (trimmed === '') return commitCellValue(row, col.id, refs.length > 1 ? { kind: 'file', value: refs.slice(1) } : null)
      commitCellValue(row, col.id, { kind: 'file', value: refs.length ? [{ ...refs[0], path: trimmed }, ...refs.slice(1)] : [{ path: trimmed }] })
    }
  }
  // The editing surface mounted in the target cell (null everywhere else). A picker APPENDS below
  // the cell's content and stays through its Bloom-out; the editor REPLACES the content in flow.
  const cellOverlay = (row: ViewRow, col: ResolvedColumn): { node: React.ReactNode; replace: boolean } | null => {
    const target =
      editing ?? (editingExit.mounted && lastEditing.current?.mode === 'picker' ? lastEditing.current : null)
    if (!target || target.rowId !== row.id || target.colId !== col.id) return null
    if (target.mode === 'editor') {
      return {
        replace: true,
        node: (
          <PropertyEditor
            initial={editorInitial(row, col)}
            numeric={declaredType(col.id, schema) === 'number'}
            onCommit={(raw) => commitEditorText(row, col, raw)}
            onCancel={() => setEditing(null)}
          />
        )
      }
    }
    const contextOptions = contextOptionsFor(col)
    // A reserved tier column has no schema def — a minimal synthetic one satisfies the picker,
    // whose options come from `contextOptions` anyway.
    const def = schema.find((d) => d.id === col.id) ?? (contextOptions ? { id: col.id, name: '', type: 'context' as const } : undefined)
    if (!def) return null
    return {
      replace: false,
      node: (
        <PropertyPicker
          def={def}
          current={resolveFieldValue(row, col.id)}
          closing={editingExit.closing}
          look={colStyle(col.id).look}
          {...(contextOptions ? { contextOptions } : {})}
          onCommit={(v) =>
            col.kind === 'tier' && v?.kind === 'context'
              ? commitTierValue(row, col.id, v.value)
              : commitCellValue(row, col.id, v)
          }
          onDismiss={() => setEditing(null)}
        />
      )
    }
  }
  // Right-click a cell → its native menu (A-13: always a menu, never an action). Title = page meta;
  // style-bearing types = the COLUMN's Style radios; link/file add Edit; picker-based cells add
  // Clear (status gets Style + Clear; select/multi/context/tier get Clear alone).
  const openCellMenu = async (row: ViewRow, col: ResolvedColumn, e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    const ctx = cellMenuContextFor(col, declaredType(col.id, schema), colStyle(col.id))
    if (!ctx) return
    const action = await window.nexus.cellMenu(ctx)
    if (!action) return
    if (action === 'title:icon') setIconPickerOpen(true)
    else if (action === 'title:delete') void mutate({ op: 'delete', path: row.path, kind: 'page' })
    else if (action === 'title:rename' || action === 'cell:edit') setEditing({ rowId: row.id, colId: col.id, mode: 'editor' })
    else if (action === 'cell:clear') {
      if (col.kind === 'tier') commitTierValue(row, col.id, [])
      else commitCellValue(row, col.id, null)
    } else if (action.startsWith('style:')) {
      const parsed = parseStyleAction(action)
      if (parsed) setColumnStyle(col.id, parsed.key, parsed.value)
    }
  }

  if (!ctx) return <div className="table-empty">Loading…</div>
  if (groups.length === 0) return <div className="table-empty">No pages here</div>

  // Saved widths are clamped to the type's [min, max] (Q-4) — a stale/out-of-range saved value can't
  // squash a column below legibility or stretch it past its cap.
  const colWidth = (id: string): number =>
    collapsing === id
      ? 0
      : clampWidth(widthOverride[id] ?? liveView.column_widths?.[id] ?? widthFor(id, schema).default, id, schema)
  // The Apple table model (Nathan, reverting the elastic-title reflow): EVERY column — title included —
  // holds its resolved width. While the sum fits the pane the trailing filler eats the slack (the capped,
  // content-inset look); the moment any resize/add pushes the sum past the pane, the grid extends beyond
  // the window and the whole view h-scrolls. No column is ever compressed to absorb growth.
  const reflowWidth = columns.reduce((sum, c) => sum + colWidth(c.id), 0)
  const cols = `${columns.map((c) => `${colWidth(c.id)}px`).join(' ')} 1fr`
  // Lead-cell left padding for ungrouped/loose rows: --loose-inset tucks the title a touch left of the
  // cell-padding-x column inset; each nesting layer adds one --row-indent step (J-3). The grip + chevron
  // live in the views gutter via absolute CSS, independent of this.
  const indent = (depth: number): string =>
    depth > 0 ? `calc(var(--loose-inset) + var(--row-indent) * ${depth})` : 'var(--loose-inset)'
  // A group header's chevron + folder glyph read as one cluster in the views gutter (with the row grips),
  // so the header is indented by nesting ALONE — no cell-padding-x base (that base is the data cells'
  // text inset). Its members keep the normal indent, one --row-indent step inside the header.
  const groupIndent = (depth: number): string => `calc(var(--row-indent) * ${depth})`

  // Column smooth-shift (A-4): grab a header → the whole column (header + every body cell + divider)
  // slides with the cursor, neighbours shifting by the dragged column's width to open the gap, the track
  // order committing on drop. Pointer-captured to the header; move/up on window (the header re-renders
  // mid-drag, so a node-bound listener would drop). `zoom` divides the screen delta back into the grid's
  // pre-zoom track space. The target slot is edge-based: whichever column's span the dragged column's
  // centre sits over, with a sticky hysteresis zone around the current slot. Edge-based (not closest-
  // centre) so a far column can't shift while the dragged one is still mid-traverse over a wide neighbour.
  // gridLeft is read live so the edges stay correct under a horizontal scroll.
  const startColumnDrag = (e: React.PointerEvent, from: number): void => {
    if (e.button !== 0) return // left-button drags; a right-press falls through to the column menu
    e.preventDefault()
    const header = e.currentTarget as HTMLElement
    const grid = header.closest('.table-grid') as HTMLElement | null
    if (!grid) return
    header.setPointerCapture(e.pointerId)
    const hr = header.getBoundingClientRect()
    // The CSS density factor (screen px per pre-zoom track px). Read from --zoom directly, NOT back-solved
    // from the header's rendered width ÷ its track width — the title track is now a minmax that shrinks, so
    // that ratio no longer equals the zoom when the title is grabbed while shrunk.
    const zoom = Number.parseFloat(getComputedStyle(grid).getPropertyValue('--zoom')) || 1
    const startCenter = hr.left + hr.width / 2 // the dragged column's centre, screen px; it tracks the cursor 1:1
    const startX = e.clientX
    const startY = e.clientY
    // null until the pointer travels ACTIVATION px — a sub-threshold press is a click, not a drag, so the
    // highlight band never flashes and a jittery click can't reorder.
    let current: { from: number; to: number; delta: number } | null = null
    const onMove = (ev: PointerEvent): void => {
      if (!current && Math.hypot(ev.clientX - startX, ev.clientY - startY) < ACTIVATION) return
      const gridLeft = grid.getBoundingClientRect().left
      const projected = startCenter + (ev.clientX - startX)
      const cur = current?.to ?? from
      // Edge-based slot: which column's span the dragged column's centre is actually over. Hold the
      // current slot until the centre leaves its span by COL_SHIFT_HYSTERESIS (a sticky zone — no flicker
      // at a boundary). This is correct for wildly-varying widths where a closest-centre rule would let a
      // far column shift while the dragged one is still mid-traverse over a wide neighbour (e.g. Title).
      let curLeft = gridLeft
      for (let i = 0; i < cur; i++) curLeft += colWidth(columns[i].id) * zoom
      const curRight = curLeft + colWidth(columns[cur].id) * zoom
      let to = cur
      if (projected < curLeft - COL_SHIFT_HYSTERESIS || projected > curRight + COL_SHIFT_HYSTERESIS) {
        let edge = gridLeft
        to = columns.length - 1
        for (let i = 0; i < columns.length; i++) {
          edge += colWidth(columns[i].id) * zoom
          if (projected < edge) {
            to = i
            break
          }
        }
      }
      current = { from, to, delta: (ev.clientX - startX) / zoom }
      setColDrag(current)
    }
    // A committed release reorders (move + clear batch into one render — reorderColumn is React state —
    // so the settle is a single frame, no snap-back flash); a no-op release (own slot / un-armed click)
    // and a pointercancel (OS/gesture abort — the escape hatch) just clear without reordering.
    const finish = (ev: PointerEvent, commit: boolean): void => {
      // Cleanup FIRST + unconditionally: detach the window listeners and clear the drag before anything
      // that can throw, so a lost-capture release or a mid-drag `columns` remount can't strand the gesture
      // (leaked listener + stuck band). The release is guarded, and the indices are bounds-checked against
      // a `columns` that may have shrunk under a watcher update since grab time.
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onCancel)
      try {
        header.releasePointerCapture(ev.pointerId)
      } catch {
        // capture already released
      }
      if (current) {
        const { from: f, to: t } = current
        if (commit && t !== f && f < columns.length && t < columns.length) {
          reorderColumn(columns[f].id, columns[t].id)
        }
        setColDrag(null)
      }
    }
    const onUp = (ev: PointerEvent): void => finish(ev, true)
    const onCancel = (ev: PointerEvent): void => finish(ev, false)
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    window.addEventListener('pointercancel', onCancel)
  }
  // The per-column translateX for the current drag: the subject tracks the cursor (delta); the columns
  // between its source and target slot shift by the subject's width to open the gap (D-2-style).
  const colTransform = (ci: number): string | undefined => {
    if (!colDrag) return undefined
    const { from, to, delta } = colDrag
    if (ci === from) return `translateX(${delta}px)`
    const w = colWidth(columns[from].id)
    if (to < from && ci >= to && ci < from) return `translateX(${w}px)`
    if (to > from && ci > from && ci <= to) return `translateX(${-w}px)`
    return undefined
  }

  // Row drag (E-3): the flat data-row order + each row's group key + path, feeding the drop-line DnD
  // (tableDnd). Where you drop disambiguates (D-8) — same group reorders, a different group reassigns.
  // The flat data-row order + id→path / id→group maps, derived purely from the resolved groups — memoized
  // so a selection / resize / drag-frame render doesn't re-walk every group and rebuild both Maps.
  const { dataRows, rowPath, rowGroup } = useMemo(() => {
    const rows: { id: string; path: string; groupKey: string }[] = []
    const collect = (g: ResolvedGroup): void => {
      for (const r of g.items) rows.push({ id: r.id, path: r.path, groupKey: g.key })
      for (const c of g.children ?? []) collect(c)
    }
    groups.forEach(collect)
    return {
      dataRows: rows,
      rowPath: new Map(rows.map((r) => [r.id, r.path] as const)),
      rowGroup: new Map(rows.map((r) => [r.id, r.groupKey] as const))
    }
  }, [groups])
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
    void mutate({ op: 'setProperty', path, propertyId: groupPropId, value })
  }
  // Within-group reorder commit — tableDnd hands the new flat order + the reordered group's key. An
  // unsorted structural/flat view is ordered by the canonical on-disk page_order, so it writes that
  // group's container page_order (movePage, same parent = a pure reorder — the whole point of a
  // filesystem-first table). A sorted / property-grouped view instead writes the per-view manual
  // tiebreaker (viewOrders). setManualOverride gives instant feedback either way: the pipeline reads it
  // as the sort tiebreaker, and it agrees with the page_order the fs reload brings back.
  const reorderTo = (orderIds: string[], groupKey: string): void => {
    setManualOverride(orderIds)
    if (structuralOrder) {
      const groupPages = orderIds.filter((id) => rowGroup.get(id) === groupKey)
      const firstPath = groupPages.length ? rowPath.get(groupPages[0]) : undefined
      if (firstPath) {
        const containerPath = firstPath.slice(0, firstPath.lastIndexOf('/'))
        void mutate({ op: 'movePage', path: firstPath, newParentPath: containerPath, order: groupPages })
      }
      return
    }
    void window.nexus.viewOrders.set(view.id, orderIds)
  }

  // A row drops its top divider (.row-lead) only when no VISIBLE data row sits directly above it — the
  // divider is a between-rows line. Headered groups: their first row follows the header, so it's always
  // lead. The ungrouped band has no header, so its first row is lead until a visible row precedes it.
  // `renderedAnyRow` counts only rows that actually render: a collapsed group's items build (the .map runs)
  // but never mount, so they mustn't mark it — else the band after a collapsed group keeps a stray divider
  // with nothing above it. `visible` carries each group's shown/hidden state down through nesting.
  let renderedAnyRow = false
  const renderRows = (g: ResolvedGroup, depth: number, visible: boolean): React.JSX.Element[] => {
    const isCollapsed = collapsed.has(g.key)
    const itemsVisible = visible && !isCollapsed
    // A headered group's members (+ any nested child group) sit one nesting step INSIDE it (a --row-indent
    // step, via indent()), so the disclosure hierarchy reads — you can see what's within a group vs the
    // base level. The ungrouped root band has no header, so its rows stay flush at the base indent.
    const itemDepth = g.kind === 'ungrouped' ? depth : depth + 1
    // A headered group's pages nest in the same gutter-anchored lane as its glyph (groupIndent, no
    // cell-pad base) — so they nudge left with the folder and sit one --row-indent step inside it; the
    // ungrouped root keeps the normal indent (its rows land under the Title column).
    const memberIndent = g.kind === 'ungrouped' ? indent : groupIndent
    const members: React.JSX.Element[] = [
      ...g.items.map((row, i) => {
        const lead = i === 0 && (g.kind !== 'ungrouped' || !renderedAnyRow)
        if (itemsVisible) renderedAnyRow = true
        return (
          <DataRow
            key={row.id}
            row={row}
            columns={columns}
            ctx={ctx}
            depth={itemDepth}
            indent={memberIndent}
            colTransform={colTransform}
            colAlign={colAlign}
            colStyle={colStyle}
            draggingCol={colDrag?.from}
            hideIcon={liveView.hide_page_icons ?? false}
            selected={selection.kind === 'page' && selection.id === row.id}
            dragDisabled={dragDisabled}
            lead={lead}
            onCellMenu={(c, e) => void openCellMenu(row, c, e)}
            onCellClick={(c, e) => onCellClick(row, c, e)}
            overlay={(c) => cellOverlay(row, c)}
          />
        )
      }),
      ...(g.children ?? []).flatMap((child) => renderRows(child, itemDepth, itemsVisible))
    ]
    // Ungrouped root band: no header, no disclosure — its rows sit flush in the grid.
    if (g.kind === 'ungrouped') return members
    // Headered group: the header stays put; its members live in a Reveal so collapse/expand animates the
    // rows (grid-rows 0fr↔1fr) on the same --disclosure motion as the chevron, and collapsed rows leave
    // the DOM. Each row keeps its own grid reading the inherited --cols, so wrapping never breaks the
    // column alignment (A-2).
    return [
      <div key={`gh-${g.key}`} className="group-header-row" style={{ paddingLeft: groupIndent(depth) }}>
        <GroupHeader
          group={g}
          view={liveView}
          ctx={ctx}
          setNames={setNames}
          setIcons={setIcons}
          collapsed={isCollapsed}
          onToggle={() => toggleCollapse(g.key)}
        />
      </div>,
      <Reveal key={`rv-${g.key}`} open={!isCollapsed}>
        {members}
      </Reveal>
    ]
  }

  return (
    <div ref={viewRef} className={cx('table-view', overflowing && 'overflowing')}>
      <IconPicker open={iconPickerOpen} onClose={() => setIconPickerOpen(false)} />
      <TableRowDnd
        rows={dataRows}
        disabled={dragDisabled}
        canReorderWithin={canReorderWithin}
        canReassign={canReassign}
        reorderTo={reorderTo}
        reassign={reassignRow}
      >
        <div
          className={cx(
            'table-grid',
            text.body.standard,
            liveView.hide_borders && 'no-borders',
            collapsing != null && 'col-hiding',
            colDrag != null && 'col-dragging-active'
          )}
          style={{ minWidth: reflowWidth, ['--cols']: cols } as React.CSSProperties}
        >
          {/* Header band — each header grabs to smooth-shift its whole column (A-4); the filler sits
              outside the columns, inert. The transitionend on the animated track set commits a column
              hide (E-11) — transform transitions (the drag) carry a different propertyName, so they pass. */}
          <div
            className="table-head"
            onTransitionEnd={(e) => {
              if (e.propertyName === 'grid-template-columns') commitHide()
            }}
          >
            {columns.map((c, i) => (
              <ColumnHeader
                key={c.id}
                id={c.id}
                label={columnLabel(c.id, schema, ctx.labels)}
                width={colWidth(c.id)}
                align={colAlign(c.id)}
                transform={colTransform(i)}
                dragging={colDrag?.from === i}
                onDragStart={(e) => startColumnDrag(e, i)}
                onResize={resizeColumn}
                onResizeCommit={commitResize}
                onContextMenu={(e) => void openHeaderMenu(c.id, c.kind === 'title', e)}
              />
            ))}
            {/* Trailing filler in the 1fr track — also the :last-child anchor that keeps the last real
                column's right divider (Table.css). Empty but load-bearing; don't remove. */}
            <div className="cell-filler" aria-hidden="true" />
          </div>
          {/* Rows (E-3) — the drop-line DnD (tableDnd) wraps the whole grid; group-header rows aren't
              drag items. */}
          {groups.flatMap((g) => renderRows(g, 0, true))}
        </div>
      </TableRowDnd>
    </div>
  )
}

/** One column header: the whole cell is the grab surface for the smooth-shift reorder (A-4 — `dragging`
 *  applies the ghost veil + solid band, `transform` slides it with the cursor) plus a right-edge resize
 *  strip (H-2). The strip stops propagation so a resize never starts a reorder; the resize pointer delta
 *  is divided by the live zoom so a screen drag maps onto the grid's pre-zoom track width. */
function ColumnHeader({
  id,
  label,
  width,
  align,
  transform,
  dragging,
  onDragStart,
  onResize,
  onResizeCommit,
  onContextMenu
}: {
  id: string
  label: string
  width: number
  align: ColumnAlign
  transform: string | undefined
  dragging: boolean
  onDragStart: (e: React.PointerEvent) => void
  onResize: (id: string, width: number) => number
  onResizeCommit: (id: string, width: number) => void
  onContextMenu?: (e: React.MouseEvent) => void
}): React.JSX.Element {
  const startResize = (e: React.PointerEvent<HTMLSpanElement>): void => {
    e.preventDefault()
    e.stopPropagation() // a resize never bubbles up to start a column reorder
    const grip = e.currentTarget
    const cell = grip.closest('.col-header')
    const zoom = (cell && cell.getBoundingClientRect().width / width) || 1
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
    <div
      className={cx('col-header', text.callout.semibold, dragging && 'col-dragging')}
      style={{ transform, textAlign: align }}
      onPointerDown={onDragStart}
      onContextMenu={onContextMenu}
    >
      {label}
      <span className="col-resizer" onPointerDown={startResize} />
    </div>
  )
}

/** One data row + its hover-revealed drag grip (E-3 / H-5). The grip sits in the lead cell's gutter
 *  lane — the same slot the group disclosure chevron occupies — so handles align with the chevrons and
 *  the row content lines up with the group headers. useTableRowDrag mutes the row while it's lifted. */
function DataRow({
  row,
  columns,
  ctx,
  depth,
  indent,
  colTransform,
  colAlign,
  colStyle,
  onCellMenu,
  onCellClick,
  overlay,
  draggingCol,
  hideIcon,
  selected,
  dragDisabled,
  lead
}: {
  row: ViewRow
  columns: ResolvedColumn[]
  ctx: ResolveContext
  depth: number
  indent: (depth: number) => string | undefined
  colTransform: (ci: number) => string | undefined
  colAlign: (id: string) => ColumnAlign
  colStyle: (id: string) => ColumnStyle
  onCellMenu: (col: ResolvedColumn, e: React.MouseEvent) => void
  onCellClick: (col: ResolvedColumn, e: React.MouseEvent) => void
  overlay: (col: ResolvedColumn) => { node: React.ReactNode; replace: boolean } | null
  draggingCol: number | undefined
  hideIcon: boolean
  selected: boolean
  dragDisabled: boolean
  lead: boolean
}): React.JSX.Element {
  const { ref, handle, isDragging } = useTableRowDrag(row.id)
  return (
    <div
      ref={ref}
      className={cx('data-row', selected && 'selected', isDragging && 'row-dragging', lead && 'row-lead')}
      // The whole row is a drag surface, not just the gutter grip — grabbing ANY cell arms the reorder, so a
      // horizontal scroll that pushes the grip out of reach can't block it. A press-release (no move past
      // ACTIVATION) is each CELL's gesture (A-7: only the title navigates; the row background is a no-op);
      // only a real drag reorders. Gated with the grip when reorder is disabled.
      {...(dragDisabled ? {} : handle)}
    >
      {columns.map((c, i) => {
        const style: React.CSSProperties = { transform: colTransform(i), textAlign: colAlign(c.id) }
        if (i === 0) style.paddingLeft = indent(depth)
        const over = overlay(c)
        const content = over?.replace ? (
          over.node
        ) : (
          <>
            <Cell row={row} column={c} ctx={ctx} hideIcon={hideIcon} style={colStyle(c.id)} />
            {over?.node}
          </>
        )
        return i === 0 ? (
          <div
            key={c.id}
            className={cx('data-cell', 'cell-lead', draggingCol === i && 'col-dragging', over != null && !over.replace && 'cell-anchored')}
            style={style}
            onContextMenu={(e) => onCellMenu(c, e)}
            onClick={(e) => {
              if (!isDragging) onCellClick(c, e)
            }}
          >
            {!dragDisabled && (
              <span className="row-grip" {...handle} onClick={(e) => e.stopPropagation()} aria-label="Drag to reorder">
                <Icon name="grip-vertical" size={14} />
              </span>
            )}
            {content}
          </div>
        ) : (
          <div
            key={c.id}
            className={cx('data-cell', draggingCol === i && 'col-dragging', over != null && !over.replace && 'cell-anchored')}
            style={style}
            onContextMenu={(e) => onCellMenu(c, e)}
            onClick={(e) => {
              if (!isDragging) onCellClick(c, e)
            }}
          >
            {content}
          </div>
        )
      })}
      {/* 1fr-track filler + last-column divider anchor (see table head). */}
      <div className="cell-filler" aria-hidden="true" />
    </div>
  )
}
