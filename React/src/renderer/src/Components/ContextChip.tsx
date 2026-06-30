import { chip, chipColor, chipLabel } from '@renderer/design-system/tokens'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { cx } from '@renderer/design-system/cx'

/** A Context reference chip (tier cells, Part 2 G-4): the chip recipe with the Context color on the
 *  border + text, but a neutral quaternary fill and an 8px (non-pill) radius — so it reads as a
 *  reference you can open, distinct from the saturated property-value chips. Deliberately isolated
 *  (its own thin component, inline overrides) so it's trivially swappable. */
export function ContextChip({ color, title }: { color: ChipColorName; title: string }): React.JSX.Element {
  return (
    <span className={cx(chip, chipColor[color])} style={{ background: 'var(--fill-quaternary)', borderRadius: '8px' }}>
      <span className={chipLabel}>{title}</span>
    </span>
  )
}
