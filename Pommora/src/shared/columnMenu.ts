import {
  COLUMN_LOOKS,
  DATE_FORMATS,
  TIME_FORMATS,
  WEEKDAY_FORMATS,
  type ColumnStyle,
} from './columnStyles'
import type { PropertyType } from './properties'
import type { ColumnAlign } from './views'

/** The table-view column-header right-click menu (E-1/E-5): hide the column, set its text alignment,
 *  or set a per-view display style. The renderer applies the resolved action, or no-ops on null
 *  (dismissed). Mirrors calloutMenu's shape. */
export type ColumnMenuAction =
  | 'column:hide'
  | 'column:toggle-icons'
  | `align:${ColumnAlign}`
  | `style:${string}:${string}`

/** Menu context — the current alignment (for the checked radio) + which items apply. The Title column is
 *  the primary column: neither alignable, hideable, nor styleable, so it pops an empty (⇒ dismissed) menu. */
export interface ColumnMenuContext {
  align: ColumnAlign
  alignable: boolean
  hideable: boolean
  /** Whether column header icons currently show (view-wide `hide_column_icons` inverted) — drives the
   *  Icon ⇄ Hide Icon toggle label. Undefined on the Title column's empty menu. */
  iconsShown?: boolean
  style?: StyleMenuContext
}

/** The Style submenu's inputs: the column's declared type picks the item set; `current` is the
 *  RESOLVED style (defaults applied) so the checked radio reflects what actually renders. */
export interface StyleMenuContext {
  type: PropertyType
  current: ColumnStyle
}

/** One Style submenu row — a radio keyed by the ColumnStyle field it sets. `separatorBefore`
 *  splits the datetime menu's date radios from its time radios (Electron groups radios per
 *  separator-bounded run, so the two groups check independently). */
export interface StyleMenuItem {
  label: string
  key: keyof ColumnStyle & string
  value: string
  checked: boolean
  separatorBefore?: boolean
}

/** The per-type Style items — the ONE place that knows which types are style-addressable
 *  (select/multi/context aren't: their chips always render pill). Datetime labels are
 *  format-type NAMES, never rendered samples. */
export function styleMenuItems(ctx: StyleMenuContext): StyleMenuItem[] {
  const { type, current } = ctx
  const row =
    (key: StyleMenuItem['key'], checked: string | undefined) =>
    (label: string, value: string, separatorBefore?: boolean): StyleMenuItem => ({
      label,
      key,
      value,
      checked: checked === value,
      ...(separatorBefore ? { separatorBefore } : {}),
    })
  const look = row('look', current.look)
  switch (type) {
    case 'status':
      return [look('Pill', 'pill'), look('Capsule', 'capsule'), look('Checkbox', 'checkbox')]
    case 'checkbox':
      return [look('Checkbox', 'checkbox'), look('Switch', 'switch')]
    case 'url':
      return [look('Title', 'title'), look('Full Link', 'full')]
    case 'file':
      return [look('Filename', 'filename'), look('Full Path', 'path')]
    case 'number':
      return [look('Number', 'number'), look('Bar', 'bar')]
    case 'datetime':
    case 'last_edited_time': {
      const date = row('date_format', current.date_format)
      const weekday = row('weekday', current.weekday)
      const time = row('time_format', current.time_format)
      return [
        date('MM/DD/YYYY', 'monthDayYear'),
        date('DD/MM/YYYY', 'dayMonthYear'),
        date('Short Date', 'short'),
        date('Full Date', 'full'),
        date('Relative', 'relative'),
        weekday('Full', 'long', true),
        weekday('Short', 'short'),
        weekday('Hidden', 'none'),
        time('12 Hours', 'twelveHour', true),
        time('24 Hours', 'twentyFourHour'),
        time('Hidden', 'none'),
      ]
    }
    default:
      return []
  }
}

const STYLE_VALUES: Record<string, readonly string[]> = {
  look: COLUMN_LOOKS,
  date_format: DATE_FORMATS,
  time_format: TIME_FORMATS,
  weekday: WEEKDAY_FORMATS,
}

/** Decode a `style:<key>:<value>` action; null for anything else or an unknown key/value. */
export function parseStyleAction(
  action: string,
): { key: keyof ColumnStyle & string; value: string } | null {
  const m = /^style:([^:]+):(.+)$/.exec(action)
  if (!m) return null
  const [, key, value] = m
  return STYLE_VALUES[key]?.includes(value)
    ? { key: key as keyof ColumnStyle & string, value }
    : null
}
