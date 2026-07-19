import { useEffect, useMemo, useRef, useState } from 'react'
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
import type { CardBanner, SavedView } from '@shared/views'
import type { ColumnStyle } from '@shared/columnStyles'
import { defaultEntityIcon, Icon, iconNameOr } from '@renderer/design-system/symbols'
import { text } from '@renderer/design-system/tokens/typography.css'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { Reveal } from '@renderer/design-system/components/Reveal'
import { type DragItem, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
import { cx } from '@renderer/design-system/cx'
import { assetUrl } from '../../../assetUrl'
import { useSession } from '../../../store'
import { findCollectionForSet } from '@renderer/Detail/Scope'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import { resolveColumns } from '../pipeline/columns'
import { contextOptionsFor as contextOptionsForTier } from '../pipeline/contextOptions'
import { flattenContainer, groupsStructurally } from '../pipeline/group'
import { resolvedSortCount } from '../pipeline/sort'
import { resolveFieldValue } from '../pipeline/value'
import { resolveView } from '../pipeline/resolveView'
import { useActiveView } from '../useActiveView'
import { columnLabel, TIER_LEVEL_BY_ID } from '../Table/columnLabel'
import { resolveContainerSchema } from '../Table/TableView'
import { buildSetIcons, buildSetNames, groupLabel } from '../Table/cellResolve'
import { buildResolveContext, type ResolveContext } from '../Table/resolveContext'
import { NavCrumbs } from '../../../Navigation/NavList'
import type { PathCrumb } from '../../../Navigation/navResolve'
import { ADDABLE_TYPES, CardAddPicker } from './CardAddPicker'
import { CardValue } from './CardValue'
import { bandShowsAdd } from './cardsBand'
import { reorderIds, resolveManualOrder } from './cardsOrder'
import './CardsView.css'

// A page's thumbnail file — navKey's `page:<id>` flips its colon to a dash on disk (io/thumbnails).
const thumbSrc = (nexusId: string, pageId: string, v: number): string =>
  `nexus-asset://nexus/.nexus/assets/${nexusId}/thumbnails/page-${pageId}.jpg?v=${v}`

/**
 * The Cards renderer — the container's Pages as a resizable card grid over the same pipeline the
 * table reads: the Set Cards row on top, then a flattened disclosure band per resolved group (cards
 * never indent — descendants roll up under their top-level band; ungrouped pages band under the
 * container's own heading). Properties on cards and card drag arrive with the mechanics pass.
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
      const tier = TIER_LEVEL_BY_ID[column.id]
      const ids = value?.kind === 'context' ? value.value : []
      const prior = effectiveValues[row.id] ?? { id: row.id }
      setValueOverride((prev) => ({ ...prev, [row.id]: { ...prior, [`tier${tier}`]: ids } }))
      void mutate({ op: 'setTier', path: row.path, tier, contextIds: ids })
      return
    }
    setProperty(row, column.id, value)
  }
  // A context column's pickable list — reserved tiers read their fixed level, a user context prop
  // its target tier; null for anything else (the table's contextOptionsFor).
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

  // Manual card order — the per-machine viewOrders tiebreaker the table's sorter reads (I-9); the
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
  const manualOrder = resolveManualOrder(sortedOrGrouped, manualOverride, viewOrders[view.id])

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
  // drops that leading crumb and starts at the next set down — the band already shows it (E-3).
  // Property/flat grouping keeps the full chain (the band is a bucket, not a location).
  const structural = useMemo(() => groupsStructurally(view.group, schema), [view.group, schema])
  const flatten = view.location_flatten ?? false
  const locFor = (row: ViewRow): PathCrumb[] | undefined => {
    if (hideLocation || !row.parentSetId) return undefined
    const chain = setChains.get(row.parentSetId)
    if (!chain) return undefined
    // Flatten (Sort by Location) suppresses the band head, so show the FULL chain — else a page under
    // a top set gets no footing (E-3); structural-with-heads drops the leading crumb the head shows.
    return structural && !flatten ? chain.slice(1) : chain
  }

  // Band collapse — seeded from the view, persisted through the shared writer (the table's model).
  const [collapsed, setCollapsed] = useState<Set<string>>(
    () => new Set(view.collapsed_groups ?? []),
  )
  // biome-ignore lint/correctness/useExhaustiveDependencies: re-seed only on a view switch.
  useEffect(() => {
    setCollapsed(new Set(view.collapsed_groups ?? []))
  }, [view.id])
  const toggleCollapse = (key: string): void => {
    const next = new Set(collapsed)
    if (next.has(key)) next.delete(key)
    else next.add(key)
    setCollapsed(next)
    void saveView({ ...view, collapsed_groups: [...next] })
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

  // Band identity (E-7): the ungrouped band wears the container's own heading; structural bands
  // their Set's icon + title; property bands the bucket's option label.
  const bandLabel = (g: ResolvedGroup): string =>
    g.kind === 'ungrouped' ? source.title : ctx ? groupLabel(g, view, ctx, setNames) : g.key
  const bandGlyph = (g: ResolvedGroup): string | undefined =>
    g.kind === 'structural-set'
      ? iconNameOr(setIcons.get(g.key), defaultEntityIcon('set'))
      : g.kind === 'ungrouped'
        ? iconNameOr(
            source.icon,
            defaultEntityIcon(source.kind === 'collection' ? 'collection' : 'set'),
          )
        : undefined

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
        // Flatten (Sort by Location) is one headerless, force-open band — a stale _ungrouped collapse
        // from structural mode would otherwise hide every card with no head to toggle.
        const isCollapsed = !flatten && collapsed.has(g.key)
        const glyph = bandGlyph(g)
        return (
          <section key={g.key} className="cards-band">
            {!flatten && (
              <div className="cards-band-head">
                <button
                  type="button"
                  className="cards-band-toggle"
                  onClick={() => toggleCollapse(g.key)}
                >
                  <Icon
                    name="chevron-right"
                    size={13}
                    className={cx('cards-band-twisty', !isCollapsed && 'open')}
                  />
                  {glyph && <Icon name={glyph} size={14} className="cards-band-glyph" />}
                  <span className={cx('cards-band-title', text.body.emphasized)}>
                    {bandLabel(g)}
                  </span>
                </button>
                {/* Hover-revealed add on structural bands only (I-2). Inert (visual + gating) — the
                  create-page routing is Nathan's creation-affordance design, deferred; matches the
                  table's stub. */}
                {bandShowsAdd(g.kind) ? (
                  <button
                    type="button"
                    className="cards-band-add"
                    tabIndex={-1}
                    onPointerDown={(e) => e.stopPropagation()}
                    aria-label="New page in group"
                  >
                    <Icon name="plus" size={13} />
                  </button>
                ) : null}
              </div>
            )}
            <Reveal open={!isCollapsed} fill>
              <div className="cards-grid">
                <SortableZone
                  items={rows.map((r) => r.id)}
                  layout="grid"
                  // Flatten (Sort by Location) is a computed order — a cross-location drop would be a
                  // movePage (deferred) and manualOrder would snap it back, so drag is off in flatten.
                  disabled={sortKeys >= 2 || flatten}
                  onReorder={(a, b) => reorderInBand(g.key, a, b)}
                  getItemLabel={(id) => rows.find((r) => r.id === id)?.title ?? id}
                >
                  {rows.map((row) => (
                    <DraggablePageCard
                      key={row.id}
                      row={row}
                      view={view}
                      banner={banner}
                      nexusId={nexusId}
                      columns={columns}
                      ctx={ctx}
                      labels={labels}
                      onCommitValue={commitValue}
                      onStyle={setColumnStyle}
                      contextOptionsFor={contextOptionsFor}
                      onOpen={openPage}
                      loc={locFor(row)}
                    />
                  ))}
                </SortableZone>
              </div>
            </Reveal>
          </section>
        )
      })}
    </div>
  )
}

