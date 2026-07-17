import { Fragment, useEffect, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { TableRowDnd, useTableRowDrag } from '../Detail/Views/Table/tableDnd'
import type { NavTarget, SelectTarget } from '@shared/types'
import { useSession } from '../store'
import { isOpenInTabs } from '../Tabs/tabsModel'
import { navKey } from './navRecents'
import type { ResolvedNav } from './navResolve'
import { EntityGlyph } from './EntityGlyph'
import './navList.css'

/** The location breadcrumb (icon › name › …) shared by the list rows and the gallery cards — same
 *  markup + shared nav-path-* classes, differing only by wrapper class + glyph size. Null when at root. */
export function NavCrumbs({
  path,
  className,
  iconSize,
}: {
  path: ResolvedNav['path']
  className: string
  iconSize: number
}): React.JSX.Element | null {
  if (path.length === 0) return null
  return (
    <OverflowScroll className={cx(className, text.caption.standard)}>
      {path.map((crumb, i) => (
        <Fragment key={i}>
          {i > 0 && <span className="nav-path-sep">›</span>}
          <Icon name={crumb.icon} size={iconSize} className="nav-path-icon" />
          <span className="nav-path-name">{crumb.title}</span>
        </Fragment>
      ))}
    </OverflowScroll>
  )
}

/** Per-row context menu (Navigation spec: open / pin / favorite / remove live in a context menu, not
 *  the row) — a NATIVE Electron menu (the tab/cell-menu pattern), popped at the cursor. The renderer
 *  sends the row's live membership; main returns the chosen action; the labels flip on that state.
 *  Renders nothing: it fires on mount and closes when the menu resolves. Shared by the NavWindow list
 *  AND gallery (the D-3 points). */
export function NavRowMenu({
  item,
  onClose,
  onOpenNewTab,
}: {
  item: ResolvedNav
  onClose: () => void
  onOpenNewTab?: (target: NavTarget) => void
}): null {
  useEffect(() => {
    let live = true
    const s = useSession.getState()
    const target = item.target
    const isPinned = s.pins.some((p) => navKey(p) === item.key)
    const isFavorite = s.favorites.some((f) => navKey(f) === item.key)
    void window.nexus
      .navRowMenu({
        canOpenNewTab: onOpenNewTab !== undefined,
        alreadyOpen: isOpenInTabs(s.tabs, s.pins, target as SelectTarget),
        isPage: target.kind === 'page',
        isPinned,
        isFavorite,
      })
      .then((action) => {
        if (!live) return
        onClose()
        const st = useSession.getState()
        switch (action) {
          case 'open-new-tab':
            onOpenNewTab?.(target)
            break
          case 'open-preview':
            if (target.kind === 'page') {
              // B-2: inside the NavWindow the override routes this to a tab in THAT window
              // (openPreviewTab lands in the open nav flavor); off → the floating preview.
              const ref = { id: target.id, path: target.path }
              if (st.navOpen && (st.previewsFile.navOverride ?? true)) st.openPreviewTab(ref)
              else st.openPreview(ref)
            }
            break
          case 'pin':
            st.pinTarget(target)
            break
          case 'unpin':
            st.unpinTarget(item.key)
            break
          case 'favorite':
            st.addFavorite(target)
            break
          case 'unfavorite':
            st.removeFavorite(item.key)
            break
          case 'remove':
            st.removeRecent(item.key)
            break
        }
      })
    return () => {
      live = false
    }
  }, [item, onClose, onOpenNewTab])
  return null
}

type RowDrag = ReturnType<typeof useTableRowDrag>

// One row: (icon)(title) … (path). Title takes the slack and eclipse-scrolls under the path when long;
// the path is right-aligned, grows left to a max, then eclipse-scrolls itself — both via OverflowScroll.
// The whole row is the drag surface + click target (the drop-line gesture suppresses the post-drag
// click itself); every row is a button-role focusable row, draggable or not.
function NavRow({
  it,
  drag,
  onSelect,
  onMenu,
}: {
  it: ResolvedNav
  drag?: RowDrag
  onSelect: (t: NavTarget) => void
  onMenu: (it: ResolvedNav, e: React.MouseEvent) => void
}): React.JSX.Element {
  return (
    <li
      ref={drag?.ref}
      role="button"
      tabIndex={0}
      onKeyDown={(e: React.KeyboardEvent) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onSelect(it.target)
        }
      }}
      {...drag?.handle}
      className={cx('nav-item', drag?.isDragging && 'is-dragging')}
      onClick={() => onSelect(it.target)}
      onContextMenu={(e) => {
        e.preventDefault()
        onMenu(it, e)
      }}
    >
      {it.pinned && <Icon name="pin" size={12} className="nav-item-pin" />}
      <div className="nav-item-main">
        <EntityGlyph item={it} size={15} className="nav-item-lead" />
        <OverflowScroll className="nav-item-title">{it.title}</OverflowScroll>
        <NavCrumbs path={it.path} className="nav-item-path" iconSize={12} />
      </div>
    </li>
  )
}

