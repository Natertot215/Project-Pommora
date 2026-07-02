// Swift-parity value formatters for the per-view column styles. Pure: no fs, no React.
// Pinned to en-US — the ordinal-day style ("March 1st") is English-only, and pinning keeps
// output deterministic across machines; currency follows Swift's locale formatter as USD.

import type { DateFormat, NumberFormat, TimeFormat } from '@shared/columnStyles'

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

/** Render an ISO date(-time) per the saved formats. A date-only value (no `T`) never grows a
 *  time; date-only strings parse as LOCAL midnight (a bare `new Date('YYYY-MM-DD')` is UTC and
 *  shifts the day west of Greenwich). Unparseable input falls back to the raw string. */
export function formatDate(iso: string, dateFormat: DateFormat, timeFormat: TimeFormat): string {
  const hasTime = iso.includes('T')
  const date = new Date(hasTime ? iso : `${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso

  const month = date.toLocaleDateString('en-US', { month: 'long' })
  const day = ordinal(date.getDate())
  let out: string
  switch (dateFormat) {
    case 'short':
      out = `${month} ${day}`
      break
    case 'full':
      out = `${date.toLocaleDateString('en-US', { weekday: 'long' })}, ${month} ${day} ${date.getFullYear()}`
      break
    case 'dayMonthYear':
      out = `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()}`
      break
    case 'monthDayYear':
      out = `${pad(date.getMonth() + 1)}/${pad(date.getDate())}/${date.getFullYear()}`
      break
  }

  if (hasTime && timeFormat !== 'none') {
    const time =
      timeFormat === 'twelveHour'
        ? date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
        : date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
    out += ` ${time}`
  }
  return out
}

/** A file chip's label per the column's look — the basename, or the full stored path. */
export function fileLabel(ref: { path: string }, look: 'filename' | 'path'): string {
  return look === 'path' ? ref.path : (ref.path.split('/').pop() ?? ref.path)
}

/** Render a number per the saved format — the Swift NumberFormatter set (percent takes the
 *  0-1 fraction: 0.42 → "42%"). */
export function formatNumber(n: number, numberFormat: NumberFormat): string {
  switch (numberFormat) {
    case 'integer':
      return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(n)
    case 'percent':
      return new Intl.NumberFormat('en-US', { style: 'percent', maximumFractionDigits: 2 }).format(n)
    case 'currency':
      return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n)
    case 'decimal':
      return new Intl.NumberFormat('en-US').format(n)
  }
}
