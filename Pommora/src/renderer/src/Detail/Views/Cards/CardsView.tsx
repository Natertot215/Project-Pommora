import { memo, useEffect, useMemo, useRef, useState } from 'react'
import type {
  CollectionNode,
  NexusLabels,
  ResolvedColumn,
  ResolvedGroup,
  SetNode,
  ViewRow,
} from '@shared/types'
import type { PageFrontmatter } from '@shared/schemas'
import { applyPropertyValue, isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { type CardBanner, isCompact, LOCATION_SORT, type SavedView } from '@shared/views'
import type { ColumnStyle } from '@shared/columnStyles'
import { defaultEntityIcon, Icon, iconNameOr } from '@renderer/design-system/symbols'
import { text } from '@renderer/design-system/tokens/typography.css'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { type DragItem, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
import { cx } from '@renderer/design-system/cx'
import { assetUrl } from '../../../assetUrl'
import { useSession } from '../../../store'
import { findCollectionForSet } from '@renderer/Detail/Scope'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import { resolveColumns } from '../pipeline/columns'
import {
  contextOptionsFor as contextOptionsForTier,
  type ContextOption,
} from '../pipeline/contextOptions'
import { flattenContainer, groupsStructurally } from '../pipeline/group'
import { resolvedSortCount, resolveManualOrder } from '../pipeline/sort'
import { resolveFieldValue } from '../pipeline/value'
import { resolveView } from '../pipeline/resolveView'
import { useActiveView } from '../useActiveView'
import { columnLabel, TIER_LEVEL_BY_ID } from '../Table/columnLabel'
import { resolveContainerSchema } from '../Table/TableView'
import { writeTierValue } from '../tierWrite'
import { buildSetIcons, buildSetNames } from '../Table/cellResolve'
import { GroupBand, resolveBandHead } from '../GroupBand'
import { buildResolveContext, type ResolveContext } from '../Table/resolveContext'
import { NavCrumbs } from '../../../Navigation/NavList'
import type { PathCrumb } from '../../../Navigation/navResolve'
import { ADDABLE_TYPES, CardAddPicker } from './CardAddPicker'
import { CardValue } from './CardValue'
import { bandShowsAdd } from './cardsBand'
import { reorderIds } from './cardsOrder'
import { type AddEntry, orderAddableEntries } from './cardValueInput'
import { hiddenListIds, hideShown, unhide } from '@renderer/Components/Detail/hiddenPaneModel'
import { IconPicker } from '@renderer/Components/IconPicker'
import { TextPicker } from '@renderer/design-system/components/TextPicker'
import { isOpenInTabs } from '../../../Tabs/tabsModel'
import './CardsView.css'

// A page's thumbnail file — navKey's `page:<id>` flips its colon to a dash on disk (io/thumbnails).
const thumbSrc = (nexusId: string, pageId: string, v: number): string =>
  `nexus-asset://nexus/.nexus/assets/${nexusId}/thumbnails/page-${pageId}.jpg?v=${v}`

// ONE source for every card/set title's type — the body ramp, semibold.
const cardTitleType = text.body.semibold

/**
 * The Cards renderer — the container's Pages as a resizable card grid over the same pipeline the
 * table reads: the Set Cards row on top, then a flattened disclosure band per resolved group (cards
 * never indent — descendants roll up under their top-level band; ungrouped pages band under the
 * container's own heading). Each card renders its visible properties as interactive values and
 * reorders within its band by drag.
 */
export function CardsView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)
  const openPreview = useSession((s) => s.openPreview)
  const load = useSession((s) => s.load)
  const nexusId = useSession((s) => s.tree?.nexus.id ?? '')
  const [values, setValues] = useState<Record<string, PageFrontmatter>>({})

  // Lazy value load on container open — the same batch IPC the table rides; `cancelled` guards a
  // fast container swap.
  useEffect(() => {
    let cancelled = false
    setValueOverride(null)
    void window.nexus.loadValues(source.path).then((v) => {
      if (!cancelled) setValues(v)
    })
    return () => {
      cancelled = true
    }
  }, [source.path])

  const schema = useMemo(() => (tree ? resolveContainerSchema(tree, source) : []), [tree, source])
  const { view } = useActiveView(source, schema)
  const saveView = useSaveView(source, load)
  const mutate = useSession((s) => s.mutate)

  // Optimistic property patches keyed by page id (the table's pattern): loadValues never re-reads
  // mid-session, so an add-picker commit re-renders only because this patch feeds the pipeline.
  const [valueOverride, setValueOverride] = useState<Record<string, PageFrontmatter> | null>(null)
  const effectiveValues = useMemo(
    () => (valueOverride ? { ...values, ...valueOverride } : values),
    [values, valueOverride],
  )
  const setProperty = (row: ViewRow, propertyId: string, value: PropertyValue | null): void => {
    const prior = effectiveValues[row.id]
    const patched: PageFrontmatter = {
      ...(prior ?? { id: row.id }),
      properties: applyPropertyValue(prior?.properties, propertyId, value),
    }
    setValueOverride((prev) => ({ ...prev, [row.id]: patched }))
    void mutate({ op: 'setProperty', path: row.path, propertyId, value })
  }
  // The commit router (the table's cell-write split): a reserved tier column writes the bare
  // `tierN` frontmatter array through setTier; everything else is a property write.
  const commitValue = (row: ViewRow, column: ResolvedColumn, value: PropertyValue | null): void => {
    if (column.kind === 'tier') {
      const ids = value?.kind === 'context' ? value.value : []
      writeTierValue(
        row,
        column.id,
        ids,
        effectiveValues[row.id] ?? { id: row.id },
        setValueOverride,
        mutate,
      )
      return
    }
    setProperty(row, column.id, value)
  }
  const contextOptionsFor = (column: ResolvedColumn): ContextOption[] | null => {
    const level =
      column.kind === 'tier'
        ? TIER_LEVEL_BY_ID[column.id]
        : schema.find((d) => d.id === column.id)?.context_target?.tier
    if (!level || !tree) return null
    return contextOptionsForTier(level, tree)
  }
  // One card-value Style key — persists per-key into the view's column_styles (the table's writer
  // minus its live override, so a style change flashes through a load() round-trip: v1-acceptable).
  const setColumnStyle = (colId: string, key: keyof ColumnStyle & string, value: string): void => {
    void saveView({
      ...view,
      column_styles: {
        ...view.column_styles,
        [colId]: { ...view.column_styles?.[colId], [key]: value },
      },
    })
  }
  // Adding a property from a card reveals it (place in order + clear the hidden flag), else the allowlist
  // keeps it hidden and the value the user just set never shows. Dedup a reveal already in flight — a
  // multi-select fills per toggle, and the view is stale until the first refetch, so each would re-walk.
  const revealingRef = useRef<Set<string>>(new Set())
  const revealProperty = (id: string): void => {
    if (revealingRef.current.has(id)) return
    if (view.property_order.includes(id) && !view.hidden_properties.includes(id)) return
    revealingRef.current.add(id)
    void saveView({ ...view, ...unhide(view, id) }).finally(() => revealingRef.current.delete(id))
  }
  // Right-click ▸ Remove on a card value — drop the property from this view (its property_order slot
  // stays as a remembered spot, so a later reveal restores it in place). The inverse of revealProperty.
  const hideProperty = (id: string): void => {
    if (view.hidden_properties.includes(id)) return
    void saveView({ ...view, ...hideShown(view, id) })
  }

  // Manual card order — the per-machine viewOrders tiebreaker the table's sorter reads; the
  // override gives instant feedback on a drop. Two+ effective sort criteria retire the drag, the
  // table's law.
  const [viewOrders, setViewOrders] = useState<Record<string, string[]>>({})
  const [manualOverride, setManualOverride] = useState<string[] | null>(null)
  useEffect(() => {
    let cancelled = false
    setManualOverride(null)
    void window.nexus.viewOrders.get().then((m) => {
      if (!cancelled) setViewOrders(m)
    })
    return () => {
      cancelled = true
    }
  }, [source.path])
  const sortKeys = useMemo(() => resolvedSortCount(view.sort, schema), [view.sort, schema])
  const sortedOrGrouped = sortKeys > 0 || view.group != null
  // Sort By: Location on its Location order is a computed filesystem order (drag off); Custom falls to
  // the manual order (drag on). In Location order the per-machine manual order must NOT feed the sorter,
  // or a prior Custom drag persists as the shown order and filesystem order never appears.
  const locationFsOrder =
    view.sort?.[0]?.property_id === LOCATION_SORT &&
    (view.structural_order_mode ?? 'location') === 'location'
  const manualOrder = locationFsOrder
    ? undefined
    : resolveManualOrder(sortedOrGrouped, manualOverride, viewOrders[view.id])

  const groups = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, effectiveValues)
    return resolveView({ rows, setTree, view, schema, manualOrder, flattenStructural: true }).groups
  }, [source, effectiveValues, view, schema, manualOrder])

  // A drop reorders within its band; the committed order is the FULL flattened id list across every
  // band, so the one per-view manual order stays coherent (the sorter reads it as a global index map).
  const reorderInBand = (bandKey: string, activeId: string, overId: string): void => {
    const full: string[] = []
    for (const g of groups) {
      const ids = flattenGroups([g]).map((r) => r.id)
      full.push(...(g.key === bandKey ? reorderIds(ids, activeId, overId) : ids))
    }
    setManualOverride(full)
    void window.nexus.viewOrders.set(view.id, full)
  }
  // Set-Card reorder — writes the container's set_order via moveSet (the sidebar's mechanism); the
  // dragged set stays under the same parent (a pure reorder, not a reparent). No optimistic reorder,
  // so the fresh order lands on the load() that moveSet triggers.
  const reorderSets = (activeId: string, overId: string): void => {
    const order = reorderIds(
      sets.map((s) => s.id),
      activeId,
      overId,
    )
    const moved = sets.find((s) => s.id === activeId)
    if (moved) void mutate({ op: 'moveSet', path: moved.path, newParentPath: source.path, order })
  }

  const setNames = useMemo(() => buildSetNames(source), [source])
  const setIcons = useMemo(() => buildSetIcons(source), [source])
  const ctx = useMemo(() => (tree ? buildResolveContext(tree, schema) : null), [tree, schema])
  const columns = useMemo(() => resolveColumns(view, schema), [view, schema])
  const labels = tree?.labels
  // Set id → its within-container location trail (Set › Sub-set crumbs) — one walk, read per card.
  const setChains = useMemo(() => {
    const m = new Map<string, PathCrumb[]>()
    const walk = (sets: SetNode[] | undefined, trail: PathCrumb[]): void => {
      for (const s of sets ?? []) {
        const t = [...trail, { icon: iconNameOr(s.icon, defaultEntityIcon('set')), title: s.title }]
        m.set(s.id, t)
        walk(s.sets, t)
      }
    }
    walk(source.sets, [])
    return m
  }, [source])
  // Under location (structural) grouping the band header IS the top-level set, so the breadcrumb
  // drops that leading crumb and starts at the next set down — the band already shows it.
  // Property/flat grouping keeps the full chain (the band is a bucket, not a location).
  const structural = useMemo(() => groupsStructurally(view.group, schema), [view.group, schema])
  // Group By: None → a single headerless, flattened band.
  const flatMode = view.group?.kind === 'flat'

  // Band collapse — seeded from the view, persisted through the shared writer (the table's model).
  const [collapsed, setCollapsed] = useState<Set<string>>(
    () => new Set(view.collapsed_groups ?? []),
  )
  // biome-ignore lint/correctness/useExhaustiveDependencies: re-seed only on a view switch.
  useEffect(() => {
    setCollapsed(new Set(view.collapsed_groups ?? []))
    // Two cards views on one container share this instance (keyed by source.id), so the [source.path]
    // reset above never fires on a cards→cards switch — drop the drag override here too, or view B
    // renders in view A's manual order (the table resets manualOverride on its own [view.id] effect).
    setManualOverride(null)
  }, [view.id])
  const toggleCollapse = (key: string): void => {
    const next = new Set(collapsed)
    if (next.has(key)) next.delete(key)
    else next.add(key)
    setCollapsed(next)
    // The local `collapsed` state already shows the toggle — skip the refetch's redundant full walk.
    void saveView({ ...view, collapsed_groups: [...next] }, { skipRefetch: true })
  }

  const banner: CardBanner = view.card_banner ?? 'cover'
  const sets = source.sets ?? []
  const showSetCards = (view.set_cards ?? true) && sets.length > 0
  const hideLocation = view.hide_location ?? false
  // A page card honors the Collection's Open In (like the table's title-click): a page-preview owner
  // opens the floating preview; ⌘ (or a full-page owner) routes to a tab. Sets always open the set.
  const owner =
    source.kind === 'collection' ? source : tree ? findCollectionForSet(tree, source.id) : undefined
  const openPage = (row: ViewRow, newTab: boolean): void => {
    if (owner?.openIn === 'page-preview' && !newTab) openPreview({ id: row.id, path: row.path })
    else void select({ kind: 'page', id: row.id, path: row.path }, { newTab })
  }

  // Card handlers handed to memoized cards as ONE identity-stable object (the table's cellApi idiom):
  // a ref carries the live closures, the memo wrapper never changes reference. So a card bails on a
  // parent re-render that leaves its own inputs untouched — chiefly a band collapse in a large
  // container, which then repaints its header, not every card.
  const handlersRef = useRef({
    commitValue,
    setColumnStyle,
    contextOptionsFor,
    openPage,
    revealProperty,
    hideProperty,
  })
  handlersRef.current = {
    commitValue,
    setColumnStyle,
    contextOptionsFor,
    openPage,
    revealProperty,
    hideProperty,
  }
  const cardApi = useMemo(
    () => ({
      onCommitValue: (row: ViewRow, column: ResolvedColumn, value: PropertyValue | null) =>
        handlersRef.current.commitValue(row, column, value),
      onStyle: (colId: string, key: keyof ColumnStyle & string, value: string) =>
        handlersRef.current.setColumnStyle(colId, key, value),
      contextOptionsFor: (column: ResolvedColumn) => handlersRef.current.contextOptionsFor(column),
      onOpen: (row: ViewRow, newTab: boolean) => handlersRef.current.openPage(row, newTab),
      onReveal: (id: string) => handlersRef.current.revealProperty(id),
      onHide: (id: string) => handlersRef.current.hideProperty(id),
    }),
    [],
  )
  // Per-card location trail, resolved ONCE per grouping/location change. Under structural grouping the
  // band header IS the top-level set, so the trail drops that leading crumb; property/flat keeps the full
  // chain. Built as a map (not called inline) — chain.slice allocates, and a fresh array per render would
  // defeat each card's memo.
  const locByRow = useMemo(() => {
    const m = new Map<string, PathCrumb[]>()
    if (hideLocation) return m
    for (const r of flattenGroups(groups)) {
      if (!r.parentSetId) continue
      const chain = setChains.get(r.parentSetId)
      if (chain) m.set(r.id, structural ? chain.slice(1) : chain)
    }
    return m
  }, [groups, setChains, structural, hideLocation])

  return (
    <div
      className={cx('cards-view', banner === 'none' && 'is-compact')}
      data-view-id={view.id}
      style={{ '--card-scale': view.card_size ?? 1 } as React.CSSProperties}
    >
      {showSetCards && (
        <div className="set-cards-row">
          <SortableZone
            items={sets.map((s) => s.id)}
            layout="grid"
            onReorder={reorderSets}
            getItemLabel={(id) => sets.find((s) => s.id === id)?.title ?? id}
          >
            {sets.map((s) => (
              <DraggableSetCard key={s.id} set={s} />
            ))}
          </SortableZone>
        </div>
      )}
      {groups.map((g) => {
        const rows = flattenGroups([g])
        // Group By: None is one headerless, force-open band — a stale collapse from another grouping
        // would otherwise hide every card with no head to toggle.
        const isCollapsed = !flatMode && collapsed.has(g.key)
        const head = ctx ? resolveBandHead(g, view, ctx, setNames, setIcons, source) : null
        return (
          <GroupBand
            key={g.key}
            glyph={head?.glyph}
            collapsed={isCollapsed}
            onToggle={() => toggleCollapse(g.key)}
            showAdd={bandShowsAdd(g.kind)}
            headless={flatMode}
            fill
          >
            <div className="cards-grid">
              <SortableZone
                items={rows.map((r) => r.id)}
                layout="grid"
                // Sort By: Location on its filesystem order is computed — a drop can't reorder it
                // (that's a movePage, deferred), so drag is off; the Custom order keeps drag on.
                disabled={sortKeys >= 2 || locationFsOrder}
                onReorder={(a, b) => reorderInBand(g.key, a, b)}
                getItemLabel={(id) => rows.find((r) => r.id === id)?.title ?? id}
              >
                {rows.map((row) => (
                  <PageCard
                    key={row.id}
                    row={row}
                    view={view}
                    banner={banner}
                    nexusId={nexusId}
                    columns={columns}
                    ctx={ctx}
                    labels={labels}
                    loc={locByRow.get(row.id)}
                    onCommitValue={cardApi.onCommitValue}
                    onStyle={cardApi.onStyle}
                    contextOptionsFor={cardApi.contextOptionsFor}
                    onOpen={cardApi.onOpen}
                    onReveal={cardApi.onReveal}
                    onHide={cardApi.onHide}
                  />
                ))}
              </SortableZone>
            </div>
          </GroupBand>
        )
      })}
    </div>
  )
}

