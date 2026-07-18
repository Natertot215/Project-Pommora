import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { PageFrontmatter } from '@shared/schemas'
import type { CardBanner, SavedView } from '@shared/views'
import { defaultEntityIcon, Icon, iconNameOr } from '@renderer/design-system/symbols'
import { text } from '@renderer/design-system/tokens/typography.css'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { Reveal } from '@renderer/design-system/components/Reveal'
import { type DragItem, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
import { cx } from '@renderer/design-system/cx'
import { assetUrl } from '../../../assetUrl'
import { useSession } from '../../../store'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import { flattenContainer } from '../pipeline/group'
import { resolvedSortCount } from '../pipeline/sort'
import { resolveView } from '../pipeline/resolveView'
import { useActiveView } from '../useActiveView'
import { resolveContainerSchema } from '../Table/TableView'
import { buildSetIcons, buildSetNames, groupLabel } from '../Table/cellResolve'
import { buildResolveContext } from '../Table/resolveContext'
import { NavCrumbs } from '../../../Navigation/NavList'
import type { PathCrumb } from '../../../Navigation/navResolve'
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
  const load = useSession((s) => s.load)
  const nexusId = useSession((s) => s.tree?.nexus.id ?? '')
  const [values, setValues] = useState<Record<string, PageFrontmatter>>({})

  // Lazy value load on container open — the same batch IPC the table rides; `cancelled` guards a
  // fast container swap.
  useEffect(() => {
    let cancelled = false
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
  const manualOrder =
    sortedOrGrouped || manualOverride ? (manualOverride ?? viewOrders[view.id]) : undefined

  const groups = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, values)
    return resolveView({ rows, setTree, view, schema, manualOrder }).groups
  }, [source, values, view, schema, manualOrder])

  // A drop reorders within its band; the committed order is the FULL flattened id list across every
  // band, so the one per-view manual order stays coherent (the sorter reads it as a global index map).
  const reorderInBand = (bandKey: string, activeId: string, overId: string): void => {
    const full: string[] = []
    for (const g of groups) {
      const ids = flattenGroups([g]).map((r) => r.id)
      if (g.key === bandKey) {
        const from = ids.indexOf(activeId)
        const to = ids.indexOf(overId)
        if (from !== -1 && to !== -1 && from !== to) {
          const [moved] = ids.splice(from, 1)
          ids.splice(to, 0, moved)
        }
      }
      full.push(...ids)
    }
    setManualOverride(full)
    void window.nexus.viewOrders.set(view.id, full)
  }

  const setNames = useMemo(() => buildSetNames(source), [source])
  const setIcons = useMemo(() => buildSetIcons(source), [source])
  const ctx = useMemo(() => (tree ? buildResolveContext(tree, schema) : null), [tree, schema])
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
      style={{ '--card-scale': view.card_size ?? 1 } as React.CSSProperties}
    >
      {showSetCards && (
        <div className="set-cards-row">
          {sets.map((s) => (
            <SetCard key={s.id} set={s} />
          ))}
        </div>
      )}
      {groups.map((g) => {
        const rows = flattenGroups([g])
        const isCollapsed = collapsed.has(g.key)
        const glyph = bandGlyph(g)
        return (
          <section key={g.key} className="cards-band">
            <button type="button" className="cards-band-head" onClick={() => toggleCollapse(g.key)}>
              <Icon
                name="chevron-right"
                size={13}
                className={cx('cards-band-twisty', !isCollapsed && 'open')}
              />
              {glyph && <Icon name={glyph} size={14} className="cards-band-glyph" />}
              <span className={cx('cards-band-title', text.body.emphasized)}>{bandLabel(g)}</span>
            </button>
            <Reveal open={!isCollapsed} fill>
              <div className="cards-grid">
                <SortableZone
                  items={rows.map((r) => r.id)}
                  layout="grid"
                  disabled={sortKeys >= 2}
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
                      loc={
                        hideLocation
                          ? undefined
                          : row.parentSetId
                            ? setChains.get(row.parentSetId)
                            : undefined
                      }
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

/** A Set Card (F-1/I-3): banner-only image (placeholder when unset) + icon + title; clicking
 *  navigates to the Set. Rides the page card's chassis at the larger set-row size. */
function SetCard({ set }: { set: SetNode }): React.JSX.Element {
  const select = useSession((s) => s.select)
  const [failed, setFailed] = useState(false)
  const src = set.banner ? assetUrl(set.banner) : undefined
  const iconName = iconNameOr(set.icon, defaultEntityIcon('set'))
  return (
    <button
      type="button"
      className="set-card"
      onClick={(e) =>
        void select({ kind: 'set', id: set.id, path: set.path }, { newTab: e.metaKey })
      }
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
          <OverflowScroll className={cx('page-card-title', text.footnote.emphasized)}>
            <Icon name={iconName} size={14} className="page-card-title-icon" />
            <span className="page-card-title-text">{set.title}</span>
          </OverflowScroll>
        </div>
      </div>
    </button>
  )
}

interface PageCardProps {
  row: ViewRow
  view: SavedView
  banner: CardBanner
  nexusId: string
  loc?: PathCrumb[]
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
  loc,
  drag,
}: PageCardProps & { drag?: DragItem }): React.JSX.Element {
  const select = useSession((s) => s.select)
  const version = useSession((s) => s.thumbVersions[`page:${row.id}`] ?? 0)
  const [failed, setFailed] = useState(false)

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
        if (!drag?.isDragging)
          void select({ kind: 'page', id: row.id, path: row.path }, { newTab: e.metaKey })
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
        <div className="page-card-text">
          {(view.wrap_titles ?? false) ? (
            <span className="page-card-title is-wrap">{titleBody}</span>
          ) : (
            <OverflowScroll className="page-card-title">{titleBody}</OverflowScroll>
          )}
          {loc && loc.length > 0 && (
            <NavCrumbs path={loc} className="page-card-loc" iconSize={11} />
          )}
        </div>
      </div>
    </div>
  )
}
