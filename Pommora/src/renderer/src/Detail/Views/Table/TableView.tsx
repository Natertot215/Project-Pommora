import { memo, useEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { UNGROUPED } from '@shared/types'
import type {
  CollectionNode,
  NexusTree,
  ResolvedColumn,
  ResolvedGroup,
  SetNode,
  ViewRow,
} from '@shared/types'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import type { ColumnStyle } from '@shared/columnStyles'
import { cellMenuContextFor } from '@shared/cellMenu'
import { parseStyleAction } from '@shared/columnMenu'
import { type ColumnAlign, type SavedView, mintDefaultView } from '@shared/views'
import { applyPropertyValue, isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { isValidLink } from '@shared/links'
import { flattenContainer, groupsStructurally } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { contextOptionsFor as contextOptionsForTier } from '../pipeline/contextOptions'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { resolvedSortCount, resolveManualOrder } from '../pipeline/sort'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { PropertyPicker, syntheticContextDef } from '../PropertyEditing/PropertyPicker'
import { DatetimeValuePicker } from '../PropertyEditing/DatetimeValuePicker'
import { nextCycleValue } from '../PropertyEditing/statusCycle'
import { useSession } from '../../../store'
import { findCollectionForSet } from '../../Scope'
import { isOpenInTabs } from '../../../Tabs/tabsModel'
import { useActiveView } from '../useActiveView'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import type { SetTreeNode } from '../pipeline/group'
import { buildResolveContext, type ResolveContext } from './resolveContext'
import { writeTierValue } from '../tierWrite'
import { buildSetIcons, buildSetNames, buildSetPaths } from './cellResolve'
import { BandDnd, type BandDrop } from './bandDnd'
import {
  allStructuralIds,
  flattenBands,
  propertyOrderAfterDrop,
  reparentFsOrder,
  structuralOrderAfterDrop,
} from './bandDndModel'
import { nextOrder } from '@renderer/Sidebar/sidebarDndModel'
import { Cell } from './Cell'
import { PropertyTypeIcon } from '@renderer/Components/Detail/PropertyTypes'
import { TableGroupBand } from './TableGroupBand'
import { resolveBandHead } from '../GroupBand'
import { columnLabel, TIER_LEVEL_BY_ID } from './columnLabel'
import { clampWidth, widthFor } from './columnWidths'
import { alignFor } from './columnAlign'
import { styleFor } from './columnStyles'
import { reorderColumns } from './columnReorder'
import { mergeOverrides, mergeStyleRecords } from './viewMerge'
import { groupKeyToValue, REASSIGNABLE_GROUP_TYPES } from './reassign'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { IconPicker } from '@renderer/Components/IconPicker'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { TextPicker } from '@renderer/design-system/components/TextPicker'
import { numberDivisor } from '../PropertyEditing/formatValue'
import { ACTIVATION } from '@renderer/design-system/interactions/shared'
import { TableRowDnd, useTableRowDrag } from './tableDnd'
import { solidColorCss } from './solidColor'
import { parseLink, urlClickTarget, urlValueFromEdit, urlValueFromRename } from './linkValue'

// ── TUNABLE ── how far past a column's edge the dragged column's centre must travel before the slot
// flips (the sticky zone around the current slot). Larger = more deliberate / harder to leave a slot;
// smaller = snappier. Bump this one number to taste.
const COL_SHIFT_HYSTERESIS = 25

/** The datetime cell's picker shell: PickerMenu portals off the cell (escaping the table's overflow
 *  clip) and self-dismisses via its own backdrop. The calendar's [data-calmenu] sub-menus portal
 *  ABOVE that backdrop (z-index), so their option clicks fall through to the menu, never the dismiss. */
function DatetimeCellPicker({
  open,
  triggerRef,
  onDismiss,
  children,
}: {
  open: boolean
  triggerRef: RefObject<HTMLElement | null>
  onDismiss: () => void
  children: React.ReactNode
}): React.JSX.Element {
  return (
    <PickerMenu solid open={open} onDismiss={onDismiss} triggerRef={triggerRef}>
      {children}
    </PickerMenu>
  )
}

/** A Collection uses its own schema; a Set inherits its ancestor Collection's (schema lives only on
 *  the Collection). [] when the owning Collection can't be found. */
export function resolveContainerSchema(
  tree: NexusTree,
  source: CollectionNode | SetNode,
): PropertyDefinition[] {
  if (source.kind === 'collection') return source.properties ?? []
  const collections = [...tree.collections, ...tree.userSections.flatMap((s) => s.collections)]
  const owns = (sets: SetNode[] | undefined): boolean =>
    (sets ?? []).some((s) => s.id === source.id || owns(s.sets))
  return collections.find((c) => owns(c.sets))?.properties ?? []
}

/** The view to render: the per-machine active view if still present, else the first saved view, else
 *  a freshly-minted default (sentinel id until first saved). Exported: the Visibility pane picks the
 *  same view by the same rule. */
export function pickView(
  source: CollectionNode | SetNode,
  activeId: string | undefined,
  schema: PropertyDefinition[],
): SavedView {
  const views = source.views ?? []
  const active = activeId ? views.find((v) => v.id === activeId) : undefined
  return active ?? views[0] ?? mintDefaultView(schema)
}

const sameIds = (a: string[], b: string[]): boolean =>
  a.length === b.length && a.every((x, i) => x === b[i])

export function TableView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)
  // The store's one write path — runs the op AND refetches immediately (load()), so a table reorder /
  // reassign propagates to the sidebar right away instead of waiting on the fs watcher's settle (~1s).
  const mutate = useSession((s) => s.mutate)
  const load = useSession((s) => s.load)
  const saveView = useSaveView(source, load)
  const [values, setValues] = useState<Record<string, PageFrontmatter>>({})
  // Optimistic property patches keyed by page id (cross-group reassignment, D-4): the loaded values
  // never re-read on a write, so a reassigned row re-groups only because this patch feeds the pipeline.
  const [valueOverride, setValueOverride] = useState<Record<string, PageFrontmatter> | null>(null)
  const [viewOrders, setViewOrders] = useState<Record<string, string[]>>({})

  // Lazy value load + manual-order cache on container open; `cancelled` guards a fast container swap.
  // (The active-view pointer is the shared store slice — read via useActiveView, not fetched here.)
  useEffect(() => {
    let cancelled = false
    setValueOverride(null) // canonical values for the new container supersede any optimistic patches
    void window.nexus.loadValues(source.path).then((v) => {
      if (!cancelled) setValues(v)
    })
    void window.nexus.viewOrders.get().then((m) => {
      if (!cancelled) setViewOrders(m)
    })
    return () => {
      cancelled = true
    }
  }, [source.path])

  const schema = useMemo(() => (tree ? resolveContainerSchema(tree, source) : []), [tree, source])
  const { view } = useActiveView(source, schema)
  // Local override layer — reorder + resize + hide + collapse apply instantly, persist async (watcher
  // confirms). Order + hidden go in `liveView` (the pipeline reads them); width stays a separate
  // override so a resize doesn't re-run the pipeline. All re-seed on view change.
  const [orderOverride, setOrderOverride] = useState<string[] | null>(null)
  const [widthOverride, setWidthOverride] = useState<Record<string, number>>({})
  const [alignOverride, setAlignOverride] = useState<Record<string, ColumnAlign>>({})
  const [styleOverride, setStyleOverride] = useState<Record<string, ColumnStyle>>({})
  const [hiddenOverride, setHiddenOverride] = useState<string[] | null>(null)
  // The optimistic band-order patch from a band drop — { group_order } (structural) or { group }
  // (property). Rides liveView so a sibling persist can't fold the stale on-disk order back over a
  // fresh drag (F1), and deliberately does NOT reset on [source]: the reparent-triggered load()
  // swaps source identity mid-flight (HIGH-3); key={source.id} already remounts real switches.
  const [bandOverride, setBandOverride] = useState<Partial<SavedView> | null>(null)
  const [manualOverride, setManualOverride] = useState<string[] | null>(null)
  const [collapsed, setCollapsed] = useState<Set<string>>(
    () => new Set(view.collapsed_groups ?? []),
  )
  const [collapsing, setCollapsing] = useState<string | null>(null)
  // Columns whose tracks are sliding to a wider per-style min after a look change (E-13): enables the
  // same grid-template-columns transition as Hide for one beat, cleared on transitionend. Populated by
  // a render-phase detection (below) so it fires for EVERY look-write path — the column menu AND the
  // property pane — through one mechanism, not a per-call-site trigger.
  const [sliding, setSliding] = useState<ReadonlySet<string>>(() => new Set())
  const prevLooks = useRef<Record<string, string | undefined>>({})
  // Live column smooth-shift (A-4): the dragged column index + the slot it's over. Deliberately
  // NOT the cursor delta — that changes per pointermove and rides a grid-level CSS var instead
  // (--col-drag-x), so a drag frame never re-renders the unmemoized row/cell tree. Transient —
  // set on grab + slot flips, cleared on drop; column indices into the resolved `columns`.
  const [colDrag, setColDrag] = useState<{ from: number; to: number } | null>(null)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)
  // The page a title:icon menu targeted (captured before the menu await — the row is out of scope by
  // the time the picker commits). The cell element anchors the picker's beak.
  const [iconTarget, setIconTarget] = useState<{ path: string; icon?: string } | null>(null)
  const iconCellRef = useRef<HTMLElement | null>(null)
  // Columns fit → the rounded content-inset look; columns overflow → the right inset flattens and
  // the table h-scrolls to the glass edge (the left gutter holds). One read per pane resize /
  // track-set change — never per scroll or per pointermove.
  const viewRef = useRef<HTMLDivElement>(null)
  const [overflowing, setOverflowing] = useState(false)
  // The column sum (pre-zoom px), readable from the overflow check without a stale closure. The
  // check compares THIS against the box — a scrollWidth read floors at clientWidth, so any
  // is-content-bigger comparison built on it can latch.
  const reflowRef = useRef(0)
  // The one in-cell editing surface (A-2/A-6 picker · A-8/A-12 editor). Cleared on dismiss; the
  // exit presence keeps a PICKER mounted through its Bloom-out (reading the last target from the
  // ref while `editing` is already null) — the editor unmounts instantly.
  const [editing, setEditing] = useState<{
    rowId: string
    colId: string
    mode: 'picker' | 'editor' | 'rename'
    // Bumped on each rename OPEN so the popover's key changes — a reopened cell mounts a fresh
    // TextPicker + field instead of reviving the prior session's measured position and stale input.
    nonce?: number
  } | null>(null)
  // The picker/datetime is ONE table-level self-managed pane — it owns its Bloom-out off `open`, so the
  // cell only tracks WHICH cell is editing + captures its element for placement. lastPicker holds the
  // exiting picker's content rendered through the Bloom-out; the inline editor unmounts instantly.
  // A column resize is in progress (set on grab, cleared on commit) — a grid-level flag so the borderless
  // table reveals its vertical dividers while you resize (its reorder twin is colDrag → col-dragging-active).
  const [resizing, setResizing] = useState(false)
  const triggerElRef = useRef<HTMLElement | null>(null)
  const lastPicker = useRef<{ rowId: string; colId: string } | null>(null)
  if (editing?.mode === 'picker')
    lastPicker.current = { rowId: editing.rowId, colId: editing.colId }
  // Its rename twin — the TextPicker alias field keeps its exiting cell through the Bloom-out the same way.
  const renameNonce = useRef(0)
  const lastRename = useRef<{ rowId: string; colId: string; nonce: number } | null>(null)
  if (editing?.mode === 'rename') {
    lastRename.current = { rowId: editing.rowId, colId: editing.colId, nonce: editing.nonce ?? 0 }
  }
  useEffect(() => {
    setOrderOverride(null)
    setWidthOverride({})
    setAlignOverride({})
    setStyleOverride({})
    setHiddenOverride(null)
    setBandOverride(null)
    setManualOverride(null)
    setCollapsing(null)
    setColDrag(null)
    setCollapsed(new Set(view.collapsed_groups ?? []))
  }, [view.id])
  // A fresh tree (a sidebar reorder, or this table's own write round-tripping back) carries the canonical
  // page_order, so drop the optimistic MANUAL ORDER it was masking — order round-trips through source.pages,
  // so canon has caught up. VALUES deliberately do NOT reset here: a PageNode carries no property value and
  // loadValues never re-reads mid-session, so clearing valueOverride on a `source`-identity change would
  // revert a just-assigned value to the frozen pre-write `values` whenever a watcher echo re-mints `source`
  // (the ~1/10 assign-vanish). The value override clears+reloads only on a real container switch, above.
  useEffect(() => {
    setManualOverride(null)
  }, [source])
  // The Visibility pane writes property_order / hidden_properties from OUTSIDE this component. Once the
  // canonical view catches an override up (this table's own write round-tripped), drop it — a pinned
  // override would mask the pane's later writes and fold stale state back over them on the next persist.
  useEffect(() => {
    if (orderOverride && sameIds(orderOverride, view.property_order)) setOrderOverride(null)
    if (hiddenOverride && sameIds(hiddenOverride, view.hidden_properties)) setHiddenOverride(null)
  }, [view, orderOverride, hiddenOverride])
  const liveView = useMemo(() => {
    if (!orderOverride && !hiddenOverride && !bandOverride) return view
    return {
      ...view,
      property_order: orderOverride ?? view.property_order,
      hidden_properties: hiddenOverride ?? view.hidden_properties,
      ...bandOverride,
    }
  }, [view, orderOverride, hiddenOverride, bandOverride])
  // Manual row order (viewOrders cache) is the sort tiebreaker (D-5/D-6) — passed to the pipeline when
  // the view is sorted or grouped (an unsorted, ungrouped view otherwise reads canonical page_order). A
  // live `manualOverride` also feeds it so an unsorted-flat reorder shows instantly (before its page_order
  // write round-trips the fs) rather than snapping back.
  // Effective count only — a dead criterion (deleted property) sorts by nothing and must not
  // retire row drag or flip the manual-order gates.
  const sortKeys = useMemo(() => resolvedSortCount(liveView.sort, schema), [liveView.sort, schema])
  const sortedOrGrouped = sortKeys > 0 || liveView.group != null
  const manualOrder = resolveManualOrder(sortedOrGrouped, manualOverride, viewOrders[view.id])
  // The grouped property + whether a cross-group drop can reassign it (D-4): status/select/checkbox map
  // a group key straight to a value; a date bucket doesn't, so date grouping isn't reassignable.
  // The property lives in TWO homes: top-level property grouping, or the view-level sub-group
  // bucketing inside structural bands.
  // EFFECTIVE mode, the pipeline's own predicate — a dead-property grouping renders structural
  // bands, so the drag writers (page_order vs viewOrders; location set_order vs group_order) must
  // agree with what's actually drawn.
  const structuralGrouping = groupsStructurally(liveView.group, schema)
  const subGrouped = structuralGrouping && liveView.sub_group !== undefined
  const groupPropId =
    liveView.group?.kind === 'property'
      ? liveView.group.property_id
      : subGrouped
        ? liveView.sub_group?.property_id
        : undefined
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
  const effectiveValues = useMemo(
    () => (valueOverride ? { ...values, ...valueOverride } : values),
    [values, valueOverride],
  )
  const { columns, groups, setTree } = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, effectiveValues)
    return { ...resolveView({ rows, setTree, view: liveView, schema, manualOrder }), setTree }
  }, [source, effectiveValues, liveView, schema, manualOrder])
  const ctx = useMemo(
    () => (tree ? buildResolveContext(tree, schema) : null),
    // biome-ignore lint/correctness/useExhaustiveDependencies: buildResolveContext reads only contexts + labels — keying on those slices keeps ctx identity across unrelated tree pushes, so memoized rows hold.
    [tree?.contexts, tree?.labels, schema],
  )
  // One mounted observer, two targets, one job (the overflowing flag): the view (pane resizes) and
  // the grid (min-width sizes its box only while the columns overflow the pane — in the fit regime
  // width:100% pins it, and nothing here needs to fire). Each fires one cheap read, never per-scroll.
  useEffect(() => {
    const el = viewRef.current
    if (!el) return
    const check = (): void => {
      const cs = getComputedStyle(el)
      const pads = Number.parseFloat(cs.paddingLeft) + Number.parseFloat(cs.paddingRight)
      const gridEl = el.querySelector('.table-grid')
      const zoom = gridEl
        ? Number.parseFloat(getComputedStyle(gridEl).getPropertyValue('zoom')) || 1
        : 1
      setOverflowing(reflowRef.current * zoom > el.clientWidth - pads + 1)
    }
    check()
    const ro = new ResizeObserver(check)
    ro.observe(el)
    const grid = el.querySelector('.table-grid')
    if (grid) ro.observe(grid)
    return () => ro.disconnect()
    // biome-ignore lint/correctness/useExhaustiveDependencies: re-bind when the loading/empty returns give way to the real grid (the nodes remount without ctx changing).
  }, [ctx === null, groups.length === 0])
  const setNames = useMemo(() => buildSetNames(source), [source])
  const setIcons = useMemo(() => buildSetIcons(source), [source])

  // The visible band list (headers only) — BandDnd's hit-test universe, snapshot at drag activation.
  const bands = useMemo(() => flattenBands(groups, collapsed), [groups, collapsed])
  const setPaths = useMemo(() => buildSetPaths(source), [source])
  const bandLabel = (id: string): string => {
    const find = (gs: ResolvedGroup[]): ResolvedGroup | undefined => {
      for (const g of gs) {
        if (g.key === id) return g
        const hit = g.children && find(g.children)
        if (hit) return hit
      }
      return undefined
    }
    const g = find(groups)
    return g && ctx ? resolveBandHead(g, liveView, ctx, setNames, setIcons, source).label : id
  }
  // The band drop router (already classified by BandDnd): structural reorder → the view-level
  // group_order (merged over the FULL tree so collapsed siblings survive) · property reorder →
  // group.order + manual (its first UI writer) · reparent → moveSet with the destination's CURRENT
  // fs children + the moved id appended (C-4 — the visual slot persists only in group_order).
  const commitBand = (patch: Partial<SavedView>): void => {
    setBandOverride((prev) => ({ ...prev, ...patch }))
    persistView(patch)
  }
  // The reparent's commit fires AFTER a real fs round-trip — route it through a ref so it merges
  // the FIRE-TIME view state: a collapse/resize persist landing mid-flight must not be clobbered
  // by this drop-render's stale closure.
  const commitBandRef = useRef(commitBand)
  commitBandRef.current = commitBand
  const childIdsOf = (nodes: SetTreeNode[], id: string): string[] | null => {
    for (const n of nodes) {
      if (n.id === id) return n.children.map((c) => c.id)
      const hit = childIdsOf(n.children, id)
      if (hit) return hit
    }
    return null
  }
  const onBandDrop = (draggedId: string, drop: BandDrop): void => {
    const dragged = bands.find((b) => b.id === draggedId)
    if (!dragged) return
    if (dragged.kind === 'property') {
      if (liveView.group?.kind === 'property') {
        if (drop.kind !== 'reorder') return
        const present = groups.filter((g) => g.kind === 'property').map((g) => g.key)
        const group = {
          ...liveView.group,
          order_mode: 'manual' as const,
          order: propertyOrderAfterDrop(present, draggedId, drop.beforeId),
        }
        commitBand({ group })
        return
      }
      if (!subGrouped || !liveView.sub_group || liveView.sub_group.order_mode !== 'manual') return
      // F-1: global sub-order — dragging one set's bucket reorders that bucket across EVERY set. A
      // cross-set drag arrives as kind 'reparent' (bandDnd routes by impliedParentId) and is STILL a
      // global reorder: only the beforeId's bucket value matters, targetParentId is ignored. The
      // key→bucket map builds once per drop, never a walk per lookup.
      const bucketByKey = new Map(
        groups.flatMap((g) =>
          (g.children ?? []).flatMap((c) =>
            c.bucket !== undefined ? [[c.key, c.bucket] as const] : [],
          ),
        ),
      )
      const draggedBucket = bucketByKey.get(draggedId)
      const beforeBucket = drop.beforeId === null ? null : (bucketByKey.get(drop.beforeId) ?? null)
      if (draggedBucket === undefined) return
      const present = [...new Set(bucketByKey.values())]
      commitBand({
        sub_group: {
          ...liveView.sub_group,
          order: propertyOrderAfterDrop(present, draggedBucket, beforeBucket),
        },
      })
      return
    }
    const group_order = structuralOrderAfterDrop(
      liveView.group_order ?? [],
      allStructuralIds(groups),
      draggedId,
      drop.beforeId,
    )
    if (drop.kind === 'reorder') {
      if (structuralGrouping && liveView.structural_order_mode === 'location') {
        // C-1c: Location mode — the same-parent reorder IS the filesystem write; group_order stays
        // untouched (preserved for the flip back to Custom). The reparent branch below is mode-blind
        // by design: its group_order write is the slot preservation.
        const parentPath = dragged.parentId === null ? source.path : setPaths.get(dragged.parentId)
        const siblingIds =
          dragged.parentId === null
            ? setTree.map((n) => n.id)
            : (childIdsOf(setTree, dragged.parentId) ?? [])
        if (!parentPath) return
        void mutate({
          op: 'reorderChildren',
          parentPath,
          key: 'set_order',
          order: nextOrder(siblingIds, draggedId, drop.beforeId),
        })
        return
      }
      commitBand({ group_order })
      return
    }
    const path = setPaths.get(draggedId)
    const destPath = drop.targetParentId === null ? source.path : setPaths.get(drop.targetParentId)
    const destChildIds =
      drop.targetParentId === null
        ? setTree.map((n) => n.id)
        : childIdsOf(setTree, drop.targetParentId)
    if (!path || !destPath || !destChildIds) return
    // One drop, two writers, possibly ONE sidecar (a de-nest to root): the fs move lands before the
    // view write — views.save and set_order are both read-modify-writes on the container sidecar.
    // A failed move (a name collision at the destination) commits NOTHING — no phantom order.
    void (async () => {
      if (
        !(await mutate({
          op: 'moveSet',
          path,
          newParentPath: destPath,
          order: reparentFsOrder(destChildIds, draggedId),
        }))
      )
        return
      commitBandRef.current({ group_order })
    })()
  }

  // Persist the saved view + every live override (order + collapse) + a patch, so no one mutation
  // clobbers another's unsaved state — the exact Swift reorder/resize data-loss H-2 guards against.
  // Adopt-only (G-1): if this fires while the entry-mint is still in flight, it awaits the minted id and
  // saves against it — never mints a rival default from its own sentinel. skipRefetch defaults true:
  // order/width/align/collapse/style all show through a live override, so a refetch would only repaint
  // redundantly. A patch with NO optimistic layer (hide_column_icons) passes false so it actually reflects.
  const persistView = (patch: Partial<SavedView>, skipRefetch = true): void => {
    void saveView(
      mergeOverrides(liveView, widthOverride, alignOverride, collapsed, patch, styleOverride),
      { skipRefetch },
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
      overId,
    )
    setOrderOverride(next)
    persistView({ property_order: next })
  }
  // Resize applies live (a separate override, so the pipeline doesn't re-run) and returns the clamped
  // width so the header tracks the real edge; commit persists the merged widths.
  const resizeColumn = (id: string, width: number): number => {
    const clamped = clampWidth(Math.round(width), id, schema, colStyle(id).look)
    setWidthOverride((prev) => ({ ...prev, [id]: clamped }))
    return clamped
  }
  const commitResize = (id: string, width: number): void => {
    setResizing(false)
    persistView({
      column_widths: {
        ...liveView.column_widths,
        ...widthOverride,
        [id]: clampWidth(width, id, schema, colStyle(id).look),
      },
    })
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
  // A column header's type glyph, gated by the per-view Column Icons toggle (`hide_column_icons`),
  // which defaults ON (icons hidden). Tier columns wear the context glyph; a schema-less column
  // (unknown type) gets none.
  const headerIcon = (id: string): React.ReactNode => {
    if (liveView.hide_column_icons ?? true) return null
    // Created At has a reserved column but no PropertyType, so it carries no registry glyph — give it
    // its own here (its sibling Modified At rides last_edited_time's registry icon via PropertyTypeIcon).
    if (id === RESERVED_PROPERTY_ID.createdAt) {
      return (
        <span className="col-header-icon">
          <Icon name="clock-plus" size={13} />
        </span>
      )
    }
    const t = declaredType(id, schema)
    if (t === undefined) return null
    return (
      <span className="col-header-icon">
        <PropertyTypeIcon type={t === 'tier' ? 'context' : t} size={13} />
      </span>
    )
  }
  // A column's resolved display style (B-1..B-5): the live override keys, over the saved per-view
  // entry, over the type default.
  const colStyle = (id: string): ColumnStyle => ({
    ...styleFor(id, schema, liveView),
    ...styleOverride[id],
  })
  // Set one style key: applies live via the override, persists per-key into column_styles — the align
  // pattern; the patch carries the not-yet-committed value so a state-batch can't drop it.
  const setColumnStyle = (id: string, key: keyof ColumnStyle & string, value: string): void => {
    const merged = { ...styleOverride[id], [key]: value } as ColumnStyle
    setStyleOverride((prev) => ({ ...prev, [id]: merged }))
    persistView({
      column_styles: mergeStyleRecords(liveView.column_styles, { ...styleOverride, [id]: merged }),
    })
  }
  // Set a column's alignment: applies live via the override, persists to the SavedView column_alignments.
  const setColumnAlign = (id: string, align: ColumnAlign): void => {
    setAlignOverride((prev) => ({ ...prev, [id]: align }))
    persistView({
      column_alignments: { ...liveView.column_alignments, ...alignOverride, [id]: align },
    })
  }
  // Whether a number column can render a bar (percent, or fraction + a denominator) — the ONE gate the
  // cell render, the cell menu, and the header menu share so all three agree on when Bar is offered.
  const numberBarCapable = (colId: string, type: ReturnType<typeof declaredType>): boolean =>
    type === 'number' && numberDivisor(schema.find((d) => d.id === colId)) !== undefined
  // Right-click a header → native column menu (E-1/E-5): Align + Style + Hide. Title is the primary
  // column — fixed left, not hideable, no style — so it pops nothing. The style ctx rides only for a
  // schema-declared property type; the shared builder decides which types actually get items.
  const openHeaderMenu = async (
    id: string,
    isTitle: boolean,
    e: React.MouseEvent,
  ): Promise<void> => {
    e.preventDefault()
    const t = declaredType(id, schema)
    const barCapable = numberBarCapable(id, t)
    const style =
      t !== undefined && t !== 'title' && t !== 'tier'
        ? { type: t, current: colStyle(id), ...(barCapable ? { barCapable: true } : {}) }
        : undefined
    const action = await window.nexus.columnMenu({
      align: colAlign(id),
      alignable: !isTitle,
      hideable: !isTitle,
      iconsShown: isTitle ? undefined : !(liveView.hide_column_icons ?? true),
      style,
    })
    if (action === 'column:hide') hideColumn(id)
    else if (action === 'column:toggle-icons')
      persistView({ hide_column_icons: !(liveView.hide_column_icons ?? true) }, false)
    else if (action?.startsWith('align:'))
      setColumnAlign(id, action.slice('align:'.length) as ColumnAlign)
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
      properties: applyPropertyValue(row.frontmatter.properties, propertyId, value),
    }
    setValueOverride((prev) => ({ ...prev, [row.id]: patched }))
    void mutate({ op: 'setProperty', path: row.path, propertyId, value })
  }
  // A context column's pickable list — the NEXUS's contexts for its tier (reserved tier columns
  // read their fixed level; a user context prop reads its def's target tier). Null for anything else.
  const contextOptionsFor = (
    col: ResolvedColumn,
  ): Array<{ value: string; label: string; color?: string }> | null => {
    const level =
      col.kind === 'tier'
        ? TIER_LEVEL_BY_ID[col.id]
        : schema.find((d) => d.id === col.id)?.context_target?.tier
    if (!level || !tree) return null
    return contextOptionsForTier(level, tree)
  }
  // A reserved tier column writes the BARE frontmatter array (`tier1/2/3`) through its own op;
  // a user context prop writes through setProperty like every other property value.
  const commitTierValue = (row: ViewRow, colId: string, ids: string[]): void => {
    writeTierValue(row, colId, ids, row.frontmatter, setValueOverride, mutate)
  }
  // A chip's hover × commits whatever remains after that chip (Phase 3): the picker's exact
  // routing — a reserved tier column through setTier, everything else through setProperty.
  const removeCellValue = (row: ViewRow, col: ResolvedColumn, next: PropertyValue | null): void => {
    if (col.kind === 'tier' && next?.kind === 'context') commitTierValue(row, col.id, next.value)
    else commitCellValue(row, col.id, next)
  }
  // Single-click acts per the cell's type (A-2/A-4/A-6): checkbox-look status cycles its group,
  // checkbox toggles, status/select/multi/context open the picker. Acting stops propagation so the
  // row's select doesn't also fire; anything else bubbles.
  const onCellClick = (row: ViewRow, col: ResolvedColumn, e: React.MouseEvent): void => {
    // Ctrl+Click is macOS's secondary-click: it fires `click` alongside `contextmenu`. Bail so the
    // right-click menu wins instead of the click acting under it (e.g. opening a link's browser tab).
    if (e.ctrlKey) return
    // Capture the clicked cell for the table-level picker's placement (harmless on non-picker clicks).
    triggerElRef.current = e.currentTarget as HTMLElement
    if (col.kind === 'title') {
      // The ONLY navigate (A-7): row-click narrowed to the title cell; row background is a no-op.
      // A page-preview Collection routes to the floating preview instead (B-1); ⌘-click is always
      // the explicit full-page bypass, to a new tab (I-19).
      e.stopPropagation()
      const owner =
        source.kind === 'collection'
          ? source
          : findCollectionForSet(useSession.getState().tree, source.id)
      if (owner?.openIn === 'page-preview') {
        if (e.metaKey) void select({ kind: 'page', id: row.id, path: row.path }, { newTab: true })
        else useSession.getState().openPreview({ id: row.id, path: row.path })
      } else void select({ kind: 'page', id: row.id, path: row.path })
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
      const v = resolveFieldValue(row, col.id, schema)
      const current = v.kind === 'status' || v.kind === 'select' ? v.value : undefined
      if (current === undefined) {
        // An EMPTY checkbox-look cell never cycles (a blind write) — it opens the picker to assign.
        setEditing({ rowId: row.id, colId: col.id, mode: 'picker' })
        return
      }
      const next = nextCycleValue(
        current,
        schema.find((d) => d.id === col.id),
      )
      if (next !== null) commitCellValue(row, col.id, { kind: 'status', value: next })
    } else if (t === 'checkbox') {
      e.stopPropagation()
      const v = resolveFieldValue(row, col.id, schema)
      // Checked → strip the key (a checkbox is true-or-absent, never a stored `false`); else set true.
      const checked = v.kind === 'checkbox' && v.value
      commitCellValue(row, col.id, checked ? null : { kind: 'checkbox', value: true })
    } else if (
      t === 'status' ||
      t === 'select' ||
      t === 'multi_select' ||
      t === 'context' ||
      t === 'datetime'
    ) {
      e.stopPropagation()
      setEditing({ rowId: row.id, colId: col.id, mode: 'picker' })
    } else if (t === 'number') {
      e.stopPropagation()
      // A Bar-look cell has no text to replace in place, so it edits through the TextPicker dropdown (the
      // link's rename popover, reused); a Number-look cell keeps the inline text editor.
      if (colStyle(col.id).look === 'bar') {
        renameNonce.current += 1
        setEditing({ rowId: row.id, colId: col.id, mode: 'rename', nonce: renameNonce.current })
      } else {
        setEditing({ rowId: row.id, colId: col.id, mode: 'editor' })
      }
    } else if (t === 'url') {
      e.stopPropagation()
      // Filled → open the link (matching the rendered <a>); empty → the inline field to type one in.
      const v = resolveFieldValue(row, col.id, schema)
      const url = urlClickTarget(v.kind === 'url' ? v.value : undefined)
      if (url) void window.nexus.openExternal(url)
      else setEditing({ rowId: row.id, colId: col.id, mode: 'editor' })
    }
  }
  // What the inline editor starts from, per the column's value shape.
  const editorInitial = (row: ViewRow, col: ResolvedColumn): string => {
    if (col.kind === 'title') return row.title
    const v = resolveFieldValue(row, col.id, schema)
    if (v.kind === 'number') return String(v.value)
    if (v.kind === 'url') return parseLink(v.value).url
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
      if (trimmed && trimmed !== row.title)
        void mutate({ op: 'rename', path: row.path, kind: 'page', newName: trimmed })
      return
    }
    const t = declaredType(col.id, schema)
    if (t === 'number') {
      if (trimmed === '') return commitCellValue(row, col.id, null)
      const n = Number.parseFloat(trimmed)
      if (!Number.isNaN(n)) commitCellValue(row, col.id, { kind: 'number', value: n })
    } else if (t === 'url') {
      // Edit rewrites the URL but rides the current alias along (urlValueFromEdit); empty clears.
      const cur = resolveFieldValue(row, col.id, schema)
      const next = urlValueFromEdit(trimmed, cur.kind === 'url' ? cur.value : undefined)
      if (next !== undefined) commitCellValue(row, col.id, next)
    } else if (t === 'file') {
      const v = resolveFieldValue(row, col.id, schema)
      const refs = v.kind === 'file' ? v.value : []
      if (trimmed === '')
        return commitCellValue(
          row,
          col.id,
          refs.length > 1 ? { kind: 'file', value: refs.slice(1) } : null,
        )
      commitCellValue(row, col.id, {
        kind: 'file',
        value: refs.length
          ? [{ ...refs[0], path: trimmed }, ...refs.slice(1)]
          : [{ path: trimmed }],
      })
    }
  }
  // The inline text/number editor, mounted in the editing cell and REPLACING its content. The value
  // pickers (status/select/multi/context) + the datetime picker are the table-level `cellPicker` below
  // — they portal off the cell, so they never live inside it (and so never clip to the table's scroll).
  const cellEditor = (row: ViewRow, col: ResolvedColumn): React.ReactNode => {
    if (editing?.mode !== 'editor' || editing.rowId !== row.id || editing.colId !== col.id)
      return null
    const t = declaredType(col.id, schema)
    return (
      <PropertyEditor
        initial={editorInitial(row, col)}
        numeric={t === 'number'}
        validate={t === 'url' ? isValidLink : undefined}
        color={
          t === 'url' ? solidColorCss(schema.find((d) => d.id === col.id)?.link_color) : undefined
        }
        onCommit={(raw) => commitEditorText(row, col, raw)}
        onCancel={() => setEditing(null)}
      />
    )
  }

  // Every row's live ViewRow by id — the table-level picker resolves its editing cell (and reads a
  // multi-select's fresh value on each toggle) through this, not a captured-stale row.
  const rowById = useMemo(() => {
    const m = new Map<string, ViewRow>()
    const walk = (gs: ResolvedGroup[]): void => {
      for (const g of gs) {
        for (const r of g.items) m.set(r.id, r)
        if (g.children) walk(g.children)
      }
    }
    walk(groups)
    return m
  }, [groups])

  // ONE self-managed picker/datetime pane for the whole table, hung off the editing cell (triggerElRef)
  // and portaled to a body top layer, so it escapes the table's overflow clip (`.table-view` is an
  // overflow-x scroller, which clips y too). `open` blooms it in on a picker cell, out when editing
  // clears; lastPicker keeps the exiting cell's content through the out; the per-cell key remeasures on
  // a cell switch (the position effect keys on the ref object, whose `.current` swap wouldn't re-fire it).
  const cellPicker = (): React.ReactNode => {
    const cell = editing?.mode === 'picker' ? editing : lastPicker.current
    const row = cell && rowById.get(cell.rowId)
    const col = cell && columns.find((c) => c.id === cell.colId)
    if (!cell || !row || !col) return null
    const open = editing?.mode === 'picker'
    const key = `${cell.rowId}:${cell.colId}`
    const dismiss = (): void => setEditing(null)
    if (col.kind === 'property' && declaredType(col.id, schema) === 'datetime') {
      const v = resolveFieldValue(row, col.id, schema)
      return (
        <DatetimeCellPicker key={key} open={open} triggerRef={triggerElRef} onDismiss={dismiss}>
          <DatetimeValuePicker
            value={v}
            dateFormat={colStyle(col.id).date_format}
            onCommit={(nv) => commitCellValue(row, col.id, nv)}
          />
        </DatetimeCellPicker>
      )
    }
    const contextOptions = contextOptionsFor(col)
    // A reserved tier column has no schema def — a minimal synthetic one satisfies the picker,
    // whose options come from `contextOptions` anyway.
    const def =
      schema.find((d) => d.id === col.id) ??
      (contextOptions ? syntheticContextDef(col.id) : undefined)
    if (!def) return null
    return (
      <PropertyPicker
        key={key}
        def={def}
        current={resolveFieldValue(row, col.id, schema)}
        open={open}
        triggerRef={triggerElRef}
        look={colStyle(col.id).look}
        {...(contextOptions ? { contextOptions } : {})}
        onCommit={(v) =>
          col.kind === 'tier' && v?.kind === 'context'
            ? commitTierValue(row, col.id, v.value)
            : commitCellValue(row, col.id, v)
        }
        onDismiss={dismiss}
      />
    )
  }
  // The rename popover — a TextPicker hung off the editing cell (like cellPicker), for a link's alias.
  // Its --accent is scoped to the link's own colour, so the field's focus stroke wears it; committing an
  // empty alias drops it back to a bare URL. The alias always wins at render, so this is the only surface
  // that sets it (Edit rewrites the URL and preserves it).
  const renameField = (): React.ReactNode => {
    const cell = editing?.mode === 'rename' ? editing : lastRename.current
    const row = cell && rowById.get(cell.rowId)
    const col = cell && columns.find((c) => c.id === cell.colId)
    if (!cell || !row || !col) return null
    const v = resolveFieldValue(row, col.id, schema)
    const open = editing?.mode === 'rename'
    const key = `${cell.rowId}:${cell.colId}:${cell.nonce}`
    // A Bar-look number edits its value through this same dropdown (no color scope — the app accent), with
    // a label-tertiary "/ N" out-of hint to its right so the value reads as a numerator over the total.
    if (declaredType(col.id, schema) === 'number') {
      const divisor = numberDivisor(schema.find((d) => d.id === col.id))
      return (
        <TextPicker
          key={key}
          open={open}
          triggerRef={triggerElRef}
          value={v.kind === 'number' ? String(v.value) : ''}
          trailing={divisor !== undefined ? `/ ${divisor}` : undefined}
          onCommit={(text) => {
            const trimmed = text.trim()
            if (trimmed === '') commitCellValue(row, col.id, null)
            else {
              const n = Number.parseFloat(trimmed)
              if (!Number.isNaN(n)) commitCellValue(row, col.id, { kind: 'number', value: n })
            }
            setEditing(null)
          }}
          onDismiss={() => setEditing(null)}
        />
      )
    }
    const raw = v.kind === 'url' ? v.value : ''
    const linkDef = schema.find((d) => d.id === col.id)
    return (
      <TextPicker
        key={key}
        open={open}
        triggerRef={triggerElRef}
        value={parseLink(raw).alias ?? ''}
        accent={solidColorCss(linkDef?.link_color)}
        onCommit={(alias) => {
          commitCellValue(row, col.id, urlValueFromRename(alias, raw))
          setEditing(null)
        }}
        onDismiss={() => setEditing(null)}
      />
    )
  }
  // Right-click a cell → its native menu (A-13: always a menu, never an action). Title = page meta;
  // style-bearing types = the COLUMN's Style radios; link/file add Edit; picker-based cells add
  // Clear (status gets Style + Clear; select/multi/context/tier get Clear alone).
  const openCellMenu = async (
    row: ViewRow,
    col: ResolvedColumn,
    e: React.MouseEvent,
  ): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    // Captured before the await — the synthetic event is recycled by the time the menu resolves, so
    // the rename popover can't read `e.currentTarget` then (it anchors the TextPicker off this cell).
    const cellEl = e.currentTarget as HTMLElement
    const filled = !isBlankValue(resolveFieldValue(row, col.id, schema))
    const dt = declaredType(col.id, schema)
    const barCapable = numberBarCapable(col.id, dt)
    const ctx = cellMenuContextFor(col, dt, colStyle(col.id), filled, false, barCapable)
    if (!ctx) return
    if (ctx.kind === 'title') {
      const { tabs, pins } = useSession.getState()
      ctx.alreadyOpen = isOpenInTabs(tabs, pins, { kind: 'page', id: row.id, path: row.path })
    }
    const action = await window.nexus.cellMenu(ctx)
    if (!action) return
    if (action === 'title:newtab')
      void useSession
        .getState()
        .select({ kind: 'page', id: row.id, path: row.path }, { newTab: true })
    else if (action === 'title:icon') {
      iconCellRef.current = cellEl
      setIconTarget({ path: row.path, icon: typeof row.icon === 'string' ? row.icon : undefined })
      setIconPickerOpen(true)
    } else if (action === 'title:delete')
      void mutate({ op: 'delete', path: row.path, kind: 'page' })
    else if (action === 'title:rename' || action === 'cell:edit')
      setEditing({ rowId: row.id, colId: col.id, mode: 'editor' })
    else if (action === 'cell:rename') {
      triggerElRef.current = cellEl
      renameNonce.current += 1
      setEditing({ rowId: row.id, colId: col.id, mode: 'rename', nonce: renameNonce.current })
    } else if (action === 'cell:clear') {
      if (col.kind === 'tier') commitTierValue(row, col.id, [])
      else commitCellValue(row, col.id, null)
    } else if (action.startsWith('style:')) {
      const parsed = parseStyleAction(action)
      if (parsed) setColumnStyle(col.id, parsed.key, parsed.value)
    }
  }

  // Saved widths are clamped to the type's [min, max] (Q-4) — a stale/out-of-range saved value can't
  // squash a column below legibility or stretch it past its cap.
  const colWidth = (id: string): number =>
    collapsing === id
      ? 0
      : clampWidth(
          widthOverride[id] ?? liveView.column_widths?.[id] ?? widthFor(id, schema).default,
          id,
          schema,
          colStyle(id).look,
        )

  // ---- Memoized-row inputs: every prop a DataRow receives must hold identity across unrelated
  // re-renders (a tree push, an editing toggle, a drag frame), so React.memo can bail per row. ----

  // Per-column look/alignment resolved ONCE per change — previously per CELL per render (styleFor
  // allocates), the measured bulk of a full-table re-render's JS floor.
  const { alignByCol, styleByCol } = useMemo(
    () => ({
      alignByCol: columns.map((c) => alignOverride[c.id] ?? alignFor(c.id, schema, liveView)),
      styleByCol: columns.map((c) => ({
        ...styleFor(c.id, schema, liveView),
        ...styleOverride[c.id],
      })),
    }),
    [columns, schema, liveView, alignOverride, styleOverride],
  )
  // Slide detection (E-13): mark any column whose look just changed to one whose rendered width grows,
  // so its track eases to the new per-style min. Render-phase + a prev-look ref, so it catches EVERY
  // look-write path — the column menu's live override AND the property pane's persisted view — through
  // this one point (the setState is guarded, so it settles in a single extra render, no loop).
  const widened: string[] = []
  columns.forEach((c, i) => {
    const look = styleByCol[i].look
    const prev = prevLooks.current[c.id]
    prevLooks.current[c.id] = look
    if (prev === undefined || prev === look) return
    const basis =
      widthOverride[c.id] ?? liveView.column_widths?.[c.id] ?? widthFor(c.id, schema).default
    if (clampWidth(basis, c.id, schema, look) > clampWidth(basis, c.id, schema, prev))
      widened.push(c.id)
  })
  if (widened.some((id) => !sliding.has(id))) setSliding((s) => new Set([...s, ...widened]))
  // The gap-shift geometry for a live column drag — identity changes on slot flips only (the
  // cursor-follow is the grid-level CSS var), which is exactly when rows must re-render.
  const dragShift = useMemo(
    () =>
      colDrag
        ? { from: colDrag.from, to: colDrag.to, width: colWidth(columns[colDrag.from].id) }
        : null,
    // biome-ignore lint/correctness/useExhaustiveDependencies: colWidth's inputs (widths, collapsing) are static during a drag; keying on colDrag + columns is the change surface.
    [colDrag, columns],
  )
  // ONE stable handler identity for every row — calls read the freshest closures through the ref,
  // so memoized rows never re-render for handler churn (and never call a stale state writer).
  const cellApiRef = useRef({ openCellMenu, onCellClick, cellEditor, removeCellValue })
  cellApiRef.current = { openCellMenu, onCellClick, cellEditor, removeCellValue }
  const cellApi = useMemo<RowCellApi>(
    () => ({
      menu: (row, col, e) => void cellApiRef.current.openCellMenu(row, col, e),
      click: (row, col, e) => cellApiRef.current.onCellClick(row, col, e),
      overlay: (row, col) => cellApiRef.current.cellEditor(row, col),
      remove: (row, col, next) => cellApiRef.current.removeCellValue(row, col, next),
    }),
    [],
  )
  // The inline editor's target cell (mode 'editor' only — the picker is the table-level cellPicker).
  // Flows to rows as a primitive so ONLY the editing row re-renders on open/close.
  const overlayTarget = editing?.mode === 'editor' ? editing : null
  // The rename popover leaves its cell in flow (unlike the editor overlay), but flips it to the full URL
  // while open so you see what you're aliasing. Threaded like overlayCol — only the renamed row re-renders.
  const renameTarget = editing?.mode === 'rename' ? editing : null
  // The cell being edited in ANY mode (picker/editor/rename) — flows to rows as a primitive for the faint
  // active-cell reveal under Hide Borders; only the editing row re-renders on open/close.
  const activeCell = editing ? { rowId: editing.rowId, colId: editing.colId } : null
  // Row drag (E-3): the flat data-row order + each row's group key + path, feeding the drop-line DnD
  // (tableDnd). Where you drop disambiguates (D-8) — same group reorders, a different group reassigns.
  // Memoized so a selection / resize / drag-frame render doesn't re-walk every group and rebuild both
  // Maps. Lives ABOVE the empty/loading returns — a hook after a conditional return crashes React the
  // moment the condition flips (an empty collection gaining its first page).
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
      rowGroup: new Map(rows.map((r) => [r.id, r.groupKey] as const)),
    }
  }, [groups])

  // The sub-group drop targets: composite band key -> its set + bucket dimensions (F-2). Above the
  // early returns like every hook in this component (see dataRows).
  const subTargets = useMemo(() => {
    const m = new Map<string, { setId: string | null; bucket: string | null }>()
    for (const g of groups) {
      if (g.kind === 'structural-set') {
        for (const c of g.children ?? []) m.set(c.key, { setId: g.key, bucket: c.bucket ?? null })
      } else if (g.kind === 'ungrouped') m.set(g.key, { setId: null, bucket: null })
    }
    return m
  }, [groups])

  if (!ctx) return <div className="table-empty">Loading…</div>
  if (groups.length === 0) return <div className="table-empty">No pages here</div>
  // The Apple table model (Nathan, reverting the elastic-title reflow): EVERY column — title included —
  // holds its resolved width. While the sum fits the pane the trailing filler eats the slack (the capped,
  // content-inset look); the moment any resize/add pushes the sum past the pane, the grid extends beyond
  // the window and the whole view h-scrolls. No column is ever compressed to absorb growth.
  const reflowWidth = columns.reduce((sum, c) => sum + colWidth(c.id), 0)
  reflowRef.current = reflowWidth
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
    // The CSS density factor (screen px per pre-zoom track px) — the RESOLVED `zoom`, which compounds the
    // base density token (--zoom) with the per-block Scale (--block-zoom on a SurfacePM tile). Read the
    // computed property, not the --zoom token alone, so a scaled tile's drag maps 1:1; NOT back-solved from
    // the header's rendered width ÷ its track width (that ratio bakes in the grid's layout slack).
    const zoom = Number.parseFloat(getComputedStyle(grid).getPropertyValue('zoom')) || 1
    const startCenter = hr.left + hr.width / 2 // the dragged column's centre, screen px; it tracks the cursor 1:1
    const startX = e.clientX
    const startY = e.clientY
    // null until the pointer travels ACTIVATION px — a sub-threshold press is a click, not a drag, so the
    // highlight band never flashes and a jittery click can't reorder.
    let current: { from: number; to: number } | null = null
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
      if (
        projected < curLeft - COL_SHIFT_HYSTERESIS ||
        projected > curRight + COL_SHIFT_HYSTERESIS
      ) {
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
      // The cursor-follow is a grid-level var (one style write; the .col-dragging cells consume
      // it) — React state updates only on activation + slot flips, never per move.
      grid.style.setProperty('--col-drag-x', `${(ev.clientX - startX) / zoom}px`)
      if (!current || current.to !== to) {
        current = { from, to }
        setColDrag(current)
      }
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
      grid.style.removeProperty('--col-drag-x')
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
  // The gap-shift translateX for a header during the current drag — the same formula the body cells
  // use (gapShift over the memoized dragShift). The SUBJECT's cursor-follow is not here — it rides
  // the grid-level --col-drag-x var on the .col-dragging cells (per-move, no state).
  const colTransform = (ci: number): string | undefined => gapShift(dragShift, ci)

  // Cross-group drop (D-4): write the dragged page's grouped property to the destination group's value
  // (the no-value band clears it), patching the loaded values now so the row re-groups before the write
  // round-trips (loadValues never re-runs mid-session).
  // Under sub-grouping the destination key is COMPOSITE (set/bucket), so the drop carries two
  // dimensions (F-2): a bucket change writes the property; a set change is a REAL movePage into
  // that set — the property write lands first, while the page still has its current path.
  const reassignRow = (pageId: string, destGroupKey: string): void => {
    const path = rowPath.get(pageId)
    if (!groupPropId || !path) return
    if (subGrouped) {
      const dest = subTargets.get(destGroupKey)
      const cur = subTargets.get(rowGroup.get(pageId) ?? '')
      if (!dest) return
      const destPath = dest.setId === null ? source.path : setPaths.get(dest.setId)
      if (!destPath) return
      const bucketChanged = dest.bucket !== (cur?.bucket ?? null)
      const setChanged = dest.setId !== (cur?.setId ?? null)
      const value = groupKeyToValue(dest.bucket ?? UNGROUPED, groupPropType)
      if (bucketChanged) {
        const prior = values[pageId]
        const patched: PageFrontmatter = {
          ...(prior ?? { id: pageId }),
          properties: applyPropertyValue(prior?.properties, groupPropId, value),
        }
        setValueOverride((prev) => ({ ...prev, [pageId]: patched }))
      }
      void (async () => {
        if (
          bucketChanged &&
          !(await mutate({ op: 'setProperty', path, propertyId: groupPropId, value }))
        )
          return
        if (setChanged) await mutate({ op: 'movePage', path, newParentPath: destPath })
      })()
      return
    }
    const value = groupKeyToValue(destGroupKey, groupPropType)
    const prior = values[pageId]
    const patched: PageFrontmatter = {
      ...(prior ?? { id: pageId }),
      properties: applyPropertyValue(prior?.properties, groupPropId, value),
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
        void mutate({
          op: 'movePage',
          path: firstPath,
          newParentPath: containerPath,
          order: groupPages,
        })
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
            padLeft={memberIndent(itemDepth)}
            dragShift={dragShift}
            alignByCol={alignByCol}
            styleByCol={styleByCol}
            api={cellApi}
            overlayCol={overlayTarget?.rowId === row.id ? overlayTarget.colId : null}
            renameCol={renameTarget?.rowId === row.id ? renameTarget.colId : null}
            activeCol={activeCell?.rowId === row.id ? activeCell.colId : null}
            hideIcon={liveView.hide_page_icons ?? false}
            selected={selection.kind === 'page' && selection.id === row.id}
            dragDisabled={dragDisabled}
            lead={lead}
          />
        )
      }),
      ...(g.children ?? []).flatMap((child) => renderRows(child, itemDepth, itemsVisible)),
    ]
    // Ungrouped root band: no header, no disclosure — its rows sit flush in the grid.
    if (g.kind === 'ungrouped') return members
    // Headered group: the head stays put; its members live in a Reveal so collapse/expand animates the
    // rows (grid-rows 0fr↔1fr) on the same --disclosure motion as the chevron, and collapsed rows leave
    // the DOM. Each row keeps its own grid reading the inherited --cols, so wrapping never breaks the
    // column alignment (A-2).
    return [
      <TableGroupBand
        key={`gb-${g.key}`}
        group={g}
        view={liveView}
        ctx={ctx}
        setNames={setNames}
        setIcons={setIcons}
        source={source}
        setPath={g.kind === 'structural-set' ? setPaths.get(g.key) : undefined}
        // Only a Collection's direct-child Sets open (the sidebar's selectable rule) — deeper sub-Sets
        // are expand-only organizing folders.
        onOpen={
          g.kind === 'structural-set' &&
          source.kind === 'collection' &&
          depth === 0 &&
          setPaths.has(g.key)
            ? () => void select({ kind: 'set', id: g.key, path: setPaths.get(g.key) as string })
            : undefined
        }
        collapsed={isCollapsed}
        onToggle={() => toggleCollapse(g.key)}
        indent={groupIndent(depth)}
      >
        {members}
      </TableGroupBand>,
    ]
  }

  return (
    <div ref={viewRef} className={cx('table-view', overflowing && 'overflowing')}>
      <IconPicker
        open={iconPickerOpen}
        onClose={() => setIconPickerOpen(false)}
        triggerRef={iconCellRef}
        value={iconTarget?.icon}
        onSelect={(icon) => {
          if (iconTarget) void mutate({ op: 'setIcon', path: iconTarget.path, kind: 'page', icon })
        }}
      />
      <BandDnd bands={bands} labelFor={bandLabel} onDrop={onBandDrop}>
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
              columns.length === 1 && 'single-column',
              collapsing != null && 'col-hiding',
              sliding.size > 0 && 'col-sliding',
              colDrag != null && 'col-dragging-active',
              resizing && 'col-resizing-active',
            )}
            style={{ minWidth: reflowWidth, ['--cols']: cols } as React.CSSProperties}
          >
            {/* Header band — each header grabs to smooth-shift its whole column (A-4); the filler sits
              outside the columns, inert. The transitionend on the animated track set commits a column
              hide (E-11) — transform transitions (the drag) carry a different propertyName, so they pass. */}
            <div
              className="table-head"
              onTransitionEnd={(e) => {
                if (e.propertyName !== 'grid-template-columns') return
                commitHide() // no-op unless a hide is in flight
                setSliding((s) => (s.size ? new Set() : s)) // the style-min slide(s) settled
              }}
            >
              {columns.map((c, i) => (
                <ColumnHeader
                  key={c.id}
                  id={c.id}
                  label={columnLabel(c.id, schema, ctx.labels)}
                  icon={headerIcon(c.id)}
                  width={colWidth(c.id)}
                  align={colAlign(c.id)}
                  transform={colTransform(i)}
                  dragging={colDrag?.from === i}
                  onDragStart={(e) => startColumnDrag(e, i)}
                  onResize={resizeColumn}
                  onResizeStart={() => setResizing(true)}
                  onResizeCommit={commitResize}
                  onContextMenu={(e) => void openHeaderMenu(c.id, c.kind === 'title', e)}
                />
              ))}
              {/* Trailing filler in the 1fr track — also the :last-child anchor that keeps the last real
                column's right divider (Table.css). Empty but load-bearing; don't remove. */}
              <div className="cell-filler" aria-hidden="true" />
            </div>
            {/* Rows (E-3) — the drop-line DnD (tableDnd) wraps the whole grid; band heads aren't row
              drag items. */}
            {groups.flatMap((g) => renderRows(g, 0, true))}
          </div>
        </TableRowDnd>
      </BandDnd>
      {cellPicker()}
      {renameField()}
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
  icon,
  width,
  align,
  transform,
  dragging,
  onDragStart,
  onResize,
  onResizeStart,
  onResizeCommit,
  onContextMenu,
}: {
  id: string
  label: string
  icon: React.ReactNode
  width: number
  align: ColumnAlign
  transform: string | undefined
  dragging: boolean
  onDragStart: (e: React.PointerEvent) => void
  onResize: (id: string, width: number) => number
  onResizeStart: () => void
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
    onResizeStart()
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
      {icon}
      {label}
      <span className="col-resizer" onPointerDown={startResize} />
    </div>
  )
}

