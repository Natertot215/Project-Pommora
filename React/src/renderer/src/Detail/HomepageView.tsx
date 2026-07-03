import { useRef, useState, type ReactNode } from 'react'
import type { NexusTree } from '@shared/types'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import * as cal from '@renderer/design-system/components/CalendarPicker/calendarPicker.css'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { DetailScaffold } from './DetailScaffold'
import { condensedDate, formatDate } from './Views/PropertyEditing/formatValue'
import type { DateFormat } from '@shared/columnStyles'

/** The property-config formatter pair the picker injects: verbatim for single dates, the
 *  picker-only condensed form for range fields (year only when the range spans years). */
const fmtDateFor =
  (fmt: DateFormat) =>
  (k: string, condensed?: { withYear: boolean }): string =>
    condensed ? condensedDate(k, fmt, condensed.withYear) : formatDate(k, fmt, 'none')

const fmtTime = (mins: number, twelve: boolean): string => {
  const d = new Date(2026, 0, 1, Math.floor(mins / 60), mins % 60)
  return twelve
    ? d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    : d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
}

/** One openable demo picker: the trigger toggles, click-off dismisses, the pane Blooms out through
 *  exit presence. Clicks INSIDE the pane stop at the boundary so picking never closes it. */
function DemoPicker({ tag, trigger, children }: { tag: string; trigger: string; children: ReactNode }): React.JSX.Element {
  const [open, setOpen] = useState(true)
  const ref = useRef<HTMLButtonElement>(null)
  const p = useExitPresence(open)
  useDismiss(ref, () => setOpen(false), open)
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
        <DemoPicker tag="short · 12-hour" trigger="July 2nd">
          <CalendarPicker formatDateValue={fmtDateFor('short')} formatTimeValue={(m) => fmtTime(m, true)} />
        </DemoPicker>
        <DemoPicker tag="full · 24-hour (overflow demo)" trigger="Wednesday, July 2nd 2026">
          <CalendarPicker formatDateValue={fmtDateFor('full')} formatTimeValue={(m) => fmtTime(m, false)} />
        </DemoPicker>
      </div>
    </DetailScaffold>
  )
}
