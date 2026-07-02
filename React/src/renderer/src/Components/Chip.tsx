import type { ReactNode } from 'react'
import {
  chip,
  chipColor,
  chipLabel,
  chipLabelBlur,
  chipLabelMelt,
  chipLabelText,
  chipRemovable,
  chipRemove
} from '@renderer/design-system/tokens'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'

/** The shared pill — the chip recipe (colored fill/border/text) with a capped, hover-scrolling label
 *  (Part 2 G-3). One source for table select/status/multi-select cells AND the inline picker.
 *  `onRemove` opts into the hover ×: it removes THIS chip's value, so the handler owns what that
 *  means (one option off a multi, the whole value off a single). */
export function Chip({
  color,
  label,
  icon,
  onRemove
}: {
  color: ChipColorName
  label: string
  icon?: ReactNode
  onRemove?: () => void
}): React.JSX.Element {
  return (
    <span className={cx(chip, chipColor[color], onRemove && chipRemovable)}>
      {onRemove ? <ChipRemoveButton onRemove={onRemove} /> : null}
      {icon}
      <ChipLabel label={label} removable={!!onRemove} />
    </span>
  )
}

/** The chip label, shared by every chip surface. A removable chip renders the text THREE times —
 *  the crisp copy plus its pre-masked melt and blur twins — so hovering the × zone smears the tail
 *  beneath it through opacity swaps alone (see the reveal note in chip.css.ts). */
export function ChipLabel({ label, removable }: { label: string; removable: boolean }): React.JSX.Element {
  return (
    <span className={chipLabel}>
      <span className={chipLabelText}>{label}</span>
      {removable ? (
        <>
          <span className={chipLabelMelt} aria-hidden>
            {label}
          </span>
          <span className={chipLabelBlur} aria-hidden>
            {label}
          </span>
        </>
      ) : null}
    </span>
  )
}

/** The hover-revealed remove × shared by every removable chip surface (Chip, ContextChip, future
 *  chip splits) — the glyph in the chip's text color, the label's tail blurring beneath it.
 *  Swallows pointerdown/click so a remove never arms the row drag or opens the cell's picker. */
export function ChipRemoveButton({ onRemove }: { onRemove: () => void }): React.JSX.Element {
  return (
    <button
      type="button"
      className={chipRemove}
      aria-label="Remove"
      onPointerDown={(e) => e.stopPropagation()}
      onClick={(e) => {
        e.stopPropagation()
        onRemove()
      }}
    >
      <Icon name="x" size={11} strokeWidth={3} />
    </button>
  )
}
