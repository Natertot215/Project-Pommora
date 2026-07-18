import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, ResolvedGroup, SetNode, ViewRow } from '@shared/types'
import type { PageFrontmatter } from '@shared/schemas'
import type { CardBanner, SavedView } from '@shared/views'
import { defaultEntityIcon, Icon, iconNameOr } from '@renderer/design-system/symbols'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { cx } from '@renderer/design-system/cx'
import { assetUrl } from '../../../assetUrl'
import { useSession } from '../../../store'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { useActiveView } from '../useActiveView'
import { resolveContainerSchema } from '../Table/TableView'
import './GalleryView.css'

// A page's thumbnail file — navKey's `page:<id>` flips its colon to a dash on disk (io/thumbnails).
const thumbSrc = (nexusId: string, pageId: string, v: number): string =>
  `nexus-asset://nexus/.nexus/assets/${nexusId}/thumbnails/page-${pageId}.jpg?v=${v}`

/**
 * The Gallery renderer — the container's Pages as a resizable card grid over the same pipeline the
 * table reads. First cut: the flat card canvas (image band per the view's Card Banner mode + the
 * title row); grouping bands, properties, Set Cards, and drag arrive with the mechanics pass.
 */
export function GalleryView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
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
  const groups = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, values)
    return resolveView({ rows, setTree, view, schema }).groups
  }, [source, values, view, schema])
  const cards = useMemo(() => flattenGroups(groups), [groups])

  const banner: CardBanner = view.card_banner ?? 'cover'
  return (
    <div
      className="gallery-view"
      style={{ '--card-scale': view.card_size ?? 1 } as React.CSSProperties}
    >
      <div className={cx('gallery-grid', banner === 'none' && 'is-compact')}>
        {cards.map((row) => (
          <GalleryCard key={row.id} row={row} view={view} banner={banner} nexusId={nexusId} />
        ))}
      </div>
    </div>
  )
}

// The gallery never indents (E-2): descendants' pages roll up flat, in resolved order.
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

function GalleryCard({
  row,
  view,
  banner,
  nexusId,
}: {
  row: ViewRow
  view: SavedView
  banner: CardBanner
  nexusId: string
}): React.JSX.Element {
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
        <Icon name={iconName} size={13} className="gallery-card-title-icon" />
      )}
      <span className="gallery-card-title-text">{row.title}</span>
    </>
  )

  return (
    <button
      type="button"
      className="gallery-card"
      onClick={(e) =>
        void select({ kind: 'page', id: row.id, path: row.path }, { newTab: e.metaKey })
      }
    >
      <div className="gallery-card-body hover-pop">
        {banner !== 'none' && (
          <div className="gallery-card-thumb">
            {src && !failed ? (
              <img src={src} alt="" onError={() => setFailed(true)} />
            ) : (
              <span className="gallery-card-ph">
                <Icon name={iconName} size={22} />
              </span>
            )}
          </div>
        )}
        <div className="gallery-card-text">
          {(view.wrap_titles ?? false) ? (
            <span className="gallery-card-title is-wrap">{titleBody}</span>
          ) : (
            <OverflowScroll className="gallery-card-title">{titleBody}</OverflowScroll>
          )}
        </div>
      </div>
    </button>
  )
}