// The cards view never indents: a band's descendants' pages roll up flat, in resolved order.
function flattenGroups(groups: ResolvedGroup[]): ViewRow[] {
  const out: ViewRow[] = []
  const walk = (gs: ResolvedGroup[]): void => {
    for (const g of gs) {
      out.push(...g.items)
      if (g.children) walk(g.children)
    }
  }
  walk(groups)
  return out
}

/** Wires a Set Card into the set-cards-row's SortableZone (reorder routes through moveSet). */
function DraggableSetCard({ set }: { set: SetNode }): React.JSX.Element {
  const drag = useDragItem(set.id)
  return <SetCard set={set} drag={drag} />
}

/** A Set Card: banner-only image (placeholder when unset) + icon + title; clicking
 *  navigates to the Set (guarded so a reorder-drop doesn't navigate). Rides the page card's chassis
 *  at the larger set-row size. */
function SetCard({ set, drag }: { set: SetNode; drag?: DragItem }): React.JSX.Element {
  const select = useSession((s) => s.select)
  const [failed, setFailed] = useState(false)
  const src = set.banner ? assetUrl(set.banner) : undefined
  const iconName = iconNameOr(set.icon, defaultEntityIcon('set'))
  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: the drag handle supplies the interaction role.
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...(drag?.handle ?? { role: 'button', tabIndex: 0 })}
      className={cx('set-card', drag?.isDragging && 'is-dragging')}
      onClick={(e) => {
        if (!drag?.isDragging)
          void select({ kind: 'set', id: set.id, path: set.path }, { newTab: e.metaKey })
      }}
    >
      <div className="page-card-body hover-pop">
        <div className="page-card-thumb">
          {src && !failed ? (
            <img src={src} alt="" onError={() => setFailed(true)} />
          ) : (
            <span className="page-card-ph">
              <Icon name={iconName} size={26} />
            </span>
          )}
        </div>
        <div className="page-card-text">
          <OverflowScroll className={cx('page-card-title', cardTitleType)}>
            <Icon name={iconName} className="page-card-title-icon" />
            <span className="page-card-title-text">{set.title}</span>
          </OverflowScroll>
        </div>
      </div>
    </div>
  )
}

