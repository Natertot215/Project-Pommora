// Pure option-array transforms shared by the renderer panes and the main-process option ops. An
// option's `value` IS its title (value=label), so identity keys on the value string. No I/O, no React
// — unit-tested in isolation; the IPC ops and panes are thin over these.

import type { PropertyType, StatusGroup } from './properties'

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

// ── Status: the same transforms, applied to one group's options within the StatusGroup[] array ──

/** Append an option to one status group (matched by id). value = label = title (the value=title
 *  model); no color, so the chip inherits the group's colour until it's recolored. */
export function addStatusOption(groups: StatusGroup[], groupId: string, title: string): StatusGroup[] {
  return groups.map((g) =>
    g.id === groupId ? { ...g, options: [...g.options, { value: title, label: title, group_id: g.id }] } : g
  )
}

/** Recolor a status option (by value, wherever it lives). undefined clears the key → the chip falls
 *  back to its group's colour. */
export function recolorStatusOption(groups: StatusGroup[], value: string, color: string | undefined): StatusGroup[] {
  return groups.map((g) => ({
    ...g,
    options: g.options.map((o) => {
      if (o.value !== value) return o
      const { color: _drop, ...rest } = o
      return color ? { ...rest, color } : rest
    })
  }))
}

/** Rename a status option (by its OLD value, wherever it lives); value + label both become the new
 *  title (value=title). The page cascade (main-process) rewrites `$status` on every assigning page. */
export function renameStatusOption(groups: StatusGroup[], oldValue: string, newTitle: string): StatusGroup[] {
  return groups.map((g) => ({
    ...g,
    options: g.options.map((o) => (o.value === oldValue ? { ...o, value: newTitle, label: newTitle } : o))
  }))
}

/** Rename a group's display label (by group id); its calendar-locked id + its options are untouched. */
export function relabelStatusGroup(groups: StatusGroup[], groupId: string, label: string): StatusGroup[] {
  return groups.map((g) => (g.id === groupId ? { ...g, label } : g))
}

/** Move an option (by value) into `toGroupId` at `toIndex`, reassigning its group_id. Same group = a
 *  reorder; a different group = a cross-group move (it inherits the new group's colour unless it carries
 *  its own). toIndex is in the target group's without-the-dragged coordinate space. */
export function moveStatusOption(groups: StatusGroup[], value: string, toGroupId: string, toIndex: number): StatusGroup[] {
  const moved = groups.flatMap((g) => g.options).find((o) => o.value === value)
  if (!moved) return groups
  const next = { ...moved, group_id: toGroupId }
  return groups.map((g) => {
    const without = g.options.filter((o) => o.value !== value)
    return g.id === toGroupId
      ? { ...g, options: [...without.slice(0, toIndex), next, ...without.slice(toIndex)] }
      : { ...g, options: without }
  })
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
