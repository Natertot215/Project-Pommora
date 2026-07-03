import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { NexusTree } from '@shared/types'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import * as cal from '@renderer/design-system/components/CalendarPicker/calendarPicker.css'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { DetailScaffold } from './DetailScaffold'
import { condensedDate, formatDate } from './Views/PropertyEditing/formatValue'
import type { DateFormat } from '@shared/columnStyles'

/** The property-config formatter the picker injects: verbatim for single dates, the picker-only
 *  condensed form for range fields (year only when the range spans years). */
const fmtDateFor =
  (fmt: DateFormat) =>
  (k: string, condensed?: { withYear: boolean }): string =>
    condensed ? condensedDate(k, fmt, condensed.withYear) : formatDate(k, fmt, 'none')

/** One openable demo picker: the trigger toggles, click-off dismisses, the pane Blooms out through
 *  exit presence. Clicks INSIDE the pane stop at the boundary so picking never closes it — and the
 *  dismiss spares [data-calmenu] portals (the picker's sub-menus live at body level; a plain
 *  useDismiss reads them as outside and closes the main pane — the real property-editor host
 *  needs the same carve-out). */
function DemoPicker({ tag, trigger, children }: { tag: string; trigger: string; children: ReactNode }): React.JSX.Element {
  const [open, setOpen] = useState(true)
  const ref = useRef<HTMLButtonElement>(null)
  const p = useExitPresence(open)
  useEffect(() => {
    if (!open) return
    const onDown = (e: PointerEvent): void => {
      const t = e.target as HTMLElement
      if (ref.current?.contains(t) || t.closest('[data-calmenu]')) return
      setOpen(false)
    }
    document.addEventListener('pointerdown', onDown, true)
    return () => document.removeEventListener('pointerdown', onDown, true)
  }, [open])
  return (
    <div className={cal.demoCell}>
      <span className={cal.demoTag}>{tag}</span>
      <button type="button" ref={ref} className={cal.demoTrigger} onClick={() => setOpen((o) => !o)}>
        {trigger}
        {p.mounted && (
          <span onClick={(e) => e.stopPropagation()}>
            <PickerMenu solid closing={p.closing}>
              {children}
            </PickerMenu>
          </span>
        )}
      </button>
    </div>
  )
}

/**
 * The homepage view — the live nexus entity (the sidebar header). v1 renders the CalendarPicker
 * prototype under its banner while Nathan iterates its design live (the picker later mounts in the
 * datetime property editor); dynamic widgets remain future work, composed here at the view level.
 */
export function HomepageView({ tree }: { tree: NexusTree | null }): React.JSX.Element {
  return (
    <DetailScaffold
      owner={{ path: '', kind: 'homepage', name: tree?.nexus.name ?? 'Home', banner: tree?.homepage.banner }}
    >
      <div className={cal.demoRow}>
        {/* Both cards ride the nexus-wide time_format setting — the same source the routed
            datetime-property picker reads. */}
        <DemoPicker tag="short" trigger="July 2nd">
          <CalendarPicker formatDateValue={fmtDateFor('short')} timeFormat={tree?.timeFormat} />
        </DemoPicker>
        <DemoPicker tag="full (overflow demo)" trigger="Wednesday, July 2nd 2026">
          <CalendarPicker formatDateValue={fmtDateFor('full')} timeFormat={tree?.timeFormat} />
        </DemoPicker>
      </div>
    </DetailScaffold>
  )
}
