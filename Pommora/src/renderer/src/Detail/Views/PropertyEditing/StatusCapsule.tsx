import type { StatusGroupId } from '@shared/properties'
import { chipCapsule, chipColor } from '@renderer/design-system/tokens'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { cx } from '@renderer/design-system/cx'
import { Icon } from '@renderer/design-system/symbols'
import { statusGroupGlyph } from './statusCycle'

/** The capsule look for a status value — an icon-only chip carrying its group glyph (upcoming falls
 *  back to the dashed circle). Shared by the table cell and the picker's capsule options so the two
 *  can't drift. */
export function StatusCapsule({
  color,
  group,
}: {
  color?: string
  group: StatusGroupId | undefined
}): React.JSX.Element {
  return (
    <span className={cx(chipCapsule, chipColor[chipColorFor(color)])}>
      <Icon name={statusGroupGlyph(group)} size={13} />
    </span>
  )
}
