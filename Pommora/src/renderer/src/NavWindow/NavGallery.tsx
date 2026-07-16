import { useState } from 'react'
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
import { NavCrumbs, NavRowMenu } from '../Navigation/NavList'
import './navGallery.css'

// The gallery view over the same nav data as NavList: pinned cards then recents in one flow, no divider,
// each zone drag-reorderable within itself. A card is the detail-pane thumbnail (3:2, pin overlaid
// top-left) over a title/location text block. Thumbnails resolve deterministically from the synced assets
// tree; a miss falls back to an icon placeholder. Active card (the open selection) gets the accent border.

const thumbFile = (key: string): string => key.replace(':', '-')

export function NavGallery({ pins, items, frozenLayout, onReorderRecent, onSelect, onOpenNewTab }: { pins: ResolvedNav[]; items: ResolvedNav[]; frozenLayout?: boolean; onReorderRecent?: (activeKey: string, overKey: string) => void; onSelect: (target: NavTarget) => void; onOpenNewTab?: (target: NavTarget) => void }): React.JSX.Element {
  const reorderPin = useSession((s) => s.reorderPin)
  const reorderRecentStore = useSession((s) => s.reorderRecent)
  // A host (NavWindow) can override to also rewrite its frozen snapshot; NavView uses the store directly.
  const reorderRecent = onReorderRecent ?? reorderRecentStore
  const nexusId = useSession((s) => s.tree?.nexus.id ?? '')
  // The cards share NavList's row menu (D-3's gallery point) — same items, same open/pin/favorite state.
  const [menu, setMenu] = useState<{ item: ResolvedNav; x: number; y: number } | null>(null)
  const openMenu = (it: ResolvedNav, e: React.MouseEvent): void => {
    e.preventDefault()
    e.stopPropagation()
    setMenu({ item: it, x: e.clientX, y: e.clientY })
  }
  const card = (it: ResolvedNav): React.JSX.Element => (
    <DraggableCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} onMenu={openMenu} />
  )
  // One grid, two independent zones sharing the flow (no divider): pins reorder among pins, recents among
  // recents — separate zones, so a drag never crosses the boundary. Search results render static (dragging
  // a filtered view would rewrite the recents order out from under the query).
  return (
    <div className="nav-gallery">
      <div className={cx('nav-gallery-grid', frozenLayout && 'is-fill')}>
        {pins.length > 0 && (
          <SortableZone items={pins.map((p) => p.key)} layout="grid" onReorder={reorderPin}>
            {pins.map(card)}
          </SortableZone>
        )}
        {frozenLayout ? (
          items.map((it) => <GalleryCard key={it.key} it={it} nexusId={nexusId} onSelect={onSelect} onMenu={openMenu} />)
        ) : (
          <SortableZone items={items.map((r) => r.key)} layout="grid" onReorder={reorderRecent}>
            {items.map(card)}
          </SortableZone>
        )}
      </div>
      {menu && <NavRowMenu item={menu.item} x={menu.x} y={menu.y} onClose={() => setMenu(null)} onOpenNewTab={onOpenNewTab} />}
    </div>
  )
}

function DraggableCard(props: { it: ResolvedNav; nexusId: string; onSelect: (t: NavTarget) => void; onMenu: (it: ResolvedNav, e: React.MouseEvent) => void }): React.JSX.Element {
  const drag = useDragItem(props.it.key)
  return <GalleryCard {...props} drag={drag} />
}

function GalleryCard({ it, nexusId, onSelect, onMenu, drag }: { it: ResolvedNav; nexusId: string; onSelect: (t: NavTarget) => void; onMenu: (it: ResolvedNav, e: React.MouseEvent) => void; drag?: DragItem }): React.JSX.Element {
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
      onContextMenu={(e) => onMenu(it, e)}
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
        <NavCrumbs path={it.path} className="nav-gallery-loc" iconSize={11} />
      </div>
      </div>
    </div>
  )
}
