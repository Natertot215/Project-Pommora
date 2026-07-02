import { useRef } from 'react'
import { isUntouchedSeed, type PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { PickerMenu, PickerOption } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { Chip } from '@renderer/Components/Chip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'

/** A pickable option — status options flatten out of their groups, select/multi read
 *  `select_options`. An untouched creation seed is scaffolding, not defined options: the
 *  picker renders empty until the user makes them real. */
const optionsOf = (def: PropertyDefinition): Array<{ value: string; label: string; color?: string }> => {
  if (isUntouchedSeed(def)) return []
  return def.type === 'status' ? (def.status_groups ?? []).flatMap((g) => g.options) : (def.select_options ?? [])
}

const selectedValues = (current: PropertyValue | null): string[] => {
  if (!current) return []
  if (current.kind === 'multiSelect') return current.value
  if (current.kind === 'select' || current.kind === 'status') return [current.value]
  return []
}

/**
 * The value dropdown every container view's status/select/multi cells share (F-2: PickerMenu for
 * values, native menus for meta). Table-agnostic and stateless: props in, `onCommit(PropertyValue)`
 * out — the caller owns the write, the optimistic patch, and open/close (`closing` rides to the
 * PickerMenu Bloom so the exit plays before unmount). Single-value types commit + dismiss on pick;
 * multi toggles against `current` and stays open.
 */
export function PropertyPicker({
  def,
  current,
  closing,
  onCommit,
  onDismiss
}: {
  def: PropertyDefinition
  current: PropertyValue | null
  closing: boolean
  onCommit: (value: PropertyValue | null) => void
  onDismiss: () => void
}): React.JSX.Element | null {
  const ref = useRef<HTMLDivElement>(null)
  const options = optionsOf(def)
  useDismiss(ref, onDismiss, !closing)
  const multi = def.type === 'multi_select'
  const selected = selectedValues(current)

  const pick = (value: string): void => {
    if (multi) {
      const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value]
      onCommit({ kind: 'multiSelect', value: next })
      return
    }
    onCommit(def.type === 'status' ? { kind: 'status', value } : { kind: 'select', value })
    onDismiss()
  }

  return (
    <div ref={ref}>
      <PickerMenu closing={closing}>
        {options.length === 0 ? (
          // A seed-only def pickers EMPTY (Nathan: scaffolding isn't options) — the spacer keeps
          // the notch pane's proportions so it doesn't collapse into a degenerate beak. Tune here.
          <div style={{ minWidth: 96, height: 24 }} />
        ) : (
          options.map((o) => (
            <PickerOption key={o.value} selected={selected.includes(o.value)} onClick={() => pick(o.value)}>
              <Chip color={chipColorFor(o.color)} label={o.label} />
            </PickerOption>
          ))
        )}
      </PickerMenu>
    </div>
  )
}
