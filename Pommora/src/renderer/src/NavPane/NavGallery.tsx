import { Fragment, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { SortableZone, useDragItem, type DragItem } from '@renderer/design-system/interactions/drag'
import type { NavTarget } from '@shared/types'
import { useSession } from '../store'
import { navKey } from '../Navigation/navRecents'
import type { ResolvedNav } from '../Navigation/navResolve'
import './navGallery.css'

// The gallery view over the same nav data as NavList: pinned cards (reorderable) in one flow above the
// recents cards, no divider. A card is the detail-pane thumbnail (3:2, pin overlaid top-left) over a
// title/location text block. Thumbnails resolve deterministically from the synced assets tree; a miss
// falls back to an icon placeholder. Active card (matches the open selection) gets the accent border.

const thumbFile = (key: string): string => key.replace(':', '-')

export function NavGallery({ pins, items, onSelect }: { pins: ResolvedNav[]; items: ResolvedNav[]; onSelect: (target: NavTarget) => void }): React.JSX.Element {
  const reorderPin = useSession((s) => s.reorderPin)
  const nexusId = useSession((s) => s.tree?.nexus.id ?? '')
  return (
    <div className="nav-gallery">
      {pins.length > 0 && (
        <SortableZone items={pins.map((p) => p.key)} layout="grid" onReorder={(a, o) => reorderPin(a, o)}>
          <div className="nav-gallery-grid">
            {pins.map((it) => (
              <PinnedCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} />
            ))}
          </div>
        </SortableZone>
      )}
      {items.length > 0 && (
        <div className="nav-gallery-grid">
          {items.map((it) => (
            <GalleryCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} />
          ))}
        </div>
      )}
    </div>
  )
}

function PinnedCard(props: { it: ResolvedNav; nexusId: string; onSelect: (t: NavTarget) => void }): React.JSX.Element {
  const drag = useDragItem(props.it.key)
  return <GalleryCard {...props} drag={drag} />
}

function GalleryCard({ it, nexusId, onSelect, drag }: { it: ResolvedNav; nexusId: string; onSelect: (t: NavTarget) => void; drag?: DragItem }): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const version = useSession((s) => s.thumbVersions[it.key] ?? 0)
  const pinTarget = useSession((s) => s.pinTarget)
  const unpinTarget = useSession((s) => s.unpinTarget)
  const [failed, setFailed] = useState(false)

  const active = selection.kind !== 'none' && navKey(selection) === it.key
  const src = `nexus-asset://nexus/.nexus/assets/${nexusId}/thumbnails/${thumbFile(it.key)}.jpg?v=${version}`
  const togglePin = (e: React.MouseEvent): void => {
    e.stopPropagation()
    if (it.pinned) unpinTarget(it.key)
    else pinTarget(it.target)
  }

  return (
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...(drag?.handle ?? { role: 'button', tabIndex: 0 })}
      className={cx('nav-gallery-card', active && 'is-active', drag?.isDragging && 'is-dragging')}
      onClick={() => onSelect(it.target)}
    >
      <div className="nav-gallery-thumb">
        {failed ? (
          <div className="nav-gallery-ph">
            <Icon name={it.icon} size={22} />
          </div>
        ) : (
          <img src={src} loading="lazy" alt="" onError={() => setFailed(true)} />
        )}
        <button type="button" className={cx('nav-gallery-pin', it.pinned && 'is-pinned')} onClick={togglePin} aria-label={it.pinned ? 'Unpin' : 'Pin'}>
          <Icon name="pin" size={13} />
        </button>
      </div>
      <div className="nav-gallery-text">
        <OverflowScroll className={cx('nav-gallery-title', text.footnote.emphasized)}>
          <Icon name={it.icon} size={13} className="nav-gallery-title-icon" />
          {it.title}
        </OverflowScroll>
        {it.path.length > 0 && (
          <OverflowScroll className={cx('nav-gallery-loc', text.caption.standard)}>
            {it.path.map((crumb, i) => (
              <Fragment key={i}>
                {i > 0 && <span className="nav-path-sep">›</span>}
                <Icon name={crumb.icon} size={11} className="nav-path-icon" />
                <span className="nav-path-name">{crumb.title}</span>
              </Fragment>
            ))}
          </OverflowScroll>
        )}
      </div>
    </div>
  )
}
