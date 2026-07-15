import { Fragment, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { MenuItem, MenuSeparator } from '@renderer/design-system/components/menu'
import type { NavTarget } from '@shared/types'
import { useSession } from '../store'
import { navKey } from './navRecents'
import type { ResolvedNav } from './navResolve'
import { EntityGlyph } from './EntityGlyph'
import './navList.css'

const MENU_GLYPH = 13

/** Per-row context menu (Navigation spec: pin / favorite / remove live in a context menu, not the row).
 *  Reuses the app's floating-menu pattern — a self-managed PickerMenu (portal + Bloom + backdrop/Escape
 *  dismiss) of MenuItem rows, hung off a zero-size anchor pinned at the click point. Pin/Favorite labels
 *  flip on live store membership; Remove drops the recents entry. */
function NavRowMenu({ item, x, y, onClose }: { item: ResolvedNav; x: number; y: number; onClose: () => void }): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const isPinned = useSession((s) => s.pins.some((p) => navKey(p) === item.key))
  const isFavorite = useSession((s) => s.favorites.some((f) => navKey(f) === item.key))
  const pinTarget = useSession((s) => s.pinTarget)
  const unpinTarget = useSession((s) => s.unpinTarget)
  const addFavorite = useSession((s) => s.addFavorite)
  const removeFavorite = useSession((s) => s.removeFavorite)
  const removeRecent = useSession((s) => s.removeRecent)

  const act = (fn: () => void) => () => {
    onClose()
    fn()
  }
  return (
    <>
      <span ref={anchorRef} aria-hidden style={{ position: 'fixed', left: x, top: y, width: 0, height: 0 }} />
      <PickerMenu open onDismiss={onClose} triggerRef={anchorRef} center>
        <div className="nav-row-menu">
          <MenuItem
            leading={<Icon name={isPinned ? 'pin-off' : 'pin'} size={MENU_GLYPH} />}
            onClick={act(() => (isPinned ? unpinTarget(item.key) : pinTarget(item.target)))}
          >
            {isPinned ? 'Unpin' : 'Pin'}
          </MenuItem>
          <MenuItem
            leading={<Icon name={isFavorite ? 'star-off' : 'star'} size={MENU_GLYPH} />}
            onClick={act(() => (isFavorite ? removeFavorite(item.key) : addFavorite(item.target)))}
          >
            {isFavorite ? 'Unfavorite' : 'Favorite'}
          </MenuItem>
          <MenuSeparator flush />
          <MenuItem leading={<Icon name="x" size={MENU_GLYPH} />} onClick={act(() => removeRecent(item.key))}>
            Remove
          </MenuItem>
        </div>
      </PickerMenu>
    </>
  )
}

// The stub row list both NavPane + NavMenu render: (icon)(title) … (path). Title takes the slack and
// eclipse-scrolls under the path when long; the path is right-aligned, grows left to a max, then
// eclipse-scrolls itself — both via the shared OverflowScroll. The Figma gallery replaces this.
export function NavList({
  items,
  extras,
  onSelect
}: {
  items: ResolvedNav[]
  /** Unresolvable hits (agenda kinds) — listed inert until Agenda routing ships. */
  extras?: { key: string; title: string; kind: string }[]
  onSelect: (target: NavTarget) => void
}): React.JSX.Element | null {
  const [menu, setMenu] = useState<{ item: ResolvedNav; x: number; y: number } | null>(null)
  if (items.length === 0 && !extras?.length) return null
  return (
    <>
      <ul className="nav-list">
        {items.map((it) => (
          <li key={it.key} className="nav-item" onContextMenu={(e) => {
            e.preventDefault()
            setMenu({ item: it, x: e.clientX, y: e.clientY })
          }}>
            {it.pinned && <Icon name="pin" size={12} className="nav-item-pin" />}
            <button type="button" className="nav-item-main" onClick={() => onSelect(it.target)}>
              <EntityGlyph item={it} size={15} className="nav-item-lead" />
              <OverflowScroll className="nav-item-title">{it.title}</OverflowScroll>
              {it.path.length > 0 && (
                <OverflowScroll className={cx('nav-item-path', text.caption.standard)}>
                  {it.path.map((crumb, i) => (
                    <Fragment key={i}>
                      {i > 0 && <span className="nav-path-sep">›</span>}
                      <Icon name={crumb.icon} size={12} className="nav-path-icon" />
                      <span className="nav-path-name">{crumb.title}</span>
                    </Fragment>
                  ))}
                </OverflowScroll>
              )}
            </button>
          </li>
        ))}
        {extras?.map((e) => (
          <li key={e.key} className="nav-item nav-item-inert" title="Agenda navigation isn't wired yet">
            <span className="nav-item-title">{e.title}</span>
            <span className={cx('nav-item-path', text.caption.standard)}>{e.kind}</span>
          </li>
        ))}
      </ul>
      {menu && <NavRowMenu item={menu.item} x={menu.x} y={menu.y} onClose={() => setMenu(null)} />}
    </>
  )
}
