import { useState } from 'react'
import type { BlockEntry, BlockStyle, DrillPickItem, PagePickerItem, ViewPick, ViewPickerItem } from '@shared/blocks'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { MenuBottomRow, MenuItem, MenuPaneTopRow, MenuScrollFrame, MenuSeparator } from '@renderer/design-system/components/menu'
import { PaneSlider } from '@renderer/Components/Detail/PaneSlider'
import { cx } from '@renderer/design-system/cx'
import * as s from './handleMenu.css'

// Icon seats follow the SettingsPane ladder at this menu's control-size rows:
// the property-row 12 (ICON.doc) for leading glyphs, the twisty 12 for chevrons.
const GLYPH = 12

/** One drill level — a nested PaneSlider per depth (the slider's documented composition),
 *  so every push AND back slides; a flat content swap animates neither. Rows come from the
 *  same DrillPickItem trees the pickers always used. */
function DrillLevel({
  nodes,
  title,
  backLabel,
  onBack,
  resolve
}: {
  nodes: Array<DrillPickItem<unknown>>
  title: string
  backLabel: string
  onBack: () => void
  resolve: (pick: unknown) => void
}): React.JSX.Element {
  const [openIdx, setOpenIdx] = useState<number | null>(null)
  const bodyNodes = nodes.filter((n) => !n.footer)
  const footerNodes = nodes.filter((n) => n.footer)
  const child = openIdx != null ? bodyNodes[openIdx] : null
  const chevron = <Icon name="chevron-right" size={GLYPH} />
  const rows = (
    <div className={s.pane}>
      <MenuScrollFrame
        maxHeight={s.PICKER_MAX_H}
        header={<MenuPaneTopRow label={backLabel} current={title} onBack={onBack} contentClassName={s.barScale} />}
        footer={
          footerNodes.length ? (
            <div className={s.barScale}>
              <MenuBottomRow
              leading={footerNodes.map((n, i) => (
                <button
                  key={`${n.label}-${String(i)}`}
                  type="button"
                  className={s.footerAction}
                  onClick={n.pick === undefined ? undefined : () => resolve(n.pick)}
                >
                  {n.label}
                </button>
              ))}
              />
            </div>
          ) : undefined
        }
      >
        {bodyNodes.map((n, i) =>
          n.submenu ? (
            <MenuItem
              key={`${n.label}-${String(i)}`}
              className={cx(s.row, n.submenu.length === 0 && s.rowDisabled)}
              leading={n.icon ? <Icon name={n.icon} size={GLYPH} /> : undefined}
              trailing={chevron}
              onClick={() => setOpenIdx(i)}
            >
              {n.label}
            </MenuItem>
          ) : (
            <MenuItem
              key={`${n.label}-${String(i)}`}
              className={cx(s.row, n.pick === undefined && s.rowDisabled)}
              leading={n.icon ? <Icon name={n.icon} size={GLYPH} /> : undefined}
              onClick={n.pick === undefined ? undefined : () => resolve(n.pick)}
            >
              {n.label}
            </MenuItem>
          )
        )}
      </MenuScrollFrame>
    </div>
  )
  return (
    <PaneSlider
      open={openIdx != null}
      root={rows}
      detail={
        child?.submenu ? (
          <DrillLevel
            nodes={child.submenu}
            title={child.label}
            backLabel={title}
            onBack={() => setOpenIdx(null)}
            resolve={resolve}
          />
        ) : null
      }
    />
  )
}