// The whole card is a drag handle (the engine pointer-captures on pointerdown, which would steal an
// inner element's click). An interactive zone stops pointerdown so its click survives; a container
// zone stops only when the pointer starts on its OWN empty space (children like the title still drag).
const stopDrag = (e: React.PointerEvent): void => e.stopPropagation()
const stopDragSelf = (e: React.PointerEvent): void => {
  if (e.target === e.currentTarget) e.stopPropagation()
}

interface PageCardProps {
  row: ViewRow
  view: SavedView
  banner: CardBanner
  nexusId: string
  columns: ResolvedColumn[]
  ctx: ResolveContext | null
  labels: NexusLabels | undefined
  loc?: PathCrumb[]
  onCommitValue: (row: ViewRow, column: ResolvedColumn, value: PropertyValue | null) => void
  onStyle: (colId: string, key: keyof ColumnStyle & string, value: string) => void
  contextOptionsFor: (column: ResolvedColumn) => ContextOption[] | null
  onOpen: (row: ViewRow, newTab: boolean) => void
  onReveal: (id: string) => void
  onHide: (id: string) => void
}

/**
 * The card's property body: the visible, non-blank columns (`shown`), each an interactive
 * CardValue (the per-kind click matrix). Standard = labeled rows; Compact = the label-less
 * clamped value flow in property order. Only rendered when there ARE properties (no empty reserve
 * gap); an empty card's add-input is the breadcrumb. Clicking the flow's empty space adds another.
 */
