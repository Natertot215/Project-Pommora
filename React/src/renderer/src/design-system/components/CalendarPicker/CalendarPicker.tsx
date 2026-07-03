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
  /** `condensed` set = the range layout asking for the picker-only short form (withYear when the
   *  range spans years); absent = the property's own format, verbatim. */
  formatDateValue: (isoDate: string, condensed?: { withYear: boolean }) => string
  formatTimeValue: (minutes: number) => string
}): React.JSX.Element {
  const now = new Date()
  const [cursor, setCursor] = useState(new Date(now.getFullYear(), now.getMonth(), 1))
  const [slide, setSlide] = useState<{ dir: 1 | -1; from: Date } | null>(null)
  const [start, setStart] = useState<string | null>(null)
  const [end, setEnd] = useState<string | null>(null)
  const [endOn, setEndOn] = useState(false)
  const [timeOn, setTimeOn] = useState(false)
  const [menu, setMenu] = useState<{ kind: 'month' | 'year'; beak: number } | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  useDismiss(rootRef, () => setMenu(null), menu !== null)
  // A press on a selected endpoint arms a drag that re-places it live (swapping roles if it
  // crosses the other end); a no-move press falls through to the click (= remove).
  const drag = useRef<{ which: 'start' | 'end'; moved: boolean } | null>(null)
  const suppressClick = useRef(false)
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

  const keyAtPoint = (x: number, y: number): string | null =>
    document.elementFromPoint(x, y)?.closest('[data-k]')?.getAttribute('data-k') ?? null

  const onGridPointerDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    const k = (e.target as HTMLElement).closest('[data-k]')?.getAttribute('data-k')
    if (!k) return
    if (k === start) drag.current = { which: 'start', moved: false }
    else if (k === end) drag.current = { which: 'end', moved: false }
    if (drag.current) e.currentTarget.setPointerCapture(e.pointerId)
  }
  const onGridPointerMove = (e: React.PointerEvent<HTMLDivElement>): void => {
    const d = drag.current
    if (!d) return
    const k = keyAtPoint(e.clientX, e.clientY)
    if (!k || k === (d.which === 'start' ? start : end)) return
    d.moved = true
    if (d.which === 'start') {
      if (end !== null && k > end) {
        setStart(end)
        setEnd(k)
        d.which = 'end'
      } else setStart(k)
    } else if (start !== null && k < start) {
      setEnd(start)
      setStart(k)
      d.which = 'start'
    } else setEnd(k)
  }
  const onGridPointerUp = (): void => {
    if (drag.current?.moved) suppressClick.current = true
    drag.current = null
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
              data-k={k}
              className={cx(s.day, d.getMonth() !== m && s.dayOut, sel && s.daySelected)}
              onClick={() => {
                if (suppressClick.current) {
                  suppressClick.current = false
                  return
                }
                pick(k)
              }}
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

  const dateField = (k: string | null, label: string, condensed?: { withYear: boolean }): React.JSX.Element => (
    <div className={s.field} key={label}>
      <Icon name="calendar" size={14} className={s.fieldIcon} />
      <OverflowScroll className={s.fieldValue}>
        {k ? formatDateValue(k, condensed) : <span className={s.fieldEmpty}>--</span>}
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
  // The grid viewport's height is COMPUTED from the target month's row count (geometry mirrors
  // the css: 24px cells · 2px row gap · 2px bottom pad) and set the instant nav fires — SizeMorph
  // then animates the delta on the same duration-base beat as the slide keyframe, so the resize
  // FLOWS with the horizontal move (the PaneSlider contract) instead of snapping after it.
  const rowsFor = (month: Date): number => {
    const lead = new Date(month.getFullYear(), month.getMonth(), 1).getDay()
    return Math.ceil((lead + new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()) / 7)
  }
  const gridHeight = rowsFor(cursor) * 24 + (rowsFor(cursor) - 1) * 2 + 2
  const jump = (y: number, m: number): void => {
    setCursor(new Date(y, m, 1))
    setMenu(null)
  }
  // ~10 years visible before the list scrolls (the menu's max-height caps it); ±10 around the cursor.
  const yearChoices = Array.from({ length: 21 }, (_, i) => year - 10 + i)
  const monthName = (m: number): string => new Date(2026, m, 1).toLocaleDateString('en-US', { month: 'long' })

  const optionRow = (label: string | number, selected: boolean): React.JSX.Element => (
    <span className={s.optionRow}>
      {label}
      {selected && <Icon name="check" size={12} className={s.optionCheck} />}
    </span>
  )
  const selectionMenu = (kind: 'month' | 'year'): React.JSX.Element => (
    <span className={s.ddWrap} onClick={(e) => e.stopPropagation()}>
      <PickerMenu solid notchInsetLeft={menu?.beak}>
        <div className={cx(s.menuList, 'scroll-edge-fade')}>
          {kind === 'month'
            ? Array.from({ length: 12 }, (_, m) => (
                <PickerOption key={m} selected={m === cursor.getMonth()} onClick={() => jump(year, m)}>
                  {optionRow(monthName(m), m === cursor.getMonth())}
                </PickerOption>
              ))
            : yearChoices.map((y) => (
                <PickerOption key={y} selected={y === year} onClick={() => jump(y, cursor.getMonth())}>
                  {optionRow(y, y === year)}
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
          <button
            type="button"
            className={s.titleBtn}
            onClick={(e) =>
              setMenu(menu?.kind === 'month' ? null : { kind: 'month', beak: e.currentTarget.offsetWidth / 2 })
            }
          >
            {cursor.toLocaleDateString('en-US', { month: 'long' })}
            {menu?.kind === 'month' && selectionMenu('month')}
          </button>
          <button
            type="button"
            className={s.titleBtn}
            onClick={(e) =>
              setMenu(menu?.kind === 'year' ? null : { kind: 'year', beak: e.currentTarget.offsetWidth / 2 })
            }
          >
            {year}
            {menu?.kind === 'year' && selectionMenu('year')}
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
      <div className={s.viewport} style={{ height: gridHeight }}>
        <div
          className={cx(s.track, slide ? (slide.dir === 1 ? s.trackLeft : s.trackRight) : undefined)}
          onAnimationEnd={() => setSlide(null)}
          onPointerDown={onGridPointerDown}
          onPointerMove={onGridPointerMove}
          onPointerUp={onGridPointerUp}
          onPointerCancel={onGridPointerUp}
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
              {/* Range fields always take the picker-only condensed form; the year rejoins only
                  when the range spans multiple years. Single-date mode below stays verbatim. */}
              {dateField(start, 'start', { withYear: start !== null && end !== null && start.slice(0, 4) !== end.slice(0, 4) })}
              {dateField(end, 'end', { withYear: start !== null && end !== null && start.slice(0, 4) !== end.slice(0, 4) })}
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
