import { useState } from 'react'
import type { BlockEntry, BlockStyle } from '@shared/blocks'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { MenuItem, MenuPaneTopRow, MenuSeparator } from '@renderer/design-system/components/menu'
import { PaneSlider } from '@renderer/Components/Detail/PaneSlider'
import { cx } from '@renderer/design-system/cx'
import * as s from './handleMenu.css'

const CHEVRON = 14
const LEADING = 16

/** The drag-handle menu (G-14/G-16, PickerMenu form): state-dependent root rows — an
 *  unconfigured markdown block links out (the one conversion); a configured page embed
 *  re-picks its Source; a view embed's Source sits inert (sources are per-view). Style
 *  drills to its radio pane; Delete confirms natively in main before resolving. */
export function BlockHandleMenu({
  entry,
  anchor,
  onClose,
  onLinkView,
  onLinkPage,
  onSource,
  onStyle,
  onDuplicate,
  onRemove
}: {
  entry: BlockEntry
  anchor: HTMLElement
  onClose: () => void
  onLinkView: () => void
  onLinkPage: () => void
  onSource: () => void
  onStyle: (style: BlockStyle) => void
  onDuplicate: () => void
  onRemove: () => void
}): React.JSX.Element {
  const [pane, setPane] = useState<'root' | 'style'>('root')
  const style: BlockStyle = entry.style === 'borderless' ? 'borderless' : 'bordered'
  const act = (fn: () => void) => () => {
    onClose()
    fn()
  }
  const chevron = <Icon name="chevron-right" size={CHEVRON} />

  const root = (
    <>
      {entry.type === 'markdown' ? (
        <>
          <MenuItem className={s.row} leading={<Icon name="link" size={LEADING} />} trailing={chevron} onClick={act(onLinkView)}>
            Link View
          </MenuItem>
          <MenuItem className={s.row} leading={<Icon name="link" size={LEADING} />} trailing={chevron} onClick={act(onLinkPage)}>
            Link Page
          </MenuItem>
        </>
      ) : (
        <MenuItem
          className={cx(s.row, entry.type === 'view' && s.rowDisabled)}
          leading={<Icon name="link" size={LEADING} />}
          trailing={chevron}
          onClick={entry.type === 'page' ? act(onSource) : undefined}
        >
          Source
        </MenuItem>
      )}
      <MenuItem className={s.row} leading={<Icon name="palette" size={LEADING} />} trailing={chevron} onClick={() => setPane('style')}>
        Style
      </MenuItem>
      <MenuSeparator flush />
      <MenuItem className={s.row} leading={<Icon name="copy" size={LEADING} />} onClick={act(onDuplicate)}>
        Duplicate
      </MenuItem>
      <MenuItem className={s.row} leading={<Icon name="x" size={LEADING} />} onClick={act(onRemove)}>
        Delete
      </MenuItem>
    </>
  )

  const stylePane = (
    <>
      <MenuPaneTopRow label="Block" current="Style" onBack={() => setPane('root')} />
      {(['bordered', 'borderless'] as const).map((v) => (
        <MenuItem
          key={v}
          className={s.row}
          trailing={style === v ? <Icon name="check" size={CHEVRON} /> : undefined}
          onClick={act(() => onStyle(v))}
        >
          {v === 'bordered' ? 'Bordered' : 'Borderless'}
        </MenuItem>
      ))}
    </>
  )

  return (
    <PickerMenu open onDismiss={onClose} triggerRef={{ current: anchor }}>
      <PaneSlider open={pane === 'style'} root={root} detail={stylePane} minWidth={168} minHeight={0} />
    </PickerMenu>
  )
}
