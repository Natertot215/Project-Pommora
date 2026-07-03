import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Icon } from '../../symbols'
import { Switch } from '../Switches/Switch'
import { OverflowScroll } from '../OverflowScroll'
import { PickerMenu, PickerOption } from '../PickerMenu/PickerMenu'
import { cx } from '../../cx'
import * as s from './calendarPicker.css'

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const HOURS_12 = Array.from({ length: 12 }, (_, i) => i + 1)
const MINUTES = Array.from({ length: 12 }, (_, i) => i * 5) // 5-minute steps — the granularity knob

type TriggerRect = { x: number; y: number; w: number; h: number }
const rectOf = (el: HTMLElement): TriggerRect => {
  const r = el.getBoundingClientRect()
  return { x: r.x, y: r.y, w: r.width, h: r.height }
}

/** The nested menus portal to body as a fixed phantom of their trigger box, so the dropdown is a
 *  REAL dropdown — free of the calendar pane's clip-path — while PickerMenu's anchor math works
 *  unchanged. The phantom is pointer-inert; only the menu re-enables hits. */
function PortalMenu({ rect, children }: { rect: TriggerRect; children: ReactNode }): React.JSX.Element {
  return createPortal(
    <div
      data-calmenu
      style={{ position: 'fixed', left: rect.x, top: rect.y, width: rect.w, height: rect.h, zIndex: 100, pointerEvents: 'none' }}
    >
      {children}
    </div>,
    document.body
  )
}

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
  formatDateValue
}: {
  /** `condensed` set = the range layout asking for the picker-only short form (withYear when the
   *  range spans years); absent = the property's own format, verbatim. */
  formatDateValue: (isoDate: string, condensed?: { withYear: boolean }) => string
}): React.JSX.Element {
  const now = new Date()
  // Per-render (never module-level) — a local-first app stays open across midnights.
  const todayKey = keyOf(now)
  const [cursor, setCursor] = useState(new Date(now.getFullYear(), now.getMonth(), 1))
  const [slide, setSlide] = useState<{ dir: 1 | -1; from: Date } | null>(null)
  const [start, setStart] = useState<string | null>(null)
  const [end, setEnd] = useState<string | null>(null)
  const [endOn, setEndOn] = useState(false)
  const [timeOn, setTimeOn] = useState(false)
  const [menu, setMenu] = useState<{ kind: 'month' | 'year'; rect: TriggerRect } | null>(null)
  // The [00][00] segment dropdowns — each segment opens its own upward PickerMenu (the fields sit
  // at the pane's bottom), beak-down at the segment.
  const [timeMenu, setTimeMenu] = useState<{ which: 'start' | 'end'; part: 'h' | 'm'; rect: TriggerRect } | null>(null)
  // Double-click a segment → caret editing in place (select-all drives replace-on-type, but the
  // selection paints transparent — highlighting disabled per Nathan).
  const [segEdit, setSegEdit] = useState<{ which: 'start' | 'end'; part: 'h' | 'm'; draft: string } | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  // Portal'd menus escape the root, so dismissal is a document listener that spares the root AND
  // any [data-calmenu] portal (useDismiss's containment check can't see through the portal). The
  // phantoms are frozen at open-time coordinates, so any outside scroll CLOSES them (the native
  // popover behavior) rather than letting them float away from their triggers.
  useEffect(() => {
    if (!menu && !timeMenu) return
    const close = (): void => {
      setMenu(null)
      setTimeMenu(null)
    }
    const onDown = (e: PointerEvent): void => {
      const t = e.target as HTMLElement
      if (rootRef.current?.contains(t) || t.closest('[data-calmenu]')) return
      close()
    }
    const onScroll = (e: Event): void => {
      if ((e.target as HTMLElement)?.closest?.('[data-calmenu]')) return // the menu's own list scrolls freely
      close()
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('scroll', onScroll, true)
    return () => {
      document.removeEventListener('pointerdown', onDown, true)
      document.removeEventListener('scroll', onScroll, true)
    }
  }, [menu, timeMenu])
  // A press on a selected endpoint arms a drag that re-places it live (swapping roles if it
  // crosses the other end); a no-move press falls through to the click (= remove).
  const drag = useRef<{ which: 'start' | 'end'; moved: boolean } | null>(null)
  const suppressClick = useRef(false)
  const [startMin, setStartMin] = useState(9 * 60)
  const [endMin, setEndMin] = useState(17 * 60)
  // Both endpoints share one time model; the segment/menu/toggle helpers all resolve their
  // endpoint through these rather than re-branching `which` at each call site.
  const minsOf = (which: 'start' | 'end'): number => (which === 'start' ? startMin : endMin)
  const setMinsFor = (which: 'start' | 'end'): typeof setStartMin => (which === 'start' ? setStartMin : setEndMin)

  const nav = (dir: 1 | -1): void => {
    if (slide) return
    // Sliding reflows the pane under any open phantom — close them with the move.
    setMenu(null)
    setTimeMenu(null)
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

  // Trackpad swipe on the calendar area only: horizontal wheel deltas accumulate to one nav per
  // gesture (natural direction — content follows the fingers). The accumulator resets on a
  // direction flip and on a wheel-idle gap, and a post-nav cooldown holds through the momentum
  // tail so one hard flick can't double-nav.
  const swipe = useRef(0)
  const swipeCooldown = useRef(false)
  const swipeIdle = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const onGridWheel = (e: React.WheelEvent): void => {
    if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return
    clearTimeout(swipeIdle.current)
    swipeIdle.current = setTimeout(() => {
      swipe.current = 0
      swipeCooldown.current = false
    }, 150)
    if (slide || swipeCooldown.current) return
    if (swipe.current !== 0 && Math.sign(e.deltaX) !== Math.sign(swipe.current)) swipe.current = 0
    swipe.current += e.deltaX
    if (Math.abs(swipe.current) > 60) {
      nav(swipe.current > 0 ? 1 : -1)
      swipe.current = 0
      swipeCooldown.current = true
    }
  }

  const keyAtPoint = (x: number, y: number): string | null =>
    document.elementFromPoint(x, y)?.closest('[data-k]')?.getAttribute('data-k') ?? null

  const onGridPointerDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    // A fresh press always re-arms clicking — the suppress flag must never outlive one gesture
    // (a drag released off the grid otherwise strands it and eats the next legitimate click).
    suppressClick.current = false
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
    if (k === (d.which === 'start' ? end : start)) return // never collapse onto the other endpoint
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

  // Weeks the month occupies (lead blanks + its days, rounded to full weeks) — no trailing
  // all-next-month row. Drives both the cell count and the animated viewport height.
  const rowsFor = (month: Date): number => {
    const lead = new Date(month.getFullYear(), month.getMonth(), 1).getDay()
    return Math.ceil((lead + new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()) / 7)
  }

  const grid = (month: Date): React.JSX.Element => {
    const y = month.getFullYear()
    const m = month.getMonth()
    const lead = new Date(y, m, 1).getDay() // Sunday-first
    const first = new Date(y, m, 1 - lead)
    const cellCount = rowsFor(month) * 7
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
  // The one time reading (Nathan): (Hour):(Minutes)(PM) — 12-hour, hour unpadded (4:20, never
  // 04:20), minutes two-digit, meridiem always present. Commits preserve the meridiem.
  const hourShown = (mins: number): number => ((Math.floor(mins / 60) + 11) % 12) + 1
  const hourToMins = (v: number, mins: number): number => ((v % 12) + (mins >= 720 ? 12 : 0)) * 60 + (mins % 60)

  const timeOptions = (which: 'start' | 'end', part: 'h' | 'm'): React.JSX.Element | null => {
    if (!timeMenu) return null
    const mins = minsOf(which)
    const setMins = setMinsFor(which)
    const current = part === 'h' ? hourShown(mins) : mins % 60
    const choose = (v: number): void => {
      setMins(part === 'h' ? hourToMins(v, mins) : Math.floor(mins / 60) * 60 + v)
      setTimeMenu(null)
    }
    return (
      <PortalMenu rect={timeMenu.rect}>
        <span className={s.ddWrap} onClick={(e) => e.stopPropagation()}>
          <PickerMenu solid direction="up">
            <div className={cx(s.menuList, 'scroll-edge-fade')}>
              {(part === 'h' ? HOURS_12 : MINUTES).map((v) => (
                <PickerOption key={v} selected={v === current} onClick={() => choose(v)}>
                  {optionRow(part === 'h' ? String(v) : pad(v), v === current)}
                </PickerOption>
              ))}
            </div>
          </PickerMenu>
        </span>
      </PortalMenu>
    )
  }
  const segCommit = (): void => {
    if (!segEdit) return
    const v = Number(segEdit.draft)
    if (segEdit.draft !== '' && Number.isFinite(v)) {
      const mins = minsOf(segEdit.which)
      const setMins = setMinsFor(segEdit.which)
      if (segEdit.part === 'h') {
        const clamped = Math.min(Math.max(v, 1), 12)
        setMins(hourToMins(clamped, mins))
      } else setMins(Math.floor(mins / 60) * 60 + Math.min(v, 59))
    }
    setSegEdit(null)
  }
  const timeSegment = (which: 'start' | 'end', part: 'h' | 'm', mins: number): React.JSX.Element =>
    segEdit?.which === which && segEdit.part === part ? (
      <input
        key={`${which}-${part}-edit`}
        className={s.timeSegInput}
        value={segEdit.draft}
        autoFocus
        spellCheck={false}
        onFocus={(e) => e.currentTarget.select()}
        onChange={(e) => {
          const draft = e.target.value
          if (/^\d{0,2}$/.test(draft)) setSegEdit({ which, part, draft })
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter') segCommit()
          else if (e.key === 'Escape') setSegEdit(null)
        }}
        onBlur={segCommit}
      />
    ) : (
      <button
        type="button"
        key={`${which}-${part}`}
        className={s.timeSeg}
        onClick={(e) => {
          if (e.detail > 1) return // the double-click pair's 2nd click must not toggle the menu shut
          setTimeMenu(
            timeMenu?.which === which && timeMenu.part === part ? null : { which, part, rect: rectOf(e.currentTarget) }
          )
        }}
        onDoubleClick={() => {
          setTimeMenu(null)
          setSegEdit({ which, part, draft: pad(part === 'h' ? Math.floor(mins / 60) : mins % 60) })
        }}
      >
        {part === 'h' ? String(hourShown(mins)) : pad(mins % 60)}
        {timeMenu?.which === which && timeMenu.part === part && timeOptions(which, part)}
      </button>
    )
  // The Swift-style meridiem segment — a plain toggle (two values never earn a dropdown), with a
  // stacked compact-chevron affordance so it reads as a control.
  const ampmSegment = (which: 'start' | 'end', mins: number): React.JSX.Element => {
    const setMins = setMinsFor(which)
    return (
      <button
        type="button"
        className={cx(s.timeSeg, s.ampmSeg)}
        onClick={() => setMins(mins >= 720 ? mins - 720 : mins + 720)}
      >
        {mins >= 720 ? 'PM' : 'AM'}
        <span className={s.ampmChevs} aria-hidden>
          <Icon name="chevron-compact-up" size={8} />
          <Icon name="chevron-compact-down" size={8} />
        </span>
      </button>
    )
  }
  const timeField = (mins: number | null, label: string, which: 'start' | 'end'): React.JSX.Element => (
    <div className={cx(s.field, s.fieldTime)} key={label}>
      <Icon name="clock" size={14} className={s.fieldIcon} />
      {mins !== null ? (
        <span className={s.timeSegs}>
          <span className={s.hmGroup}>
            {timeSegment(which, 'h', mins)}
            <span className={s.timeColon}>:</span>
            {timeSegment(which, 'm', mins)}
          </span>
          {ampmSegment(which, mins)}
        </span>
      ) : (
        <span className={cx(s.fieldValue, s.fieldEmpty)}>--</span>
      )}
    </div>
  )

  const prevMonth = slide?.from ?? cursor
  const year = cursor.getFullYear()
  // The grid viewport's height is COMPUTED from the target month's row count (geometry mirrors
  // the css: 24px cells · 2px row gap · 2px bottom pad) and set the instant nav fires — SizeMorph
  // then animates the delta on the same duration-base beat as the slide keyframe, so the resize
  // FLOWS with the horizontal move (the PaneSlider contract) instead of snapping after it.
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
  const selectionMenu = (kind: 'month' | 'year'): React.JSX.Element | null =>
    menu && (
      <PortalMenu rect={menu.rect}>
        <span className={s.ddWrap} onClick={(e) => e.stopPropagation()}>
          <PickerMenu solid>
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
      </PortalMenu>
    )

  return (
    <div className={s.root} ref={rootRef}>
      <SizeMorph>
      <div className={s.head}>
        <span className={s.titleGroup}>
          <button
            type="button"
            className={s.titleBtn}
            onClick={(e) => setMenu(menu?.kind === 'month' ? null : { kind: 'month', rect: rectOf(e.currentTarget) })}
          >
            {cursor.toLocaleDateString('en-US', { month: 'long' })}
            {menu?.kind === 'month' && selectionMenu('month')}
          </button>
          <button
            type="button"
            className={s.titleBtn}
            onClick={(e) => setMenu(menu?.kind === 'year' ? null : { kind: 'year', rect: rectOf(e.currentTarget) })}
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
      <div className={s.viewport} style={{ height: gridHeight }} onWheel={onGridWheel}>
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
        {/* Grid logic (Nathan, Swift-DatePicker model): equal halves everywhere — a range is
            [Date][Date] with times on their own [Time][Time] row; single date+time is [Date][Time].
            Equal sizing buys the AM/PM segment its room. Range fields take the picker-only
            condensed form (year rejoins only across years); single-date stays verbatim. */}
        {(() => {
          if (endOn) {
            const condensed = { withYear: start !== null && end !== null && start.slice(0, 4) !== end.slice(0, 4) }
            return (
              <>
                <div className={s.fieldRow}>
                  {dateField(start, 'start', condensed)}
                  {dateField(end, 'end', condensed)}
                </div>
                {timeOn && (
                  <div className={s.fieldRow}>
                    {timeField(start ? startMin : null, 'start-t', 'start')}
                    {timeField(end ? endMin : null, 'end-t', 'end')}
                  </div>
                )}
              </>
            )
          }
          return (
            <div className={s.fieldRow}>
              {dateField(start, 'date')}
              {timeOn && timeField(start ? startMin : null, 'time', 'start')}
            </div>
          )
        })()}
      </div>
      {/* Toggling unmounts field rows — any open segment menu or uncommitted caret edit dies with
          them (an unmounting focused input never fires onBlur, so a live segEdit would otherwise
          resurrect stale on re-toggle). */}
      <div className={s.switchRow}>
        <span className={s.switchLabel}>End Date</span>
        <span className={s.switchScale}>
          <Switch
            checked={endOn}
            ariaLabel="End Date"
            onChange={(v) => {
              setEndOn(v)
              if (!v) setEnd(null)
              setSegEdit(null)
              setTimeMenu(null)
            }}
          />
        </span>
      </div>
      <div className={s.switchRow}>
        <span className={s.switchLabel}>Use Time</span>
        <span className={s.switchScale}>
          <Switch
            checked={timeOn}
            ariaLabel="Use Time"
            onChange={(v) => {
              setTimeOn(v)
              setSegEdit(null)
              setTimeMenu(null)
            }}
          />
        </span>
      </div>
      </SizeMorph>
    </div>
  )
}
