// The PropertyDefinition model — one schema entry inside a Type / agenda-config
// sidecar's `property_definitions[]`. The zod schema IS the codec AND the type
// (z.infer), mirroring Swift's PropertyDefinition + PropertyType + nested config +
// ReservedPropertyID, minus the ~117 lines of Codable / CodingKeys ceremony.
//
// Snake_case keys = the on-disk shape. Loose ⇒ foreign keys within a def survive a
// rewrite. Only structurally load-bearing fields are modeled; pure display config
// (number_format, date_format, time_format, display_as, date_includes_time) rides
// through as foreign keys until a UI reads it — "catch up to Swift, don't go ahead".
// The renderable structure (type, options, relation target, tier reverse labels,
// icons) IS modeled because the write path + tier synthesis read it.

import { z } from 'zod'

/** Property type catalog. Raw lowercase / snake_case strings = the on-disk values. */
export const propertyType = z.enum([
  'number',
  'checkbox',
  'date', // calendar date only; normalized to `datetime` on read (see properties/schema.ts)
  'datetime',
  'select',
  'multi_select',
  'status',
  'url',
  'relation', // tier-only tolerance; retired from user creation
  'last_edited_time',
  'file'
])
export type PropertyType = z.infer<typeof propertyType>

export const selectColor = z.enum([
  'gray',
  'brown',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'red',
  'teal',
  'indigo'
])

const selectOption = z.looseObject({
  value: z.string(),
  label: z.string(),
  // Lenient: an unknown color degrades to undefined rather than failing the whole def parse.
  color: selectColor.optional().catch(undefined)
})

/** Three fixed status-group slots — a fourth breaks EventKit sync mapping. */
export const statusGroupId = z.enum(['upcoming', 'in_progress', 'done'])
export type StatusGroupId = z.infer<typeof statusGroupId>

const statusOption = z.looseObject({
  value: z.string(),
  label: z.string(),
  color: selectColor.optional().catch(undefined),
  group_id: statusGroupId
})

const statusGroup = z.looseObject({
  id: statusGroupId,
  label: z.string(),
  // Required, but an unknown color falls back rather than dropping the group.
  color: selectColor.catch('gray'),
  options: z.array(statusOption)
})
export type StatusGroup = z.infer<typeof statusGroup>

/** Relation picker constraint. On-disk: `{ kind: "context_tier", tier: N }`. Lenient
 *  `kind` so a retired user-relation target survives parse (it's dropped later by
 *  `droppingUserRelations`, not by failing the whole sidecar). */
const relationTarget = z.looseObject({
  kind: z.string(),
  tier: z.number().optional()
})

/** One property schema entry. Loose ⇒ display config + any foreign keys ride through. */
export const propertyDefinition = z.looseObject({
  id: z.string(),
  name: z.string(),
  type: propertyType,
  icon: z.string().optional(),
  select_options: z.array(selectOption).optional(),
  status_groups: z.array(statusGroup).optional(),
  relation_target: relationTarget.optional(),
  reverse_name: z.string().optional(),
  reverse_icon: z.string().optional(),
  accept: z.array(z.string()).optional()
})
export type PropertyDefinition = z.infer<typeof propertyDefinition>

// MARK: - Reserved property IDs

/** Built-in property IDs use a `_` prefix; user properties use `prop_<ulid>` (minted by
 *  `mintPropertyId` in ids.ts). Only the ID is reserved — display names are
 *  unrestricted. Mirrors Swift `ReservedPropertyID`. */
export const RESERVED_PROPERTY_ID = {
  id: '_id',
  title: '_title',
  createdAt: '_created_at',
  modifiedAt: '_modified_at',
  status: '_status',
  type: '_type',
  tier1: '_tier1',
  tier2: '_tier2',
  tier3: '_tier3'
} as const

const RESERVED_SET = new Set<string>(Object.values(RESERVED_PROPERTY_ID))

/** True iff `id` is in the reserved catalog (the schema editor blocks claiming one). */
export function isReservedPropertyId(id: string): boolean {
  return RESERVED_SET.has(id)
}

/** The context tier levels. The one source for iterating tiers (1 = Area, 2 = Topic,
 *  3 = Project). Callers validate the 1–3 bound at the CRUD boundary. */
export const TIER_LEVELS = [1, 2, 3] as const

/** Tier level → the BARE frontmatter-root array field (`tier1`/`tier2`/`tier3`). */
export function tierFieldName(level: number): string {
  return `tier${level}`
}

/** Tier level → the RESERVED property id (`_tier1`/`_tier2`/`_tier3`) used in the schema +
 *  context_links.property_id. Distinct from the bare root field (tierFieldName). */
export function tierPropertyId(level: number): string {
  return `_tier${level}`
}

/** Default 3-group seed written when a Status property is first added. Mirrors Swift
 *  `StatusGroup.defaultSeed()` + Properties.md § "Status property type → Default seed". */
export function defaultStatusSeed(): StatusGroup[] {
  return [
    {
      id: 'upcoming',
      label: 'Upcoming',
      color: 'gray',
      options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }]
    },
    {
      id: 'in_progress',
      label: 'In Progress',
      color: 'blue',
      options: [{ value: 'in_progress', label: 'In progress', color: 'blue', group_id: 'in_progress' }]
    },
    {
      id: 'done',
      label: 'Done',
      color: 'green',
      options: [{ value: 'done', label: 'Done', color: 'green', group_id: 'done' }]
    }
  ]
}

/** Default single-option seed written when a Select / Multi-Select property is first added. A select
 *  needs ≥1 option (validateDefinition), so creation seeds a starter the user then renames/extends. */
export function defaultSelectSeed(): { value: string; label: string }[] {
  return [{ value: 'option_1', label: 'Option 1' }]
}
