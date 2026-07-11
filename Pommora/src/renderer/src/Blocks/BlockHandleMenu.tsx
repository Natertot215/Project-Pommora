import { useState } from 'react'
import type { BlockEntry, BlockStyle, DrillPickItem, PagePickerItem, ViewPick, ViewPickerItem } from '@shared/blocks'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { MenuItem, MenuPaneTopRow, MenuScrollFrame, MenuSeparator } from '@renderer/design-system/components/menu'
import { PaneSlider } from '@renderer/Components/Detail/PaneSlider'
import { cx } from '@renderer/design-system/cx'
import * as s from './handleMenu.css'

// Icon seats follow the SettingsPane ladder at this menu's control-size rows:
// the property-row 12 (ICON.doc) for leading glyphs, the twisty 12 for chevrons.
const GLYPH = 12
const MENU_MIN_W = 148

type Pane = { kind: 'root' } | { kind: 'style' } | { kind: 'drill'; which: 'page' | 'view'; stack: number[] }

/** The drag-handle menu (G-14/G-16, PickerMenu form): state-dependent root rows — an
 *  unconfigured markdown block links out (the one conversion); a configured page embed
 *  re-picks its Source; a view embed's Source sits inert (sources are per-view). The
 *  pickers are sliding panes INSIDE the menu (never native); Delete still confirms in
 *  main before resolving. */
export function BlockHandleMenu({
  entry,
  anchor,
  pageItems,
  viewItems,
  onClose,
  onPickPage,
  onPickView,
  onStyle,
  onDuplicate,
  onRemove
}: {
  entry: BlockEntry
  anchor: HTMLElement
  pageItems: PagePickerItem[]
  viewItems: ViewPickerItem[]
  onClose: () => void
  onPickPage: (pageId: string) => void
  onPickView: (pick: ViewPick) => void
  onStyle: (style: BlockStyle) => void
  onDuplicate: () => void
  onRemove: () => void
}): React.JSX.Element {
  const [pane, setPane] = useState<Pane>({ kind: 'root' })
  const style: BlockStyle = entry.style === 'borderless' ? 'borderless' : 'bordered'
  const act = (fn: () => void) => () => {
    onClose()
    fn()
  }
  const chevron = <Icon name="chevron-right" size={GLYPH} />

  const root = (
    <>
      {entry.type === 'markdown' ? (
        <>
          <MenuItem
            className={s.row}
            leading={<Icon name="link" size={GLYPH} />}
            trailing={chevron}
            onClick={() => setPane({ kind: 'drill', which: 'view', stack: [] })}
          >
            Link View
          </MenuItem>
          <MenuItem
            className={s.row}
            leading={<Icon name="link" size={GLYPH} />}
            trailing={chevron}
            onClick={() => setPane({ kind: 'drill', which: 'page', stack: [] })}
          >
            Link Page
          </MenuItem>
        </>
      ) : (
        <MenuItem
          className={cx(s.row, entry.type === 'view' && s.rowDisabled)}
          leading={<Icon name="link" size={GLYPH} />}
          trailing={chevron}
          onClick={entry.type === 'page' ? () => setPane({ kind: 'drill', which: 'page', stack: [] }) : undefined}
        >
          Source
        </MenuItem>
      )}
      <MenuItem className={s.row} leading={<Icon name="palette" size={GLYPH} />} trailing={chevron} onClick={() => setPane({ kind: 'style' })}>
        Style
      </MenuItem>
      <MenuSeparator flush />
      <MenuItem className={s.row} leading={<Icon name="copy" size={GLYPH} />} onClick={act(onDuplicate)}>
        Duplicate
      </MenuItem>
      <MenuItem className={s.row} leading={<Icon name="x" size={GLYPH} />} onClick={act(onRemove)}>
        Delete
      </MenuItem>
    </>
  )

  const stylePane = (
    <>
      <MenuPaneTopRow label="Block" current="Style" onBack={() => setPane({ kind: 'root' })} />
      {(['bordered', 'borderless'] as const).map((v) => (
        <MenuItem
          key={v}
          className={s.row}
          trailing={style === v ? <Icon name="check" size={GLYPH} /> : undefined}
          onClick={act(() => onStyle(v))}
        >
          {v === 'bordered' ? 'Bordered' : 'Borderless'}
        </MenuItem>
      ))}
    </>
  )

  // The drill panes render the same item trees the pickers always used — a node with
  // `submenu` pushes a level, a node with `pick` resolves, separators pass through.
  const drillPane = (which: 'page' | 'view', stack: number[]): React.JSX.Element => {
    const rootLabel = which === 'page' ? (entry.type === 'markdown' ? 'Link Page' : 'Source') : 'Link View'
    let nodes: Array<DrillPickItem<unknown>> = which === 'page' ? pageItems : viewItems
    let title = rootLabel
    let backLabel = 'Block'
    for (const i of stack) {
      const next = nodes[i]
      if (!next?.submenu) break
      backLabel = title
      title = next.label
      nodes = next.submenu
    }
    const resolve = (v: unknown): void => {
      if (which === 'page') onPickPage(v as string)
      else onPickView(v as ViewPick)
    }
    return (
      <MenuScrollFrame header={<MenuPaneTopRow label={backLabel} current={title} onBack={() => setPane(stack.length ? { kind: 'drill', which, stack: stack.slice(0, -1) } : { kind: 'root' })} />}>
        {nodes.map((n, i) =>
          n.separator ? (
            <MenuSeparator key={`sep-${String(i)}`} flush />
          ) : n.submenu ? (
            <MenuItem
              key={`${n.label}-${String(i)}`}
              className={cx(s.row, n.submenu.length === 0 && s.rowDisabled)}
              trailing={chevron}
              onClick={() => setPane({ kind: 'drill', which, stack: [...stack, i] })}
            >
              {n.label}
            </MenuItem>
          ) : (
            <MenuItem
              key={`${n.label}-${String(i)}`}
              className={cx(s.row, n.pick === undefined && s.rowDisabled)}
              onClick={n.pick === undefined ? undefined : act(() => resolve(n.pick))}
            >
              {n.label}
            </MenuItem>
          )
        )}
      </MenuScrollFrame>
    )
  }

  const detail = pane.kind === 'style' ? stylePane : pane.kind === 'drill' ? drillPane(pane.which, pane.stack) : null

  return (
    <PickerMenu open onDismiss={onClose} triggerRef={{ current: anchor }}>
      <PaneSlider open={pane.kind !== 'root'} root={root} detail={detail} minWidth={MENU_MIN_W} minHeight={0} />
    </PickerMenu>
  )
}