// The cards view never indents (E-2): a band's descendants' pages roll up flat, in resolved order.
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

/** Wires a Set Card into the set-cards-row's SortableZone (F-1 reorder → moveSet). */
function DraggableSetCard({ set }: { set: SetNode }): React.JSX.Element {
  const drag = useDragItem(set.id)
  return <SetCard set={set} drag={drag} />
}

/** A Set Card (F-1/I-3): banner-only image (placeholder when unset) + icon + title; clicking
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
          <OverflowScroll className={cx('page-card-title', text.footnote.semibold)}>
            <Icon name={iconName} size={14} className="page-card-title-icon" />
            <span className="page-card-title-text">{set.title}</span>
          </OverflowScroll>
        </div>
      </div>
    </div>
  )
}

type ContextOption = { value: string; label: string; color?: string }

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
}

/**
 * The card's property body (C-2/C-3): the visible, non-blank columns (`shown`), each an interactive
 * CardValue (the ratified per-kind click matrix). Standard = labeled rows; Compact = the label-less
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
  contextOptionsFor,
}: Pick<
  PageCardProps,
  'row' | 'view' | 'ctx' | 'labels' | 'onCommitValue' | 'onStyle' | 'contextOptionsFor'
> & {
  shown: ResolvedColumn[]
  onZoneClick: (e: React.MouseEvent) => void
}): React.JSX.Element | null {
  if (!ctx || !labels) return null
  const compact = (view.format ?? 'standard') === 'compact'
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
          <span className={cx('card-prop-label', text.caption.standard)}>
            {columnLabel(c.id, ctx.schema, labels)}
          </span>
          {value(c)}
        </div>
      ))}
    </div>
  )
}

/** Wires one card into its band's SortableZone — the drag shell rides the card root (NavGallery's
 *  DraggableCard split: the engine owns the root's transform; hover-pop lives on the body inside). */
