// Agenda item models — Tasks (EKReminder-shaped) + Events (EKEvent-shaped), stored as
// pure JSON at `<Tasks>/<title>.task.json` / `<Events>/<title>.event.json`. One zod schema
// per kind = codec = type, mirroring Swift's AgendaTask/AgendaEvent minus the Codable
// ceremony. Loose ⇒ foreign keys ride through. `title` is derived from the filename (never
// stored). tier1/2/3 are bare ULID arrays at the root; dates are ISO strings. Reads are
// lenient (optional); the writer enforces the required fields (an event needs start/end).

import { z } from 'zod'

/** Fields shared by Tasks + Events. */
const agendaBase = z.looseObject({
  id: z.string(),
  icon: z.string().optional(),
  description: z.string().optional(),
  tier1: z.array(z.string()).optional(),
  tier2: z.array(z.string()).optional(),
  tier3: z.array(z.string()).optional(),
  properties: z.record(z.string(), z.unknown()).optional(),
  created_at: z.string().optional(),
  modified_at: z.string().optional(),
  // Recurrence rides as a loose object (round-tripped, not edited by the data layer).
  recurrence: z.looseObject({}).optional(),
  alarm_offsets: z.array(z.number()).optional(), // seconds; negative = before
  calendar_id: z.string().optional(),
  eventkit_uuid: z.string().optional()
})

/** AgendaTask — has an optional due date, completion, priority, and a "not before" start. */
export const agendaTask = agendaBase.extend({
  due_at: z.string().optional(),
  due_floating: z.boolean().optional(),
  due_all_day: z.boolean().optional(),
  start_at: z.string().optional(),
  completed: z.boolean().optional(),
  completed_at: z.string().optional(),
  priority: z.number().optional()
})
export type AgendaTask = z.infer<typeof agendaTask>

/** AgendaEvent — required start_at + end_at, all-day flag, location, absolute alarms. */
export const agendaEvent = agendaBase.extend({
  start_at: z.string().optional(), // required by the writer; lenient on read
  end_at: z.string().optional(),
  all_day: z.boolean().optional(),
  location: z.string().optional(),
  alarm_absolute: z.array(z.string()).optional()
})
export type AgendaEvent = z.infer<typeof agendaEvent>

export type AgendaKind = 'task' | 'event'

/** The on-disk filename suffix per kind (the item's kind authority + title boundary). */
export const AGENDA_SUFFIX: Record<AgendaKind, string> = {
  task: '.task.json',
  event: '.event.json'
}

/** The agenda kind of a file by its suffix, or null if it isn't an agenda item. */
export function agendaKindOf(filename: string): AgendaKind | null {
  if (filename.endsWith(AGENDA_SUFFIX.task)) return 'task'
  if (filename.endsWith(AGENDA_SUFFIX.event)) return 'event'
  return null
}

/** The title (filename minus the agenda suffix) for an agenda file, or null if not one. */
export function agendaTitleOf(filename: string): string | null {
  const kind = agendaKindOf(filename)
  return kind ? filename.slice(0, -AGENDA_SUFFIX[kind].length) : null
}
