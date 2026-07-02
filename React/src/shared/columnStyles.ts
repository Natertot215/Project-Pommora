// Per-view column display styles — the `column_styles` record on a SavedView (a deliberate
// divergence from Swift's def-level format keys, which ride through defs as foreign keys).

import { z } from 'zod'

export const COLUMN_LOOKS = ['pill', 'capsule', 'checkbox', 'switch', 'title', 'full', 'filename', 'path'] as const
export type ColumnLook = (typeof COLUMN_LOOKS)[number]

export const DATE_FORMATS = ['short', 'full', 'dayMonthYear', 'monthDayYear'] as const
export type DateFormat = (typeof DATE_FORMATS)[number]

export const TIME_FORMATS = ['none', 'twelveHour', 'twentyFourHour'] as const
export type TimeFormat = (typeof TIME_FORMATS)[number]

export const NUMBER_FORMATS = ['integer', 'decimal', 'percent', 'currency'] as const
export type NumberFormat = (typeof NUMBER_FORMATS)[number]

/** One column's saved style entry. Loose + per-field catch ⇒ a bad value drops that field,
 *  never the entry; unknown keys ride through. */
export const columnStyle = z.looseObject({
  look: z.enum(COLUMN_LOOKS).optional().catch(undefined),
  date_format: z.enum(DATE_FORMATS).optional().catch(undefined),
  time_format: z.enum(TIME_FORMATS).optional().catch(undefined),
  number_format: z.enum(NUMBER_FORMATS).optional().catch(undefined)
})
export type ColumnStyle = z.infer<typeof columnStyle>

/** The type-default style — string-keyed so `shared/` needs nothing from the renderer's
 *  `declaredType`. Select/multi aren't style-addressable: their chips always render pill. */
export function defaultStyleFor(declaredType: string | undefined): ColumnStyle {
  switch (declaredType) {
    case 'status':
      return { look: 'pill' }
    case 'checkbox':
      return { look: 'checkbox' }
    case 'url':
      return { look: 'full' }
    case 'file':
      return { look: 'filename' }
    case 'datetime':
    case 'last_edited_time':
      return { date_format: 'full', time_format: 'none' }
    case 'number':
      return { number_format: 'decimal' }
    default:
      return {}
  }
}