function DraggablePageCard(props: PageCardProps): React.JSX.Element {
  const drag = useDragItem(props.row.id)
  return <PageCard {...props} drag={drag} />
}

function PageCard({
  row,
  view,
  banner,
  nexusId,
  columns,
  ctx,
  labels,
  loc,
  drag,
  onCommitValue,
  onStyle,
  contextOptionsFor,
  onOpen,
}: PageCardProps & { drag?: DragItem }): React.JSX.Element {
  const version = useSession((s) => s.thumbVersions[`page:${row.id}`] ?? 0)
  const [failed, setFailed] = useState(false)

  // The add-picker (G-1): the property zone's empty space AND the location row both open it,
  // anchored to the card's text area. Lists the page's blank, pickable properties.
  const [addOpen, setAddOpen] = useState(false)
  const textRef = useRef<HTMLDivElement>(null)
  const openAdd = (e: React.MouseEvent): void => {
    e.stopPropagation()
    if (!drag?.isDragging) setAddOpen(true)
  }
  const addable = useMemo(
    () =>
      ctx
        ? ctx.schema.filter(
            (d) =>
              ADDABLE_TYPES.has(d.type) && isBlankValue(resolveFieldValue(row, d.id, ctx.schema)),
          )
        : [],
    [ctx, row],
  )
  // The card's filled properties — the property body renders only when non-empty (no reserve gap),
  // and the breadcrumb becomes the add surface when empty (G-1).
  const shown = useMemo(
    () =>
      ctx
        ? columns.filter(
            (c) => c.kind !== 'title' && !isBlankValue(resolveFieldValue(row, c.id, ctx.schema)),
          )
        : [],
    [ctx, columns, row],
  )
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
        <Icon name={iconName} size={13} className="page-card-title-icon" />
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
        if (!drag?.isDragging) onOpen(row, e.metaKey)
      }}
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
            <span className={cx('page-card-title is-wrap', text.footnote.emphasized)}>
              {titleBody}
            </span>
          ) : (
            <OverflowScroll className={cx('page-card-title', text.footnote.emphasized)}>
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
              contextOptionsFor={contextOptionsFor}
              onZoneClick={openAdd}
            />
          )}
          {crumbs.length > 0 && (
            // biome-ignore lint/a11y/noStaticElementInteractions: the breadcrumb is ALWAYS an add-property input (G-1) — NavCrumbs is non-navigable here.
            <div className="page-card-loc-zone" onClick={openAdd} onPointerDown={stopDrag}>
              <NavCrumbs path={crumbs} className="page-card-loc" iconSize={11} />
            </div>
          )}
        </div>
      </div>
      {addOpen && ctx && (
        <CardAddPicker
          defs={addable}
          currentOf={(d) => resolveFieldValue(row, d.id, ctx.schema)}
          open={addOpen}
          anchorRef={textRef}
          onCommit={(d, v) => onCommitValue(row, { id: d.id, kind: 'property' }, v)}
          onDismiss={() => setAddOpen(false)}
        />
      )}
    </div>
  )
}
