import { useEffect, useState } from 'react'
import type { AgendaEntry } from '@shared/types'
import { Icon } from '@renderer/design-system/symbols'

/**
 * The Agenda sidebar mode — a read-only list of Tasks then Events, fetched on activation through
 * the lazy `agenda:list` IPC. Rows are display-only for now: no `SelectionState` kind routes an
 * agenda entity, so clicking doesn't open anything (a detail surface is future work).
 */
export function AgendaMode(): React.JSX.Element {
  const [data, setData] = useState<{ tasks: AgendaEntry[]; events: AgendaEntry[] }>({
    tasks: [],
    events: [],
  })
  useEffect(() => {
    let live = true
    void window.nexus.agenda.list().then((r) => {
      if (live && r.ok) setData({ tasks: r.tasks, events: r.events })
    })
    return () => {
      live = false
    }
  }, [])

  const row = (e: AgendaEntry): React.JSX.Element => (
    <div key={e.id} className="agenda-row">
      <Icon name={e.icon ?? (e.kind === 'task' ? 'circle' : 'calendar')} size={16} />
      <span className="agenda-title">{e.title}</span>
    </div>
  )

  if (data.tasks.length === 0 && data.events.length === 0) {
    return <div className="agenda-empty">No tasks or events</div>
  }
  return (
    <div className="agenda-mode">
      {data.tasks.map(row)}
      {data.events.map(row)}
    </div>
  )
}
