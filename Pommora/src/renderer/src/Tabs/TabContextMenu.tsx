import { useRef } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { MenuItem, MenuSeparator } from '@renderer/design-system/components/menu'
import { useSession } from '../store'

const MENU_GLYPH = 13

/** A tab's right-click menu (I-12): Pin/Unpin · Close · Close to the Right — the app's floating-menu
 *  pattern (NavRowMenu's shape) hung at the click point. A pinned tab offers Unpin only (D-10 — unpin
 *  reveals the ×); the NavView tab can't pin. Close to the Right acts on the unpinned strip. */
export function TabContextMenu({
  tabId,
  pinned,
  isNewTab,
  hasRight,
  x,
  y,
  onClose
}: {
  tabId: string
  pinned: boolean
  isNewTab: boolean
  hasRight: boolean
  x: number
  y: number
  onClose: () => void
}): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const pinTab = useSession((s) => s.pinTab)
  const unpinTab = useSession((s) => s.unpinTab)
  const closeTab = useSession((s) => s.closeTab)
  const closeTabsRight = useSession((s) => s.closeTabsRight)

  const act = (fn: () => void) => () => {
    onClose()
    fn()
  }
  return (
    <>
      <span ref={anchorRef} aria-hidden style={{ position: 'fixed', left: x, top: y, width: 0, height: 0 }} />
      <PickerMenu open onDismiss={onClose} triggerRef={anchorRef} center>
        <div className="nav-row-menu">
          {!isNewTab && (
            <MenuItem
              leading={<Icon name={pinned ? 'pin-off' : 'pin'} size={MENU_GLYPH} />}
              onClick={act(() => (pinned ? unpinTab(tabId) : pinTab(tabId)))}
            >
              {pinned ? 'Unpin' : 'Pin'}
            </MenuItem>
          )}
          {!pinned && (
            <>
              {!isNewTab && <MenuSeparator flush />}
              <MenuItem leading={<Icon name="x" size={MENU_GLYPH} />} onClick={act(() => closeTab(tabId))}>
                Close
              </MenuItem>
              {hasRight && (
                <MenuItem leading={<Icon name="chevrons-right" size={MENU_GLYPH} />} onClick={act(() => closeTabsRight(tabId))}>
                  Close to the Right
                </MenuItem>
              )}
            </>
          )}
        </div>
      </PickerMenu>
    </>
  )
}
