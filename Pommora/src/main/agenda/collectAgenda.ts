// Lazy, on-demand agenda read for the sidebar's Agenda mode — a lean sibling of the index
// builder's collectAgenda (index/build.ts), which stays richer (properties/tiers/modifiedAt) for
// the SQLite upserts. This one yields only what a read-only list needs, so it never joins the
// tree walk (readNexus) — agenda cost is paid only when Agenda mode asks for it.

import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { agendaTask, agendaEvent, AGENDA_SUFFIX } from '@shared/agenda'
import type { AgendaEntry } from '@shared/types'
import { SIDECAR_FILENAME } from '../paths'
import { pathExists } from '../crud/util'

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

export async function collectAgendaEntries(
  nexusRoot: string,
): Promise<{ tasks: AgendaEntry[]; events: AgendaEntry[] }> {
  const tasks: AgendaEntry[] = []
  const events: AgendaEntry[] = []
  let dirs: string[]
  try {
    dirs = (await readdir(nexusRoot, { withFileTypes: true }))
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
  } catch {
    return { tasks, events }
  }
  for (const name of dirs) {
    const folder = join(nexusRoot, name)
    const isTask = await pathExists(join(folder, SIDECAR_FILENAME.taskConfig))
    const isEvent = !isTask && (await pathExists(join(folder, SIDECAR_FILENAME.eventConfig)))
    if (!isTask && !isEvent) continue

    const suffix = isTask ? AGENDA_SUFFIX.task : AGENDA_SUFFIX.event
    let files: string[]
    try {
      files = (await readdir(folder)).filter((f) => f.endsWith(suffix))
    } catch {
      continue
    }
    for (const f of files) {
      let content = ''
      try {
        content = await readFile(join(folder, f), 'utf8')
      } catch {
        continue
      }
      const parsed = (isTask ? agendaTask : agendaEvent).safeParse(JSON.parse(content || '{}'))
      if (!parsed.success) continue
      const item = parsed.data as Record<string, unknown>
      const icon = typeof item.icon === 'string' ? item.icon : undefined
      const common = { id: str(item.id), title: f.slice(0, -suffix.length), icon }
      if (isTask) {
        tasks.push({ ...common, kind: 'task', dueAt: str(item.due_at) || undefined })
      } else {
        events.push({
          ...common,
          kind: 'event',
          startAt: str(item.start_at) || undefined,
          endAt: str(item.end_at) || undefined,
        })
      }
    }
  }
  return { tasks, events }
}
