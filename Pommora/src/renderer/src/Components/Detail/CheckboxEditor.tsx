import { useRef, useState } from 'react'
import { chipColorFor, colorLabel } from '@renderer/design-system/tokens/colorMap'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { Chip } from '../Chip'
import { ColorPicker } from './ColorPicker'
import { PickerControl } from './PickerControl'
import * as s from './settingsPane.css'

export type CheckboxLook = 'checkbox' | 'switch'

const STYLE_OPTIONS: { value: CheckboxLook; label: string }[] = [
  { value: 'checkbox', label: 'Checkbox' },
  { value: 'switch', label: 'Switch' },
]

/** Resolve the pane's colour chip: its key + display label. Absent = the configured accent, shown
 *  "Accent" — as is a chosen colour that equals the accent (the accent is a live user config, so it's
 *  named, never frozen to a palette label). */
function resolveColor(
  color: string | undefined,
  accentName: ChipColorName,
): { name: ChipColorName; label: string } {
  if (!color) return { name: accentName, label: 'Accent' }
  const name = chipColorFor(color)
  return { name, label: name === accentName ? 'Accent' : colorLabel(name) }
}

/**
 * The Checkbox property editor body — a property-wide Colour chip (the Link editor's colour logic:
 * absent = the system accent, "Default") plus a per-VIEW Style picker (Checkbox ⇄ Switch, the shared
 * double-chevron control). The caller owns the two writes: Colour → the def (`setCheckboxColor`),
 * Style → the active view's `column_styles`.
 */
export function CheckboxEditor({
  color,
  look,
  accent,
  onSetColor,
  onSetStyle,
}: {
  color: string | undefined
  look: CheckboxLook
  /** The nexus-configured accent (a palette key). Drives the "Accent" default + the equals-accent label. */
  accent: string | undefined
  onSetColor: (color: string | undefined) => void
  onSetStyle: (look: CheckboxLook) => void
}): React.JSX.Element {
  const [coloring, setColoring] = useState(false)
  const chipRef = useRef<HTMLButtonElement>(null)
  const chosen = resolveColor(color, accent ? chipColorFor(accent) : 'accent')

  return (
    <div className={s.configEditor}>
      <div className={s.configRow}>
        <span className={s.configLabel}>Color</span>
        <span className={s.colorCluster}>
          <button
            ref={chipRef}
            type="button"
            className={s.colorChip}
            onClick={() => setColoring((v) => !v)}
          >
            <Chip shape="label" color={chosen.name} label={chosen.label} />
          </button>
          <ColorPicker
            open={coloring}
            selected={chosen.name}
            onPick={(next) => {
              onSetColor(next)
              setColoring(false)
            }}
            onDismiss={() => setColoring(false)}
            triggerRef={chipRef}
          />
        </span>
      </div>
      <div className={s.configRow}>
        <span className={s.configLabel}>Style</span>
        <PickerControl
          ariaLabel="Checkbox style"
          value={look}
          options={STYLE_OPTIONS}
          onPick={onSetStyle}
        />
      </div>
    </div>
  )
}
