// Pure option-array transforms shared by the renderer panes and the main-process option ops. An
// option's `value` IS its title (value=label), so identity keys on the value string. No I/O, no React
// — unit-tested in isolation; the IPC ops and panes are thin over these.

import type { PropertyType } from './properties'

export type Option = { value: string; label: string; color?: string; group_id?: string }

/** The empty-name fallback when a rename field is left blank: Select / Multi → "Label"; Status → its
 *  group's label (so an unnamed status option reads as its group). */
export function fallbackTitle(type: PropertyType, groupLabel?: string): string {
  return type === 'status' ? (groupLabel ?? 'Label') : 'Label'
}

/** Append a new option whose value and label both equal the title. No color — it renders as the
 *  neutral default (grey-default) until recolored. */
export function addOption(options: Option[], title: string, groupId?: string): Option[] {
  return [...options, { value: title, label: title, ...(groupId ? { group_id: groupId } : {}) }]
}

/** Rename by OLD value; value and label both become the new title. Identity keys on the old value. */
export function renameOption(options: Option[], oldValue: string, title: string): Option[] {
  return options.map((o) => (o.value === oldValue ? { ...o, value: title, label: title } : o))
}

/** Set or clear an option's color key (undefined removes the field, so it renders as default). */
export function recolorOption(options: Option[], value: string, color: string | undefined): Option[] {
  return options.map((o) => {
    if (o.value !== value) return o
    const { color: _drop, ...rest } = o
    return color ? { ...rest, color } : rest
  })
}

/** Move the option with `value` to `toIndex` (in the without-the-dragged coordinate space). */
export function reorderOption(options: Option[], value: string, toIndex: number): Option[] {
  const moved = options.find((o) => o.value === value)
  if (!moved) return options
  const without = options.filter((o) => o.value !== value)
  return [...without.slice(0, toIndex), moved, ...without.slice(toIndex)]
}
