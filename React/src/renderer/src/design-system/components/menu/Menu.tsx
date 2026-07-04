import type { ReactNode, MouseEvent, CSSProperties } from 'react'
import { Icon } from '../../symbols'
import * as s from './menu.css'
import { cx } from '../../cx'

type MenuItemProps = {
  /** Leading glyph cluster — disclosure and/or icon (label-secondary, sized at 1em). */
  leading?: ReactNode
  /** Optional second line under the title (Caption, secondary). */
  subLabel?: ReactNode
  /** Optional trailing detail text (Footnote, secondary) — e.g. a count or shortcut. */
  detail?: ReactNode
  /** Optional trailing glyph — e.g. a submenu chevron (1em, secondary). */
  trailing?: ReactNode
  selected?: boolean
  /** Tree depth — adds 14px of left inset per level on top of the 8px base. */
  indent?: number
  onClick?: () => void
  onContextMenu?: (e: MouseEvent) => void
  className?: string
  /** The title line. */
  children: ReactNode
}

/** The row primitive (menu item + sidebar row). Geometry + states only — every
 *  behaviour (selection, rename, drag, context menu) is the consumer's, passed in. */
export function MenuItem({
  leading,
  subLabel,
  detail,
  trailing,
  selected = false,
  indent = 0,
  onClick,
  onContextMenu,
  className,
  children
}: MenuItemProps): React.JSX.Element {
  const rowStyle: CSSProperties | undefined = indent ? { paddingLeft: 8 + indent * 14 } : undefined
  const hasTrailing = detail != null || trailing != null
  return (
    <div
      className={cx(s.item, selected && s.itemSelected, className)}
      style={rowStyle}
      onClick={onClick}
      onContextMenu={onContextMenu}
    >
      {leading != null && <span className={s.side}>{leading}</span>}
      <span className={s.titleWrap}>
        <span className={s.titleText}>{children}</span>
        {subLabel != null && <span className={s.subLabel}>{subLabel}</span>}
      </span>
      {hasTrailing && (
        <span className={s.side}>
          {detail != null && <span className={s.detail}>{detail}</span>}
          {trailing}
        </span>
      )}
    </div>
  )
}

/** A heading row within a menu — 13px Semibold, label-secondary. */
export function MenuHeading({
  leading,
  detail,
  children
}: {
  leading?: ReactNode
  detail?: ReactNode
  children: ReactNode
}): React.JSX.Element {
  return (
    <div className={s.heading}>
      {leading != null && <span className={s.side}>{leading}</span>}
      <span className={s.titleText} style={{ flex: '1 1 auto', minWidth: 0 }}>
        {children}
      </span>
      {detail != null && <span className={cx(s.side, s.detail)}>{detail}</span>}
    </div>
  )
}

/** A horizontal divider between menu groups — 11px band, centered hairline. `flush` drops the side
 *  inset so the hairline spans the full gutter (aligns with full-width rows inside a MenuSurface). */
export function MenuSeparator({ flush = false }: { flush?: boolean } = {}): React.JSX.Element {
  return (
    <div className={cx(s.separator, flush && s.separatorFlush)} role="separator">
      <span className={s.separatorLine} />
    </div>
  )
}

/** A non-interactive caption / empty-state line inside a menu — body text, centered + secondary. */
export function MenuCaption({ children }: { children: ReactNode }): React.JSX.Element {
  return <div className={s.caption}>{children}</div>
}

/** A pane's TopRow — a leading ‹ chevron + label that pops the nav stack one level, plus an optional
 *  trailing action (the property editor's ⋮ / the list's +). The action rides the row's trailing slot
 *  so it reads — and colours — as part of the TopRow, not a floating toolbar button beside it.
 *  `className` composes surface-local tuning (e.g. the ViewPane's vertical-padding knob). */
export function MenuTopRow({
  label,
  onClick,
  className,
  trailing
}: {
  label: string
  onClick: () => void
  className?: string
  trailing?: ReactNode
}): React.JSX.Element {
  return (
    <MenuItem
      className={cx(s.topRow, trailing != null && s.flushTrailing, className)}
      leading={<Icon name="chevron-left" size={12} />}
      trailing={trailing}
      onClick={onClick}
    >
      {label}
    </MenuItem>
  )
}

/** A flush vertical stack of rows with 6px top/bottom padding. */
export function Menu({ className, children }: { className?: string; children: ReactNode }): React.JSX.Element {
  return <div className={cx(s.menu, className)}>{children}</div>
}
