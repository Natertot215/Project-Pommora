import type { ReactNode, MouseEvent, CSSProperties } from 'react'
import { Icon, type IconName } from '../../symbols'
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
export function MenuSeparator({
  flush = false,
  className
}: { flush?: boolean; className?: string } = {}): React.JSX.Element {
  return (
    <div className={cx(s.separator, flush && s.separatorFlush, className)} role="separator">
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
      leading={
        <span className={s.topBarLeadingSymbol}>
          <Icon name="chevron-left" size={14} />
        </span>
      }
      trailing={trailing}
      onClick={onClick}
    >
      <span className={s.topBarLeadingLabel}>{label}</span>
    </MenuItem>
  )
}

/** A flush vertical stack of rows with 6px top/bottom padding. */
export function Menu({ className, children }: { className?: string; children: ReactNode }): React.JSX.Element {
  return <div className={cx(s.menu, className)}>{children}</div>
}

/** The shared icon-button affordance (ellipsis · plus · eye · palette). Box defaults to 16px; pass
 *  `box` for a consumer's own hit target. `variant` classes (ghost/hidden rest) compose via className. */
export function AccessoryButton({
  icon,
  size,
  ariaLabel,
  box,
  onClick,
  className
}: {
  icon: IconName
  size: number
  ariaLabel: string
  box?: number
  onClick: () => void
  className?: string
}): React.JSX.Element {
  return (
    <button
      type="button"
      className={cx(s.accessoryButton, className)}
      style={box ? ({ '--accessory-box': `${box}px` } as CSSProperties) : undefined}
      aria-label={ariaLabel}
      onClick={(e) => {
        e.stopPropagation()
        onClick()
      }}
    >
      <Icon name={icon} size={size} />
    </button>
  )
}

/** A pane's TopRow scheme: the ‹ back row (+ optional trailing action) over its flush separator —
 *  the header pair every pushable pane shares. */
export function MenuPaneTopRow({
  label,
  onBack,
  trailing,
  current,
  contentClassName
}: {
  label: string
  onBack: () => void
  /** A trailing action (⋮) — only ViewSettings + a property editor carry one. */
  trailing?: ReactNode
  /** The current pane's name — a right-side label-secondary breadcrumb when there's no action. */
  current?: string
  /** Scale/tone the CONTENT row only (e.g. the handle menu's barScale) — the separator stays full so a
   *  density zoom never thins or shifts the divider. */
  contentClassName?: string
}): React.JSX.Element {
  const right = trailing ? (
    <span className={s.topBarTrailingSymbol}>{trailing}</span>
  ) : current ? (
    <span className={s.topBarTrailingLabel}>{current}</span>
  ) : undefined
  return (
    <>
      <MenuTopRow label={label} onClick={onBack} className={cx(s.topRowPad, contentClassName)} trailing={right} />
      <MenuSeparator flush className={s.paneSeparator} />
    </>
  )
}

/** A pane footer bar — a flush separator over a row with `leading` pinned left, `trailing` pinned
 *  right. Either side may be absent (a footer needs neither). */
export function MenuBottomRow({ leading, trailing }: { leading?: ReactNode; trailing?: ReactNode }): React.JSX.Element {
  return (
    <>
      <MenuSeparator flush />
      <div className={s.bottomRow}>
        {leading}
        <span style={{ flex: '1 1 auto' }} />
        {trailing}
      </div>
    </>
  )
}

/** Pinned-edge scroll frame — the pane's sole cap + scroll + footer-pin mechanism. An optional `header`
 *  and `footer` hold their place (never scroll) while `children` scroll between them, capped at
 *  `maxHeight` (the dropdown ceiling by default; a pane overrides for its own max). The body is the ONE
 *  overflow region, so nothing slides under an edge; it owns the scroll ancestor, so a drag inside
 *  auto-scrolls it, and carries the shared edge-fade mask. PaneSlider slides between frames but never
 *  caps/scrolls a slot itself — the frame is the single source, so no pane re-wires the cap each time. */
export function MenuScrollFrame({
  header,
  footer,
  maxHeight = s.MENU_MAX_HEIGHT,
  children
}: {
  header?: ReactNode
  footer?: ReactNode
  /** Height ceiling (px) before the body scrolls — defaults to the shared MENU_MAX_HEIGHT. */
  maxHeight?: number
  children: ReactNode
}): React.JSX.Element {
  return (
    <div className={s.scrollFrame} style={{ maxHeight }}>
      {header && <div className={s.scrollFrameEdge}>{header}</div>}
      <div className={cx(s.scrollFrameBody, 'scroll-edge-fade')}>{children}</div>
      {footer && <div className={s.scrollFrameEdge}>{footer}</div>}
    </div>
  )
}