function CardProperties({
  row,
  view,
  ctx,
  labels,
  shown,
  onZoneClick,
  onCommitValue,
  onStyle,
  onHide,
  contextOptionsFor,
}: Pick<
  PageCardProps,
  'row' | 'view' | 'ctx' | 'labels' | 'onCommitValue' | 'onStyle' | 'onHide' | 'contextOptionsFor'
> & {
  shown: ResolvedColumn[]
  onZoneClick: (e: React.MouseEvent) => void
}): React.JSX.Element | null {
  if (!ctx || !labels) return null
  const compact = isCompact(view)
  // Keep the inline chip-× only at a large-enough card scale: below it the × zone overlaps a short chip
  // and steals the picker click, deleting the value.
  const allowInlineRemove = (view.card_size ?? 1) >= 0.8
  const style = (id: string): ColumnStyle => view.column_styles?.[id] ?? {}
  const zoneClick = (e: React.MouseEvent): void => {
    if (e.target === e.currentTarget) onZoneClick(e)
  }
  const value = (c: ResolvedColumn): React.JSX.Element => (
    <CardValue
      row={row}
      column={c}
      ctx={ctx}
      style={style(c.id)}
      contextOptions={contextOptionsFor(c)}
      onCommit={(col, v) => onCommitValue(row, col, v)}
      onStyle={onStyle}
      onHide={onHide}
      allowInlineRemove={allowInlineRemove}
    />
  )
  return compact ? (
    // biome-ignore lint/a11y/noStaticElementInteractions: the flow's empty space adds a property.
    <div className="card-props is-flow" onClick={zoneClick} onPointerDown={stopDragSelf}>
      {shown.map((c) => (
        <span key={c.id}>{value(c)}</span>
      ))}
    </div>
  ) : (
    // biome-ignore lint/a11y/noStaticElementInteractions: the flow's empty space adds a property.
    <div className="card-props" onClick={zoneClick} onPointerDown={stopDragSelf}>
      {shown.map((c) => (
        <div key={c.id} className="card-prop-row">
          <span className={cx('card-prop-label', text.caption.emphasized)}>
            {columnLabel(c.id, ctx.schema, labels)}
          </span>
          {value(c)}
        </div>
      ))}
    </div>
  )
}