/** One data row + its hover-revealed drag grip (E-3 / H-5). The grip sits in the lead cell's gutter
 *  lane — the same slot the group disclosure chevron occupies — so handles align with the chevrons and
 *  the row content lines up with the group headers. useTableRowDrag mutes the row while it's lifted. */
/** One stable per-table handler set for the memoized rows — identities never change; calls read
 *  the freshest closures through a ref in TableView. */
type RowCellApi = {
  menu: (row: ViewRow, col: ResolvedColumn, e: React.MouseEvent) => void
  click: (row: ViewRow, col: ResolvedColumn, e: React.MouseEvent) => void
  overlay: (row: ViewRow, col: ResolvedColumn) => React.ReactNode
  remove: (row: ViewRow, col: ResolvedColumn, next: PropertyValue | null) => void
}

type DragShift = { from: number; to: number; width: number }

/** The gap-shift translateX for a cell during a column drag (the dragged column itself rides the
 *  grid-level --col-drag-x var, not an inline transform). */
function gapShift(d: DragShift | null, ci: number): string | undefined {
  if (!d) return undefined
  if (d.to < d.from && ci >= d.to && ci < d.from) return `translateX(${d.width}px)`
  if (d.to > d.from && ci > d.from && ci <= d.to) return `translateX(${-d.width}px)`
  return undefined
}