function DraggableRow(props: {
  it: ResolvedNav
  onSelect: (t: NavTarget) => void
  onMenu: (it: ResolvedNav, e: React.MouseEvent) => void
}): React.JSX.Element {
  const drag = useTableRowDrag(props.it.key)
  return <NavRow {...props} drag={drag} />
}

// The row list NavWindow renders. `reorderable` runs the app's drop-line gesture (the table/settings
// row drag): an accent insertion line marks the slot, the lifted row mutes in place, nothing displaces.
// Pins and recents are separate groups — reassign is off, so a drag never crosses the boundary. Otherwise
// a plain, static list (favorites rail, search results).
export function NavList({
  items,
  pins,
  extras,
  reorderable,
  onReorderRecent,
  onSelect,
  onOpenNewTab,
}: {
  items: ResolvedNav[]
  /** Reorderable only: the durable pins, rendered as their own group above `items` (the recents) —
   *  membership comes from the caller's pin set, never a flag on the rows (mirrors NavGallery). */
  pins?: ResolvedNav[]
  /** Unresolvable hits (agenda kinds) — listed inert until Agenda routing ships. */
  extras?: { key: string; title: string; kind: string }[]
  /** Run the drop-line drag: pins→reorderPin, recents→reorderRecent, never across the boundary. */
  reorderable?: boolean
  /** Host override for the recents reorder (NavWindow rewrites its frozen snapshot too). */
  onReorderRecent?: (activeKey: string, overKey: string) => void
  onSelect: (target: NavTarget) => void
  /** Wires the row menu's "Open in New Tab" (D-3); omitted = the item doesn't render. */
  onOpenNewTab?: (target: NavTarget) => void
}): React.JSX.Element | null {
  const reorderPin = useSession((s) => s.reorderPin)
  const reorderRecentStore = useSession((s) => s.reorderRecent)
  const reorderRecent = onReorderRecent ?? reorderRecentStore
  const [menu, setMenu] = useState<{ item: ResolvedNav } | null>(null)
  const openMenu = (it: ResolvedNav): void => setMenu({ item: it })
  const pinRows = reorderable ? (pins ?? []) : []
  if (items.length === 0 && pinRows.length === 0 && !extras?.length) return null
  const recents = reorderable ? items : []

  // Translate the gesture's order-shaped commit into the stores' (active, over) shape: `over` is the
  // old order's occupant of the index the dragged row landed on — the exact splice the stores perform.
  const commitReorder = (orderIds: string[], groupKey: string, activeId: string): void => {
    const group = groupKey === 'pins' ? pinRows : recents
    const keys = new Set(group.map((g) => g.key))
    const nextOrder = orderIds.filter((id) => keys.has(id))
    const over = group[nextOrder.indexOf(activeId)]?.key
    if (!over || over === activeId) return
    ;(groupKey === 'pins' ? reorderPin : reorderRecent)(activeId, over)
  }

  const list = (
    <ul className="nav-list">
      {(reorderable ? [...pinRows, ...recents] : items).map((it) =>
        reorderable ? (
          <DraggableRow key={it.key} it={it} onSelect={onSelect} onMenu={openMenu} />
        ) : (
          <NavRow key={it.key} it={it} onSelect={onSelect} onMenu={openMenu} />
        ),
      )}
      {extras?.map((e) => (
        <li
          key={e.key}
          className="nav-item nav-item-inert"
          title="Agenda navigation isn't wired yet"
        >
          <span className="nav-item-title">{e.title}</span>
          <span className={cx('nav-item-path', text.caption.standard)}>{e.kind}</span>
        </li>
      ))}
    </ul>
  )
  return (
    <>
      {reorderable ? (
        <TableRowDnd
          rows={[
            ...pinRows.map((p) => ({ id: p.key, groupKey: 'pins' })),
            ...recents.map((r) => ({ id: r.key, groupKey: 'recents' })),
          ]}
          disabled={false}
          canReorderWithin
          canReassign={false}
          reorderTo={commitReorder}
          reassign={() => {}}
        >
          {list}
        </TableRowDnd>
      ) : (
        list
      )}
      {menu && (
        <NavRowMenu item={menu.item} onClose={() => setMenu(null)} onOpenNewTab={onOpenNewTab} />
      )}
    </>
  )
}
