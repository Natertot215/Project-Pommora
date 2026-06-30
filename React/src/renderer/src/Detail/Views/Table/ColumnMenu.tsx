import { useRef } from 'react'
import { Menu, MenuItem, MenuSurface } from '@renderer/design-system/components/menu'
import { useDismiss } from '@renderer/design-system/components/Popover'

/** The header right-click menu (E-1). Rendered at the `.table-view` level — not inside the th, whose
 *  `overflow: hidden` would clip it — positioned below the clicked header. Just "Hide Property" for now;
 *  the rich header menu (sort/filter/insert) mounts more items here later. */
export function ColumnMenu({
  left,
  top,
  onHide,
  onClose
}: {
  left: number
  top: number
  onHide: () => void
  onClose: () => void
}): React.JSX.Element {
  const ref = useRef<HTMLDivElement>(null)
  useDismiss(ref, onClose, true)
  return (
    <div ref={ref} className="column-menu" style={{ left, top }}>
      <MenuSurface>
        <Menu>
          <MenuItem onClick={onHide}>Hide Property</MenuItem>
        </Menu>
      </MenuSurface>
    </div>
  )
}