// Memoized: a row re-renders only when ITS inputs change — every prop is identity-stable across
// unrelated renders (tree pushes, another row's editing, drag frames). `overlayCol` flips only for the
// row holding the inline editor, so only it re-renders on open/close.
const DataRow = memo(function DataRow({
  row,
  columns,
  ctx,
  padLeft,
  dragShift,
  alignByCol,
  styleByCol,
  api,
  overlayCol,
  renameCol,
  activeCol,
  hideIcon,
  selected,
  dragDisabled,
  lead,
}: {
  row: ViewRow
  columns: ResolvedColumn[]
  ctx: ResolveContext
  padLeft: string | undefined
  dragShift: DragShift | null
  alignByCol: ColumnAlign[]
  styleByCol: ColumnStyle[]
  api: RowCellApi
  overlayCol: string | null
  renameCol: string | null
  /** The cell being edited in this row (any mode) — its data-cell wears the faint accent active ring. */
  activeCol: string | null
  hideIcon: boolean
  selected: boolean
  dragDisabled: boolean
  lead: boolean
}): React.JSX.Element {
  const { ref, handle, isDragging } = useTableRowDrag(row.id)
  return (
    <div
      ref={ref}
      className={cx(
        'data-row',
        selected && 'selected',
        isDragging && 'row-dragging',
        lead && 'row-lead',
      )}
      // The whole row is a drag surface, not just the gutter grip — grabbing ANY cell arms the reorder, so a
      // horizontal scroll that pushes the grip out of reach can't block it. A press-release (no move past
      // ACTIVATION) is each CELL's gesture (A-7: only the title navigates; the row background is a no-op);
      // only a real drag reorders. Gated with the grip when reorder is disabled.
      {...(dragDisabled ? {} : handle)}
    >
      {columns.map((c, i) => {
        const style: React.CSSProperties = {
          transform: gapShift(dragShift, i),
          textAlign: alignByCol[i],
        }
        // The lead cell's indent (loose-inset + group nesting) is a LEFT treatment — it tucks left-read
        // content like the Title. A centered first column (a checkbox/switch/chip moved before the Title)
        // must NOT get it: the indent eats the narrow cell and shoves the control off-centre / past the
        // fold, so it clips left. Center-aligned lead → no padding, the control centres in the full cell.
        if (i === 0 && alignByCol[i] === 'left') style.paddingLeft = padLeft
        // Borderless reveal: the edited cell wears the faint accent ring (Table.css, no-borders only).
        const stateCx = activeCol === c.id && 'cell-active'
        // The inline editor (mode 'editor') REPLACES the cell in flow; the value pickers are the
        // table-level cellPicker (portaled), never in the cell.
        const editor = overlayCol === c.id ? api.overlay(row, c) : null
        const content = editor ?? (
          <Cell
            row={row}
            column={c}
            ctx={ctx}
            hideIcon={hideIcon}
            style={styleByCol[i]}
            showFullLink={renameCol === c.id}
            remove={(next) => api.remove(row, c, next)}
          />
        )
        return i === 0 ? (
          <div
            key={c.id}
            className={cx(
              'data-cell',
              'cell-lead',
              dragShift?.from === i && 'col-dragging',
              stateCx,
            )}
            style={style}
            onContextMenu={(e) => api.menu(row, c, e)}
            onClick={(e) => {
              if (!isDragging) api.click(row, c, e)
            }}
          >
            {!dragDisabled && (
              <span
                className="row-grip"
                {...handle}
                onClick={(e) => e.stopPropagation()}
                aria-label="Drag to reorder"
              >
                <Icon name="grip-vertical" size={14} />
              </span>
            )}
            {content}
          </div>
        ) : (
          <div
            key={c.id}
            className={cx('data-cell', dragShift?.from === i && 'col-dragging', stateCx)}
            style={style}
            onContextMenu={(e) => api.menu(row, c, e)}
            onClick={(e) => {
              if (!isDragging) api.click(row, c, e)
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
})
