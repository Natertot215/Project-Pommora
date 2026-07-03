import type { NexusTree } from '@shared/types'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import * as cal from '@renderer/design-system/components/CalendarPicker/calendarPicker.css'
import { DetailScaffold } from './DetailScaffold'
import { formatDate } from './Views/PropertyEditing/formatValue'

const fmtTime = (mins: number, twelve: boolean): string => {
  const d = new Date(2026, 0, 1, Math.floor(mins / 60), mins % 60)
  return twelve
    ? d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    : d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
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
        <div className={cal.demoCell}>
          <span className={cal.demoTag}>short · 12-hour</span>
          <div className={cal.demoCard}>
            <CalendarPicker formatDateValue={(k) => formatDate(k, 'short', 'none')} formatTimeValue={(m) => fmtTime(m, true)} />
          </div>
        </div>
        <div className={cal.demoCell}>
          <span className={cal.demoTag}>full · 24-hour (overflow demo)</span>
          <div className={cal.demoCard}>
            <CalendarPicker formatDateValue={(k) => formatDate(k, 'full', 'none')} formatTimeValue={(m) => fmtTime(m, false)} />
          </div>
        </div>
      </div>
    </DetailScaffold>
  )
}
