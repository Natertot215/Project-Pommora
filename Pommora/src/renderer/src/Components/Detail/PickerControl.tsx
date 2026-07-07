import { useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu, PickerOption } from '../../design-system/components/PickerMenu'
import * as s from './pickerControl.css'

export type PickerChoice<T extends string> = { value: T; label: string }

export const labelOf = <T extends string>(opts: PickerChoice<T>[], v: T): string =>
  opts.find((o) => o.value === v)?.label ?? opts[0].label

/** A bare value + double-chevron trigger that pops a centered PickerMenu of radio options — the shared
 *  control for the property editors' Format / Style rows. The caller owns the surrounding row (label,
 *  glyph); this owns only the trigger + its menu. */
export function PickerControl<T extends string>({
  ariaLabel,
  value,
  options,
  onPick
}: {
  ariaLabel: string
  value: T
  options: PickerChoice<T>[]
  onPick: (v: T) => void
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  return (
    <>
      <button ref={ref} type="button" className={s.trigger} aria-label={ariaLabel} onClick={() => setOpen(true)}>
        <span className={s.value}>{labelOf(options, value)}</span>
        <Icon name="chevrons-up-down" size={12} />
      </button>
      <PickerMenu open={open} onDismiss={() => setOpen(false)} triggerRef={ref} center>
        {options.map((o) => (
          <PickerOption
            key={o.value}
            selected={o.value === value}
            onClick={() => {
              onPick(o.value)
              setOpen(false)
            }}
          >
            {o.label}
          </PickerOption>
        ))}
      </PickerMenu>
    </>
  )
}
