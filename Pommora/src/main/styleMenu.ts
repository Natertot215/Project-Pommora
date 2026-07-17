import type { MenuItemConstructorOptions } from 'electron'
import type { StyleMenuItem } from '@shared/columnMenu'

type StyleAction = `style:${string}:${string}`

/** The Style submenu template shared by the column-header and cell menus: each row is a radio, and a
 *  `separatorBefore` row is preceded by a separator (Electron scopes radio groups per separator run,
 *  so the datetime menu's date/time radios check independently). */
export function styleSubmenu(
  rows: StyleMenuItem[],
  pick: (a: StyleAction) => () => void,
): MenuItemConstructorOptions[] {
  return rows.flatMap((r): MenuItemConstructorOptions[] => [
    ...(r.separatorBefore ? [{ type: 'separator' } as MenuItemConstructorOptions] : []),
    { label: r.label, type: 'radio', checked: r.checked, click: pick(`style:${r.key}:${r.value}`) },
  ])
}
