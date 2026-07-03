import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { Icon } from '../../symbols'
import { Switch } from '../Switches/Switch'
import { OverflowScroll } from '../OverflowScroll'
import { PickerMenu, PickerOption } from '../PickerMenu/PickerMenu'
import { useDismiss } from '../Popover'
import { cx } from '../../cx'
import * as s from './calendarPicker.css'

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

/** PaneSlider's animated-viewport half, single-slot: content size changes morph on the shared
 *  beat instead of snapping (the ViewPane/menus feel). */
function SizeMorph({ children }: { children: ReactNode }): React.JSX.Element {
  const ref = useRef<HTMLDivElement>(null)
  const [h, setH] = useState(0)
  const [armed, setArmed] = useState(false)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const measure = (): void => setH(el.offsetHeight)
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  useEffect(() => setArmed(true), [])
  return (
    <div className={cx(s.morph, armed && s.morphAnimated)} style={{ height: h || undefined }}>
      <div ref={ref}>{children}</div>
    </div>
  )
}
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
  const [menu, setMenu] = useState<'month' | 'year' | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  useDismiss(rootRef, () => setMenu(null), menu !== null)
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

  const prevMonth = slide?.from ?? cursor
  const year = cursor.getFullYear()
  const jump = (y: number, m: number): void => {
    setCursor(new Date(y, m, 1))
    setMenu(null)
  }
  // ~10 years visible before the list scrolls (the menu's max-height caps it); ±10 around the cursor.
  const yearChoices = Array.from({ length: 21 }, (_, i) => year - 10 + i)
  const monthName = (m: number): string => new Date(2026, m, 1).toLocaleDateString('en-US', { month: 'long' })

  const selectionMenu = (kind: 'month' | 'year'): React.JSX.Element => (
    <span onClick={(e) => e.stopPropagation()}>
      <PickerMenu solid>
        <div className={s.menuList}>
          {kind === 'month'
            ? Array.from({ length: 12 }, (_, m) => (
                <PickerOption key={m} selected={m === cursor.getMonth()} onClick={() => jump(year, m)}>
                  {monthName(m)}
                </PickerOption>
              ))
            : yearChoices.map((y) => (
                <PickerOption key={y} selected={y === year} onClick={() => jump(y, cursor.getMonth())}>
                  {y}
                </PickerOption>
              ))}
        </div>
      </PickerMenu>
    </span>
  )

  return (
    <div className={s.root} ref={rootRef}>
      <SizeMorph>
      <div className={s.head}>
        <span className={s.titleGroup}>
          <button type="button" className={s.titleBtn} onClick={() => setMenu(menu === 'month' ? null : 'month')}>
            {cursor.toLocaleDateString('en-US', { month: 'long' })}
            {menu === 'month' && selectionMenu('month')}
          </button>
          <button type="button" className={s.titleBtn} onClick={() => setMenu(menu === 'year' ? null : 'year')}>
            {year}
            {menu === 'year' && selectionMenu('year')}
          </button>
        </span>
        <span className={s.nav}>
          <button type="button" className={s.navBtn} aria-label="Previous month" onClick={() => nav(-1)}>
            <Icon name="chevron-left" size={16} />
          </button>
          <span className={s.navSegment} aria-hidden />
          <button type="button" className={s.navBtn} aria-label="Next month" onClick={() => nav(1)}>
            <Icon name="chevron-right" size={16} />
          </button>
        </span>
      </div>
      <div className={s.headDivider} />
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
      </SizeMorph>
    </div>
  )
}
