import { chipContext, chipColor, chipRemovable } from '@renderer/design-system/tokens'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { cx } from '@renderer/design-system/cx'
import { ChipLabel, ChipRemoveButton } from './Chip'

/** A Context reference chip (tier cells, Part 2 G-4). The whole look lives in the chipContext
 *  shape (neutral quaternary fill, 8px radius, --chip-fill following the fill) — this component
 *  only wires the label + remove affordance. */
export function ContextChip({
  color,
  title,
  onRemove,
}: {
  color: ChipColorName
  title: string
  onRemove?: () => void
}): React.JSX.Element {
  return (
    <span className={cx(chipContext, chipColor[color], onRemove && chipRemovable)}>
      {onRemove ? <ChipRemoveButton onRemove={onRemove} /> : null}
      <ChipLabel label={title} removable={!!onRemove} />
    </span>
  )
}