/** The drag-handle menu (G-14/G-16, PickerMenu form): state-dependent root rows — an
 *  unconfigured markdown block links out (the one conversion); a configured page embed
 *  re-picks its Source; a view embed's Source sits inert (sources are per-view). The
 *  pickers slide as nested panes INSIDE the menu; Delete still confirms in main. */
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
  onRemove,
  onToggleLock
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
  onToggleLock: () => void
}): React.JSX.Element {
  const [pane, setPane] = useState<'root' | 'style' | 'page' | 'view'>('root')
  const style: BlockStyle = entry.style === 'borderless' ? 'borderless' : 'bordered'
  // Per-tile content lock (B-5): frozen tiles dim + inert every action but Lock itself, which stays
  // live to toggle back. The dim is the house rowDisabled (opacity on the row content, so the text +
  // labels fade, not a full-row veil). Toggling keeps the menu open so the check + dim flip in place.
  const locked = entry.locked ?? false
  const rowMute = locked ? s.rowDisabled : undefined
  const act = (fn: () => void) => () => {
    onClose()
    fn()
  }
  const chevron = <Icon name="chevron-right" size={GLYPH} />

  const root = (
    <div className={s.pane}>
      <MenuScrollFrame
        footer={
          <div className={s.barScale}>
            <MenuSeparator flush className={s.footerDivider} />
            <div className={s.footerRow}>
              <button
                type="button"
                className={s.footerLockAction}
                aria-label={locked ? 'Unlock tile' : 'Lock tile'}
                onClick={() => onToggleLock()}
              >
                <Icon name="lock" size={GLYPH} />
                {locked ? 'Unlock' : 'Lock'}
              </button>
            </div>
          </div>
        }
      >
        {entry.type === 'markdown' ? (
          <>
            <MenuItem className={cx(s.row, rowMute)} leading={<Icon name="link" size={GLYPH} />} trailing={chevron} onClick={locked ? undefined : () => setPane('view')}>
              Link View
            </MenuItem>
            <MenuItem className={cx(s.row, rowMute)} leading={<Icon name="link" size={GLYPH} />} trailing={chevron} onClick={locked ? undefined : () => setPane('page')}>
              Link Page
            </MenuItem>
          </>
        ) : (
          <MenuItem
            className={cx(s.row, entry.type === 'view' && s.rowDisabled, rowMute)}
            leading={<Icon name="link" size={GLYPH} />}
            trailing={chevron}
            onClick={!locked && entry.type === 'page' ? () => setPane('page') : undefined}
          >
            Source
          </MenuItem>
        )}
        <MenuItem className={cx(s.row, rowMute)} leading={<Icon name="palette" size={GLYPH} />} trailing={chevron} onClick={locked ? undefined : () => setPane('style')}>
          Style
        </MenuItem>
        <MenuSeparator flush />
        <MenuItem className={cx(s.row, rowMute)} leading={<Icon name="copy" size={GLYPH} />} onClick={locked ? undefined : act(onDuplicate)}>
          Duplicate
        </MenuItem>
        <MenuItem className={cx(s.row, rowMute)} leading={<Icon name="x" size={GLYPH} />} onClick={locked ? undefined : act(onRemove)}>
          Delete
        </MenuItem>
      </MenuScrollFrame>
    </div>
  )

  const stylePane = (
    <div className={s.pane}>
      <MenuPaneTopRow label="Menu" current="Style" onBack={() => setPane('root')} contentClassName={s.barScale} />

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
    </div>
  )

  const drillRootLabel = pane === 'page' ? (entry.type === 'markdown' ? 'Link Page' : 'Source') : 'Link View'
  const detail =
    pane === 'style' ? (
      stylePane
    ) : pane === 'page' || pane === 'view' ? (
      <DrillLevel
        nodes={pane === 'page' ? pageItems : viewItems}
        title={drillRootLabel}
        backLabel="Menu"
        onBack={() => setPane('root')}
        resolve={(v) => {
          onClose()
          if (pane === 'page') onPickPage(v as string)
          else onPickView(v as ViewPick)
        }}
      />
    ) : null

  return (
    <PickerMenu open onDismiss={onClose} triggerRef={{ current: anchor }} center>
      <PaneSlider open={pane !== 'root'} root={root} detail={detail} />
    </PickerMenu>
  )
}
