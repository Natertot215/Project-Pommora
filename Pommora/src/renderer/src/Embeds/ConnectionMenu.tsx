import { useRef } from 'react'
import { MenuItem } from '@renderer/design-system/components/menu'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { Icon } from '@renderer/design-system/symbols'
import type { ConnPage } from '@renderer/MarkdownPM/connections'
import { useSession } from '../store'

/** The wikilink right-click menu — a self-managed PickerMenu hung off a zero-size anchor pinned at
 *  the click point (the NavRowMenu pattern). Hosted by every ConnectionsApi provider. */
export function ConnectionMenu({
  page,
  x,
  y,
  onClose,
}: {
  page: ConnPage
  x: number
  y: number
  onClose: () => void
}): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const openPreview = useSession((s) => s.openPreview)
  return (
    <>
      <span
        ref={anchorRef}
        aria-hidden
        style={{ position: 'fixed', left: x, top: y, width: 0, height: 0 }}
      />
      <PickerMenu open onDismiss={onClose} triggerRef={anchorRef} center>
        <MenuItem
          leading={<Icon name="app-window" size={13} />}
          onClick={() => {
            onClose()
            openPreview({ id: page.id, path: page.path })
          }}
        >
          Open in Preview
        </MenuItem>
      </PickerMenu>
    </>
  )
}
