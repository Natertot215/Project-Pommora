// Swift-parity value formatters for the per-view column styles. Pure: no fs, no React.
// Pinned to en-US — the ordinal-day style ("March 1st") is English-only, and pinning keeps
// output deterministic across machines; currency follows Swift's locale formatter as USD.

import type { DateFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'
import type { DateGranularity, DateSeparator } from '@shared/views'
import type { NumberConfig } from '@shared/properties'

function ordinal(day: number): string {
  if (day % 100 >= 11 && day % 100 <= 13) return `${day}th`
  switch (day % 10) {
    case 1:
      return `${day}st`
    case 2:
      return `${day}nd`
    case 3:
      return `${day}rd`
    default:
      return `${day}th`
  }
}

const pad = (n: number): string => String(n).padStart(2, '0')

function clockOf(date: Date, timeFormat: TimeFormat): string {
  return timeFormat === 'twelveHour'
    ? date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    : date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
}

// ── Relative thresholds (Nathan-tunable) ──
const WEEK_DAYS = 7 // |Δdays| ≤ this shows named/day-count form (with clock when time-shown)

const startOfDay = (d: Date): Date => new Date(d.getFullYear(), d.getMonth(), d.getDate())

/** Capitalized relative wording. Within a week: named day / "N Days Ago" / "N Days from now" (+ "at
 *  <clock>" when time is shown). Past a week: weeks → months → years, clock dropped. */
function formatRelative(date: Date, hasTime: boolean, timeFormat: TimeFormat, now: Date): string {
  const DAY = 86_400_000
  const diffDays = Math.round((startOfDay(date).getTime() - startOfDay(now).getTime()) / DAY)
  const ago = diffDays < 0
  const n = Math.abs(diffDays)

  if (n <= WEEK_DAYS) {
    const dayWord = n === 0 ? 'Today' : n === 1 ? (ago ? 'Yesterday' : 'Tomorrow') : ago ? `${n} Days Ago` : `${n} Days from now`
    return hasTime && timeFormat !== 'none' ? `${dayWord} at ${clockOf(date, timeFormat)}` : dayWord
  }
  const [unit, count] =
    n < 30 ? ['Week', Math.round(n / 7)] : n < 365 ? ['Month', Math.round(n / 30)] : ['Year', Math.round(n / 365)]
  const plural = count === 1 ? unit : `${unit}s`
  return ago ? `${count} ${plural} Ago` : `${count} ${plural} from now`
}

/** Render an ISO date(-time) per the saved formats. A date-only value (no `T`) never grows a
 *  time; date-only strings parse as LOCAL midnight (a bare `new Date('YYYY-MM-DD')` is UTC and
 *  shifts the day west of Greenwich). Unparseable input falls back to the raw string. Weekday is a
 *  decoupled dimension prepended for the worded formats only; `relative` composes its own wording. */
export function formatDate(
  iso: string,
  dateFormat: DateFormat,
  timeFormat: TimeFormat,
  weekday: WeekdayFormat = 'none',
  now: Date = new Date()
): string {
  const hasTime = iso.includes('T')
  const date = new Date(hasTime ? iso : `${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso
  if (dateFormat === 'relative') return formatRelative(date, hasTime, timeFormat, now)

  const month = date.toLocaleDateString('en-US', { month: 'long' })
  const day = ordinal(date.getDate())
  let out: string
  switch (dateFormat) {
    case 'short':
      out = `${month} ${day}`
      break
    case 'full':
      out = `${month} ${day}, ${date.getFullYear()}`
      break
    case 'dayMonthYear':
      out = `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()}`
      break
    case 'monthDayYear':
      out = `${pad(date.getMonth() + 1)}/${pad(date.getDate())}/${date.getFullYear()}`
      break
  }

  if ((dateFormat === 'short' || dateFormat === 'full') && weekday !== 'none') {
    out = `${date.toLocaleDateString('en-US', { weekday: weekday === 'long' ? 'long' : 'short' })}, ${out}`
  }
  if (hasTime && timeFormat !== 'none') out += ` ${clockOf(date, timeFormat)}`
  return out
}

const NUMERIC_FORMATS = new Set<DateFormat>(['dayMonthYear', 'monthDayYear'])

/** A date group-heading label from its stable bucket key: worded formats read written
 *  ("July 2026"); numeric formats read numeric with the view's separator ("07-2026"). */
export function formatBucketLabel(
  key: string,
  granularity: DateGranularity,
  dateFormat: DateFormat,
  separator: DateSeparator
): string {
  const numeric = NUMERIC_FORMATS.has(dateFormat)
  const sep = separator === 'slash' ? '/' : '-'
  switch (granularity) {
    case 'year':
      return key
    case 'week': {
      const m = /^(\d{4})-W(\d{2})$/.exec(key)
      if (!m) return key
      return numeric ? `W${m[2]}${sep}${m[1]}` : `Week ${Number(m[2])}, ${m[1]}`
    }
    case 'month': {
      const m = /^(\d{4})-(\d{2})$/.exec(key)
      if (!m) return key
      if (numeric) return `${m[2]}${sep}${m[1]}`
      const month = new Date(`${key}-01T00:00:00`).toLocaleDateString('en-US', { month: 'long' })
      return `${month} ${m[1]}`
    }
    case 'day': {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return key
      const out = formatDate(key, dateFormat, 'none')
      return numeric && separator === 'dash' ? out.replaceAll('/', '-') : out
    }
  }
}

/** The picker's condensed range-date form (Nathan's rule — picker-only, never in cells): worded
 *  formats collapse to the short "July 7th"; numeric formats drop to MM/DD (or DD/MM), expanding
 *  back to the full numeric form only when the range spans multiple years. */
export function condensedDate(iso: string, dateFormat: DateFormat, withYear: boolean): string {
  const date = new Date(iso.includes('T') ? iso : `${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso
  switch (dateFormat) {
    case 'relative':
    case 'short':
    case 'full':
      return `${date.toLocaleDateString('en-US', { month: 'long' })} ${ordinal(date.getDate())}`
    case 'dayMonthYear':
      return `${pad(date.getDate())}/${pad(date.getMonth() + 1)}${withYear ? `/${date.getFullYear()}` : ''}`
    case 'monthDayYear':
      return `${pad(date.getMonth() + 1)}/${pad(date.getDate())}${withYear ? `/${date.getFullYear()}` : ''}`
  }
}

/** A file chip's label per the column's look — the basename, or the full stored path. */
export function fileLabel(ref: { path: string }, look: 'filename' | 'path'): string {
  return look === 'path' ? ref.path : (ref.path.split('/').pop() ?? ref.path)
}

/** Fraction-option digit settings for `Intl` — 'hidden' shows no places, a fixed count pins min=max,
 *  absent shows the number's natural decimals (Intl default). */
function fractionDigits(decimals: NumberConfig['number_decimals']): Intl.NumberFormatOptions {
  if (decimals === 'hidden') return { maximumFractionDigits: 0 }
  if (typeof decimals === 'number') return { minimumFractionDigits: decimals, maximumFractionDigits: decimals }
  return {}
}

/** One scalar formatted by the family (no fraction wrapping). Percent is LITERAL — the number plus '%',
 *  never Intl's ×100 percent style. Currency uses the chosen ISO code (default USD). */
function formatScalar(n: number, cfg: NumberConfig | undefined): string {
  const useGrouping = cfg?.number_separators !== false
  const digits = fractionDigits(cfg?.number_decimals)
  if (cfg?.number_family === 'currency') {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: cfg.number_currency ?? 'USD', useGrouping, ...digits }).format(n)
  }
  const num = new Intl.NumberFormat('en-US', { useGrouping, ...digits }).format(n)
  return cfg?.number_family === 'percent' ? `${num}%` : num
}

/** Render a number per its def-level config. Fraction (Number/Currency) wraps the scalar as
 *  "N out of Value"; every other case is the bare scalar. */
export function formatNumber(n: number, cfg: NumberConfig | undefined): string {
  if (cfg?.number_fraction && cfg.number_family !== 'percent' && cfg.number_denominator !== undefined) {
    return `${formatScalar(n, cfg)} out of ${formatScalar(cfg.number_denominator, cfg)}`
  }
  return formatScalar(n, cfg)
}

/** The bar's divisor: 100 for percent, the fraction denominator for Number/Currency, else undefined
 *  (no bar). A zero / missing denominator returns undefined so the bar never divides by zero. */
export function numberDivisor(cfg: NumberConfig | undefined): number | undefined {
  if (cfg?.number_family === 'percent') return 100
  if (cfg?.number_fraction && cfg.number_denominator) return cfg.number_denominator
  return undefined
}
