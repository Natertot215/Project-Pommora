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
import { EntityGlyph } from '../Navigation/EntityGlyph'
import './navGallery.css'

// The gallery view over the same nav data as NavList: pinned cards (reorderable) in one flow above the
// recents cards, no divider. A card is the detail-pane thumbnail (3:2, pin overlaid top-left) over a
// title/location text block. Thumbnails resolve deterministically from the synced assets tree; a miss
// falls back to an icon placeholder. Active card (matches the open selection) gets the accent border.

const thumbFile = (key: string): string => key.replace(':', '-')

export function NavGallery({ pins, items, onSelect }: { pins: ResolvedNav[]; items: ResolvedNav[]; onSelect: (target: NavTarget) => void }): React.JSX.Element {
  const reorderPin = useSession((s) => s.reorderPin)
  const nexusId = useSession((s) => s.tree?.nexus.id ?? '')
  // One grid, one flow: pinned cards first (draggable to reorder), recents straight after them. Only
  // the pins register with the zone, so a drag reorders pins; the recents sit static in the same flow.
  return (
    <div className="nav-gallery">
      <SortableZone items={pins.map((p) => p.key)} layout="grid" onReorder={(a, o) => reorderPin(a, o)}>
        <div className="nav-gallery-grid">
          {pins.map((it) => (
            <PinnedCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} />
          ))}
          {items.map((it) => (
            <GalleryCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} />
          ))}
        </div>
      </SortableZone>
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
  // Adopted entities re-mint their id on adoption, so they can't hold a durable pin — hide the affordance.
  const pinnable = !('id' in it.target && it.target.id.startsWith('adopted-'))
  // The drag engine fires a synthesized click after a pointer drag — don't treat a reorder-drop as a
  // navigation (mirrors TableView's `!isDragging` guard).
  const open = (): void => {
    if (!drag?.isDragging) onSelect(it.target)
  }
  const togglePin = (e: React.MouseEvent): void => {
    e.stopPropagation()
    if (it.pinned) unpinTarget(it.key)
    else pinTarget(it.target)
  }

  return (
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...(drag?.handle ?? {
        role: 'button',
        tabIndex: 0,
        onKeyDown: (e: React.KeyboardEvent) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            onSelect(it.target)
          }
        }
      })}
      className={cx('nav-gallery-card', active && 'is-active', drag?.isDragging && 'is-dragging')}
      onClick={open}
    >
      <div className="nav-gallery-card-body hover-pop">
        <div className="nav-gallery-thumb">
        {failed ? (
          <div className="nav-gallery-ph">
            <EntityGlyph item={it} size={22} />
          </div>
        ) : (
          <img src={src} loading="lazy" alt="" onError={() => setFailed(true)} />
        )}
        {pinnable && (
          // stopPropagation on pointerdown too — else the press bubbles to the card's drag handle and
          // arms a reorder instead of toggling the pin.
          <button
            type="button"
            className={cx('nav-gallery-pin', it.pinned && 'is-pinned')}
            onPointerDown={(e) => e.stopPropagation()}
            onClick={togglePin}
            aria-label={it.pinned ? 'Unpin' : 'Pin'}
          >
            <Icon name="pin" size={13} />
          </button>
        )}
      </div>
      <div className="nav-gallery-text">
        <OverflowScroll className={cx('nav-gallery-title', text.footnote.emphasized)}>
          <EntityGlyph item={it} size={13} className="nav-gallery-title-icon" />
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
    </div>
  )
}
