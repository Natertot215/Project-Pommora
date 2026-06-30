import type { ReactNode } from 'react'
import { chip, chipColor, chipLabel } from '@renderer/design-system/tokens'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { cx } from '@renderer/design-system/cx'

/** The shared pill — the chip recipe (colored fill/border/text) with a capped, hover-scrolling label
 *  (Part 2 G-3). One source for table select/status/multi-select cells AND the inline picker. */
export function Chip({ color, label, icon }: { color: ChipColorName; label: string; icon?: ReactNode }): React.JSX.Element {
  return (
    <span className={cx(chip, chipColor[color])}>
      {icon}
      <span className={chipLabel}>{label}</span>
    </span>
  )
}
