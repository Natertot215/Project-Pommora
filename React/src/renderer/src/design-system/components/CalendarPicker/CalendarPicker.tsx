import { useState } from 'react'
import { Icon } from '../../symbols'
import { Switch } from '../Switches/Switch'
import { OverflowScroll } from '../OverflowScroll'
import { cx } from '../../cx'
import * as s from './calendarPicker.css'

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const pad = (n: number): string => String(n).padStart(2, '0')
// Local YYYY-MM-DD key (never toISOString — a UTC key shifts the day west of Greenwich; the
// formatters parse date-only strings as LOCAL midnight, so the key must be minted locally too).
const keyOf = (d: Date): string => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const todayKey = keyOf(new Date())

/**
 * The date(-time) picker prototype (Nathan's Figma direction, iterating live on the Homepage):
 * Month-Year header with duration-base slide nav · Mon-first label-secondary week row ·
 * connected range selection (endpoints tint-secondary, in-between band tint-tertiary; clicking a
 * selected date removes it) · a divider · separator-stroked value fields (calendar/clock icon,
 * `--` empty state, OverflowScroll on long formats) whose layout morphs on the two booleans
 * (real Switches). Display formats are INJECTED so the owning property's config stays the boss;
 * times are display-only until the entry UX is designed.
 */
export function CalendarPicker({
  formatDateValue,
  formatTimeValue
}: {
  formatDateValue: (isoDate: string) => string
  formatTimeValue: (minutes: number) => string
}): React.JSX.Element {
  const now = new Date()
  const [cursor, setCursor] = useState(new Date(now.getFullYear(), now.getMonth(), 1))
  const [slide, setSlide] = useState<{ dir: 1 | -1; from: Date } | null>(null)
  const [start, setStart] = useState<string | null>(null)
  const [end, setEnd] = useState<string | null>(null)
  const [endOn, setEndOn] = useState(false)
  const [timeOn, setTimeOn] = useState(false)
  const startMin = 9 * 60
  const endMin = 17 * 60

  const nav = (dir: 1 | -1): void => {
    if (slide) return
    setSlide({ dir, from: cursor })
    setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + dir, 1))
  }

  // YYYY-MM-DD keys compare lexicographically, so string < / > is date order.
  const pick = (k: string): void => {
    if (k === start) {
      setStart(end)
      setEnd(null)
    } else if (k === end) {
      setEnd(null)
    } else if (!start) {
      setStart(k)
    } else if (endOn && !end) {
      if (k < start) {
        setEnd(start)
        setStart(k)
      } else setEnd(k)
    } else {
      setStart(k)
      setEnd(null)
    }
  }

  const grid = (month: Date): React.JSX.Element => {
    const y = month.getFullYear()
    const m = month.getMonth()
    const lead = new Date(y, m, 1).getDay() // Sunday-first
    const first = new Date(y, m, 1 - lead)
    // Only the weeks this month occupies — no trailing all-next-month row.
    const cellCount = Math.ceil((lead + new Date(y, m + 1, 0).getDate()) / 7) * 7
    const ranged = start !== null && end !== null
    return (
      <div className={s.days} key={keyOf(month)}>
        {Array.from({ length: cellCount }, (_, i) => {
          const d = new Date(first.getFullYear(), first.getMonth(), first.getDate() + i)
          const k = keyOf(d)
          const sel = k === start || k === end
          const mid = ranged && start !== null && end !== null && k > start && k < end
          const col = i % 7
          return (
            <button
              type="button"
              key={k}
              className={cx(s.day, d.getMonth() !== m && s.dayOut, sel && s.daySelected)}
              onClick={() => pick(k)}
            >
              {sel && ranged && (
                <span className={cx(s.pill, k === start ? s.bandUnderStart : s.bandUnderEnd)} />
              )}
              <span
                className={cx(
                  s.pill,
                  k === todayKey && !sel && !mid && s.pillToday,
                  sel && s.pillSelected,
                  mid && s.pillMid,
                  mid && col === 0 && s.pillRowFirst,
                  mid && col === 6 && s.pillRowLast
                )}
              />
              {d.getDate()}
            </button>
          )
        })}
      </div>
    )
  }

  const dateField = (k: string | null, label: string): React.JSX.Element => (
    <div className={s.field} key={label}>
      <Icon name="calendar" size={14} className={s.fieldIcon} />
      <OverflowScroll className={s.fieldValue}>
        {k ? formatDateValue(k) : <span className={s.fieldEmpty}>--</span>}
      </OverflowScroll>
    </div>
  )
  const timeField = (mins: number | null, label: string): React.JSX.Element => (
    <div className={s.field} key={label}>
      <Icon name="clock" size={14} className={s.fieldIcon} />
      <OverflowScroll className={s.fieldValue}>
        {mins !== null ? formatTimeValue(mins) : <span className={s.fieldEmpty}>--</span>}
      </OverflowScroll>
    </div>
  )

  const monthTitle = `${cursor.toLocaleDateString('en-US', { month: 'long' })} ${cursor.getFullYear()}`
  const prevMonth = slide?.from ?? cursor

  return (
    <div className={s.root}>
      <div className={s.head}>
        <span className={s.title}>{monthTitle}</span>
        <span className={s.nav}>
          <button type="button" className={s.navBtn} aria-label="Previous month" onClick={() => nav(-1)}>
            <Icon name="chevron-left" size={14} />
          </button>
          <button type="button" className={s.navBtn} aria-label="Next month" onClick={() => nav(1)}>
            <Icon name="chevron-right" size={14} />
          </button>
        </span>
      </div>
      <div className={s.weekRow}>
        {WEEKDAYS.map((w) => (
          <span key={w} className={s.weekday}>
            {w}
          </span>
        ))}
      </div>
      <div className={s.viewport}>
        <div
          className={cx(s.track, slide ? (slide.dir === 1 ? s.trackLeft : s.trackRight) : undefined)}
          onAnimationEnd={() => setSlide(null)}
        >
          {slide ? (
            slide.dir === 1 ? (
              <>
                {grid(prevMonth)}
                {grid(cursor)}
              </>
            ) : (
              <>
                {grid(cursor)}
                {grid(prevMonth)}
              </>
            )
          ) : (
            grid(cursor)
          )}
        </div>
      </div>
      <div className={s.divider} />
      <div className={s.fields}>
        {endOn ? (
          <>
            <div className={s.fieldRow}>
              {dateField(start, 'start')}
              {dateField(end, 'end')}
            </div>
            {timeOn && (
              <div className={s.fieldRow}>
                {timeField(start ? startMin : null, 'start-t')}
                {timeField(end ? endMin : null, 'end-t')}
              </div>
            )}
          </>
        ) : (
          <div className={s.fieldRow}>
            {dateField(start, 'date')}
            {timeOn && timeField(start ? startMin : null, 'time')}
          </div>
        )}
      </div>
      <div className={s.switchRow}>
        <span className={s.switchLabel}>End Date</span>
        <span className={s.switchScale}>
          <Switch checked={endOn} ariaLabel="End Date" onChange={(v) => { setEndOn(v); if (!v) setEnd(null) }} />
        </span>
      </div>
      <div className={s.switchRow}>
        <span className={s.switchLabel}>Use Time</span>
        <span className={s.switchScale}>
          <Switch checked={timeOn} ariaLabel="Use Time" onChange={setTimeOn} />
        </span>
      </div>
    </div>
  )
}