// One card into its band's SortableZone — the drag shell rides the card root (NavGallery's DraggableCard
// split: the engine owns the root's transform; hover-pop lives on the body inside). Memoized (the table's
// DataRow idiom) so a card bails on a parent re-render its inputs didn't touch; the drag hook lives inside,
// so the dragging band still repaints per frame via its Zone.
const PageCard = memo(function PageCard({
  row,
  view,
  banner,
  nexusId,
  columns,
  ctx,
  labels,
  loc,
  onCommitValue,
  onStyle,
  contextOptionsFor,
  onOpen,
  onReveal,
  onHide,
}: PageCardProps): React.JSX.Element {
  const drag = useDragItem(row.id)
  const version = useSession((s) => s.thumbVersions[`page:${row.id}`] ?? 0)
  const [failed, setFailed] = useState(false)

  // The add-picker: the property zone's empty space AND the location row both open it,
  // anchored to the card's text area. Lists the page's blank, pickable properties.
  const [addOpen, setAddOpen] = useState(false)
  const textRef = useRef<HTMLDivElement>(null)
  const openAdd = (e: React.MouseEvent): void => {
    e.stopPropagation()
    // Nothing addable → don't pop a dead-end empty picker (the native menu already omits its submenu).
    if (!drag?.isDragging && addable.length > 0) setAddOpen(true)
  }
  // What shows is the view's VISIBLE property set (`columns` already honors hidden_properties).
  // Standard keeps a blank one as a labeled, fillable row (add = make it visible); Compact's
  // label-less flow can't render an empty value, so there it drops blanks — EXCEPT a checkbox, which
  // renders its own (unchecked) box and is the on-card toggle, so it stays.
  const compactLayout = isCompact(view)
  const shown = useMemo(
    () =>
      ctx
        ? columns.filter(
            (c) =>
              c.kind !== 'title' &&
              (!compactLayout ||
                !isBlankValue(resolveFieldValue(row, c.id, ctx.schema)) ||
                ctx.schema.find((d) => d.id === c.id)?.type === 'checkbox'),
          )
        : [],
    [ctx, columns, row, compactLayout],
  )
  // The add menu is everything NOT currently shown: the Visibility hidden list (hidden tiers + hidden/
  // unaccounted props) plus any schema prop that's revealed-but-blank (compact drops it, so it stays
  // addable to re-fill). Each row's pane vs reveal-only split is computed below (see AddEntry).
  const addable = useMemo<AddEntry[]>(() => {
    if (!ctx || !labels) return []
    const shownIds = new Set(shown.map((c) => c.id))
    const bySchema = new Map(ctx.schema.map((d) => [d.id, d]))
    const ids = [...new Set([...hiddenListIds(view, ctx.schema), ...ctx.schema.map((d) => d.id)])]
    return ids
      .filter((id) => !shownIds.has(id))
      .map((id) => {
        const def = bySchema.get(id) ?? null
        const type = def?.type ?? 'context'
        const blank = isBlankValue(resolveFieldValue(row, id, ctx.schema))
        const revealOnly = !def || !ADDABLE_TYPES.has(type) || type === 'checkbox' || !blank
        return { id, name: columnLabel(id, ctx.schema, labels), type, def, revealOnly }
      })
  }, [ctx, view, row, labels, shown])
  const mutate = useSession((s) => s.mutate)
  const [renameOpen, setRenameOpen] = useState(false)
  const [iconOpen, setIconOpen] = useState(false)
  const [addPicked, setAddPicked] = useState<AddEntry | null>(null)
  // The card's native right-click menu: page meta (Open · Rename · Change Icon · Delete) + an
  // Add Property ▸ submenu — the add path for cards with no in-body add surface. A value right-click
  // is caught by CardValue's own menu (it stops propagation), so this handles the empty/title/thumb.
  const onCardContextMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    if (!ctx || drag?.isDragging) return
    const { tabs, pins } = useSession.getState()
    const alreadyOpen = isOpenInTabs(tabs, pins, { kind: 'page', id: row.id, path: row.path })
    const menuAddable = orderAddableEntries(addable).map((e) => ({ id: e.id, name: e.name }))
    const action = await window.nexus.cardMenu({ addable: menuAddable, alreadyOpen })
    if (!action) return
    if (action === 'title:newtab') onOpen(row, true)
    else if (action === 'title:rename') setRenameOpen(true)
    else if (action === 'title:icon') setIconOpen(true)
    else if (action === 'title:delete') void mutate({ op: 'delete', path: row.path, kind: 'page' })
    else if (action.startsWith('add:')) {
      const entry = addable.find((e) => e.id === action.slice(4))
      if (!entry) return
      // A reveal-only entry (tier/context, hidden-filled, checkbox) just unhides; a pane entry opens
      // the value pane to set a value.
      if (entry.revealOnly) onReveal(entry.id)
      else {
        setAddPicked(entry)
        setAddOpen(true)
      }
    }
  }
  const hasProps = shown.length > 0
  const crumbs = loc ?? []

  const cover = typeof row.frontmatter.cover === 'string' ? row.frontmatter.cover : undefined
  const src =
    banner === 'cover'
      ? cover && assetUrl(cover)
      : banner === 'preview'
        ? thumbSrc(nexusId, row.id, version)
        : undefined
  const iconName = iconNameOr(row.icon, defaultEntityIcon('page'))
  const titleBody = (
    <>
      {!(view.hide_page_icons ?? false) && (
        <Icon name={iconName} className="page-card-title-icon" />
      )}
      <span className="page-card-title-text">{row.title}</span>
    </>
  )

  // The drag engine fires a synthesized click after a pointer drag — a reorder-drop must not
  // navigate (NavGallery's `!isDragging` guard).
  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: the drag handle supplies the interaction role.
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...(drag?.handle ?? { role: 'button', tabIndex: 0 })}
      className={cx('page-card', drag?.isDragging && 'is-dragging')}
      onClick={(e) => {
        if (drag?.isDragging) return
        // Only the title + banner open the page. A click landing anywhere else — a value's picker that
        // just dismissed, the reflowed compact flow, the close-animation window — must not navigate.
        // elementFromPoint reads the real element under the pointer (the drag engine's pointer-capture
        // retargets the click's own target to this card root, so e.target can't be trusted here).
        const hit = document.elementFromPoint(e.clientX, e.clientY)
        if (
          hit &&
          e.currentTarget.contains(hit) &&
          hit.closest('.page-card-title, .page-card-thumb')
        )
          onOpen(row, e.metaKey)
      }}
      onContextMenu={onCardContextMenu}
    >
      <div className="page-card-body hover-pop">
        {banner !== 'none' && (
          <div className="page-card-thumb">
            {src && !failed ? (
              <img src={src} alt="" onError={() => setFailed(true)} />
            ) : (
              <span className="page-card-ph">
                <Icon name={iconName} size={22} />
              </span>
            )}
          </div>
        )}
        {/* biome-ignore lint/a11y/noStaticElementInteractions: empty text-area space is an add surface (title/props/loc bubble past). */}
        <div
          className="page-card-text"
          ref={textRef}
          onClick={(e) => {
            if (e.target === e.currentTarget) openAdd(e)
          }}
          onPointerDown={stopDragSelf}
        >
          {(view.wrap_titles ?? false) ? (
            <span className={cx('page-card-title is-wrap', cardTitleType)}>{titleBody}</span>
          ) : (
            <OverflowScroll className={cx('page-card-title', cardTitleType)}>
              {titleBody}
            </OverflowScroll>
          )}
          {hasProps && (
            <CardProperties
              row={row}
              view={view}
              ctx={ctx}
              labels={labels}
              shown={shown}
              onCommitValue={onCommitValue}
              onStyle={onStyle}
              onHide={onHide}
              contextOptionsFor={contextOptionsFor}
              onZoneClick={openAdd}
            />
          )}
          {crumbs.length > 0 && (
            // biome-ignore lint/a11y/noStaticElementInteractions: the breadcrumb is ALWAYS an add-property input — NavCrumbs is non-navigable here.
            <div className="page-card-loc-zone" onClick={openAdd} onPointerDown={stopDrag}>
              <NavCrumbs path={crumbs} className="page-card-loc" iconSize={11} />
            </div>
          )}
        </div>
      </div>
      {addOpen && ctx && (
        <CardAddPicker
          entries={addable}
          currentOf={(e) => resolveFieldValue(row, e.id, ctx.schema)}
          open={addOpen}
          anchorRef={textRef}
          initialEntry={addPicked}
          onCommit={(e, v) => {
            onReveal(e.id)
            onCommitValue(row, { id: e.id, kind: 'property' }, v)
          }}
          onReveal={(e) => onReveal(e.id)}
          onDismiss={() => {
            setAddOpen(false)
            setAddPicked(null)
          }}
        />
      )}
      {renameOpen && (
        <TextPicker
          open={renameOpen}
          triggerRef={textRef}
          value={row.title}
          onCommit={(name) => {
            setRenameOpen(false)
            const t = name.trim()
            if (t && t !== row.title)
              void mutate({ op: 'rename', path: row.path, kind: 'page', newName: t })
          }}
          onDismiss={() => setRenameOpen(false)}
        />
      )}
      {iconOpen && (
        <IconPicker
          open={iconOpen}
          triggerRef={textRef}
          value={typeof row.icon === 'string' ? row.icon : undefined}
          onSelect={(icon) => void mutate({ op: 'setIcon', path: row.path, kind: 'page', icon })}
          onClose={() => setIconOpen(false)}
        />
      )}
    </div>
  )
})
