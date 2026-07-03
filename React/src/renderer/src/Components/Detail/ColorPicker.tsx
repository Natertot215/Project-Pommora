import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { cx } from '@renderer/design-system/cx'
import * as s from './colorPicker.css'

/** The ten solid-palette keys, laid out 2 columns × 5 rows. */
const SWATCHES = ['red', 'orange', 'yellow', 'green', 'lightBlue', 'cyan', 'blue', 'purple', 'lavender', 'grey'] as const

/**
 * The 2×5 solid-colour picker (Planning 7-3, Phase 2) — a PickerMenu shell over the shared colour
 * tokens. `selected` is the option's resolved chip colour; picking a swatch sets it, picking the
 * already-selected one clears to Default (`onPick(undefined)`). A larger picker over the same tokens
 * is a Prospect — the swatch list is the only thing that grows.
 */
export function ColorPicker({
  open,
  selected,
  onPick,
  onDismiss
}: {
  open: boolean
  selected: ChipColorName
  onPick: (color: string | undefined) => void
  onDismiss: () => void
}): React.JSX.Element | null {
  return (
    <PickerMenu open={open} onDismiss={onDismiss} solid direction="down" align="end" radius={8} notchWidth={14}>
      <div className={s.grid}>
        {SWATCHES.map((color) => (
          <button
            key={color}
            type="button"
            aria-label={color}
            className={cx(s.swatch, s.swatchColor[color])}
            onClick={() => onPick(selected === color ? undefined : color)}
          />
        ))}
      </div>
    </PickerMenu>
  )
}
